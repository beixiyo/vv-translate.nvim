-- vv-translate.nvim 公共入口：组合取词、标识符处理、异步 provider 和浮窗
local Async = require('vv-utils.async')
local Dictionary = require('vv-translate.dictionary')
local Identifier = require('vv-translate.identifier')
local Provider = require('vv-translate.provider')
local Source = require('vv-translate.source')
local View = require('vv-translate.view')
local Highlights = require('vv-translate.view.highlights')

local M = {}
local config = {}
local scope = Async.scope({ cancel_previous = true })

local defaults = {
  provider = 'local',
  providers = {
    ['local'] = {},
  },
  highlights = {},
  view = {
    max_width = 72,
    max_height = 16,
    wrap = true,
    keymaps = {
      close = { 'q', '<Esc>' },
      scroll_down = '<C-e>',
      scroll_up = '<C-y>',
    },
    loading = {
      preset = 'braille',
      interval_ms = 80,
      hl = 'VVTranslatePhonetic',
      virt_text_pos = 'eol',
    },
    window = {
      border = 'rounded',
      title_pos = 'center',
    },
  },
}

---关闭浮窗并取消当前翻译
function M.close()
  scope:cancel()
  View.close(false)
end

---下载并安装最新版离线词典
---@param callback? fun(result: VVTranslateDictionaryInstallResult)
---@return fun() cancel
function M.download_dictionary(callback)
  vim.notify('Downloading the latest translation dictionary...')
  local local_config = config.providers and config.providers['local'] or {}
  return Dictionary.download_latest({ destination = local_config.dictionary_path }, function(result)
    if result.ok then
      vim.notify(('Translation dictionary %s installed'):format(result.version))
    else
      vim.notify('Failed to install translation dictionary: ' .. result.message, vim.log.levels.ERROR)
    end
    if callback then callback(result) end
  end)
end

---翻译给定文本
---@param text string
---@param opts? VVTranslateTextOptions
function M.translate_text(text, opts)
  opts = opts or {}
  text = vim.trim(text)
  if text == '' then
    vim.notify('No text to translate', vim.log.levels.WARN)
    return
  end

  local query = opts.identifier and Identifier.normalize(text) or text
  M.close()
  local request_payload = {
    text = query,
    kind = opts.kind or 'text',
    source_language = opts.source_language,
    target_language = opts.target_language,
    metadata = opts.metadata,
  }
  View.open(request_payload, function() scope:cancel() end)

  local request = scope:begin({ key = 'translate', mode = 'latest' })
  local cancel = Provider.translate(request_payload, {
    name = config.provider,
    providers = config.providers,
  }, function(err, result)
    if not request:finish() then return end
    if err then
      View.error(request_payload, err)
    else
      View.result(request_payload, result)
    end
  end)
  if cancel then request:set_cancel(cancel) end
end

---翻译光标下的单词
function M.translate_word()
  local text = Source.word()
  if not text then
    vim.notify('No translatable word under the cursor', vim.log.levels.WARN)
    return
  end
  M.translate_text(text, { identifier = true, kind = 'word' })
end

---翻译 Visual 选区
function M.translate_visual()
  local text = Source.visual()
  if not text then
    vim.notify('The visual selection is empty', vim.log.levels.WARN)
    return
  end
  M.translate_text(text, { identifier = false, kind = 'selection' })
end

---根据当前模式翻译光标词或选区
function M.translate()
  local mode = vim.fn.mode(1)
  if mode == 'v' or mode == 'V' or mode == '\22' then
    M.translate_visual()
  else
    M.translate_word()
  end
end

---初始化插件
---@param opts? VVTranslateConfig
function M.setup(opts)
  config = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
  Highlights.setup(config.highlights)
  View.setup(config.view)

  vim.api.nvim_create_user_command('VVTranslate', M.translate, { desc = 'Translate word or visual selection', force = true })
  vim.api.nvim_create_user_command('VVTranslateWord', M.translate_word, { desc = 'Translate word under cursor', force = true })
  vim.api.nvim_create_user_command('VVTranslateVisual', M.translate_visual, { desc = 'Translate visual selection', force = true })
  vim.api.nvim_create_user_command('VVTranslateClose', M.close, { desc = 'Close translation', force = true })
  vim.api.nvim_create_user_command('VVTranslateDownloadDictionary', M.download_dictionary, {
    desc = 'Download the latest offline translation dictionary',
    force = true,
  })
end

---返回归一化后的配置副本
---@return VVTranslateConfig
function M.get_config()
  return vim.deepcopy(config)
end

return M

---@class VVTranslateConfig
---@field provider? string 当前 provider 名称 @default 'local'
---@field providers? table<string, VVTranslateProviderConfig> provider 配置表
---@field highlights? VVTranslateHighlightConfig 语义高亮覆盖；默认链接当前主题
---@field view? VVTranslateViewConfig 浮窗配置

