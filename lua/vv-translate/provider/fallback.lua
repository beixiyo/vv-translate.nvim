-- Provider fallback 执行器：按声明顺序尝试，并维护单一可取消阶段
local M = {}

---依次执行 provider，首个成功结果结束链路
---@param opts VVTranslateFallbackOptions
---@param callback fun(error: VVTranslateError?, result: VVTranslateResult?)
---@return fun() cancel 幂等取消当前阶段，并压制后续 fallback
function M.run(opts, callback)
  local cancelled = false
  local finished = false
  local phase = 0
  local cancel_phase
  local failures = {}

  local function finish(err, result)
    if cancelled or finished then return end
    finished = true
    callback(err, result)
  end

  local function attempt(index)
    if cancelled or finished then return end
    local provider = opts.providers[index]
    if not provider then
      local last = failures[#failures]
      if last then
        finish({
          code = last.code,
          message = last.message,
          provider = last.provider,
          cause = { last = last.cause, attempts = failures },
        }, nil)
      else
        finish({
          code = 'provider_fallback_exhausted',
          message = 'No translation provider succeeded',
        }, nil)
      end
      return
    end

    phase = phase + 1
    local current_phase = phase
    local ok, returned_cancel = pcall(opts.run, provider, function(err, result)
      if cancelled or finished or phase ~= current_phase then return end
      if err then
        failures[#failures + 1] = {
          provider = provider,
          code = err.code,
          message = err.message,
        }
        attempt(index + 1)
        return
      end

      if #failures > 0 then
        if type(result.metadata) ~= 'table' then result.metadata = {} end
        result.metadata.fallback = { attempts = vim.deepcopy(failures) }
      end
      finish(nil, result)
    end)
    if not ok and phase == current_phase and not finished and not cancelled then
      failures[#failures + 1] = {
        provider = provider,
        code = 'provider_runner_failed',
        message = 'Failed to start a translation provider',
      }
      attempt(index + 1)
      return
    end
    if phase == current_phase and not finished and not cancelled then
      cancel_phase = type(returned_cancel) == 'function' and returned_cancel or nil
    end
  end

  attempt(1)

  return function()
    if cancelled or finished then return end
    cancelled = true
    phase = phase + 1
    if cancel_phase then pcall(cancel_phase) end
  end
end

return M

---@class VVTranslateFallbackOptions
---@field providers string[] 按顺序尝试的 provider
---@field run fun(provider: string, callback: fun(error: VVTranslateError?, result: VVTranslateResult?)): cancel: fun()?
