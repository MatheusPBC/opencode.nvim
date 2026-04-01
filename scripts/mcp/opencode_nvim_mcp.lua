---OpenCode Neovim MCP Server
---Terminal-first MCP server that connects to the current Neovim instance.
---Run: nvim --headless -u NONE -l scripts/mcp/opencode_nvim_mcp.lua
---
---Protocol: JSON-RPC 2.0 over stdio (LSP-style Content-Length)
---Transport: msgpack-rpc over TCP/Unix socket to parent Neovim
---
---Tools:
---  open_file: Open a single file in a new tab
---  open_candidates: Show picker for multiple file candidates

---- Constants
local ENV_SOCKET = "OPENCODE_NVIM_RPC"
local CONTENT_LENGTH_PATTERN = "^Content%-Length:%s*(%d+)"

---- State
local socket_path = nil
local socket_client = nil
local stdin_pipe = nil
local stdout_pipe = nil
local pending_buffer = ""
local is_shutting_down = false

---- MCP Tool Definitions
local TOOLS = {
  {
    name = "open_file",
    description = "Open a file in the current Neovim instance. Use this when there is a single clear target and explicit intent to open/navigate.",
    inputSchema = {
      type = "object",
      properties = {
        path = {
          type = "string",
          description = "Absolute path to the file (required)",
        },
        line = {
          type = "integer",
          description = "Line number (1-based, optional)",
        },
        col = {
          type = "integer",
          description = "Column number (1-based, optional)",
        },
      },
      required = { "path" },
    },
  },
  {
    name = "open_candidates",
    description = "Show a picker for multiple file candidates. Use this when there is ambiguity or multiple reasonable targets.",
    inputSchema = {
      type = "object",
      properties = {
        candidates = {
          type = "array",
          description = "List of file candidates",
          items = {
            type = "object",
            properties = {
              path = {
                type = "string",
                description = "Absolute path to the file (required)",
              },
              line = {
                type = "integer",
                description = "Line number (1-based, optional)",
              },
              col = {
                type = "integer",
                description = "Column number (1-based, optional)",
              },
              label = {
                type = "string",
                description = "Display label for the picker (optional)",
              },
            },
            required = { "path" },
          },
        },
        prompt = {
          type = "string",
          description = "Optional prompt text for the picker",
        },
      },
      required = { "candidates" },
    },
  },
}

---- Helpers

---Encode msgpack-rpc request (type 0)
local function encode_request(id, method, args)
  return vim.mpack.encode({ 0, id, method, args or {} })
end

---Encode msgpack-rpc notification (type 2)
local function encode_notification(method, args)
  return vim.mpack.encode({ 2, method, args or {} })
end

---Decode msgpack-rpc response
local function decode_response(data)
  local ok, decoded = pcall(vim.mpack.decode, data)
  if not ok then
    return nil, "invalid msgpack: " .. tostring(decoded)
  end
  if decoded[1] ~= 1 then
    return nil, "not a response type"
  end
  return { id = decoded[2], result = decoded[3], error = decoded[4] }, nil
end

---- JSON-RPC Response

---Send JSON-RPC response to stdout
local function send_response(id, result)
  local response = vim.json.encode({
    jsonrpc = "2.0",
    result = result,
    id = id,
  })
  local length = #response
  local msg = "Content-Length: " .. length .. "\r\n\r\n" .. response
  vim.loop.write(stdout_pipe, msg)
end

---Send JSON-RPC error to stdout
local function send_error(id, code, message, data)
  local err = { code = code, message = message }
  if data then
    err.data = data
  end
  local response = vim.json.encode({
    jsonrpc = "2.0",
    error = err,
    id = id,
  })
  local length = #response
  local msg = "Content-Length: " .. length .. "\r\n\r\n" .. response
  vim.loop.write(stdout_pipe, msg)
end

---- Socket Connection

---Connect to Neovim RPC socket
local function connect_socket(path, callback)
  local client = vim.loop.new_tcp()
  if not client then
    callback(nil, "failed to create TCP client")
    return
  end

  local function on_connect(err)
    if err then
      client:close()
      callback(nil, "connection failed: " .. tostring(err))
      return
    end
    callback(client, nil)
  end

  -- Unix socket (starts with /) or TCP host:port
  if path:sub(1, 1) == "/" then
    client:connect(path, on_connect)
  else
    local host, port = path:match("^([^:]+):(%d+)$")
    if host and port then
      client:connect(host, tonumber(port), on_connect)
    else
      client:close()
      callback(nil, "invalid socket path: " .. path)
    end
  end
end

---Validate socket by calling nvim_get_api_info
local function validate_socket(client, callback)
  local request_id = 1
  local msg = encode_request(request_id, "nvim_get_api_info", {})
  
  local response_data = {}
  local timer = vim.loop.new_timer()
  
  -- Timer for timeout
  timer:start(5000, 0, function()
    timer:close()
    callback(nil, "timeout waiting for validation response")
  end)
  
  -- Read handler
  client:read_start(function(err, data)
    if err then
      timer:close()
      callback(nil, "read error during validation: " .. tostring(err))
      return
    end
    if not data then
      timer:close()
      callback(nil, "connection closed during validation")
      return
    end
    
    table.insert(response_data, data)
    local concatenated = table.concat(response_data)
    
    local decoded, decode_err = decode_response(concatenated)
    if decoded then
      timer:close()
      client:read_stop()
      if decoded.error then
        callback(nil, "validation rpc error: " .. vim.inspect(decoded.error))
      else
        callback(true, nil)
      end
    end
    -- Partial data - keep reading
  end)
  
  -- Send validation request
  client:write(msg, function(err)
    if err then
      timer:close()
      callback(nil, "write error during validation: " .. tostring(err))
    end
  end)
