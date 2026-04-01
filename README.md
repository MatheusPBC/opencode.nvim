# opencode.nvim

Integrate the [opencode](https://github.com/sst/opencode) AI assistant with Neovim — streamline editor-aware research, reviews, and requests.

<https://github.com/user-attachments/assets/077daa78-d401-4b8b-98d1-9ba9f94c2330>

## ✨ Features

- Connect to _any_ `opencode`, or provide an integrated instance
- Share editor context (buffer, selection, diagnostics, etc.)
- Input prompts with completions, highlights, and normal-mode support
- Select prompts from a library and define your own
- Execute commands
- Monitor and respond to events
- View, accept or reject, and reload edits
- Interact with `opencode` via an in-process LSP
- _Vim-y_ — supports ranges and dot-repeat
- Simple, sensible defaults to get you started quickly

### 🆕 Fork Features

- **Slash Commands**: Execute real slash commands (`/agents`, `/new`, etc.) via HTTP API
- **Agents Picker**: Browse and select agents from the `opencode` server
- **Skills Picker**: Discover locally available skills from project and global directories
- **Slash Commands Picker**: Browse and execute slash commands interactively
- **Context Profiles**: Named sets of default contexts with persistence (global + project-specific)
- **Completion for Slash Commands**: Auto-complete `/commands` in the input prompt

## 📦 Setup

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "nickjvandyke/opencode.nvim",
  version = "*", -- Latest stable release
  dependencies = {
    {
      -- `snacks.nvim` integration is recommended, but optional
      ---@module "snacks" <- Loads `snacks.nvim` types for configuration intellisense
      "folke/snacks.nvim",
      optional = true,
      opts = {
        input = {}, -- Enhances `ask()`
        picker = { -- Enhances `select()`
          actions = {
            opencode_send = function(...) return require("opencode").snacks_picker_send(...) end,
          },
          win = {
            input = {
              keys = {
                ["<a-a>"] = { "opencode_send", mode = { "n", "i" } },
              },
            },
          },
        },
      },
    },
  },
  config = function()
    ---@type opencode.Opts
    vim.g.opencode_opts = {
      -- Your configuration, if any; goto definition on the type or field for details
    }

    vim.o.autoread = true -- Required for `opts.events.reload`

    -- Recommended/example keymaps
    vim.keymap.set({ "n", "x" }, "<C-a>", function() require("opencode").ask("@this: ", { submit = true }) end, { desc = "Ask opencode…" })
    vim.keymap.set({ "n", "x" }, "<C-x>", function() require("opencode").select() end,                          { desc = "Execute opencode action…" })
    vim.keymap.set({ "n", "t" }, "<C-.>", function() require("opencode").toggle() end,                          { desc = "Toggle opencode" })

    vim.keymap.set({ "n", "x" }, "go",  function() return require("opencode").operator("@this ") end,        { desc = "Add range to opencode", expr = true })
    vim.keymap.set("n",          "goo", function() return require("opencode").operator("@this ") .. "_" end, { desc = "Add line to opencode", expr = true })

    vim.keymap.set("n", "<S-C-u>", function() require("opencode").command("session.half.page.up") end,   { desc = "Scroll opencode up" })
    vim.keymap.set("n", "<S-C-d>", function() require("opencode").command("session.half.page.down") end, { desc = "Scroll opencode down" })

    -- You may want these if you use the opinionated `<C-a>` and `<C-x>` keymaps above — otherwise consider `<leader>o…` (and remove terminal mode from the `toggle` keymap)
    vim.keymap.set("n", "+", "<C-a>", { desc = "Increment under cursor", noremap = true })
    vim.keymap.set("n", "-", "<C-x>", { desc = "Decrement under cursor", noremap = true })
  end,
}
```

### Configuration with Profiles

Profiles allow you to define named sets of default contexts that are automatically prepended to prompts:

```lua
---@type opencode.Opts
vim.g.opencode_opts = {
  profiles = {
    -- Default profile: no automatic contexts
    default = {},
    -- Code review profile: automatically include diff and diagnostics
    code_review = { "@diff", "@diagnostics" },
    -- Full context profile: include all relevant contexts
    full = { "@buffer", "@diagnostics", "@diff" },
  },
}
```

**Profile Precedence:**
1. Explicit profile passed to API
2. Project-specific override
3. Global profile
4. Default (empty contexts)

### [nixvim](https://github.com/nix-community/nixvim)

```nix
programs.nixvim = {
  extraPlugins = [
    pkgs.vimPlugins.opencode-nvim
  ];
};
```

> [!TIP]
> Run `:checkhealth opencode` after setup.

## ⚙️ Configuration

`opencode.nvim` provides a rich and reliable default experience — see all available options and their defaults [here](./lua/opencode/config.lua).

### Contexts

`opencode.nvim` replaces placeholders in prompts with the corresponding context:

| Placeholder    | Context                                                         |
| -------------- | --------------------------------------------------------------- |
| `@this`        | Operator range or visual selection if any, else cursor position |
| `@buffer`      | Current buffer                                                  |
| `@buffers`     | Open buffers                                                    |
| `@visible`     | Visible text                                                    |
| `@diagnostics` | Current buffer diagnostics                                      |
| `@quickfix`    | Quickfix list                                                   |
| `@diff`        | Git diff                                                        |
| `@marks`       | Global marks                                                    |
| `@grapple`     | [grapple.nvim](https://github.com/cbochs/grapple.nvim) tags     |

> [!TIP]
> `opencode` reads referenced files from disk — save your changes!

### Prompts

Select or reference prompts to review, explain, and improve your code:

| Name          | Prompt                                                                 |
| ------------- | ---------------------------------------------------------------------- |
| `diagnostics` | Explain `@diagnostics`                                                 |
| `diff`        | Review the following git diff for correctness and readability: `@diff` |
| `document`    | Add comments documenting `@this`                                       |
| `explain`     | Explain `@this` and its context                                        |
| `fix`         | Fix `@diagnostics`                                                     |
| `implement`   | Implement `@this`                                                      |
| `optimize`    | Optimize `@this` for performance and readability                       |
| `review`      | Review `@this` for correctness and readability                         |
| `test`        | Add tests for `@this`                                                  |

### Server

You can manually run `opencode`s however you like and `opencode.nvim` will find them!

> [!IMPORTANT]
> You _must_ run `opencode` with the `--port` flag to expose its server.

If `opencode.nvim` can't find an existing `opencode`, it uses the configured server to start one for you, defaulting to an embedded terminal.

#### Keymaps

`opencode.nvim` sets these normal-mode keymaps in the embedded terminal for Neovim-like message navigation:

| Keymap  | Command                  | Description           |
| ------- | ------------------------ | --------------------- |
| `<C-u>` | `session.half.page.up`   | Scroll up half page   |
| `<C-d>` | `session.half.page.down` | Scroll down half page |
| `gg`    | `session.first`          | Go to first message   |
| `G`     | `session.last`           | Go to last message    |
| `<Esc>` | `session.interrupt`      | Interrupt             |

#### Customization

Example using [`snacks.terminal`](https://github.com/folke/snacks.nvim/blob/main/docs/terminal.md) instead:

```lua
local opencode_cmd = 'opencode --port'
---@type snacks.terminal.Opts
local snacks_terminal_opts = {
  win = {
    position = 'right',
    enter = false,
    on_win = function(win)
      -- Set up keymaps and cleanup for an arbitrary terminal
      require('opencode.terminal').setup(win.win)
    end,
  },
}
---@type opencode.Opts
vim.g.opencode_opts = {
  server = {
    start = function()
      require('snacks.terminal').open(opencode_cmd, snacks_terminal_opts)
    end,
    stop = function()
      require('snacks.terminal').get(opencode_cmd, snacks_terminal_opts):close()
    end,
    toggle = function()
      require('snacks.terminal').toggle(opencode_cmd, snacks_terminal_opts)
    end,
  },
}
```

## 🚀 Usage

### Ask — `require("opencode").ask()`

Input a prompt for `opencode`.

- Press `<Up>` to browse recent asks.
- Highlights and completes contexts and `opencode` subagents.
  - Press `<Tab>` to trigger built-in completion.
- End the prompt with `\n` to append instead of submit.
- Additionally, when using `snacks.input`:
  - Press `<S-CR>` to append instead of submit.
  - Offers completions via in-process LSP.

### Select — `require("opencode").select()`

Select from all `opencode.nvim` functionality.

- Prompts
- Commands
- Server controls
- **Agents** (from HTTP API)
- **Skills** (from local filesystem)
- **Slash Commands** (from HTTP API)
- **Profiles** (context presets)

Highlights and previews items when using `snacks.picker`.

### Prompt — `require("opencode").prompt()`

Prompt `opencode`.

- Resolves named references to configured prompts.
- Injects configured contexts.
- `opencode` will interpret `@` references to files or subagents.
- **Auto-prepends active profile contexts** (if configured).

### Operator — `require("opencode").operator()`

Wraps `prompt` as an operator, supporting ranges and dot-repeat.

### Command — `require("opencode").command()`

Command `opencode`:

| Command                  | Description                                        |
| ------------------------ | -------------------------------------------------- |
| `session.list`           | List sessions                                      |
| `session.new`            | Start a new session                                |
| `session.select`         | Select a session                                   |
| `session.share`          | Share the current session                          |
| `session.interrupt`      | Interrupt the current session                      |
| `session.compact`        | Compact the current session (reduce context size)  |
| `session.page.up`        | Scroll messages up by one page                     |
| `session.page.down`      | Scroll messages down by one page                   |
| `session.half.page.up`   | Scroll messages up by half a page                  |
| `session.half.page.down` | Scroll messages down by half a page                |
| `session.first`          | Jump to the first message in the session           |
| `session.last`           | Jump to the last message in the session            |
| `session.undo`           | Undo the last action in the current session        |
| `session.redo`           | Redo the last undone action in the current session |
| `prompt.submit`          | Submit the TUI input                               |
| `prompt.clear`           | Clear the TUI input                                |
| `agent.cycle`            | Cycle the selected agent                           |

---

## 🆕 Fork API Reference

### Slash Commands — `require("opencode").slash()`

Execute real slash commands via HTTP API:

```lua
-- Execute a slash command
require("opencode").slash("/new")
require("opencode").slash("/agents", { arg = "value" })

