---@class opencode.Skill
---@field name string Skill name (derived from directory or frontmatter)
---@field description string Short description from SKILL.md
---@field path string Full path to skill directory
---@field source string "global"|"project"|"superpowers"

local M = {}

---Get all skill directories to search, in priority order
---@return string[]
local function get_skill_directories()
  local dirs = {}
  
  -- Project-local skills (highest priority)
  local cwd = vim.fn.getcwd()
  table.insert(dirs, cwd .. "/.opencode/skills")
  
  -- User global skills
  local config_home = vim.fn.stdpath("config")
  table.insert(dirs, config_home .. "/skills")
  
  -- Superpowers skills (shared)
  local data_home = vim.fn.stdpath("data")
  table.insert(dirs, data_home .. "/opencode/skills/superpowers")
  
  return dirs
end

---Parse SKILL.md to extract name and description from frontmatter
---@param path string Path to SKILL.md
---@return { name: string?, description: string? }
local function parse_skill_md(path)
  local file = io.open(path, "r")
  if not file then
    return {}
  end
  
  local content = file:read("*a")
  file:close()
  
  local result = {}
  
  -- Extract name from frontmatter (name: or first heading)
  local name_match = content:match("^%-%-%-\n.-\nname:%s*(.-)\n")
  if name_match then
    result.name = vim.trim(name_match)
  end
  
  -- Extract description from frontmatter
  local desc_match = content:match("^%-%-%-\n.-\ndescription:%s*(.-)\n")
  if desc_match then
    result.description = vim.trim(desc_match)
  end
  
  -- Fallback: extract name from directory
  if not result.name then
    local dir_path = vim.fn.fnamemodify(path, ":h")
    result.name = vim.fn.fnamemodify(dir_path, ":t")
  end
  
  -- Fallback: use filename as description hint
  if not result.description then
    result.description = "Skill: " .. result.name
  end
  
  return result
end

---Discover all available skills from filesystem
---@return opencode.Skill[]
function M.list()
  local skills = {}
  local seen_names = {}
  local dirs = get_skill_directories()
  local sources = { "project", "global", "superpowers" }
  
  for i, dir in ipairs(dirs) do
    local source = sources[i] or "global"
    
    -- Check if directory exists
    if vim.fn.isdirectory(dir) == 1 then
      local subdirs = vim.fn.readdir(dir)
      
      for _, subdir in ipairs(subdirs) do
        local skill_path = dir .. "/" .. subdir
        local skill_md = skill_path .. "/SKILL.md"
        
        -- Only process directories with SKILL.md
        if vim.fn.filereadable(skill_md) == 1 then
          local parsed = parse_skill_md(skill_md)
          local name = parsed.name or subdir
          
          -- Deduplicate by name (project > superpowers > global)
          if not seen_names[name] then
            seen_names[name] = true
            table.insert(skills, {
              name = name,
              description = parsed.description or "",
              path = skill_path,
              source = source,
            })
          end
        end
      end
    end
  end
  
  -- Sort alphabetically by name
  table.sort(skills, function(a, b)
    return a.name < b.name
  end)
  
  return skills
end

return M