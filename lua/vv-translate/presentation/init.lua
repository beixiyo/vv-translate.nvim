-- 通用展示内容契约：校验 presenter 与 renderer 交给浮窗的数据边界
local M = {}

---检查通用展示内容是否可安全写入 Neovim buffer
---@param content any
---@return boolean
function M.valid(content)
  if type(content) ~= 'table' or type(content.lines) ~= 'table' then return false end
  if content.title ~= nil and type(content.title) ~= 'string' then return false end

  for _, line in ipairs(content.lines) do
    if type(line) ~= 'string' then return false end
  end

  if content.highlights ~= nil and type(content.highlights) ~= 'table' then return false end
  return true
end

return M
