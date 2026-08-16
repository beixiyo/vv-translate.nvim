-- 代码标识符规范化：拆分常见命名风格，普通自然语言保持原样
local M = {}

---将代码标识符拆成适合翻译引擎处理的英文短语
---@param text string
---@return string
function M.normalize(text)
  text = vim.trim(text)
  local is_ascii = true
  for index = 1, #text do
    if text:byte(index) > 127 then
      is_ascii = false
      break
    end
  end

  if text == '' or text:find('[^%w_-]') or not is_ascii then
    return text
  end

  local chars = {}
  for index = 1, #text do
    chars[index] = text:sub(index, index)
  end

  local words = {}
  local current = {}

  local function kind(char)
    if not char then return nil end
    if char:match('%u') then return 'upper' end
    if char:match('%l') then return 'lower' end
    if char:match('%d') then return 'digit' end
    return 'separator'
  end

  local function flush()
    if #current == 0 then return end
    words[#words + 1] = table.concat(current):lower()
    current = {}
  end

  for index, char in ipairs(chars) do
    local current_kind = kind(char)
    if current_kind == 'separator' then
      flush()
    else
      local previous_kind = kind(chars[index - 1])
      local next_kind = kind(chars[index + 1])
      local boundary = #current > 0 and (
        (current_kind == 'upper' and (previous_kind == 'lower' or previous_kind == 'digit'))
        or (current_kind == 'upper' and previous_kind == 'upper' and next_kind == 'lower')
        or (current_kind == 'digit' and previous_kind ~= 'digit')
        or (current_kind ~= 'digit' and previous_kind == 'digit')
      )

      if boundary then flush() end
      current[#current + 1] = char
    end
  end

  flush()
  return table.concat(words, ' ')
end

---提取适合离线词典逐项查询的英文单词
---@param text string
---@return string[]
function M.words(text)
  local normalized = M.normalize(text)
  local words = {}
  local seen = {}

  for word in normalized:gmatch("[A-Za-z][A-Za-z0-9']*") do
    word = word:lower()
    if not seen[word] then
      seen[word] = true
      words[#words + 1] = word
    end
  end

  return words
end

return M
