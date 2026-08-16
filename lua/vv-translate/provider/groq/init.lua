-- Groq provider：通过 OpenAI-compatible Chat Completions API 执行非流式翻译
local M = {}
local Http = require('vv-utils.http')
local Bilingual = require('vv-translate.presentation.bilingual')

local PROVIDER = 'groq'
local DEFAULT_ENDPOINT = 'https://api.groq.com/openai/v1/chat/completions'
local DEFAULT_MODEL = 'qwen/qwen3.6-27b'
local DEFAULT_TIMEOUT_MS = 30000
local DEFAULT_TARGET_LANGUAGE = 'Simplified Chinese'
local DEFAULT_SYSTEM_PROMPT = table.concat({
  'You are a professional translator.',
  'Translate the user text accurately and naturally.',
  'Preserve meaning, formatting, code, punctuation, and line breaks.',
  'Return only the translation without explanations.',
})

local function provider_error(code, message, cause)
  return {
    code = code,
    message = message,
    provider = PROVIDER,
    cause = cause,
  }
end

local function resolve_api_key(config)
  local configured = config.api_key
  if configured ~= nil then
    if type(configured) == 'function' then
      local ok, value = pcall(configured)
      if not ok then return nil, provider_error('invalid_api_key', 'Unable to resolve the Groq API key') end
      configured = value
    end
    if type(configured) ~= 'string' then
      return nil, provider_error('invalid_api_key', 'Groq API key must be a string or function')
    end
    if vim.trim(configured) == '' then
      return nil, provider_error('missing_api_key', 'Groq API key is not configured')
    end
    return configured
  end

  local environment_key = (vim.env and vim.env.GROQ_API_KEY) or os.getenv('GROQ_API_KEY')
  if type(environment_key) ~= 'string' or vim.trim(environment_key) == '' then
    return nil, provider_error('missing_api_key', 'Groq API key is not configured')
  end
  return environment_key
end

local function decode_response(response)
  if type(response) ~= 'table' then
    return nil, provider_error('invalid_response', 'Groq returned an empty response')
  end

  local status = tonumber(response.status)
  if not status or status < 200 or status >= 300 then
    if status then
      return nil, provider_error('http_error', ('Groq request failed with HTTP status %d'):format(status), {
        status = status,
      })
    end
    return nil, provider_error('invalid_response', 'Groq returned an invalid HTTP response')
  end

  if type(response.body) ~= 'string' then
    return nil, provider_error('invalid_response', 'Groq returned an invalid response body')
  end

  local ok, decoded = pcall(vim.json.decode, response.body)
  if not ok or type(decoded) ~= 'table' then
    return nil, provider_error('invalid_response', 'Groq returned invalid JSON')
  end

  local choices = decoded.choices
  local first_choice = type(choices) == 'table' and choices[1] or nil
  local message = type(first_choice) == 'table' and first_choice.message or nil
  local content = type(message) == 'table' and message.content or nil
  if type(content) ~= 'string' or content == '' then
    return nil, provider_error('invalid_response', 'Groq returned no translation content')
  end

  return decoded, content
end

local function target_language(request, config)
  local requested = request and request.target_language
  if type(requested) == 'string' and vim.trim(requested) ~= '' then return requested end

  local configured = config.target_language
  if type(configured) == 'string' and vim.trim(configured) ~= '' then return configured end

  return DEFAULT_TARGET_LANGUAGE
end

---调用 Groq Chat Completions API，使用非流式响应返回完整翻译结果
---@param request VVTranslateRequest
---@param config VVTranslateGroqProviderConfig
---@param callback fun(error: VVTranslateError?, result: VVTranslateResult?)
---@return fun() cancel 幂等取消函数
function M.translate(request, config, callback)
  config = config or {}

  local finished = false
  local cancel_called = false
  local transport_cancel

  local function cancel()
    if cancel_called then return end
    cancel_called = true
    if finished then return end
    finished = true
    if type(transport_cancel) == 'function' then pcall(transport_cancel) end
  end

  local function finish(error, result)
    if finished then return end
    finished = true
    callback(error, result)
  end

  local api_key, key_error = resolve_api_key(config)
  if not api_key then
    finish(key_error, nil)
    return cancel
  end

  local payload = {
    model = config.model or DEFAULT_MODEL,
    messages = {
      {
        role = 'system',
        content = ('%s\nTranslate the text into %s.'):format(
          config.system_prompt or DEFAULT_SYSTEM_PROMPT,
          target_language(request, config)
        ),
      },
      { role = 'user', content = request.text },
    },
    stream = false,
  }

  local ok_encode, body = pcall(vim.json.encode, payload)
  if not ok_encode then
    finish(provider_error('request_encode_failed', 'Failed to encode the Groq request'), nil)
    return cancel
  end

  local transport_request = {
    url = config.endpoint or DEFAULT_ENDPOINT,
    method = 'POST',
    headers = {
      ['Authorization'] = 'Bearer ' .. api_key,
      ['Content-Type'] = 'application/json',
    },
    body = body,
    timeout_ms = config.timeout_ms or DEFAULT_TIMEOUT_MS,
  }

  local ok_request, request_cancel = pcall(Http.request, transport_request, function(transport_error, response)
    if finished then return end
    if transport_error then
      finish(provider_error('request_failed', 'Groq request failed'), nil)
      return
    end

    local data, content_or_error = decode_response(response)
    if not data then
      finish(content_or_error, nil)
      return
    end

    finish(nil, {
      provider = PROVIDER,
      text = content_or_error,
      data = data,
    })
  end)

  if not ok_request then
    finish(provider_error('request_failed', 'Groq request failed'), nil)
  elseif type(request_cancel) == 'function' then
    transport_cancel = request_cancel
    if cancel_called then pcall(transport_cancel) end
  end

  return cancel
end

---将 Groq 的翻译文本转换为通用浮窗展示内容
---@param result VVTranslateResult
---@param context VVTranslatePresentContext
---@return VVTranslateContent
function M.present(result, context)
  if type(result.text) ~= 'string' then
    return { lines = { 'Groq returned no displayable translation' } }
  end
  return Bilingual.render(context.request.text, result.text)
end

---@class VVTranslateGroqProviderConfig: VVTranslateProviderConfig
---@field api_key? string|fun(): string Groq API key；默认读取 GROQ_API_KEY
---@field endpoint? string Chat Completions endpoint；默认 Groq 官方 endpoint
---@field model? string 模型 ID；默认 qwen/qwen3.6-27b
---@field system_prompt? string 系统提示词
---@field target_language? string 目标语言；request.target_language 优先，默认 Simplified Chinese
---@field timeout_ms? integer 请求超时毫秒数；默认 30000

return M
