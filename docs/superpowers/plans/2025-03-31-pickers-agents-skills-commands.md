# Pickers para Agents, Skills e Slash Commands - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar pickers funcionais para agents, skills e slash commands, integrando ao fluxo principal do plugin opencode.nvim.

**Architecture:** Três novos pickers dedicados + módulo de descoberta local de skills. Integração via sections no picker principal existente. Skills descobertas via filesystem; agents e commands via HTTP API.

**Tech Stack:** Lua, Neovim API, Promise pattern (existente), snacks.picker (existente)

---

## File Structure

### New Files
- `lua/opencode/skills.lua` - Descoberta local de skills via filesystem
- `lua/opencode/ui/select_agents.lua` - Picker de agents via HTTP
- `lua/opencode/ui/select_skills.lua` - Picker de skills locais
- `lua/opencode/ui/select_commands.lua` - Picker de slash commands via HTTP

### Modified Files
- `lua/opencode/ui/select.lua` - Adicionar sections: agents, skills, slash_commands
- `lua/opencode.lua` - Adicionar APIs públicas: select_agents(), select_skills(), select_commands()
- `lua/opencode/config.lua` - Adicionar defaults para novas sections

---

## Task 1: Módulo de Descoberta de Skills

**Files:**
- Create: `lua/opencode/skills.lua`

- [ ] **Step 1: Criar módulo skills.lua com estrutura base**

```lua
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
```

- [ ] **Step 2: Validar sintaxe Lua**

Run: `luac -p /home/matheus/Documentos/vscode/opencode-nvim-fork/lua/opencode/skills.lua`
Expected: No output (success)

- [ ] **Step 3: Commit inicial do módulo skills**

```bash
cd /home/matheus/Documentos/vscode/opencode-nvim-fork
git add lua/opencode/skills.lua
git commit -m "feat: add local skills discovery module"
```

---

## Task 2: Picker de Agents

**Files:**
- Create: `lua/opencode/ui/select_agents.lua`

- [ ] **Step 1: Criar picker de agents usando API HTTP existente**

```lua
local M = {}

---Select an agent from available agents via HTTP API
---@return Promise
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
              { item.description or "", "Comment" },
            }
          else
            local mode_indicator = item.agent.mode == "primary" and "[P]" or "[S]"
            return string.format("%s %s%s  %s", mode_indicator, item.name, string.rep(" ", 20 - #item.name), item.description or "")
          end
        end,
      }
      
      return Promise.select(items, select_opts)
    end)
    :next(function(choice) ---@param choice opencode.select_agents.Item
      -- For Part 2: just display info, no automatic action
      -- Future Part 3: could set agent or inject context
      vim.notify(
        string.format("Agent selected: %s\n\n%s", choice.agent.name, choice.agent.description or "No description"),
        vim.log.levels.INFO,
        { title = "opencode" }
      )
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
```

- [ ] **Step 2: Validar sintaxe Lua**

Run: `luac -p /home/matheus/Documentos/vscode/opencode-nvim-fork/lua/opencode/ui/select_agents.lua`
Expected: No output (success)

- [ ] **Step 3: Commit do picker de agents**

```bash
cd /home/matheus/Documentos/vscode/opencode-nvim-fork
git add lua/opencode/ui/select_agents.lua
git commit -m "feat: add agent picker via HTTP API"
```

---

## Task 3: Picker de Slash Commands

**Files:**
- Create: `lua/opencode/ui/select_commands.lua`

- [ ] **Step 1: Criar picker de slash commands usando API HTTP existente**

```lua
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
              { item.description or "", "Comment" },
            }
          else
            return string.format("%s%s  %s", item.name, string.rep(" ", 25 - #item.name), item.description or "")
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
```

- [ ] **Step 2: Validar sintaxe Lua**

Run: `luac -p /home/matheus/Documentos/vscode/opencode-nvim-fork/lua/opencode/ui/select_commands.lua`
Expected: No output (success)

- [ ] **Step 3: Commit do picker de commands**

```bash
cd /home/matheus/Documentos/vscode/opencode-nvim-fork
git add lua/opencode/ui/select_commands.lua
git commit -m "feat: add slash command picker with execution"
```

---

## Task 4: Picker de Skills

**Files:**
- Create: `lua/opencode/ui/select_skills.lua`

- [ ] **Step 1: Criar picker de skills usando descoberta local**

