---Editor actions for MCP integration.
---Provides functions to open files and selections in the current Neovim instance.
---These are invoked by the MCP server via RPC.
local M = {}

---@class opencode.editor_actions.open_file.Opts
---@field path string Absolute path to the file (required)
---@field line? integer Line number (1-based, optional)
---@field col? integer Column number (1-based, optional)

---@class opencode.editor_actions.open_candidates.Candidate
---@field path string Absolute path to the file (required)
---@field line? integer Line number (1-based, optional)
---@field col? integer Column number (1-based, optional)
---@field label? string Display label for the picker (optional)

---@class opencode.editor_actions.open_candidates.Opts
---@field candidates opencode.editor_actions.open_candidates.Candidate[] List of candidates (required)

---Check if a path is absolute.
---Handles both Unix (/) and Windows (X:\) absolute paths.
---@param path string Path to check
---@return boolean is_absolute True if the path is absolute
local function is_absolute_path(path)
  if not path or path == "" then
    return false
  end
  -- Unix absolute path
  if path:sub(1, 1) == "/" then
    return true
  end
  -- Windows absolute path (e.g., C:\)
  if path:match("^[A-Za-z]:[\\/]") then
    return true
  end
  return false
end

---Validate that a path is absolute and the file exists.
---@param path string Path to validate
---@return boolean ok True if valid, false otherwise
---@return string|nil err Error message if invalid, nil otherwise
local function validate_path(path)
  if not path or path == "" then
    return false, "path is required"
  end
  
  -- Check if path is absolute
  if not is_absolute_path(path) then
    return false, string.format("path must be absolute: got '%s'", path)
  end
  
  -- Check file existence
  local stat = vim.loop.fs_stat(path)
  if not stat then
    return false, string.format("file does not exist: '%s'", path)
  end
  
  if stat.type ~= "file" then
    return false, string.format("path is not a file: '%s'", path)
  end
  
  return true, nil
end

---Open a file in a new tab with optional cursor positioning.
---@param opts opencode.editor_actions.open_file.Opts Options for opening the file.
---@return boolean success True if the file was opened successfully.
local function open_file(opts)
  -- Validate required path
  if not opts or not opts.path then
    vim.notify("open_file: 'path' is required", vim.log.levels.ERROR, { title = "opencode" })
    return false
  end
  
  -- Validate path exists and is absolute
  local ok, err = validate_path(opts.path)
  if not ok then
    vim.notify("open_file: " .. err, vim.log.levels.ERROR, { title = "opencode" })
    return false
  end
  
  -- Open in new tab
  vim.cmd("tabedit " .. vim.fn.fnameescape(opts.path))
  
  -- Position cursor if line is provided
  if opts.line and opts.line > 0 then
    local line = opts.line
    local col = opts.col and opts.col > 0 and opts.col or 1
    
    -- Validate line is within buffer bounds
    local buf_line_count = vim.api.nvim_buf_line_count(0)
    if line > buf_line_count then
      vim.notify(
        string.format("open_file: line %d exceeds buffer size (%d lines), using last line", line, buf_line_count),
        vim.log.levels.WARN,
        { title = "opencode" }
      )
      line = buf_line_count
    end
    
    -- Move cursor to position
    vim.api.nvim_win_set_cursor(0, { line, col - 1 }) -- col is 0-based in API
  end
  
  return true
end

---
---Open a file in a new tab with optional cursor positioning.
---This is the main entry point for the MCP server.
---@param payload opencode.editor_actions.open_file.Opts Options for opening the file.
---@return boolean success True if the file was opened successfully.
function M.open_file(payload)
  return open_file(payload)
end

---
---Open a picker to select from multiple file candidates.
---Each candidate can specify path, line, col, and an optional label.
---Upon selection, opens in a new tab.
---@param payload opencode.editor_actions.open_candidates.Opts Options containing the candidates list.
---@return Promise promise Promise that resolves when a candidate is selected and opened.
function M.open_candidates(payload)
  local Promise = require("opencode.promise")
  
  -- Validate required candidates
  if not payload or not payload.candidates then
    vim.notify("open_candidates: 'candidates' is required", vim.log.levels.ERROR, { title = "opencode" })
    return Promise.reject("candidates is required")
  end
  
  if #payload.candidates == 0 then
    vim.notify("open_candidates: no candidates provided", vim.log.levels.WARN, { title = "opencode" })
    return Promise.reject("no candidates provided")
  end
  
  -- Filter out invalid candidates (non-existent files)
  local valid_candidates = {}
  for _, candidate in ipairs(payload.candidates) do
    local ok, _ = validate_path(candidate.path)
    if ok then
      table.insert(valid_candidates, candidate)
    end
  end
  
  if #valid_candidates == 0 then
    vim.notify("open_candidates: no valid candidates (all files do not exist)", vim.log.levels.ERROR, { title = "opencode" })
    return Promise.reject("no valid candidates")
  end
  
  -- Build items for picker
  ---@class opencode.editor_actions.picker.Item : snacks.picker.finder.Item
  ---@field candidate opencode.editor_actions.open_candidates.Candidate
  
  local items = {}
  for _, candidate in ipairs(valid_candidates) do
    -- Build display label: use provided label or derive from path
    local display_label = candidate.label
    if not display_label or display_label == "" then
      display_label = vim.fn.fnamemodify(candidate.path, ":t") -- filename only
    end
    
    -- Build location info for display
    local location = candidate.path
    if candidate.line then
      location = location .. ":" .. candidate.line
      if candidate.col then
        location = location .. ":" .. candidate.col
      end
    end
    
    table.insert(items, {
      candidate = candidate,
      name = display_label,
      text = location,
      highlights = { { location, "Comment" } },
      preview = {
        text = string.format(
          "File: %s\nLine: %s\nColumn: %s\n\n%s",
          candidate.path,
          candidate.line or "N/A",
          candidate.col or "N/A",
          candidate.label or display_label
        ),
      },
    })
  end
  
  ---@type snacks.picker.ui_select.Opts
  local select_opts = {
    prompt = "Select File: ",
    format_item = function(item, is_snacks)
      if is_snacks then
        return {
          { item.name, "Normal" },
          { "  ", "Normal" },
          { item.text, "Comment" },
        }
      else
        return string.format("%s  %s", item.name, item.text)
      end
    end,
  }
  
  return Promise.select(items, select_opts)
    :next(function(choice) ---@param choice opencode.editor_actions.picker.Item
      local success = open_file({
        path = choice.candidate.path,
        line = choice.candidate.line,
        col = choice.candidate.col,
      })
      
      if not success then
        vim.notify(
          string.format("Failed to open file: %s", choice.candidate.path),
          vim.log.levels.ERROR,
          { title = "opencode" }
        )
        return Promise.reject("failed to open file")
      end
      
      return choice.candidate
    end)
    :catch(function(err)
      if err and err ~= "" then
        vim.notify(err, vim.log.levels.WARN, { title = "opencode" })
      end
      return Promise.reject(err)
    end)
end

return M