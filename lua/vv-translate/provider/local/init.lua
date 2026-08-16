-- 本地 provider：将请求拆成英文单词，并通过离线分片词典查询
local Dictionary = require('vv-translate.provider.local.dictionary')
local Formatter = require('vv-translate.provider.local.formatter')
local Identifier = require('vv-translate.identifier')

local M = {}

local function lookup(word, dictionary_path)
  if #word < 2 then return nil end
  local shard, err = Dictionary.load(dictionary_path, word:sub(1, 2))
  if not shard then return nil, err end
  return shard[word]
end

---使用本地分片词典翻译请求中的英文单词
---@param request VVTranslateRequest
---@param config VVTranslateLocalProviderConfig
---@param callback fun(error: VVTranslateError?, result: VVTranslateResult?)
function M.translate(request, config, callback)
  local dictionary_path = config.dictionary_path or Dictionary.default_path()
  if vim.fn.isdirectory(dictionary_path) ~= 1 then
    callback({
      code = 'dictionary_not_found',
      message = ('Offline dictionary directory not found: %s'):format(dictionary_path),
      provider = 'local',
    }, nil)
    return
  end

  local words = Identifier.words(request.text)
  if #words == 0 then
    callback({
      code = 'unsupported_local_query',
      message = 'The offline dictionary only supports English words and code identifiers',
      provider = 'local',
    }, nil)
    return
  end

  local lines = {}
  local highlights = {}

  for _, word in ipairs(words) do
    local entry, err = lookup(word, dictionary_path)
    if err then
      callback(err, nil)
      return
    end

    if #lines > 0 then lines[#lines + 1] = '' end

    local row_offset = #lines
    local content = Formatter.entry(word, entry)
    vim.list_extend(lines, content.lines)

    for _, highlight in ipairs(content.highlights) do
      highlights[#highlights + 1] = vim.tbl_extend('force', highlight, {
        row = highlight.row + row_offset,
      })
    end
  end

  callback(nil, {
    text = table.concat(lines, '\n'),
    provider = 'local',
    highlights = highlights,
    content = {
      lines = lines,
      highlights = highlights,
    },
    data = {
      words = words,
    },
  })
end

M.clear_cache = Dictionary.clear_cache

return M
