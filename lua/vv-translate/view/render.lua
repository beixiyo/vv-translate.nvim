-- 翻译浮窗内容渲染：计算尺寸并更新 buffer/window
local M = {}
local Highlights = require('vv-translate.view.highlights')
local namespace = vim.api.nvim_create_namespace('vv_translate_view')

local function valid(state)
  return state.buf
    and state.win
    and vim.api.nvim_buf_is_valid(state.buf)
    and vim.api.nvim_win_is_valid(state.win)
end

local function dimensions(lines, config)
  local max_width = math.max(20, math.min(config.max_width, vim.o.columns - 4))
  local width = 20
  local height = 0
  for _, line in ipairs(lines) do
    local line_width = math.max(1, vim.fn.strdisplaywidth(line))
    width = math.max(width, math.min(max_width, line_width))
    height = height + math.max(1, math.ceil(line_width / max_width))
  end
  return width, math.min(math.max(1, height), config.max_height)
end

---更新浮窗内容与标题
---@param state table
---@param config VVTranslateViewConfig
---@param content VVTranslateContent
function M.set_content(state, config, content)
  if not valid(state) then return end
  local lines = content.lines

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(state.buf, namespace, 0, -1)
  for _, highlight in ipairs(content.highlights or {}) do
    local group = Highlights.group(highlight.role)
    if group then
      vim.api.nvim_buf_set_extmark(state.buf, namespace, highlight.row, highlight.start_col, {
        end_col = highlight.end_col,
        hl_group = group,
      })
    end
  end
  vim.bo[state.buf].modifiable = false

  local width, height = dimensions(lines, config)
  local window = config.window or {}

  vim.api.nvim_win_set_config(state.win, {
    relative = window.relative or 'cursor',
    row = window.row or 1,
    col = window.col or 0,
    width = width,
    height = height,
    title = content.title and (' %s '):format(content.title) or '',
    title_pos = window.title_pos or 'center',
  })
end

return M
