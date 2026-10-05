-- 翻译浮窗生命周期：管理窗口、buffer、关闭回调和状态切换
local Render = require('vv-translate.view.render')
local DefaultRenderer = require('vv-translate.view.default_renderer')
local Input = require('vv-translate.view.input')
local Layout = require('vv-translate.view.layout')
local Loading = require('vv-translate.view.loading')
local Presentation = require('vv-translate.presentation')
local UIWindow = require('vv-utils.ui_window')

local M = {}
local config = {}
local state = {
  buf = nil,
  win = nil,
  group = nil,
  keymaps = nil,
  stop_loading = nil,
  source_buf = nil,
  on_close = nil,
  -- 最近一次结果或错误内容；VimResized 时按它重新排版，loading 期间为 nil
  content = nil,
}

local function valid_buf()
  return state.buf and vim.api.nvim_buf_is_valid(state.buf)
end

local function valid_win()
  return state.win and vim.api.nvim_win_is_valid(state.win)
end

---初始化浮窗配置；opts 必须已在 setup 边界合并默认值，非法 layout/hints 直接抛错
---@param opts VVTranslateViewConfig
function M.setup(opts)
  Layout.validate(opts.layout)
  if type(opts.hints) ~= 'boolean' then
    error(('vv-translate: view.hints must be a boolean, got %s'):format(vim.inspect(opts.hints)), 0)
  end
  config = opts
end

local function content_for(event, context)
  context.default_render = function() return DefaultRenderer.render(event, context) end
  if not config.render then return context.default_render() end

  local ok, content = pcall(config.render, event, context)
  if ok and Presentation.valid(content) then return content end

  vim.notify('Custom translation renderer failed; using the default renderer', vim.log.levels.ERROR)
  return context.default_render()
end

local function stop_loading()
  if not state.stop_loading then return end
  state.stop_loading()
  state.stop_loading = nil
end

---打开翻译浮窗
---@param request VVTranslateRequest
---@param on_close? fun()
function M.open(request, on_close)
  M.close(false)

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = 'nofile'
  vim.bo[state.buf].bufhidden = 'wipe'
  vim.bo[state.buf].swapfile = false
  vim.bo[state.buf].filetype = 'vv-translate'
  state.on_close = on_close
  state.source_buf = vim.api.nvim_get_current_buf()

  local window_config = vim.tbl_extend('force', {
    relative = 'cursor',
    row = 1,
    col = 0,
    width = 20,
    height = 1,
    style = 'minimal',
    border = config.border,
    focusable = false,
    zindex = 60,
    title = '',
    title_pos = 'center',
  }, config.window or {})

  window_config.width = 20
  window_config.height = 1
  window_config.title = ''

  state.win = vim.api.nvim_open_win(state.buf, false, window_config)
  UIWindow.hide_chrome_until_buf_wiped(state.win, state.buf, { wrap = config.wrap })
  local layout = Render.set_content(state, config, content_for('loading', { request = request }))
  state.stop_loading = Loading.start(state, config, { truncated = layout.truncated })
  state.keymaps = Input.attach(state, config, function() M.close(true) end)

  state.group = vim.api.nvim_create_augroup('VVTranslateView', { clear = true })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'InsertEnter', 'BufLeave' }, {
    group = state.group,
    buffer = state.source_buf,
    once = true,
    callback = function() M.close(true) end,
  })
  vim.api.nvim_create_autocmd('VimResized', {
    group = state.group,
    callback = function()
      -- loading 期间内容是临时原文且 footer 可能被帧占用，等结果到达时再按新尺寸排版
      if state.stop_loading or not state.content then return end
      Render.set_content(state, config, state.content)
    end,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = state.group,
    pattern = tostring(state.win),
    once = true,
    callback = function() M.close(true) end,
  })
end

---显示翻译结果
---@param request VVTranslateRequest
---@param result VVTranslateResult
function M.result(request, result)
  stop_loading()
  state.content = content_for('result', { request = request, result = result })
  Render.set_content(state, config, state.content)
end

---显示可行动错误
---@param request VVTranslateRequest
---@param error VVTranslateError
function M.error(request, error)
  stop_loading()
  state.content = content_for('error', { request = request, error = error })
  Render.set_content(state, config, state.content)
end

---关闭浮窗
---@param notify_owner? boolean
function M.close(notify_owner)
  local on_close = notify_owner and state.on_close or nil
  state.on_close = nil

  stop_loading()
  if state.keymaps then state.keymaps:detach() end
  if state.group then pcall(vim.api.nvim_del_augroup_by_id, state.group) end
  if valid_win() then pcall(vim.api.nvim_win_close, state.win, true) end
  if valid_buf() then pcall(vim.api.nvim_buf_delete, state.buf, { force = true }) end

  state.buf, state.win, state.group, state.keymaps, state.source_buf = nil, nil, nil, nil, nil
  state.content = nil
  if on_close then on_close() end
end

---返回当前浮窗
---@return integer? win
---@return integer? buf
function M.current()
  return valid_win() and state.win or nil, valid_buf() and state.buf or nil
end

return M
