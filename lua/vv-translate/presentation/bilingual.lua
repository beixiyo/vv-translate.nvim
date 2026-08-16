-- 双语展示：统一排列原文和译文，并生成对应语义高亮
local M = {}

local function append(lines, highlights, text, role)
  for _, line in ipairs(vim.split(text, '\n', { plain = true })) do
    local row = #lines
    lines[#lines + 1] = line
    if line ~= '' then
      highlights[#highlights + 1] = {
        row = row,
        start_col = 0,
        end_col = #line,
        role = role,
      }
    end
  end
end

---渲染原文、分隔空行和译文
---@param source string
---@param translation string
---@return VVTranslateContent
function M.render(source, translation)
  local lines = {}
  local highlights = {}
  append(lines, highlights, source, 'source')
  lines[#lines + 1] = ''
  append(lines, highlights, translation, 'translation')
  return { lines = lines, highlights = highlights }
end

return M
