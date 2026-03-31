local M = {}

---Select a skill from locally discovered skills
---@return Promise
function M.select()
  local Promise = require("opencode.promise")
  
  -- Get skills synchronously (local filesystem, no HTTP)
  local ok, skills = pcall(function()
    return require("opencode.skills").list()
  end)
  
  if not ok then
    skills = {}
  end
  
  if #skills == 0 then
    vim.notify("No skills found in local directories", vim.log.levels.INFO, { title = "opencode" })
    return Promise.reject("No skills available")
  end
  
  ---@class opencode.select_skills.Item : snacks.picker.finder.Item
  ---@field skill opencode.Skill
  
  local items = {}
  
  -- Skills are already sorted by name from skills.list()
  for _, skill in ipairs(skills) do
    table.insert(items, {
      skill = skill,
      name = skill.name,
      text = skill.description or "",
      highlights = { { skill.description or "", "Comment" } },
      preview = {
        text = string.format(
          "Skill: %s\n\nSource: %s\nPath: %s\n\n%s",
          skill.name,
          skill.source,
          skill.path,
          skill.description or "No description"
        ),
      },
    })
  end
  
  ---@type snacks.picker.ui_select.Opts
  local select_opts = {
    prompt = "Select Skill: ",
    format_item = function(item, is_snacks)
      if is_snacks then
        local source_highlight = item.skill.source == "project" and "Title" or "Keyword"
        return {
          { "[" .. item.skill.source:sub(1, 1):upper() .. "] ", source_highlight },
          { item.name, "Normal" },
          { string.rep(" ", 20 - #item.name) },
          { item.skill.description or "", "Comment" },
        }
      else
        return string.format("[%s] %s%s  %s", item.skill.source:sub(1, 1):upper(), item.name, string.rep(" ", 20 - #item.name), item.skill.description or "")
      end
    end,
  }
  
  return Promise.select(items, select_opts)
    :next(function(choice) ---@param choice opencode.select_skills.Item
      vim.fn.setreg("+", choice.skill.name)
      vim.notify(
        string.format("Skill: %s\n\nSource: %s\nDescription: %s\n\nSkill name copied to clipboard.\nUse in prompts when skill syntax is defined.",
          choice.name,
          choice.skill.source,
          choice.skill.description or "No description"
        ),
        vim.log.levels.INFO,
        { title = "opencode" }
      )
      return choice.skill
    end)
    :catch(function(err)
      if err then
        vim.notify(err, vim.log.levels.WARN, { title = "opencode" })
      end
      return Promise.reject(err)
    end)
end

return M