```lua
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
        local source_highlight = item.source == "project" and "Title" or "Keyword"
        return {
          { "[" .. item.source:sub(1, 1):upper() .. "] ", source_highlight },
          { item.name, "Normal" },
          { string.rep(" ", 20 - #item.name) },
          { item.description or "", "Comment" },
        }
      else
        return string.format("[%s] %s%s  %s", item.source:sub(1, 1):upper(), item.name, string.rep(" ", 20 - #item.name), item.description or "")
      end
    end,
  }
  
  return Promise.select(items, select_opts)
    :next(function(choice) ---@param choice opencode.select_skills.Item
      -- For Part 2: just display info and copy name to clipboard
      -- Future Part 3: could insert @[skill:...] into input
      vim.fn.setreg("+", choice.skill.name)
      vim.notify(
        string.format("Skill: %s\n\nSource: %s\nPath: %s\n\nName copied to clipboard.\nSkill execution available in Part 3.",
          choice.skill.name,
          choice.source,
          choice.skill.path
        ),
        vim.log.levels.INFO,
        { title = "opencode" }
      )
      return choice.skill
    end)
    :catch(function(err)
      if err then
        -- Error already handled above, just propagate
      end
      return Promise.reject(err)
    end)
end

return M
```

- [ ] **Step 2: Validar sintaxe Lua**

Run: `luac -p /home/matheus/Documentos/vscode/opencode-nvim-fork/lua/opencode/ui/select_skills.lua`
Expected: No output (success)

- [ ] **Step 3: Commit do picker de skills**

```bash
cd /home/matheus/Documentos/vscode/opencode-nvim-fork
git add lua/opencode/ui/select_skills.lua
git commit -m "feat: add local skill picker with info display"
```

---

## Task 5: Integrar Pickers ao Menu Principal

**Files:**
- Modify: `lua/opencode/ui/select.lua`

- [ ] **Step 1: Adicionar sections para agents, skills e commands no select.lua**

Localize a seção de configuração (linhas 5-20) e adicione os novos campos de tipo:

```lua
---@class opencode.select.sections.Opts
---
---Whether to show the prompts section.
---@field prompts? boolean
---
---Commands to display, and their descriptions.
---Or `false` to hide the commands section.
---@field commands? table<opencode.Command|string, string>|false
---
---@field server? boolean Whether to show server controls.
---
---Whether to show the agents section (from HTTP API).
---@field agents? boolean
---
---Whether to show the skills section (from local filesystem).
---@field skills? boolean
---
---Whether to show the slash commands section (from HTTP API).
---@field slash_commands? boolean
```

- [ ] **Step 2: Adicionar tratamento dos novos tipos no select.lua**

Localize a função `M.select(opts)` e adicione após a seção "Commands" (aproximadamente linha 100):

```lua
      -- Agents section
      if opts.sections.agents then
        table.insert(items, { __group = true, name = "AGENTS", preview = { text = "" } })
        -- Agents will be fetched on-demand when this section is expanded
        -- For now, show a single entry that triggers the agent picker
        table.insert(items, {
          __type = "agent",
          name = "agents.select",
          text = "Select an agent",
          highlights = { { "Select an agent", "Comment" } },
          preview = { text = "Browse and select from available agents (primary and subagents)" },
        })
      end

      -- Skills section
      if opts.sections.skills then
        table.insert(items, { __group = true, name = "SKILLS", preview = { text = "" } })
        table.insert(items, {
          __type = "skill",
          name = "skills.select",
          text = "Select a skill",
          highlights = { { "Select a skill", "Comment" } },
          preview = { text = "Browse locally discovered skills from project and global directories" },
        })
      end

      -- Slash Commands section
      if opts.sections.slash_commands then
        table.insert(items, { __group = true, name = "COMMANDS", preview = { text = "" } })
        table.insert(items, {
          __type = "slash_command",
          name = "commands.select",
          text = "Select a slash command",
          highlights = { { "Select a slash command", "Comment" } },
          preview = { text = "Browse and execute slash commands (/agents, /new, etc.)" },
        })
      end
```

- [ ] **Step 3: Adicionar handlers para os novos tipos no select.lua**

Localize a seção de handlers (após linha 176) e adicione antes do `else` final:

```lua
      elseif choice.__type == "agent" then
        return require("opencode").select_agents()
      elseif choice.__type == "skill" then
        return require("opencode").select_skills()
      elseif choice.__type == "slash_command" then
        return require("opencode").select_commands()
```

- [ ] **Step 4: Validar sintaxe Lua do arquivo modificado**

Run: `luac -p /home/matheus/Documentos/vscode/opencode-nvim-fork/lua/opencode/ui/select.lua`
Expected: No output (success)

- [ ] **Step 5: Commit da integração**

```bash
cd /home/matheus/Documentos/vscode/opencode-nvim-fork
git add lua/opencode/ui/select.lua
git commit -m "feat: integrate agents, skills, and slash commands into main picker"
```

---

## Task 6: Adicionar APIs Públicas

**Files:**
- Modify: `lua/opencode.lua`

- [ ] **Step 1: Adicionar funções públicas para os novos pickers em opencode.lua**

Localize o final do arquivo (antes do `return M`, aproximadamente linha 185) e adicione:

```lua
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

---Select and execute a slash command (from HTTP API).
M.select_commands = function()
  return require("opencode.ui.select_commands").select():catch(function(err)
    if err then
      vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
    end
  end)
end
```

- [ ] **Step 2: Validar sintaxe Lua**

Run: `luac -p /home/matheus/Documentos/vscode/opencode-nvim-fork/lua/opencode.lua`
Expected: No output (success)

