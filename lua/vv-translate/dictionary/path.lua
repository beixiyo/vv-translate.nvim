-- 离线词典路径约定
local M = {}

local source = debug.getinfo(1, 'S').source:sub(2)
local plugin_root = source
for _ = 1, 4 do plugin_root = vim.fs.dirname(plugin_root) end

---返回插件根目录
---@return string
function M.plugin_root()
  return plugin_root
end

---返回默认词典安装目录
---@return string
function M.install_dir()
  return vim.fs.joinpath(plugin_root, 'dict')
end

return M
