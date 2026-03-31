---`opencode.nvim` public API.
local M = {}

----------
--- UI ---
----------

---Input a prompt for `opencode`.
---
--- - Press the up arrow to browse recent asks.
--- - Highlights and completes contexts and `opencode` subagents.
---   - Press `<Tab>` to trigger built-in completion.
--- - End the prompt with `\n` to append instead of submit.
--- - Additionally, when using `snacks.input`:
---   - Press `<S-CR>` to append instead of submit.
---   - Offers completions via in-process LSP.
---
---@param default? string Text to pre-fill the input with.
---@param opts? opencode.api.prompt.Opts Options for `prompt()`.
M.ask = function(default, opts)
  opts = opts or {}
  opts.context = opts.context or require("opencode.context").new()

  return require("opencode.ui.ask")
    .ask(default, opts.context)
    :next(function(input) ---@param input string
      -- TODO: Should we remove `opts.clear` and `opts.submit` in favor of just checking if the input ends with `\n`?
      -- (maybe even in `prompt()` itself?)
      -- Confusing to have both.
      -- I think it's better, but don't love the breaking change.
      -- Although for most users, I imagine they just use `opts.submit = false` and thus won't be affected.
      if input:sub(-2) == "\\n" then
        input = input:sub(1, -3) .. "\n" -- Remove the escaped `\n` and add an actual newline character for `opencode` to interpret.
        opts.clear = false
        opts.submit = false
      end
      opts.context:clear()
      return require("opencode.api.prompt").prompt(input, opts)
    end)
    :catch(function(err)
      if err then
        vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
      end
    end)
end

---Select from all `opencode.nvim` functionality.
---
--- - Prompts
--- - Commands
--- - Server controls
---
--- Highlights and previews items when using `snacks.picker`.
---
---@param opts? opencode.select.Opts Override configured options for this call.
M.select = function(opts)
  return require("opencode.ui.select").select(opts):catch(function(err)
    if err then
      vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
    end
  end)
end

---Select the active `opencode` session.
M.select_session = function()
  return require("opencode.ui.select_session")
    .select_session()
    :next(function(result) ---@param result { session: opencode.server.Session, server: opencode.server.Server }
      result.server:select_session(result.session.id)
    end)
    :catch(function(err)
      if err then
        vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
      end
    end)
end

---Select an `opencode` server to connect to,
---sending future requests to it and subscribing to its events.
M.select_server = function()
  -- Should we also offer connected and configured server here?
  return require("opencode.server")
    .get_all()
    :next(function(servers) ---@param servers opencode.server.Server[]
      return require("opencode.ui.select_server").select_server(servers)
    end)
    :next(function(server) ---@param server opencode.server.Server
      require("opencode.events").connect(server)
      return server
    end)
    :catch(function(err)
      if err then
        vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
      end
    end)
end

M.statusline = require("opencode.status").statusline

------------------------
--- Programmatic API ---
------------------------

---Prompt `opencode`.
---
--- - Resolves `prompt` if it references an `opts.prompts` entry by name.
--- - Injects `opts.contexts` into `prompt`.
--- - `opencode` will interpret `@` references to files or subagents
---
---@param prompt string
---@param opts? opencode.api.prompt.Opts
M.prompt = function(prompt, opts)
  return require("opencode.api.prompt").prompt(prompt, opts):catch(function(err)
    if err then
      vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
    end
  end)
end

---Command `opencode`.
---
---@param command opencode.Command|string The command to send. Can be built-in or reference your custom commands.
M.command = function(command)
  require("opencode.api.command").command(command):catch(function(err)
    if err then
      vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
    end
  end)
end

---Execute a slash command in `opencode`.
---Discovers the active session and executes the command via HTTP API.
---
---@param command string The slash command to execute (e.g., "/agents", "/new")
---@param args? table<string, any> Arguments for the command
---@param opts? opencode.api.slash.Opts
---@return Promise
M.slash = function(command, args, opts)
  return require("opencode.api.slash").slash(command, args, opts):catch(function(err)
    if err then
      vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
    end
  end)
end

M.operator = require("opencode.api.operator").operator

----------------
--- Server ---
----------------

---Toggle the configured `opencode` server.
M.toggle = function()
  local opts = require("opencode.config").opts
  if opts.server and opts.server.toggle then
    opts.server.toggle()
  else
    vim.notify("No server `toggle` function configured", vim.log.levels.ERROR, { title = "opencode" })
  end
end
---Start the configured `opencode` server.
M.start = function()
  local opts = require("opencode.config").opts
  if opts.server and opts.server.start then
    opts.server.start()
  else
    vim.notify("No server `start` function configured", vim.log.levels.ERROR, { title = "opencode" })
  end
end
---Stop the configured `opencode` server.
M.stop = function()
  local opts = require("opencode.config").opts
  if opts.server and opts.server.stop then
    opts.server.stop()
  else
    vim.notify("No server `stop` function configured", vim.log.levels.ERROR, { title = "opencode" })
  end
end

--------------------
--- Integrations ---
--------------------

M.snacks_picker_send = require("opencode.integrations.pickers.snacks").send

----------------------
--- Public Pickers ---
----------------------

---Select an agent from available agents (from HTTP API).
---Displays agent info on selection.
M.select_agents = function()
  return require("opencode.ui.select_agents").select():catch(function(err)
    if err then
      vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
    end
  end)
end

---Select a skill from locally discovered skills.
---Displays skill info on selection, copies name to clipboard.
M.select_skills = function()
  return require("opencode.ui.select_skills").select():catch(function(err)
    if err then
      vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
    end
  end)
end

---Select a profile from available profiles.
---Set as global or current project profile on selection.
M.select_profile = function()
  return require("opencode.ui.select_profiles").select():catch(function(err)
    if err then
      vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
    end
  end)
end

---Get the currently active profile name (resolved with precedence).
---@return string
M.get_profile = function()
  return require("opencode.profiles").get_active_profile()
end

---Set the global profile.
---@param name string Profile name
M.set_profile_global = function(name)
  require("opencode.profiles").set_global_profile(name)
end

---Set the profile override for the current project.
---@param name string Profile name
M.set_profile_project = function(name)
  require("opencode.profiles").set_project_profile(name)
end

---Clear the profile override for the current project.
M.clear_profile_project = function()
  require("opencode.profiles").clear_project_profile()
end

---Get list of available profile names.
---@return string[]
M.list_profiles = function()
  return require("opencode.profiles").list_profiles()
end

---Get contexts for a specific profile.
---@param name string Profile name
---@return string[]
M.get_profile_contexts = function(name)
  return require("opencode.profiles").get_contexts(name)
end

---Select and execute a slash command (from HTTP API).
M.select_commands = function()
  return require("opencode.ui.select_commands").select():catch(function(err)
    if err then
      vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
    end
  end)
end

return M