---@class VVTranslateTextOptions
---@field identifier? boolean 是否按代码标识符规范化 @default false
---@field kind? 'word'|'selection'|'text' 请求来源 @default 'text'
---@field source_language? string 源语言；provider 可选择是否使用
---@field target_language? string 目标语言；provider 可选择是否使用
---@field metadata? table 调用方透传元数据

---@class VVTranslateProviderOptions
---@field name string 当前 provider 名称
---@field providers table<string, VVTranslateProviderConfig>

---@class VVTranslateProviderConfig
---@field translate? fun(request: VVTranslateRequest, config: VVTranslateProviderConfig, callback: fun(error: VVTranslateError?, result: VVTranslateResult?)): cancel: fun()?
---@field present? fun(result: VVTranslateResult, context: VVTranslatePresentContext): VVTranslateContent
---@field [string] any provider 自有配置

---@class VVTranslateLocalProviderConfig: VVTranslateProviderConfig
---@field dictionary_path? string 本地词典目录；默认插件根目录下的 `dict`

---@class VVTranslateRequest
---@field text string 已按调用场景规范化的待翻译文本
---@field kind 'word'|'selection'|'text' 请求来源
---@field source_language? string
---@field target_language? string
---@field metadata? table

---@class VVTranslateResult
---@field text? string 简单 provider 可直接提供的翻译文本
---@field provider string 实际执行翻译的 provider
---@field data? any provider 的完整原始结果
---@field content? VVTranslateContent provider presenter 生成的通用展示内容
---@field metadata? table provider 返回的扩展元数据
---@field highlights? VVTranslateContentHighlight[] 可选语义高亮范围
---@field [string] any provider 可以保留其他私有返回字段

---@class VVTranslateError
---@field code string 稳定错误码
---@field message string 英文用户可见错误
---@field provider? string
---@field cause? any 仅供诊断，不直接展示

---@alias VVTranslateHighlightRole 'source'|'phonetic'|'part_of_speech'|'translation'|'missing'|'error'

---@class VVTranslateContentHighlight
---@field row integer 从 0 开始的行号
---@field start_col integer 从 0 开始的字节列
---@field end_col integer 结尾字节列，不包含该列
---@field role VVTranslateHighlightRole 语义类型

---@class VVTranslateContent
---@field title? string 浮窗标题
---@field lines string[]
---@field highlights? VVTranslateContentHighlight[]

---@class VVTranslatePresentContext
---@field request VVTranslateRequest
---@field config VVTranslateProviderConfig

---@alias VVTranslateViewEvent 'loading'|'result'|'error'

---@class VVTranslateRenderContext
---@field request VVTranslateRequest
---@field result? VVTranslateResult
---@field error? VVTranslateError
---@field default_render fun(): VVTranslateContent

---@class VVTranslateHighlightConfig
---@field source? vim.api.keyset.highlight 查询词 @default link Title
---@field phonetic? vim.api.keyset.highlight 音标 @default link Comment
---@field part_of_speech? vim.api.keyset.highlight 词性 @default link Type
---@field translation? vim.api.keyset.highlight 释义 @default link NormalFloat
---@field missing? vim.api.keyset.highlight 缺词提示 @default link DiagnosticWarn
---@field error? vim.api.keyset.highlight 错误 @default link DiagnosticError

---@class VVTranslateViewConfig
---@field max_width? integer 最大宽度；默认 72
---@field max_height? integer 最大高度；默认 16
---@field wrap? boolean 是否换行 @default true
---@field keymaps? VVTranslateViewKeymaps 来源 buffer 的临时浮窗控制键
---@field loading? VVTranslateLoadingConfig loading 动画配置
---@field window? vim.api.keyset.win_config 不含动态计算的 width、height 和 title
---@field render? fun(event: VVTranslateViewEvent, context: VVTranslateRenderContext): VVTranslateContent 自定义内容 renderer

---@class VVTranslateViewKeymaps
---@field close? string[] 关闭浮窗 @default { 'q', '<Esc>' }
---@field scroll_down? string|false 向下滚动浮窗 @default '<C-e>'
---@field scroll_up? string|false 向上滚动浮窗 @default '<C-y>'

---@class VVTranslateLoadingConfig
---@field preset? 'braille'|'dots'|'bounce' vv-utils.loading 预设 @default 'braille'
---@field frames? string[] 自定义动画帧；优先于 preset
---@field interval_ms? integer 帧间隔 @default 80
---@field hl? string 高亮组 @default 'VVTranslatePhonetic'
---@field prefix? string 帧前缀 @default ' '
---@field virt_text_pos? 'eol'|'inline'|'right_align' @default 'eol'
---@field hl_mode? 'replace'|'combine'|'blend' @default 'combine'
