-- 离线词典分片加载与缓存，不负责查询策略或结果展示
local M = {}
local cache = {}

local source = debug.getinfo(1, 'S').source:sub(2)
local default_path = source
for _ = 1, 5 do default_path = vim.fs.dirname(default_path) end
default_path = vim.fs.joinpath(default_path, 'dict')

---返回默认词典目录
---@return string
function M.default_path()
  return default_path
end

---读取一个词典分片
---@param dictionary_path string
---@param prefix string
---@return table? shard
---@return VVTranslateError? error
function M.load(dictionary_path, prefix)
  local path = vim.fs.joinpath(dictionary_path, prefix .. '.json')
  if cache[path] then return cache[path] end

  local file, open_error = io.open(path, 'rb')
  if not file then
    return nil, {
      code = 'dictionary_shard_unreadable',
      message = ('Failed to read offline dictionary shard: %s'):format(path),
      provider = 'local',
      cause = open_error,
    }
  end

  local content = file:read('*a')
  file:close()
  local ok, shard = pcall(vim.json.decode, content)
  if not ok or type(shard) ~= 'table' then
    return nil, {
      code = 'dictionary_shard_invalid',
      message = ('Invalid offline dictionary shard: %s'):format(path),
      provider = 'local',
      cause = ok and 'root must be an object' or shard,
    }
  end

  cache[path] = shard
  return shard
end

---清空已加载的词典分片
function M.clear_cache()
  cache = {}
end

return M