-- Available slash commands depend on your `opencode` configuration
```

**Note:** Slash commands starting with `/` in the input prompt are automatically detected and routed to this API.

### Agents Picker — `require("opencode").select_agents()`

Browse and select agents from the connected `opencode` server:

```lua
require("opencode").select_agents()
-- On selection:
-- - If input is active: inserts "@AgentName " at cursor
-- - If input is inactive: opens new input pre-filled with "@AgentName "
```

### Skills Picker — `require("opencode").select_skills()`

Browse locally discovered skills from project and global directories:

```lua
require("opencode").select_skills()
-- On selection: copies skill name to clipboard and shows info notification
```

**Note:** Skills are discovered from `.opencode/skills/` directories. There is no canonical skill syntax yet — skills currently operate in "safe mode" (info + clipboard).

### Slash Commands Picker — `require("opencode").select_commands()`

Browse and execute slash commands interactively:

```lua
require("opencode").select_commands()
-- On selection: executes the selected slash command
```

### Profiles API — Context Presets

Manage context profiles with persistence:

```lua
local opencode = require("opencode")

-- Open profile picker
opencode.select_profile()

-- Get current active profile (resolved with precedence)
opencode.get_profile()

-- Get list of available profile names
opencode.list_profiles()

-- Get contexts for a specific profile
opencode.get_profile_contexts("code_review")

