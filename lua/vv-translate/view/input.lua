-- 翻译浮窗输入控制：临时接管来源 buffer 映射，并把滚动动作转发给非聚焦浮窗
local Keymap = require('vv-utils.keymap')

local M = {}

local function scroll(state, key)
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end
  vim.api.nvim_win_call(state.win, function()
    vim.cmd.normal({ args = { vim.keycode(key) }, bang = true })
  end)
end

---绑定浮窗存续期间的来源 buffer 控制键
---@param state table
---@param config VVTranslateViewConfig
---@param close fun()
---@return VVKeymapHandle
function M.attach(state, config, close)
  local keymaps = config.keymaps
  local mappings = {}

  for _, lhs in ipairs(keymaps.close or {}) do
    local callback = close
    if lhs == '<Esc>' then
      callback = function()
        close()
        vim.schedule(function() vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'n', false) end)
      end
    end
    mappings[#mappings + 1] = {
      mode = { 'n', 'x' },
      lhs = lhs,
      rhs = callback,
      opts = { silent = true, nowait = true, desc = 'Close translation' },
    }
  end

  if keymaps.scroll_down then
    mappings[#mappings + 1] = {
      mode = { 'n', 'x' },
      lhs = keymaps.scroll_down,
      rhs = function() scroll(state, '<C-e>') end,
      opts = { silent = true, nowait = true, desc = 'Scroll translation down' },
    }
  end

  if keymaps.scroll_up then
    mappings[#mappings + 1] = {
      mode = { 'n', 'x' },
      lhs = keymaps.scroll_up,
      rhs = function() scroll(state, '<C-y>') end,
      opts = { silent = true, nowait = true, desc = 'Scroll translation up' },
    }
  end

  return Keymap.attach({
    id = 'vv-translate-view',
    when = function(context) return context.buf == state.source_buf end,
    mappings = mappings,
  })
end

return M