end

---- MCP Handlers

---Handle initialize request
local function handle_initialize(id)
  send_response(id, {
    protocolVersion = "2024-11-05",
    capabilities = {
      tools = { listChanged = false },
    },
    serverInfo = {
      name = "opencode-nvim-mcp",
      version = "1.0.0",
    },
  })
end

---Handle tools/list request
local function handle_tools_list(id)
  send_response(id, { tools = TOOLS })
end

---Handle tools/call request
local function handle_tools_call(id, params)
  if not params or not params.name then
    send_error(id, -32602, "missing tool name")
    return
  end
  
  local tool_name = params.name
  local tool_args = params.arguments or {}
  
  if tool_name ~= "open_file" and tool_name ~= "open_candidates" then
    send_error(id, -32601, "unknown tool: " .. tool_name)
    return
  end
  
  if not socket_client then
    send_error(id, -32429, "socket not connected")
    return
  end
  
  -- Build Lua code for parent Neovim
  local lua_code
  if tool_name == "open_file" then
    lua_code = string.format(
      [[local ok, mod = pcall(require, "opencode.editor_actions"); if ok then mod.open_file(%s) end]],
      vim.inspect(tool_args)
    )
  else -- open_candidates
    lua_code = string.format(
      [[local ok, mod = pcall(require, "opencode.editor_actions"); if ok then mod.open_candidates(%s) end]],
      vim.inspect(tool_args)
    )
  end
  
  -- Fire-and-forget notification to parent Neovim
  local notification = encode_notification("nvim_exec_lua", { lua_code, {} })
  socket_client:write(notification)
  
  -- Respond immediately
  local result
  if tool_name == "open_file" then
    result = { content = { { type = "text", text = "opened" } } }
  else
    result = { content = { { type = "text", text = "picker_shown" } } }
  end
  send_response(id, result)
end

---Process a parsed JSON-RPC request
local function process_request(req)
  local method = req.method
  local id = req.id
  local params = req.params or {}
  
  -- Notifications don't get responses
  if method == "notifications/initialized" then
    return
  end
  
  if method == "initialize" then
    handle_initialize(id)
  elseif method == "tools/list" then
    handle_tools_list(id)
  elseif method == "tools/call" then
    handle_tools_call(id, params)
  elseif method == "shutdown" then
    send_response(id, {})
    is_shutting_down = true
  else
    if id then
      send_error(id, -32601, "method not found: " .. method)
    end
  end
end

---Parse and handle complete JSON-RPC message
local function handle_message(body)
  local ok, decoded = pcall(vim.json.decode, body)
  if not ok then
    send_error(nil, -32700, "parse error: " .. tostring(decoded))
    return
  end
  
  if decoded.jsonrpc ~= "2.0" then
    send_error(nil, -32600, "invalid jsonrpc version")
    return
  end
  
  process_request(decoded)
end

---Parse Content-Length headers and extract body
local function parse_headers(buffer)
  local pos = buffer:find("\r\n\r\n", 1, true)
  if not pos then
    return nil, buffer -- Need more data
  end
  
  local header_section = buffer:sub(1, pos - 1)
  local rest = buffer:sub(pos + 4)
  
  local content_length = nil
  for line in header_section:gmatch("[^\r\n]+") do
    local len = line:match(CONTENT_LENGTH_PATTERN)
    if len then
      content_length = tonumber(len)
    end
  end
  
  if not content_length then
    send_error(nil, -32600, "missing Content-Length header")
    return nil, rest
  end
  
  if #rest < content_length then
    return nil, buffer -- Need more data
  end
  
  local body = rest:sub(1, content_length)
  local remaining = rest:sub(content_length + 1)
  
  return body, remaining
end

---- Main Entry

local function main()
  -- Setup pipes for stdio
  stdin_pipe = vim.loop.new_pipe(false)
  stdout_pipe = vim.loop.new_pipe(false)
  
  if not stdin_pipe or not stdout_pipe then
    io.stderr:write("Failed to create stdio pipes\n")
    os.exit(1)
    return
  end
  
  stdin_pipe:open(0) -- stdin
  stdout_pipe:open(1) -- stdout
  
  -- Get socket from environment
  socket_path = os.getenv(ENV_SOCKET)
  if not socket_path or socket_path == "" then
    send_error(nil, -32429, "missing " .. ENV_SOCKET .. " environment variable")
    vim.loop.stop()
    return
  end
  
  -- Connect to Neovim socket
  connect_socket(socket_path, function(client, err)
    if err then
      send_error(nil, -32429, "socket connection failed: " .. err)
      vim.loop.stop()
      return
    end
    
    socket_client = client
    
    -- Validate socket
    validate_socket(client, function(valid, val_err)
      if val_err then
        send_error(nil, -32429, "socket validation failed: " .. val_err)
        vim.loop.stop()
        return
      end
      
      -- Start reading stdin
      stdin_pipe:read_start(function(read_err, data)
        if read_err or not data then
          -- EOF or error - shutdown
          stdin_pipe:close()
          stdout_pipe:close()
          if socket_client then
            socket_client:close()
          end
          vim.loop.stop()
          return
        end
        
        pending_buffer = pending_buffer .. data
        
        -- Process all complete messages
        local body
        while true do
          body, pending_buffer = parse_headers(pending_buffer)
          if body then
            handle_message(body)
          else
            break
          end
        end
        
        if is_shutting_down then
          stdin_pipe:close()
          stdout_pipe:close()
          if socket_client then
            socket_client:close()
          end
          vim.loop.stop()
        end
      end)
    end)
  end)
  
  -- Run event loop
  vim.loop.run()
end

main()