local M = {}

---Select a slash command from available commands via HTTP API
---@return Promise
function M.select()
  local Promise = require("opencode.promise")
  local Server = require("opencode.server")
  local opencode = require("opencode")
  
  return Server.get()
    :next(function(server) ---@param server opencode.server.Server
      return Promise.new(function(resolve, reject)
        server:get_slash_commands(function(commands) ---@param commands opencode.server.SlashCommand[]
          if not commands or #commands == 0 then
            return reject("No slash commands available")
          end
          resolve(commands)
        end)
      end)
    end)
    :next(function(commands) ---@param commands opencode.server.SlashCommand[]
      ---@class opencode.select_commands.Item : snacks.picker.finder.Item
      ---@field command opencode.server.SlashCommand
      
      local items = {}
      
      -- Sort commands by name
      table.sort(commands, function(a, b)
        return a.name < b.name
      end)
      
      for _, command in ipairs(commands) do
        table.insert(items, {
          command = command,
          name = command.name,
          text = command.description or "",
          highlights = { { command.description or "", "Comment" } },
          preview = {
            text = string.format(
              "Command: %s\n\n%s",
              command.name,
              command.description or "No description"
            ),
          },
        })
      end
      
      ---@type snacks.picker.ui_select.Opts
      local select_opts = {
        prompt = "Select Slash Command: ",
        format_item = function(item, is_snacks)
          if is_snacks then
            return {
              { item.name, "Keyword" },
              { string.rep(" ", 25 - #item.name) },
              { item.command.description or "", "Comment" },
            }
          else
            return string.format("%s%s  %s", item.name, string.rep(" ", 25 - #item.name), item.command.description or "")
          end
        end,
      }
      
      return Promise.select(items, select_opts)
    end)
    :next(function(choice) ---@param choice opencode.select_commands.Item
      -- Execute the slash command using existing API
      return opencode.slash(choice.command.name)
    end)
    :catch(function(err)
      if err then
        vim.notify(err, vim.log.levels.WARN, { title = "opencode" })
      end
      return Promise.reject(err)
    end)
end

return M