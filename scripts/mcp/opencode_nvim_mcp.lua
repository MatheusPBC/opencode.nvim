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
local MAX_MESSAGE_SIZE = 10 * 1024 * 1024 -- 10MB max message size
local MAX_CANDIDATES = 100 -- Maximum candidates in picker

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

---Validate tool arguments for security
local function validate_tool_call(tool_name, tool_args)
  if tool_name == "open_file" then
    if not tool_args.path or type(tool_args.path) ~= "string" then
      return nil, { code = -32602, message = "Invalid params: path must be a non-empty string" }
    end
    if tool_args.path == "" then
      return nil, { code = -32602, message = "Invalid params: path must be non-empty" }
    end
    if tool_args.line and (type(tool_args.line) ~= "number" or tool_args.line < 1 or tool_args.line ~= math.floor(tool_args.line)) then
      return nil, { code = -32602, message = "Invalid params: line must be positive integer" }
    end
    if tool_args.col and (type(tool_args.col) ~= "number" or tool_args.col < 1 or tool_args.col ~= math.floor(tool_args.col)) then
      return nil, { code = -32602, message = "Invalid params: col must be positive integer" }
    end
  end
  
  if tool_name == "open_candidates" then
    if not tool_args.candidates or type(tool_args.candidates) ~= "table" then
      return nil, { code = -32602, message = "Invalid params: candidates must be an array" }
    end
    if #tool_args.candidates > MAX_CANDIDATES then
      return nil, { code = -32602, message = "Invalid params: too many candidates (max " .. MAX_CANDIDATES .. ")" }
    end
    for i, candidate in ipairs(tool_args.candidates) do
      if not candidate.path or type(candidate.path) ~= "string" or candidate.path == "" then
        return nil, { code = -32602, message = "Invalid params: candidates[" .. i .. "].path must be non-empty string" }
      end
      if candidate.line and (type(candidate.line) ~= "number" or candidate.line < 1 or candidate.line ~= math.floor(candidate.line)) then
        return nil, { code = -32602, message = "Invalid params: candidates[" .. i .. "].line must be positive integer" }
      end
      if candidate.col and (type(candidate.col) ~= "number" or candidate.col < 1 or candidate.col ~= math.floor(candidate.col)) then
        return nil, { code = -32602, message = "Invalid params: candidates[" .. i .. "].col must be positive integer" }
      end
    end
  end
  
  return true, nil
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
  local mode = path:sub(1, 1) == "/" and "pipe" or "tcp"
  local ok, client = pcall(vim.fn.sockconnect, mode, path, { rpc = true })
  if not ok or client <= 0 then
    callback(nil, "connection failed: " .. tostring(client))
    return
  end

  callback(client, nil)
end

---Validate socket by calling nvim_get_api_info
local function validate_socket(client, callback)
  local ok, result = pcall(vim.rpcrequest, client, "nvim_get_api_info")
  if not ok then
    callback(nil, "validation rpc error: " .. tostring(result))
    return
  end

  if not result then
    callback(nil, "empty validation response")
    return
  end

  callback(true, nil)
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
  
  -- Validate arguments
  local valid, validation_err = validate_tool_call(tool_name, tool_args)
  if not valid then
    send_error(id, validation_err.code, validation_err.message)
    return
  end
  
  if not socket_client then
    send_error(id, -32429, "socket not connected")
    return
  end
  
  -- Build Lua code for parent Neovim using safe JSON encoding
  -- This prevents Lua injection by passing args as JSON and decoding them in the parent
  local args_json = vim.json.encode(tool_args)
  -- Escape ]=] sequence to prevent breaking the long bracket
  local args_json_escaped = args_json:gsub("]=", "]=] =")
  local lua_code
  if tool_name == "open_file" then
    lua_code = "local args = vim.json.decode([=[" .. args_json_escaped .. "]=]); local ok, mod = pcall(require, 'opencode.editor_actions'); if ok then mod.open_file(args) end"
  else -- open_candidates
    lua_code = "local args = vim.json.decode([=[" .. args_json_escaped .. "]=]); local ok, mod = pcall(require, 'opencode.editor_actions'); if ok then mod.open_candidates(args) end"
  end
  
  -- Fire-and-forget notification to parent Neovim
  local ok, notify_err = pcall(vim.rpcnotify, socket_client, "nvim_exec_lua", lua_code, {})
  if not ok then
    send_error(id, -32429, "failed to notify Neovim: " .. tostring(notify_err))
    return
  end
  
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
            pcall(vim.fn.chanclose, socket_client)
          end
          vim.loop.stop()
          return
        end
        
        pending_buffer = pending_buffer .. data
        
        -- Check max message size to prevent memory exhaustion
        if #pending_buffer > MAX_MESSAGE_SIZE then
          send_error(nil, -32603, "message too large (max " .. math.floor(MAX_MESSAGE_SIZE / 1024 / 1024) .. "MB)")
          pending_buffer = ""
          return
        end
        
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
            pcall(vim.fn.chanclose, socket_client)
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
