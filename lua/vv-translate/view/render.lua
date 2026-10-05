-- 翻译浮窗内容渲染：按排版结果更新 buffer、换行方式、窗口尺寸、标题与按键提示
local M = {}
local Layout = require('vv-translate.view.layout')
local UIWindow = require('vv-utils.ui_window')
local namespace = vim.api.nvim_create_namespace('vv_translate_view')

local function valid(state)
  return state.buf
    and state.win
    and vim.api.nvim_buf_is_valid(state.buf)
    and vim.api.nvim_win_is_valid(state.win)
end

---按真实配置的控制键生成提示；被禁用的滚动键不显示
---@param keymaps VVTranslateViewKeymaps
---@return VVKeyHint[]
local function key_hints(keymaps)
  local hints = {}
  if keymaps.close and keymaps.close[1] then hints[#hints + 1] = { key = keymaps.close[1], desc = 'close' } end
  if keymaps.scroll_down then hints[#hints + 1] = { key = keymaps.scroll_down, desc = 'scroll down' } end
  if keymaps.scroll_up then hints[#hints + 1] = { key = keymaps.scroll_up, desc = 'scroll up' } end
  return hints
end

---把按键提示写入 footer；loading 占用 footer 时由 win_text 记住此值并在停止时恢复
---无边框窗口不支持 footer，set_config 失败视为不显示
local function set_hints(state, config, width)
  if not config.hints then return end
  local chunks = UIWindow.key_hints(key_hints(config.keymaps or {}), { max_width = width })
  pcall(vim.api.nvim_win_set_config, state.win, {
    footer = chunks or '',
    footer_pos = (config.window or {}).footer_pos or 'center',
  })
end

---更新浮窗内容与标题
---@param state table
---@param config VVTranslateViewConfig
---@param content VVTranslateContent
---@return { truncated: boolean } layout truncated 表示内容超过最大高度，末尾行不可见
function M.set_content(state, config, content)
  if not valid(state) then return { truncated = false } end
  local layout = Layout.arrange(content, config)

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, layout.lines)
  vim.api.nvim_buf_clear_namespace(state.buf, namespace, 0, -1)
  for _, highlight in ipairs(layout.highlights) do
    vim.api.nvim_buf_set_extmark(state.buf, namespace, highlight.row, highlight.start_col, {
      end_col = highlight.end_col,
      hl_group = highlight.hl,
    })
  end
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_set_option_value('wrap', layout.wrap, { win = state.win, scope = 'local' })

  local window = config.window or {}
  vim.api.nvim_win_set_config(state.win, {
    relative = window.relative or 'cursor',
    row = window.row or 1,
    col = window.col or 0,
    width = layout.width,
    height = math.min(#layout.lines, config.max_height),
    title = content.title and (' %s '):format(content.title) or '',
    title_pos = window.title_pos or 'center',
  })

  -- 宽度和 wrap 生效后按真实窗口计算屏幕行数：显示宽度估算会漏算宽字符整字换行
  local content_height = math.max(1, vim.api.nvim_win_text_height(state.win, {}).all)
  local height = math.min(content_height, config.max_height)
  vim.api.nvim_win_set_config(state.win, { height = height })
  set_hints(state, config, layout.width)
  return { truncated = content_height > height }
end

return M
