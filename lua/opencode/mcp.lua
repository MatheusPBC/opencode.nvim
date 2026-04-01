---MCP integration module for OpenCode.
---Provides RPC socket access and environment helpers for MCP server communication.
local M = {}

---Environment variable name for the Neovim RPC socket.
---Opencode will read this to connect to the current Neovim instance.
M.OPENCODE_NVIM_RPC = "OPENCODE_NVIM_RPC"

---Get the current Neovim RPC socket path.
---This is the primary source of truth for the socket location.
---@return string|nil The RPC socket path, or nil if not available.
local function get_rpc_socket()
  return vim.v.servername
end

---Get environment variables to inject into OpenCode terminal.
---Returns a table with the RPC socket path set.
---@return table<string, string> Environment variables table.
function M.get_env()
  local socket = get_rpc_socket()
  local env = {}
  if socket and socket ~= "" then
    env[M.OPENCODE_NVIM_RPC] = socket
  end
  return env
end

---Check if Neovim has an active RPC socket.
---@return boolean True if socket is available.
function M.has_socket()
  local socket = get_rpc_socket()
  return socket ~= nil and socket ~= ""
end

---Get the path to the MCP server script.
---The script connects to Neovim's RPC socket and provides tools for OpenCode.
---@return string Absolute path to the MCP server script.
function M.get_server_script_path()
  local runtime_files = vim.api.nvim_get_runtime_file("lua/opencode.lua", false)
  if #runtime_files == 0 then
    vim.notify("OpenCode: could not locate plugin root", vim.log.levels.WARN)
    return ""
  end
  local opencode_lua = runtime_files[1]
  local plugin_root = opencode_lua:gsub("/lua/opencode%.lua$", "")
  return plugin_root .. "/scripts/mcp/opencode_nvim_mcp.lua"
end

---Internal helper for testing and debugging.
---@return string|nil
function M._get_rpc_socket()
  return get_rpc_socket()
end

return M
