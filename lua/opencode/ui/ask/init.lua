---@module 'snacks.input'

local M = {}

---@class opencode.ask.Opts
---
---Text of the prompt.
---@field prompt? string
---
---Options for [`snacks.input`](https://github.com/folke/snacks.nvim/blob/main/docs/input.md).
---@field snacks? snacks.input.Opts

local active_input_buf = nil
local active_input_win = nil

---Check if a snacks.input is currently active.
---@return boolean
function M.is_active()
  return active_input_buf ~= nil and vim.api.nvim_buf_is_valid(active_input_buf)
end

---Get the buffer number of the active input, if any.
---@return integer|nil
function M.get_buffer()
  if M.is_active() then
    return active_input_buf
  end
  return nil
end

---Insert text at the cursor position in the active input.
---Returns true if successful, false if no active input.
---@param text string
---@return boolean
function M.insert_text(text)
  if not M.is_active() then
    return false
  end

  local buf = active_input_buf
  local win = active_input_win

  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end

  local cursor = vim.api.nvim_win_get_cursor(win)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  if #lines == 0 then
    lines = { "" }
  end

  local line = lines[cursor[1]] or ""
  local col = cursor[2]

  local new_line = line:sub(1, col) .. text .. line:sub(col + 1)
  lines[cursor[1]] = new_line
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  vim.api.nvim_win_set_cursor(win, { cursor[1], col + #text })

  return true
end

---Open a new ask prompt with text pre-filled.
---@param text string Text to pre-fill.
---@param opts? opencode.ask.Opts
---@return Promise<string>
function M.ask_prefilled(text, opts)
  opts = opts or {}
  opts.prompt = text
  local context = require("opencode.context").new()
  return M.ask(text, context)
end

---Prompt for input with `vim.ui.input`, with context- and server-aware completion.
---
---@param default? string Text to pre-fill the input with.
---@param context opencode.Context
---@return Promise<string> input
function M.ask(default, context)
  local Promise = require("opencode.promise")

  return require("opencode.server")
    .get()
    :next(function(server) ---@param server opencode.server.Server
      ---@type snacks.input.Opts
      local input_opts = {
        default = default,
        highlight = function(text)
          local rendered = context:render(text, server.subagents)
          return context.input_highlight(rendered.input)
        end,
      }
      -- Nest `snacks.input` options under `opts.ask.snacks` for consistency with other `snacks`-exclusive config,
      -- and to keep its fields optional. Double-merge is kinda ugly but seems like the lesser evil.
      input_opts = vim.tbl_deep_extend("force", input_opts, require("opencode.config").opts.ask)
      input_opts = vim.tbl_deep_extend("force", input_opts, require("opencode.config").opts.ask.snacks)

      local original_on_submit = input_opts.on_submit
      input_opts.on_submit = function(value, opts_inner)
        active_input_buf = nil
        active_input_win = nil
        if original_on_submit then
          original_on_submit(value, opts_inner)
        end
      end

      local original_on_cancel = input_opts.on_cancel
      input_opts.on_cancel = function(opts_inner)
        active_input_buf = nil
        active_input_win = nil
        if original_on_cancel then
          original_on_cancel(opts_inner)
        end
      end

      return Promise.new(function(resolve, reject)
        Promise.input(input_opts)
          :next(function(result)
            resolve(result)
          end)
          :catch(function(err)
            reject(err)
          end)

        vim.schedule(function()
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            local buf = vim.api.nvim_win_get_buf(win)
            local bufname = vim.api.nvim_buf_get_name(buf)
            if bufname:match("snacks%.input") or vim.b[buf].snacks_input then
              active_input_buf = buf
              active_input_win = win
              break
            end
          end

          if not active_input_buf then
            for _, win in ipairs(vim.api.nvim_list_wins()) do
              local buf = vim.api.nvim_win_get_buf(win)
              local ft = vim.api.nvim_get_option_value("filetype", { buf = buf })
              local bt = vim.api.nvim_get_option_value("buftype", { buf = buf })
              if ft == "snacks_input" or bt == "prompt" then
                active_input_buf = buf
                active_input_win = win
                break
              end
            end
          end
        end)
      end)
    end)
    :catch(function(err)
      context:resume()
      return Promise.reject(err)
    end)
end

-- FIX: Overridden by blink.cmp cmdline completion if enabled, and that won't have the below items.
-- Can we wire up the below as a blink.cmp cmdline source?

---Completion function for context placeholders and `opencode` subagents.
---Must be a global variable for use with `vim.ui.select`.
---
---@param ArgLead string The text being completed.
---@param CmdLine string The entire current input line.
---@param CursorPos number The cursor position in the input line.
---@return table<string> items A list of filtered completion items.
_G.opencode_completion = function(ArgLead, CmdLine, CursorPos)
  -- Not sure if it's me or vim, but ArgLead = CmdLine... so we have to parse and complete the entire line, not just the last word.
  local start_idx, end_idx = CmdLine:find("([^%s]+)$")
  local latest_word = start_idx and CmdLine:sub(start_idx, end_idx) or nil

  local completions = {}
  for placeholder, _ in pairs(require("opencode.config").opts.contexts) do
    table.insert(completions, placeholder)
  end
  local server = require("opencode.events").connected_server
  local agents = server and server.subagents or {}
  for _, agent in ipairs(agents) do
    table.insert(completions, "@" .. agent.name)
  end

  local items = {}
  for _, completion in pairs(completions) do
    if not latest_word then
      local new_cmd = CmdLine .. completion
      table.insert(items, new_cmd)
    elseif completion:find(latest_word, 1, true) == 1 then
      local new_cmd = CmdLine:sub(1, start_idx - 1) .. completion .. CmdLine:sub(end_idx + 1)
      table.insert(items, new_cmd)
    end
  end
  return items
end

return M
