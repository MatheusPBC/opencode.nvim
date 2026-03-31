local M = {}

local Promise = require("opencode.promise")
local profiles = require("opencode.profiles")

---Select a profile and choose an action (set global, set project, clear project override)
---@return Promise
function M.select()
  local available_profiles = profiles.list_profiles()

  if #available_profiles == 0 then
    vim.notify("No profiles configured", vim.log.levels.INFO, { title = "opencode" })
    return Promise.reject("No profiles available")
  end

  local active_profile = profiles.get_active_profile()
  local project_override = profiles.get_project_profile()
  local global_profile = profiles.get_global_profile()

  ---@class opencode.select_profiles.Item : snacks.picker.finder.Item
  ---@field profile_name string
  ---@field is_active boolean
  ---@field is_project boolean

  local items = {}

  for _, profile_name in ipairs(available_profiles) do
    local contexts = profiles.get_contexts(profile_name)
    local is_active = profile_name == active_profile
    local is_project = profile_name == project_override

    local description = profiles.get_description(profile_name)

    -- Build status indicators
    local status = ""
    if is_project then
      status = " [PROJECT]"
    elseif profile_name == global_profile then
      status = " [GLOBAL]"
    end
    if is_active then
      status = status .. " ★"
    end

    table.insert(items, {
      profile_name = profile_name,
      name = profile_name,
      text = description .. status,
      is_active = is_active,
      is_project = is_project,
      highlights = { { description, "Comment" } },
      preview = {
        text = string.format(
          "Profile: %s\n\nContexts:\n%s\n\nActions:\n- <CR> Set as global profile\n- <C-p> Set as project profile override\n- <C-x> Clear project override",
          profile_name,
          #contexts > 0 and "  " .. table.concat(contexts, "\n  ") or "  (none)"
        ),
      },
    })
  end

  ---@type snacks.picker.ui_select.Opts
  local select_opts = {
    prompt = "Select Profile: ",
    format_item = function(item, is_snacks)
      if is_snacks then
        local hl = item.is_active and "Title" or "Keyword"
        local parts = {
          { item.name, hl },
          { string.rep(" ", 20 - #item.name) },
          { item.text, "Comment" },
        }
        return parts
      else
        local indicator = item.is_active and "★ " or "  "
        return indicator .. item.name .. string.rep(" ", 20 - #item.name) .. item.text
      end
    end,
  }

  return Promise.select(items, select_opts)
    :next(function(choice) ---@param choice opencode.select_profiles.Item
      -- Default action: set as global profile
      profiles.set_global_profile(choice.profile_name)
      return choice.profile_name
    end)
    :catch(function(err)
      if err then
        vim.notify(err, vim.log.levels.WARN, { title = "opencode" })
      end
      return Promise.reject(err)
    end)
end

---Set the selected profile as global
---@param profile_name string
function M.set_global(profile_name)
  profiles.set_global_profile(profile_name)
end

---Set the selected profile as project override
---@param profile_name string
function M.set_project(profile_name)
  profiles.set_project_profile(profile_name)
end

---Clear the project override
function M.clear_project()
  profiles.clear_project_profile()
end

return M
