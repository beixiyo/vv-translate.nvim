-- 翻译 provider 路由：解析内置或调用方配置的 provider，不包含具体服务策略
local M = {}
local Callback = require('vv-utils.callback')
local Presentation = require('vv-translate.presentation')

local BUILTIN = {
  ['groq'] = function() return require('vv-translate.provider.groq') end,
  ['local'] = function() return require('vv-translate.provider.local') end,
  ['mymemory'] = function() return require('vv-translate.provider.mymemory') end,
}

local function error_result(code, message, provider, cause)
  return {
    code = code,
    message = message,
    provider = provider,
    cause = cause,
  }
end

---执行一次翻译请求
---@param request VVTranslateRequest
---@param config VVTranslateProviderOptions
---@param callback fun(error: VVTranslateError?, result: VVTranslateResult?)
---@return fun()? cancel
function M.translate(request, config, callback)
  callback = Callback.limit(callback)

  local name = config.name
  local provider_config = config.providers[name] or {}
  local translate = provider_config.translate
  local present = provider_config.present
  local builtin

  local load_builtin = BUILTIN[name]
  if load_builtin then
    builtin = load_builtin()
    translate = translate or builtin.translate
    present = present or builtin.present
  end

  if not translate then
    callback(error_result(
      'provider_not_found',
      ('Unknown translation provider: %s'):format(tostring(name)),
      name
    ), nil)
    return nil
  end

  local function deliver(err, result)
    if err then
      if type(err) ~= 'table' or type(err.code) ~= 'string' or type(err.message) ~= 'string' then
        callback(error_result(
          'invalid_provider_error',
          ('Translation provider %s returned an invalid error'):format(name),
          name,
          err
        ), nil)
        return
      end

      callback(err, nil)
      return
    end

    if type(result) ~= 'table' then
      callback(error_result(
        'invalid_provider_result',
        ('Translation provider %s returned an invalid result'):format(name),
        name,
        result
      ), nil)
      return
    end

    if result.provider == nil then result.provider = name end

    if present then
      local present_ok, content = pcall(present, result, {
        request = request,
        config = provider_config,
      })

      if not present_ok then
        callback(error_result(
          'provider_presenter_failed',
          ('Translation provider %s failed to present its result'):format(name),
          name,
          content
        ), nil)
        return
      end

      if not Presentation.valid(content) then
        callback(error_result(
          'invalid_provider_content',
          ('Translation provider %s returned invalid display content'):format(name),
          name,
          content
        ), nil)
        return
      end

      result.content = content
    end

    if result.content ~= nil and not Presentation.valid(result.content) then
      callback(error_result(
        'invalid_provider_content',
        ('Translation provider %s returned invalid display content'):format(name),
        name,
        result.content
      ), nil)
      return
    end

    callback(nil, result)
  end
  deliver = Callback.limit(deliver)

  local ok, cancel_or_error = pcall(translate, request, provider_config, deliver)
  if not ok then
    callback(error_result(
      'provider_failed',
      ('Translation provider %s failed'):format(name),
      name,
      cancel_or_error
    ), nil)
    return nil
  end

  return cancel_or_error
end

return M
