---Profile management for opencode.nvim
---Profiles are named sets of default contexts
local M = {}

local state = require("opencode.state")
local config = require("opencode.config")

---Get project key (git root or cwd fallback)
---@return string
function M.get_project_key()
  -- Try git root first
  local git_root = vim.fs.root(vim.fn.getcwd(), ".git")
  if git_root then
    return git_root
  end

  -- Fallback to cwd
  return vim.fn.getcwd()
end

---Get list of available profile names from config
---@return string[]
function M.list_profiles()
  local profiles_config = config.opts.profiles or {}
  local names = {}

  -- Always include "default"
  table.insert(names, "default")

  for name, _ in pairs(profiles_config) do
    if name ~= "default" then
      table.insert(names, name)
    end
  end

  -- Sort alphabetically
  table.sort(names)

  return names
end

---Check if a profile exists in config
---@param name string
---@return boolean
function M.profile_exists(name)
  if name == "default" then
    return true
  end

  local profiles_config = config.opts.profiles or {}
  return profiles_config[name] ~= nil
end

---Get contexts for a profile
---@param name string
---@return string[] contexts List of context placeholders (e.g., "@buffer", "@diagnostics")
function M.get_contexts(name)
  if name == "default" then
    return {}
  end

  local profiles_config = config.opts.profiles or {}
  local contexts = profiles_config[name]

  if type(contexts) ~= "table" then
    return {}
  end

  -- Ensure we return a copy
  return vim.deepcopy(contexts)
end

---Resolve the active profile with precedence:
---1. explicit (passed in opts)
---2. project override
---3. global profile
---4. "default" fallback
---@param opts? { explicit?: string }
---@return string profile_name
function M.resolve(opts)
  -- 1. Explicit profile
  if opts and opts.explicit and M.profile_exists(opts.explicit) then
    return opts.explicit
  end

  -- 2. Project override
  local project_key = M.get_project_key()
  local project_override = state.get_project_override(project_key)
  if project_override and M.profile_exists(project_override) then
    return project_override
  end

  -- 3. Global profile
  local global_profile = state.get_global_profile()
  if global_profile and M.profile_exists(global_profile) then
    return global_profile
  end

  -- 4. Default fallback
  return "default"
end

---Get description for a profile (derived from contexts)
---@param name string
---@return string
function M.get_description(name)
  local contexts = M.get_contexts(name)
  if #contexts == 0 then
    return "No default contexts"
  end
  return table.concat(contexts, ", ")
end

---Get the currently active profile name (resolved)
---@return string
function M.get_active_profile()
  return M.resolve()
end

---Get global profile
---@return string
function M.get_global_profile()
  return state.get_global_profile()
end

---Set global profile
---@param name string
function M.set_global_profile(name)
  if not M.profile_exists(name) then
    vim.notify("Profile '" .. name .. "' not found", vim.log.levels.WARN, { title = "opencode" })
    return
  end
  state.set_global_profile(name)
  vim.notify("Global profile set to: " .. name, vim.log.levels.INFO, { title = "opencode" })
end

---Get profile override for current project
---@return string|nil
function M.get_project_profile()
  local project_key = M.get_project_key()
  return state.get_project_override(project_key)
end

---Set profile override for current project
---@param name string
function M.set_project_profile(name)
  if not M.profile_exists(name) then
    vim.notify("Profile '" .. name .. "' not found", vim.log.levels.WARN, { title = "opencode" })
    return
  end
  local project_key = M.get_project_key()
  state.set_project_override(project_key, name)
  vim.notify("Project profile set to: " .. name, vim.log.levels.INFO, { title = "opencode" })
end

---Clear profile override for current project
function M.clear_project_profile()
  local project_key = M.get_project_key()
  local current = state.get_project_override(project_key)
  state.clear_project_override(project_key)
  if current then
    vim.notify("Project profile override cleared", vim.log.levels.INFO, { title = "opencode" })
  end
end

return M
