-- vv-translate.nvim 公共入口：组合取词、标识符处理、异步 provider 和浮窗
local Async = require('vv-utils.async')
local Dictionary = require('vv-translate.dictionary')
local Identifier = require('vv-translate.identifier')
local Provider = require('vv-translate.provider')
local Fallback = require('vv-translate.provider.fallback')
local Route = require('vv-translate.provider.route')
local Source = require('vv-translate.source')
local View = require('vv-translate.view')
local Highlights = require('vv-translate.view.highlights')

local M = {}
local config = {}
local scope = Async.scope({ cancel_previous = true })

local function default_sentence_route(request)
  if config.provider ~= 'local' then return nil end
  if request.text:match('^[%a%d_%-]+$') then return nil end

  if vim.env.GROQ_API_KEY and vim.trim(vim.env.GROQ_API_KEY) ~= '' then
    return { 'groq', 'mymemory', 'local' }
  end
  return { 'mymemory', 'local' }
end

local defaults = {
  provider = 'local',
  routes = {
    selection = default_sentence_route,
    text = default_sentence_route,
  },
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
  local request_payload = {
    text = query,
    kind = opts.kind or 'text',
    source_language = opts.source_language,
    target_language = opts.target_language,
    metadata = opts.metadata,
  }
  local provider_names, route_error = Route.resolve(request_payload, {
    routes = config.routes,
    fallback = config.provider,
    override = opts.provider,
  })

  M.close()
  View.open(request_payload, function() scope:cancel() end)
  if route_error then
    View.error(request_payload, route_error)
    return
  end

  local request = scope:begin({ key = 'translate', mode = 'latest' })
  local cancel = Fallback.run({
    providers = provider_names,
    run = function(provider_name, callback)
      local local_config = config.providers and config.providers['local'] or {}
      local dictionary_path = local_config.dictionary_path
        or require('vv-translate.provider.local.dictionary').default_path()

      if provider_name == 'local' and vim.fn.isdirectory(dictionary_path) ~= 1 then
        local installing = true
        local install_cancel
        local provider_cancel
        local cancelled = false

        install_cancel = M.download_dictionary(function(result)
          installing = false
          if cancelled then return end
          if result.ok then
            provider_cancel = Provider.translate(request_payload, {
              name = provider_name,
              providers = config.providers,
            }, callback)
          else
            callback({
              code = result.code or 'dictionary_install_failed',
              message = result.message or 'Failed to install the offline dictionary',
              provider = 'local',
            }, nil)
          end
        end)

        return function()
          if cancelled then return end
          cancelled = true
          if installing and install_cancel then
            install_cancel()
          elseif provider_cancel then
            provider_cancel()
          end
        end
      end

      return Provider.translate(request_payload, {
        name = provider_name,
        providers = config.providers,
      }, callback)
    end,
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
---@field provider? VVTranslateProviderSelection 默认 provider 或 fallback 顺序 @default 'local'
---@field routes? table<'word'|'selection'|'text', VVTranslateProviderSelection|fun(request: VVTranslateRequest): VVTranslateProviderSelection?> 按请求来源选择 provider 或 fallback 顺序
---@field providers? table<string, VVTranslateProviderConfig> provider 配置表
---@field highlights? VVTranslateHighlightConfig 语义高亮覆盖；默认链接当前主题
---@field view? VVTranslateViewConfig 浮窗配置

---@class VVTranslateTextOptions
---@field identifier? boolean 是否按代码标识符规范化 @default false
---@field kind? 'word'|'selection'|'text' 请求来源 @default 'text'
---@field source_language? string 源语言；provider 可选择是否使用
---@field target_language? string 目标语言；provider 可选择是否使用
---@field metadata? table 调用方透传元数据
---@field provider? VVTranslateProviderSelection 单次调用显式指定 provider 或 fallback 顺序

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
