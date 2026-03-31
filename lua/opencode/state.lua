---State persistence for opencode.nvim
---Stores plugin state in stdpath("data") as JSON
local M = {}

---Get the state directory path
---@return string
local function get_state_dir()
  local data_dir = vim.fn.stdpath("data") .. "/opencode"
  if vim.fn.isdirectory(data_dir) == 0 then
    vim.fn.mkdir(data_dir, "p")
  end
  return data_dir
end

---Get the state file path
---@return string
local function get_state_file()
  return get_state_dir() .. "/profiles.json"
end

---Default state structure
---@type table
local default_state = {
  global_profile = "default",
  project_overrides = {},
}

---Load state from disk
---@return table
function M.load()
  local state_file = get_state_file()

  if vim.fn.filereadable(state_file) == 0 then
    return vim.deepcopy(default_state)
  end

  local ok, content = pcall(vim.fn.readfile, state_file)
  if not ok or #content == 0 then
    return vim.deepcopy(default_state)
  end

  local ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
  if not ok or type(data) ~= "table" then
    return vim.deepcopy(default_state)
  end

  -- Merge with defaults for forward compatibility
  return vim.tbl_deep_extend("force", default_state, data)
end

---Save state to disk
---@param data table
function M.save(data)
  local state_file = get_state_file()
  local ok, encoded = pcall(vim.json.encode, data)
  if not ok then
    vim.notify("Failed to encode opencode state", vim.log.levels.ERROR, { title = "opencode" })
    return
  end

  local ok, err = pcall(vim.fn.writefile, { encoded }, state_file)
  if not ok then
    vim.notify("Failed to save opencode state: " .. err, vim.log.levels.ERROR, { title = "opencode" })
  end
end

---Get global profile name
---@return string
function M.get_global_profile()
  local state = M.load()
  return state.global_profile or "default"
end

---Set global profile name
---@param name string
function M.set_global_profile(name)
  local state = M.load()
  state.global_profile = name
  M.save(state)
end

---Get project override for a project key
---@param project_key string
---@return string|nil
function M.get_project_override(project_key)
  local state = M.load()
  return state.project_overrides and state.project_overrides[project_key]
end

---Set project override for a project key
---@param project_key string
---@param name string
function M.set_project_override(project_key, name)
  local state = M.load()
  state.project_overrides = state.project_overrides or {}
  state.project_overrides[project_key] = name
  M.save(state)
end

---Clear project override for a project key
---@param project_key string
function M.clear_project_override(project_key)
  local state = M.load()
  if state.project_overrides then
    state.project_overrides[project_key] = nil
    M.save(state)
  end
end

return M
