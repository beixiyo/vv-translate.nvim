-- 通用默认 renderer：将 loading、error 和不同形状的 provider 结果转换为浮窗内容
local M = {}

local function translation_highlights(lines)
  local highlights = {}
  for row, line in ipairs(lines) do
    if line ~= '' then
      highlights[#highlights + 1] = {
        row = row - 1,
        start_col = 0,
        end_col = #line,
        role = 'translation',
      }
    end
  end
  return highlights
end

local function scalar(value)
  if value == vim.NIL or value == nil then return 'null' end
  if type(value) == 'string' then return value end
  if type(value) == 'number' or type(value) == 'boolean' then return tostring(value) end
  return ('<%s>'):format(type(value))
end

local function append_data(lines, value, indent, seen, depth)
  if type(value) ~= 'table' then
    lines[#lines + 1] = string.rep(' ', indent) .. scalar(value)
    return
  end
  if seen[value] then
    lines[#lines + 1] = string.rep(' ', indent) .. '[Circular]'
    return
  end
  if depth >= 4 then
    lines[#lines + 1] = string.rep(' ', indent) .. '[Nested data]'
    return
  end

  seen[value] = true
  local keys = vim.tbl_keys(value)
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  if #keys == 0 then lines[#lines + 1] = string.rep(' ', indent) .. '{}' end

  for _, key in ipairs(keys) do
    local item = value[key]
    local prefix = string.rep(' ', indent) .. tostring(key) .. ':'
    if type(item) == 'table' then
      lines[#lines + 1] = prefix
      append_data(lines, item, indent + 2, seen, depth + 1)
    else
      lines[#lines + 1] = prefix .. ' ' .. scalar(item)
    end
  end
  seen[value] = nil
end

local function result_content(result)
  if result.content then return vim.deepcopy(result.content) end

  local lines
  if type(result.text) == 'string' then
    lines = vim.split(result.text, '\n', { plain = true })
  elseif result.data ~= nil then
    lines = {}
    append_data(lines, result.data, 0, {}, 0)
  else
    lines = { 'The translation provider returned no displayable content' }
  end

  return {
    lines = lines,
    highlights = result.highlights or translation_highlights(lines),
  }
end

---使用内置策略渲染一个 view 事件
---@param event VVTranslateViewEvent
---@param context VVTranslateRenderContext
---@return VVTranslateContent
function M.render(event, context)
  if event == 'loading' then
    local text = context.request.text
    return {
      lines = { text, '' },
      highlights = { { row = 0, start_col = 0, end_col = #text, role = 'source' } },
    }
  end

  if event == 'error' then
    local lines = vim.split(context.error.message, '\n', { plain = true })
    local highlights = {}
    for row, line in ipairs(lines) do
      highlights[#highlights + 1] = {
        row = row - 1,
        start_col = 0,
        end_col = #line,
        role = 'error',
      }
    end
    return { title = 'Translation failed', lines = lines, highlights = highlights }
  end

  return result_content(context.result)
end

return M
