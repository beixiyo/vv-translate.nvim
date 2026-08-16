-- 离线词典下载公共入口，负责并发状态和 provider 缓存刷新
local Installer = require('vv-translate.dictionary.installer')

local M = {}
local active

local function add_waiter(operation, callback)
  local waiter = { callback = callback, active = true }
  operation.waiters[#operation.waiters + 1] = waiter

  return function()
    if not waiter.active then return end
    waiter.active = false

    for _, current in ipairs(operation.waiters) do
      if current.active then return end
    end
    if active == operation then
      active = nil
      if operation.cancel then operation.cancel() end
    end
  end
end

---下载并安装最新版离线词典
---@param opts? VVTranslateDictionaryInstallOptions
---@param callback fun(result: VVTranslateDictionaryInstallResult)
---@return fun() cancel
function M.download_latest(opts, callback)
  opts = opts or {}
  local destination = opts.destination
  if active then
    if active.destination ~= destination then
      callback({ ok = false, code = 'download_in_progress', message = 'A dictionary download is already in progress' })
      return function() end
    end
    return add_waiter(active, callback)
  end

  local operation = { destination = destination, waiters = {} }
  active = operation
  local cancel_waiter = add_waiter(operation, callback)
  operation.cancel = Installer.install(opts, function(result)
    if active == operation then active = nil end
    if result.ok then require('vv-translate.provider.local.dictionary').clear_cache() end
    for _, waiter in ipairs(operation.waiters) do
      if waiter.active then
        waiter.active = false
        waiter.callback(result)
      end
    end
  end)
  return cancel_waiter
end

return M
