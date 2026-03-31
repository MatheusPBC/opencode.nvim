local M = {}

---@class opencode.api.slash.Opts
---@field messageID? string
---@field agent? string
---@field model? string

---Execute a slash command in `opencode`.
---Discovers the active session and executes the command via HTTP API.
---
---@param command string The slash command to execute (e.g., "/agents", "/new")
---@param args? table<string, any> Arguments for the command
---@param opts? opencode.api.slash.Opts
---@return Promise
function M.slash(command, args, opts)
  local Promise = require("opencode.promise")

  return require("opencode.server")
    .get()
    :next(function(server) ---@param server opencode.server.Server
      return Promise.new(function(resolve, reject)
        server:get_active_session(function(session) ---@param session opencode.server.Session|nil
          if not session then
            reject("No active session found")
            return
          end
          resolve({ server = server, session = session })
        end)
      end)
    end)
    :next(function(result) ---@param result { server: opencode.server.Server, session: opencode.server.Session }
      return Promise.new(function(resolve)
        result.server:execute_slash_command(result.session.id, command, args, opts, function(response)
          resolve(response)
        end)
      end)
    end)
end

return M