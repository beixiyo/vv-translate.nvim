-- 翻译浮窗语义高亮：默认链接主题高亮组，并允许用户完整覆盖
local Registry = require('vv-utils.hl')

local M = {}

local groups = {
  source = 'VVTranslateSource',
  phonetic = 'VVTranslatePhonetic',
  part_of_speech = 'VVTranslatePartOfSpeech',
  translation = 'VVTranslateTranslation',
  missing = 'VVTranslateMissing',
  error = 'VVTranslateError',
}

local defaults = {
  source = { link = 'Title' },
  phonetic = { link = 'Comment' },
  part_of_speech = { link = 'Type' },
  translation = { link = 'NormalFloat' },
  missing = { link = 'DiagnosticWarn' },
  error = { link = 'DiagnosticError' },
}

---注册语义高亮；用户配置按单个语义完整覆盖默认 spec
---@param overrides? VVTranslateHighlightConfig
function M.setup(overrides)
  local specs = {}
  for role, name in pairs(groups) do
    specs[name] = vim.deepcopy(overrides and overrides[role] or defaults[role])
  end
  Registry.register('VVTranslateHighlights', specs, { default = false })
end

---返回语义对应的实际高亮组
---@param role VVTranslateHighlightRole
---@return string?
function M.group(role)
  return groups[role]
end

return M
