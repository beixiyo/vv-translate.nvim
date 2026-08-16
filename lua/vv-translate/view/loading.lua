-- 翻译 loading 生命周期：复用 vv-utils.loading，并由浮窗 owner 负责停止
local Loading = require('vv-utils.loading')

local M = {}

---在浮窗第一行启动 loading 动画
---@param state table
---@param config VVTranslateViewConfig
---@return fun() stop
function M.start(state, config)
  local opts = config.loading or {}
  local frames = opts.frames or Loading.presets[opts.preset or 'braille']

  return Loading.start({
    buf = state.buf,
    get_row = function()
      return state.buf and vim.api.nvim_buf_is_valid(state.buf) and 1 or nil
    end,
    frames = frames,
    interval_ms = opts.interval_ms,
    hl = opts.hl or 'VVTranslatePhonetic',
    prefix = opts.prefix,
    virt_text_pos = opts.virt_text_pos,
    hl_mode = opts.hl_mode,
  })
end

return M
