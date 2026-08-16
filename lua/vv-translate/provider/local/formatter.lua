-- 离线词典条目格式化，只负责生成用户可见文本
local M = {}

local function translation_line(text, row)
  local prefix, prefix_end
  local _, word_end, word_prefix = text:find('^([%a][%a%-]*%.)%s*')
  if word_prefix then
    prefix, prefix_end = word_prefix, word_end
  else
    local _, bracket_end, bracket_prefix = text:find('^(%b[])%s*')
    prefix, prefix_end = bracket_prefix, bracket_end
  end
  local highlights = {}
  if prefix then
    highlights[#highlights + 1] = { row = row, start_col = 0, end_col = #prefix, role = 'part_of_speech' }
  end
  local translation_start = prefix_end or 0
  if translation_start < #text then
    highlights[#highlights + 1] = {
      row = row,
      start_col = translation_start,
      end_col = #text,
      role = 'translation',
    }
  end
  return highlights
end

---格式化单个词典条目及其语义范围
---@param word string
---@param entry any
---@return VVTranslateContent
function M.entry(word, entry)
  if not entry then
    local missing = '  Not found in the offline dictionary'
    return {
      lines = { word, missing },
      highlights = {
        { row = 0, start_col = 0, end_col = #word, role = 'source' },
        { row = 1, start_col = 0, end_col = #missing, role = 'missing' },
      },
    }
  end

  local translation = type(entry) == 'table' and entry.t or entry
  local phonetic = type(entry) == 'table' and entry.p or nil
  local display_word = type(entry) == 'table' and entry.w or nil
  translation = tostring(translation or ''):gsub('\\n', '\n')

  local source = display_word or word
  local title = source
  local highlights = {
    { row = 0, start_col = 0, end_col = #source, role = 'source' },
  }
  if phonetic and phonetic ~= '' then
    local phonetic_text = ('/%s/'):format(phonetic)
    local start_col = #title + 2
    title = title .. '  ' .. phonetic_text
    highlights[#highlights + 1] = {
      row = 0,
      start_col = start_col,
      end_col = start_col + #phonetic_text,
      role = 'phonetic',
    }
  end

  local lines = { title }
  for _, line in ipairs(vim.split(translation, '\n', { plain = true })) do
    lines[#lines + 1] = line
    vim.list_extend(highlights, translation_line(line, #lines - 1))
  end
  return { lines = lines, highlights = highlights }
end

return M
