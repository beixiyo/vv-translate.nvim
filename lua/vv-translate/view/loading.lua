-- 翻译 loading 生命周期：复用 vv-utils.loading，并由浮窗 owner 负责停止
local Loading = require('vv-utils.loading')

local M = {}

---启动 loading 动画：默认画在浮窗最后一行（默认 renderer 为其保留独立空行）；
---内容超过浮窗最大高度、最后一行不可见时改画在浮窗 footer
---@param state table
---@param config VVTranslateViewConfig
---@param opts { truncated: boolean }
---@return fun() stop
function M.start(state, config, opts)
  local loading = config.loading or {}
  local common = {
    frames = loading.frames or Loading.presets[loading.preset or 'braille'],
    interval_ms = loading.interval_ms,
  }
  local hl = loading.hl or 'VVTranslatePhonetic'

  local handle
  if opts.truncated then
    handle = Loading.win_text(vim.tbl_extend('force', common, {
      win = state.win,
      slot = 'footer',
      format = function(frame) return { { (' %s '):format(frame), hl } } end,
    }))
  else
    handle = Loading.mark(vim.tbl_extend('force', common, {
      buf = state.buf,
      get_pos = function()
        if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return nil end
        return { row = vim.api.nvim_buf_line_count(state.buf) }
      end,
      pos = loading.virt_text_pos or 'eol',
      hl = hl,
      prefix = loading.prefix,
      hl_mode = loading.hl_mode,
    }))
  end

  return function() handle:stop() end
end

return M
