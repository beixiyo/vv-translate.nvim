-- Provider 路由策略：按请求来源选择实际 provider，不执行翻译
local M = {}

local function normalize(selection)
  if type(selection) == 'string' then selection = { selection } end
  if type(selection) ~= 'table' then return nil end

  local providers = {}
  local seen = {}
  for _, provider in ipairs(selection) do
    if type(provider) ~= 'string' or provider == '' then return nil end
    if not seen[provider] then
      seen[provider] = true
      providers[#providers + 1] = provider
    end
  end
  if #providers == 0 then return nil end
  return providers
end

---解析请求依次尝试的 provider
---@param request VVTranslateRequest
---@param opts VVTranslateRouteOptions
---@return string[]? providers
---@return VVTranslateError? error
function M.resolve(request, opts)
  local route = opts.override

  if route == nil then route = opts.routes[request.kind] end
  if type(route) == 'function' then
    local ok, selected = pcall(route, request)

    if not ok then
      return nil, {
        code = 'provider_route_failed',
        message = 'Failed to select a translation provider',
        cause = selected,
      }
    end
    route = selected
  end

  local providers = normalize(route or opts.fallback)
  if not providers then
    return nil, {
      code = 'invalid_provider_route',
      message = 'Translation provider route must select one or more providers',
      cause = route,
    }
  end
  return providers
end

return M

---@class VVTranslateRouteOptions
---@field routes table<'word'|'selection'|'text', VVTranslateProviderSelection|fun(request: VVTranslateRequest): VVTranslateProviderSelection?>
---@field fallback VVTranslateProviderSelection
---@field override? VVTranslateProviderSelection

---@alias VVTranslateProviderSelection string|string[]