-- Set global profile (persists across sessions)
opencode.set_profile_global("code_review")

-- Set project-specific profile override
opencode.set_profile_project("full")

-- Clear project override (falls back to global)
opencode.clear_profile_project()
```

**Profile Resolution Precedence:**
1. Explicit profile passed to API
2. Project-specific override
3. Global profile
4. Default (no contexts)

**Persistence:** Profile settings are stored in `stdpath("data")/opencode/profiles.json`.

### LSP

> [!WARNING]
> This feature is experimental! Try it out with `vim.g.opencode_opts.lsp.enabled = true`.

`opencode.nvim` provides an in-process LSP to interact with `opencode` via the LSP functions you're used to!

| LSP Function | `opencode.nvim` Handler                                                |
| ------------ | ---------------------------------------------------------------------- |
| Hover        | Asks `opencode` for a brief explanation of the symbol under the cursor |
| Code Actions | Asks `opencode` to explain or fix diagnostics under the cursor         |

## 👀 Events

`opencode.nvim` forwards `opencode`'s Server-Sent-Events as an `OpencodeEvent` autocmd:

```lua
-- Handle `opencode` events
vim.api.nvim_create_autocmd("User", {
  pattern = "OpencodeEvent:*", -- Optionally filter event types
  callback = function(args)
    ---@type opencode.server.Event
    local event = args.data.event
    ---@type number
    local port = args.data.port

    -- See the available event types and their properties
    vim.notify(vim.inspect(event))
    -- Do something useful
    if event.type == "session.idle" then
      vim.notify("`opencode` finished responding")
    end
  end,
})
```

### Edits

When `opencode` edits a file, `opencode.nvim` automatically reloads the corresponding buffer.

### Permissions

When `opencode` requests a permission, `opencode.nvim` waits for idle to ask you to approve or deny it.

#### Edits

For edit requests, `opencode.nvim` opens the target file in a new tab and uses Neovim's `:diffpatch` to display the proposed changes side-by-side. See `:h 'diffopt'` for customization.

| Keymap  | Function                                                                      |
| ------- | ----------------------------------------------------------------------------- |
| `da`    | Accept the entire edit request                                                |
| `dr`    | Reject the entire edit request                                                |
| `]c/[c` | Next/prev change                                                              |
| `dp`    | Natively accept _only_ the hunk under the cursor, and reject the edit request |
| `do`    | Natively reject _only_ the hunk under the cursor, and reject the edit request |
| `q`     | Close the diff                                                                |

### Statusline

```lua
require("lualine").setup({
  sections = {
    lualine_z = {
      {
        require("opencode").statusline,
      },
    }
  }
})
```

## 🙏 Acknowledgments

- Inspired by [nvim-aider](https://github.com/GeorgesAlkhouri/nvim-aider), [neopencode.nvim](https://github.com/loukotal/neopencode.nvim), and [sidekick.nvim](https://github.com/folke/sidekick.nvim).
- Uses `opencode`'s TUI for simplicity — see [sudo-tee/opencode.nvim](https://github.com/sudo-tee/opencode.nvim) for a Neovim frontend.
- [mcp-neovim-server](https://github.com/bigcodegen/mcp-neovim-server) may better suit you, but it lacks customization and tool calls are slow and unreliable.

---

## ⚠️ Known Limitations

| Feature | Limitation |
| ------- | ---------- |
| **Agents** | Inserted as `@AgentName` in input — no canonical skill syntax for automatic invocation |
| **Skills** | No canonical syntax yet; operates in safe mode (info notification + clipboard) |
| **Slash Commands** | Only recognized when input starts with `/`; rely on HTTP API |
| **Profiles** | Project identification uses git root (fallback to cwd); picker selection currently sets the global profile only |
| **Completion** | Slash command completion requires active `opencode` server connection |

---

## ⌨️ Suggested Keymaps

Add these keymaps to your configuration for quick access to fork features:

```lua
local opencode = require("opencode")

-- Main menu (includes all pickers)
vim.keymap.set("n", "<leader>o", function() opencode.select() end, { desc = "opencode: Main menu" })

-- Fork-specific pickers
vim.keymap.set("n", "<leader>oa", function() opencode.select_agents() end, { desc = "opencode: Select agent" })
vim.keymap.set("n", "<leader>os", function() opencode.select_skills() end, { desc = "opencode: Select skill" })
vim.keymap.set("n", "<leader>oc", function() opencode.select_commands() end, { desc = "opencode: Select slash command" })
vim.keymap.set("n", "<leader>op", function() opencode.select_profile() end, { desc = "opencode: Select profile" })

-- Profile management
vim.keymap.set("n", "<leader>opg", function() opencode.set_profile_global("code_review") end, { desc = "opencode: Set global profile to 'code_review'" })
vim.keymap.set("n", "<leader>opp", function() opencode.set_profile_project("full") end, { desc = "opencode: Set project profile to 'full'" })
vim.keymap.set("n", "<leader>opc", function() opencode.clear_profile_project() end, { desc = "opencode: Clear project profile override" })

-- Quick slash commands
vim.keymap.set("n", "<leader>on", function() opencode.slash("/new") end, { desc = "opencode: New session" })
vim.keymap.set("n", "<leader>oA", function() opencode.slash("/agents") end, { desc = "opencode: List agents" })
```

---

## 🔌 OpenCode MCP Integration

OpenCode is a **terminal-first AI coding agent** that can connect to external tools via MCP (Model Context Protocol). This plugin provides an MCP server that allows OpenCode to control Neovim directly.

### Overview

When you run OpenCode inside Neovim's terminal, the plugin can:
1. **Automatically inject** the `OPENCODE_NVIM_RPC` environment variable with Neovim's RPC socket path
2. **Register the MCP server** script with OpenCode so it can send commands back to your editor

This creates a **terminal-first workflow** where OpenCode runs in Neovim's terminal but can still open files, navigate to specific locations, and show pickers when the AI needs user input.

### How It Works

```
┌─────────────────────┐
│  Neovim             │
│  ┌───────────────┐  │
│  │ opencode.nvim │  │
│  │  (plugin)     │  │
│  └───────┬───────┘  │
│          │ RPC      │
│          ▼          │
│  ┌───────────────┐  │
│  │ MCP Server    │◄────── stdio (JSON-RPC)
│  │ (script)       │  │
│  └───────────────┘  │
└─────────────────────┘
         ▲
         │ communicates via
         │ OPENCODE_NVIM_RPC
         │
┌─────────────────────┐
│  OpenCode TUI       │
│  (in :terminal)     │
└─────────────────────┘
```

### Configuration

Add the MCP server to your OpenCode configuration (`opencode.json`):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "opencode-nvim": {
      "type": "local",
      "command": ["nvim", "--headless", "-u", "NONE", "-l", "<SCRIPT_PATH>"],
      "enabled": true,
      "environment": {}
    }
  }
}
```

**Finding the script path:**

1. **From Lua**: Use `require("opencode").mcp_server_script()` to get the absolute path:
   ```lua
   :lua print(require("opencode").mcp_server_script())
   ```

2. **Manual discovery**: The script is located at:
   ```
   <plugin-path>/scripts/mcp/opencode_nvim_mcp.lua
   ```

**Getting the RPC socket:**

If you need the RPC socket path manually:
```lua
:lua print(require("opencode").rpc_socket())
```

### Automatic Injection

When OpenCode is launched from Neovim's terminal (`:terminal opencode`), the plugin automatically:
1. Detects current Neovim instance's RPC socket
2. Sets `OPENCODE_NVIM_RPC` environment variable
3. The MCP server script reads this variable to connect back

**Note:** The environment variable is only set when OpenCode is started from within Neovim's terminal. For external terminals, you'll need to set it manually.

### Available Tools

Once configured, OpenCode can use these MCP tools:

#### `open_file`

Open a single file in Neovim at a specific location.

```json
{
  "path": "/absolute/path/to/file.lua",
  "line": 42,
  "col": 10
}
```

- **Use when:** There's a single, clear target file and explicit intent to open/navigate
- **Behavior:** Opens file in a new tab, moves cursor to specified line/column

#### `open_candidates`

Show a picker with multiple file candidates.

```json
{
  "candidates": [
    { "path": "/path/to/file1.lua", "label": "Main handler" },
    { "path": "/path/to/file2.lua", "line": 15, "label": "Helper function" }
  ],
  "prompt": "Select a file to open"
}
```

- **Use when:** There's ambiguity or multiple reasonable targets
- **Behavior:** Opens a vim.ui.select picker, user chooses which file to open

### Usage Rule

> **Important:** The AI model should only call these tools when explicitly asked to open files or navigate. They should not be called proactively during regular coding tasks.

### Example Prompts

```
Open the configuration file at /etc/config.json
```
→ OpenCode calls `open_file` directly

```
Where is the authentication logic? Show me the options.
```
→ OpenCode calls `open_candidates` with relevant files

```
Fix the bug in src/auth.lua at line 50
```
→ OpenCode calls `open_file` to show the location

---

## 🧪 Smoke Tests / Manual Checklist

Use this checklist to verify functionality after setup:

### Basic Functionality
- [ ] `:lua require("opencode").ask()` opens input prompt
- [ ] `:lua require("opencode").select()` opens main menu
- [ ] `:lua require("opencode").toggle()` toggles opencode terminal

### Slash Commands
- [ ] `:lua require("opencode").slash("/new")` executes slash command
- [ ] `:lua require("opencode").select_commands()` opens slash command picker
- [ ] Typing `/new` in ask prompt routes to slash command API

### Agents
- [ ] `:lua require("opencode").select_agents()` opens agents picker
- [ ] Selecting agent with active input inserts `@AgentName `
- [ ] Selecting agent without active input opens pre-filled ask()

### Skills
- [ ] `:lua require("opencode").select_skills()` opens skills picker
- [ ] Selecting skill shows info notification
- [ ] Skill name copied to clipboard

### Profiles
- [ ] `:lua require("opencode").select_profile()` opens profile picker
- [ ] `:lua require("opencode").list_profiles()` returns table of profile names
- [ ] `:lua require("opencode").get_profile()` returns active profile name
- [ ] Setting global profile persists across Neovim restarts
- [ ] Setting project profile persists across Neovim restarts
- [ ] Project profile takes precedence over global profile
- [ ] Clearing project override falls back to global profile

### Completion
- [ ] Context placeholders (`@buffer`, `@this`, etc.) appear in completion
- [ ] Agent names (`@AgentName`) appear in completion
- [ ] Slash commands (`/new`, `/agents`) appear when typing `/` in input

### MCP Integration
- [ ] `:lua print(require("opencode").rpc_socket())` prints a valid socket path
- [ ] `:lua print(require("opencode").mcp_server_script())` prints the script path
- [ ] MCP script exists at returned path
- [ ] OpenCode started from Neovim's terminal has `OPENCODE_NVIM_RPC` environment variable set
- [ ] MCP tools (`open_file`, `open_candidates`) are available in OpenCode when configured

---

## 📝 Changelog

See [CHANGELOG.md](./CHANGELOG.md) for release history.
