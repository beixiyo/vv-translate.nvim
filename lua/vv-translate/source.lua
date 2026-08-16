-- 翻译文本来源：无副作用地读取光标词或 Visual 选区
local M = {}

---读取光标下的 keyword
---@return string|nil
function M.word()
  local word = vim.trim(vim.fn.expand('<cword>'))
  return word ~= '' and word or nil
end

---读取当前或最近一次 Visual 选区
---@return string|nil
function M.visual()
  local mode = vim.fn.mode(1)
  if mode ~= 'v' and mode ~= 'V' and mode ~= '\22' then
    mode = vim.fn.visualmode()
  end

  local start_pos = vim.fn.getpos(mode == vim.fn.mode(1) and 'v' or "'<")
  local end_pos = vim.fn.getpos(mode == vim.fn.mode(1) and '.' or "'>")
  local lines = vim.fn.getregion(start_pos, end_pos, { type = mode })
  local text = vim.trim(table.concat(lines, '\n'))
  return text ~= '' and text or nil
end

return M