- [ ] **Step 3: Commit das APIs públicas**

```bash
cd /home/matheus/Documentos/vscode/opencode-nvim-fork
git add lua/opencode.lua
git commit -m "feat: add public APIs for select_agents, select_skills, select_commands"
```

---

## Task 7: Atualizar Config Defaults

**Files:**
- Modify: `lua/opencode/config.lua`

- [ ] **Step 1: Adicionar defaults das novas sections em config.lua**

Localize a tabela `select` (aproximadamente linha 130) e adicione os novos campos:

```lua
  select = {
    prompt = "opencode: ",
    sections = {
      prompts = true,
      commands = {
        ["session.new"] = "Start a new session",
        ["session.select"] = "Select a session",
        ["session.share"] = "Share the current session",
        ["session.interrupt"] = "Interrupt the current session",
        ["session.compact"] = "Compact the current session (reduce context size)",
        ["session.undo"] = "Undo the last action in the current session",
        ["session.redo"] = "Redo the last undone action in the current session",
        ["agent.cycle"] = "Cycle the selected agent",
        ["prompt.submit"] = "Submit the current prompt",
        ["prompt.clear"] = "Clear the current prompt",
      },
      server = true,
      agents = true,      -- NEW: Show agents section
      skills = true,      -- NEW: Show skills section
      slash_commands = true, -- NEW: Show slash commands section
    },
    snacks = {
      preview = "preview",
      layout = {
        preset = "vscode",
        hidden = {},
      },
    },
  },
```

- [ ] **Step 2: Atualizar o tipo opencode.select.Opts no topo do arquivo**

Localize a definição do tipo (após linha 5) e adicione:

```lua
---@class opencode.select.Opts : snacks.picker.ui_select.Opts
---
---Configure the displayed sections.
---@field sections? opencode.select.sections.Opts
```

(O resto permanece igual)

- [ ] **Step 3: Validar sintaxe Lua**

Run: `luac -p /home/matheus/Documentos/vscode/opencode-nvim-fork/lua/opencode/config.lua`
Expected: No output (success)

- [ ] **Step 4: Commit das configurações**

```bash
cd /home/matheus/Documentos/vscode/opencode-nvim-fork
git add lua/opencode/config.lua
git commit -m "feat: add default config for agents, skills, slash_commands sections"
```

---

## Task 8: Validação Final e Teste

- [ ] **Step 1: Executar validação de sintaxe em todos os arquivos criados/modificados**

Run: `luac -p /home/matheus/Documentos/vscode/opencode-nvim-fork/lua/opencode/skills.lua`
Run: `luac -p /home/matheus/Documentos/vscode/opencode-nvim-fork/lua/opencode/ui/select_agents.lua`
Run: `luac -p /home/matheus/Documentos/vscode/opencode-nvim-fork/lua/opencode/ui/select_commands.lua`
Run: `luac -p /home/matheus/Documentos/vscode/opencode-nvim-fork/lua/opencode/ui/select_skills.lua`
Run: `luac -p /home/matheus/Documentos/vscode/opencode-nvim-fork/lua/opencode/ui/select.lua`
Run: `luac -p /home/matheus/Documentos/vscode/opencode-nvim-fork/lua/opencode.lua`
Run: `luac -p /home/matheus/Documentos/vscode/opencode-nvim-fork/lua/opencode/config.lua`

Expected: No output for all (success)

- [ ] **Step 2: Verificar se stylua está disponível e rodar formatação**

Run: `which stylua && stylua --check /home/matheus/Documentos/vscode/opencode-nvim-fork/lua/ || echo "stylua not available, skipping format check"`

- [ ] **Step 3: Criar commit final com todas as alterações**

```bash
cd /home/matheus/Documentos/vscode/opencode-nvim-fork
git add -A
git status
```

Verifique se apenas os arquivos esperados estão staged. Se sim:

```bash
cd /home/matheus/Documentos/vscode/opencode-nvim-fork
git commit -m "feat: add pickers for agents, skills, and slash commands

- Add local skills discovery module (lua/opencode/skills.lua)
- Add agent picker via HTTP API
- Add slash command picker with execution
- Add skill picker with info display
- Integrate all pickers into main select menu
- Add public APIs: select_agents(), select_skills(), select_commands()
- Update config defaults for new sections"
```

---

## Summary

**Files Created:**
- `lua/opencode/skills.lua` - Skills discovery module
- `lua/opencode/ui/select_agents.lua` - Agent picker
- `lua/opencode/ui/select_skills.lua` - Skill picker
- `lua/opencode/ui/select_commands.lua` - Slash command picker

**Files Modified:**
- `lua/opencode/ui/select.lua` - Added new sections
- `lua/opencode.lua` - Added public APIs
- `lua/opencode/config.lua` - Added defaults

**Limitations for Part 3:**
- Skills: Only display/copy name, no @[skill:...] insertion
- Agents: Only display info, no automatic agent selection
- No input/completion integration yet