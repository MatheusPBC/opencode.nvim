local M = {}

local profiles = require("opencode.profiles")

---@class opencode.api.prompt.Opts
---@field clear? boolean Clear the TUI input before.
---@field submit? boolean Submit the TUI input after.
---@field context? opencode.Context The context the prompt is being made in.

---Prompt `opencode`.
---On success, clears the context. On failure, resumes the context.
---
---@param prompt string
---@param opts? opencode.api.prompt.Opts
---@return Promise
function M.prompt(prompt, opts)
  -- Check if prompt starts with / (slash command)
  local slash_match = prompt:match("^(/%S+)")
  if slash_match then
    local command = slash_match
    local args_text = prompt:sub(#command + 1):match("^%s*(.*)")
    local args = nil
    if args_text and args_text ~= "" then
      args = { text = args_text }
    end
    return require("opencode.api.slash").slash(command, args, opts)
  end

  -- TODO: Referencing `ask = true` prompts doesn't actually ask.
  local referenced_prompt = require("opencode.config").opts.prompts[prompt]
  prompt = referenced_prompt and referenced_prompt.prompt or prompt
  opts = {
    clear = opts and opts.clear or false,
    submit = opts and opts.submit or false,
    context = opts and opts.context or require("opencode.context").new(),
  }

  -- Resolve active profile and prepend profile contexts to prompt
  local active_profile = profiles.resolve({ explicit = opts and opts.profile })
  local profile_contexts = profiles.get_contexts(active_profile)

  -- Prepend profile contexts to the prompt (if any)
  if #profile_contexts > 0 then
    local contexts_str = table.concat(profile_contexts, " ")
    prompt = contexts_str .. " " .. prompt
  end

  local Promise = require("opencode.promise")
  return require("opencode.server")
    .get()
    :next(function(server) ---@param server opencode.server.Server
      if opts.clear then
        return Promise.new(function(resolve)
          server:tui_execute_command("prompt.clear", function()
            resolve(server)
          end)
        end)
      end
      return server
    end)
    :next(function(server) ---@param server opencode.server.Server
      local rendered = opts.context:render(prompt, server.subagents)
      local plaintext = opts.context.plaintext(rendered.output)
      return Promise.new(function(resolve)
        server:tui_append_prompt(plaintext, function()
          resolve(server)
        end)
      end)
    end)
    :next(function(server) ---@param server opencode.server.Server
      if opts.submit then
        server:tui_execute_command("prompt.submit")
      end
    end)
    :next(function()
      opts.context:clear()
    end)
    :catch(function(err)
      opts.context:resume()
      return Promise.reject(err)
    end)
end

return M
