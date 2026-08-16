-- MyMemory 非流式 provider：构造请求、解析响应并转换为通用展示内容
local Http = require('vv-utils.http')
local Bilingual = require('vv-translate.presentation.bilingual')

local M = {}

local DEFAULT_ENDPOINT = 'https://api.mymemory.translated.net/get'
local DEFAULT_SOURCE_LANGUAGE = 'en'
local DEFAULT_TARGET_LANGUAGE = 'zh-CN'
local MAX_QUERY_BYTES = 500

local function error_result(code, message, cause)
  return {
    code = code,
    message = message,
    provider = 'mymemory',
    cause = cause,
  }
end

local function configured_email(config)
  local email = config.email
  if email == nil then
    email = (vim.env and vim.env.MYMEMORY_EMAIL) or os.getenv('MYMEMORY_EMAIL')
  elseif type(email) == 'function' then
    local ok, value = pcall(email)
    if not ok then return nil, false end
    email = value
  end

  if email == nil or email == '' then return nil, true end
  if type(email) ~= 'string' then return nil, false end
  return email, true
end

local function response_status(value)
  if type(value) == 'number' then return value end
  if type(value) == 'string' and value:match('^%d+$') then return tonumber(value) end
end

local function safe_detail(detail)
  if type(detail) ~= 'string' or detail == '' then return nil end
  -- responseDetails 属于服务端诊断信息，不直接展示，避免回显请求内容或联系邮箱
  return 'The translation service returned an error'
end

local function parse_response(response)
  if type(response) ~= 'table' or type(response.status) ~= 'number' or type(response.body) ~= 'string' then
    return nil, error_result('mymemory_invalid_response', 'MyMemory returned an invalid HTTP response')
  end

  if response.status < 200 or response.status >= 300 then
    return nil, error_result('mymemory_http_error', ('MyMemory returned HTTP status %d'):format(response.status), {
      status = response.status,
    })
  end

  local decoded_ok, decoded = pcall(vim.json.decode, response.body)
  if not decoded_ok or type(decoded) ~= 'table' then
    return nil, error_result('mymemory_invalid_response', 'MyMemory returned invalid JSON')
  end

  local api_status = response_status(decoded.responseStatus)
  local response_data = decoded.responseData
  local translated_text = type(response_data) == 'table' and response_data.translatedText or nil
  if api_status ~= 200 then
    return nil, error_result('mymemory_api_error', 'MyMemory rejected the translation request', {
      response_status = decoded.responseStatus,
      response_details = safe_detail(decoded.responseDetails),
    })
  end

  if type(response_data) ~= 'table' or type(translated_text) ~= 'string' or translated_text == '' then
    return nil, error_result('mymemory_invalid_response', 'MyMemory returned no translated text', {
      response_status = decoded.responseStatus,
      response_details = safe_detail(decoded.responseDetails),
    })
  end

  return {
    provider = 'mymemory',
    text = translated_text,
    data = decoded,
  }
end

---使用 MyMemory Get API 翻译单个非流式请求
---@param request VVTranslateRequest
---@param config VVTranslateMyMemoryProviderConfig
---@param callback fun(error: VVTranslateError?, result: VVTranslateResult?)
---@return fun() cancel
function M.translate(request, config, callback)
  config = config or {}
  if type(request) ~= 'table' or type(request.text) ~= 'string' then
    callback(error_result('mymemory_invalid_request', 'MyMemory requires a text string'))
    return function() end
  end

  if #request.text > MAX_QUERY_BYTES then
    callback(error_result('mymemory_text_too_long', 'MyMemory requests must be 500 bytes or fewer'))
    return function() end
  end

  local source_language = request.source_language or config.source_language or DEFAULT_SOURCE_LANGUAGE
  local target_language = request.target_language or config.target_language or DEFAULT_TARGET_LANGUAGE
  local endpoint = config.endpoint or DEFAULT_ENDPOINT
  if type(source_language) ~= 'string' or type(target_language) ~= 'string' or type(endpoint) ~= 'string' then
    callback(error_result('mymemory_invalid_config', 'MyMemory provider configuration is invalid'))
    return function() end
  end

  local email, email_ok = configured_email(config)
  if not email_ok then
    callback(error_result('mymemory_invalid_config', 'MyMemory provider configuration is invalid'))
    return function() end
  end

  local query = {
    q = request.text,
    langpair = source_language .. '|' .. target_language,
  }
  if email then query.de = email end
  local url = Http.append_query(endpoint, query)
  local settled = false
  local cancelled = false
  local transport_cancel

  local function finish(err, result)
    if settled or cancelled then return end
    settled = true
    callback(err, result)
  end

  local ok, cancel_or_error = pcall(Http.request, {
    url = url,
    method = 'GET',
    headers = { Accept = 'application/json' },
    timeout_ms = config.timeout_ms,
  }, function(transport_error, response)
    if transport_error then
      finish(error_result('mymemory_request_failed', 'MyMemory translation request failed', {
        type = 'transport',
      }))
      return
    end

    local result, parse_error = parse_response(response)
    if parse_error then
      finish(parse_error)
    else
      finish(nil, result)
    end
  end)

  if not ok then
    finish(error_result('mymemory_request_failed', 'MyMemory translation request failed', {
      type = 'transport_exception',
    }))
  elseif type(cancel_or_error) == 'function' then
    transport_cancel = cancel_or_error
  end

  return function()
    if cancelled then return end
    cancelled = true
    if transport_cancel then pcall(transport_cancel) end
  end
end

---将 MyMemory 结果转换为浮窗展示契约
---@param result VVTranslateResult
---@param context VVTranslatePresentContext
---@return VVTranslateContent
function M.present(result, context)
  return Bilingual.render(context.request.text, result.text or '')
end

return M

---@class VVTranslateMyMemoryProviderConfig: VVTranslateProviderConfig
---@field endpoint? string MyMemory Get API 地址；默认官方 endpoint
---@field source_language? string provider 默认源语言代码；默认 en，请求级 source_language 优先
---@field target_language? string provider 默认目标语言代码；默认 zh-CN，请求级 target_language 优先
---@field email? string|fun(): string 通过 de 参数提供的联系邮箱；默认读取 MYMEMORY_EMAIL
---@field timeout_ms? integer HTTP 请求超时毫秒数
