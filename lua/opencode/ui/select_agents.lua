local M = {}

---Select an agent from available agents via HTTP API
---@return Promise<opencode.server.Agent>
function M.select()
  local Promise = require("opencode.promise")
  local Server = require("opencode.server")
  
  return Server.get()
    :next(function(server) ---@param server opencode.server.Server
      return Promise.new(function(resolve, reject)
        server:get_agents(function(agents) ---@param agents opencode.server.Agent[]
          if not agents or #agents == 0 then
            return reject("No agents available")
          end
          resolve(agents)
        end)
      end)
    end)
    :next(function(agents) ---@param agents opencode.server.Agent[]
      ---@class opencode.select_agents.Item : snacks.picker.finder.Item
      ---@field agent opencode.server.Agent
      
      local items = {}
      
      -- Sort agents: primary first, then by name
      table.sort(agents, function(a, b)
        if a.mode ~= b.mode then
          return a.mode == "primary"
        end
        return a.name < b.name
      end)
      
      for _, agent in ipairs(agents) do
        table.insert(items, {
          agent = agent,
          name = agent.name,
          text = agent.description or "",
          highlights = { { agent.description or "", "Comment" } },
          preview = {
            text = string.format(
              "Agent: %s\n\nMode: %s\nDescription: %s",
              agent.name,
              agent.mode,
              agent.description or "No description"
            ),
          },
        })
      end
      
      ---@type snacks.picker.ui_select.Opts
      local select_opts = {
        prompt = "Select Agent: ",
        format_item = function(item, is_snacks)
          if is_snacks then
            local mode_highlight = item.agent.mode == "primary" and "Title" or "Keyword"
            return {
              { item.name, mode_highlight },
              { string.rep(" ", 20 - #item.name) },
              { item.agent.description or "", "Comment" },
            }
          else
            local mode_indicator = item.agent.mode == "primary" and "[P]" or "[S]"
            return string.format("%s %s%s  %s", mode_indicator, item.name, string.rep(" ", 20 - #item.name), item.agent.description or "")
          end
        end,
      }
      
      return Promise.select(items, select_opts)
    end)
    :next(function(choice) ---@param choice opencode.select_agents.Item
      local ask = require("opencode.ui.ask")
      local agent_ref = "@" .. choice.agent.name .. " "

      if ask.is_active() then
        ask.insert_text(agent_ref)
        vim.notify(
          string.format("Inserted: %s\n\n%s", agent_ref:sub(1, -2), choice.agent.description or "No description"),
          vim.log.levels.INFO,
          { title = "opencode" }
        )
      else
        ask.ask_prefilled(agent_ref, { context = require("opencode.context").new() })
          :next(function(input)
            if input and input:match("^@" .. choice.agent.name) then
              vim.notify(
                string.format("Agent: %s\n\n%s", choice.agent.name, choice.agent.description or "No description"),
                vim.log.levels.INFO,
                { title = "opencode" }
              )
            end
          end)
      end

      return choice.agent
    end)
    :catch(function(err)
      if err then
        vim.notify(err, vim.log.levels.WARN, { title = "opencode" })
      end
      return Promise.reject(err)
    end)
end

return M