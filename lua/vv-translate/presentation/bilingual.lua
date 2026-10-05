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

---按顺序上下排列文本块，块之间插入一个空行；每块按 '\n' 拆行并整行标注语义
---@param blocks VVTranslateBilingualBlock[]
---@return string[] lines
---@return VVTranslateContentHighlight[] highlights
function M.stack(blocks)
  local lines = {}
  local highlights = {}
  for index, block in ipairs(blocks) do
    if index > 1 then lines[#lines + 1] = '' end
    append(lines, highlights, block.text, block.role)
  end
  return lines, highlights
end

---渲染原文、分隔空行和译文；同时附带原始分段，供浮窗在长内容时改用双栏对照
---lines/highlights 是单栏回退布局，不依赖 sections 的 renderer 行为不变
---@param source string
---@param translation string
---@return VVTranslateContent
function M.render(source, translation)
  local lines, highlights = M.stack({
    { text = source, role = 'source' },
    { text = translation, role = 'translation' },
  })
  return {
    lines = lines,
    highlights = highlights,
    sections = { source = source, translation = translation },
  }
end

return M

---@class VVTranslateBilingualBlock
---@field text string 可含 '\n' 的文本
---@field role VVTranslateHighlightRole 整块文字的语义
