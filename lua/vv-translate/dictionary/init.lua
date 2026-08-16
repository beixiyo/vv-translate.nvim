-- 离线词典下载公共入口，负责并发状态和 provider 缓存刷新
local Installer = require('vv-translate.dictionary.installer')

local M = {}
local active = false

---下载并安装最新版离线词典
---@param opts? VVTranslateDictionaryInstallOptions
---@param callback fun(result: VVTranslateDictionaryInstallResult)
---@return fun() cancel
function M.download_latest(opts, callback)
  if active then
    callback({ ok = false, code = 'download_in_progress', message = 'A dictionary download is already in progress' })
    return function() end
  end

  active = true
  local cancel_install = Installer.install(opts, function(result)
    active = false
    if result.ok then require('vv-translate.provider.local.dictionary').clear_cache() end
    callback(result)
  end)
  local cancelled = false
  return function()
    if cancelled then return end
    cancelled = true
    active = false
    cancel_install()
  end
end

return M
