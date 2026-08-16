<div align="center">

# vv-translate.nvim

面向 Neovim 代码标识符和 Visual 选区的离线优先翻译插件

[English](README.md) | [中文](README.zh-CN.md)

</div>

## 功能

- Normal 模式下翻译光标所在单词
- Visual 模式下翻译精确选区
- 自动拆分 `camelCase`、`PascalCase`、`snake_case`、`kebab-case` 和连续大写缩写
- 使用可下载的英汉词典，翻译时无需网络或外部命令
- 按需加载词典分片，并阻止过期请求覆盖最新结果
- 支持同步或异步的自定义翻译 provider

## 环境要求

- Neovim 0.12+
- [vv-utils.nvim](https://github.com/beixiyo/vv-utils.nvim)
- `curl`（Windows 使用系统自带的 `curl.exe`）

## 安装

```lua
{
  'beixiyo/vv-translate.nvim',
  dependencies = { 'beixiyo/vv-utils.nvim' },
  cmd = {
    'VVTranslate',
    'VVTranslateWord',
    'VVTranslateVisual',
    'VVTranslateClose',
    'VVTranslateDownloadDictionary',
  },
  keys = {
    { '<leader>tw', '<cmd>VVTranslate<cr>', mode = { 'n', 'x' }, desc = 'Translate text' },
  },
  opts = {},
}
```

## 配置

```lua
require('vv-translate').setup({
  provider = 'local',
  providers = {
    ['local'] = {
      -- dictionary_path = '/path/to/dict',
    },
  },
  highlights = {
    -- source = { link = 'Title' },
    -- phonetic = { link = 'Comment' },
    -- part_of_speech = { link = 'Type' },
    -- translation = { link = 'NormalFloat' },
    -- missing = { link = 'DiagnosticWarn' },
    -- error = { link = 'DiagnosticError' },
  },
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
      preset = 'braille', -- braille | dots | bounce
      interval_ms = 80,
      hl = 'VVTranslatePhonetic',
      virt_text_pos = 'eol',
    },
    window = {
      relative = 'cursor',
      row = 1,
      col = 0,
      border = 'rounded',
      focusable = false,
      zindex = 60,
      title_pos = 'center',
    },
  },
})
```

首次翻译时，如果本地没有词典，插件会自动下载最新 Release，校验 SHA-256 与 manifest，再安装到 `<plugin-root>/dict` 并继续刚才的翻译。之后内置 `local` provider 翻译时不依赖 `translate-shell` 或任何网络服务。插件启动时不会检查更新；需要更新或重新安装时可手动执行 `:VVTranslateDownloadDictionary`

浮窗打开期间，其控制键会临时接管来源 buffer：Normal 或 Visual 模式下使用 `<C-e>`、`<C-y>` 滚动翻译内容，使用 `q`、`<Esc>` 关闭浮窗。关闭后会恢复原有 buffer-local 映射

## 使用

- `:VVTranslate` 根据当前模式翻译光标词或活动 Visual 选区
- `:VVTranslateWord` 翻译光标下的单词
- `:VVTranslateVisual` 翻译当前或最近一次 Visual 选区
- `:VVTranslateClose` 关闭浮窗并取消当前请求
- `:VVTranslateDownloadDictionary` 下载并安装最新版离线词典

## 句子翻译

默认情况下，单个英文单词或代码标识符使用本地词典；Visual 自然语言选区和直接文本请求在存在 `GROQ_API_KEY` 时优先使用 Groq，否则使用 MyMemory；API 错误或超时后最终回退到本地词典：

```text
单词 / getUserProfile → local
句子且存在 key       → groq → mymemory → local
句子且没有 key       → mymemory → local
```

默认无需配置 routes。需要调整顺序或根据内容自定义策略时再覆盖：

```lua
local sentence_providers = vim.env.GROQ_API_KEY
  and { 'groq', 'mymemory' }
  or { 'mymemory' }

require('vv-translate').setup({
  provider = 'local',
  routes = {
    word = 'local',
    selection = sentence_providers,
    text = function(request)
      if #request.text > 500 then return { 'groq' } end
      return sentence_providers
    end,
  },
  providers = {
    ['local'] = {},
    groq = {
      -- api_key = function() return vim.env.GROQ_API_KEY end,
      -- model = 'qwen/qwen3.6-27b',
      -- target_language = 'Simplified Chinese',
    },
    mymemory = {
      -- email = function() return vim.env.MYMEMORY_EMAIL end,
      -- source_language = 'en',
      -- target_language = 'zh-CN',
    },
  },
})
```

在 [Groq Console](https://console.groq.com/keys) 免费创建 key，然后在启动 Neovim 前设置环境变量：

```sh
export GROQ_API_KEY='gsk_...'
```

Groq provider 使用非流式 Chat Completions 请求，默认读取 `GROQ_API_KEY`。`api_key` 也可以直接传字符串或返回字符串的函数。默认模型为 `qwen/qwen3.6-27b`，默认目标语言为简体中文

MyMemory 无需 key 即可匿名使用，官方额度为每天 5000 字符、单次最多 500 bytes。设置 `MYMEMORY_EMAIL` 后，官方额度提高到每天 50000 字符。发送给任一云端 provider 的文本都会离开本机，只应在接受这一行为时配置相应路由。详见 [MyMemory API](https://mymemory.translated.net/doc/spec.php) 和[使用限制](https://mymemory.translated.net/doc/usagelimits.php)

每条 route 可以是 provider 名称、按顺序排列的 provider 数组，也可以是接收完整请求并返回上述任一形式的函数

数组中的 provider 返回错误时会从左到右继续尝试；成功或取消会立即停止

顶层 `provider` 同样支持字符串或数组，但只有 route 未匹配或函数返回 `nil` 时才使用，不会把它偷偷追加到显式 route 数组末尾

fallback 成功后，之前的失败摘要保存在 `result.metadata.fallback.attempts`。`translate_text()` 的单次 `provider` 覆盖也支持相同形式

配置数组代表用户明确允许前一个 provider 失败后，把同一段文本继续发送给后续服务；只应加入可以接受其隐私行为的 provider

## 自定义 provider

Provider 接收结构化请求，可以同步或异步完成翻译。结果可以包含简单 `text`、可直接展示的 `content`、任意结构的 `data`，也可以同时包含它们。Provider 还可以返回一个可选的幂等取消函数

```lua
require('vv-translate').setup({
  provider = 'example',
  providers = {
    example = {
      endpoint = 'https://example.com/translate',
      translate = function(request, config, callback)
        -- 使用 request.text 和 config.endpoint 发起 HTTP 请求
        local response = {
          detected_language = 'en',
          translations = { { text = '翻译结果' } },
        }
        callback(nil, {
          provider = 'example',
          data = {
            detected_language = 'en',
            translations = response.translations,
          },
        })

        return function()
          -- 取消尚未完成的请求
        end
      end,

      present = function(result, context)
        return {
          title = ('Example · %s'):format(result.data.detected_language),
          lines = { result.data.translations[1].text },
          highlights = {},
        }
      end,
    },
  },
})
```

请求包含 `text`、`kind`，以及可选的 `source_language`、`target_language` 和 `metadata`。错误使用 `{ code, message, provider?, cause? }`；其中 `message` 必须是可直接展示给用户的英文信息

`present(result, context)` 是可选函数，用于把 provider 私有 `data` 转换为通用的 `{ title?, lines, highlights? }` 内容。没有 presenter 时，默认 renderer 会依次使用 `content`、`text`，最后把任意 `data` 渲染为可读的嵌套键值列表。其他 provider 私有字段会原样保留在 `result` 上，供自定义 renderer 使用

## 自定义渲染

通过 `view.render` 可以自定义 loading、result 和 error 内容，同时继续复用内置浮窗的生命周期、取消、尺寸计算和资源清理：

```lua
view = {
  render = function(event, context)
    if event ~= 'result' then return context.default_render() end

    return {
      title = 'My translation',
      lines = { context.result.data.translations[1].text },
      highlights = {},
    }
  end,
}
```

Renderer 可以读取原始请求以及完整的 provider 结果或错误。调用 `context.default_render()` 可以把任意事件交回通用默认 renderer

Provider 自己负责鉴权、网络传输、重试、响应解析和私有数据展示转换。核心负责选择 provider、保证回调只生效一次、提供通用默认渲染，并防止过期请求更新界面

## 离线词典

可下载的离线词典改编自采用 MIT 许可证的 [w88975/code-translate-vscode](https://github.com/w88975/code-translate-vscode)，固定来源提交为 `e280dbb1cad87c848f99c17fcd31d63050d395b4`，感谢原作者和贡献者

## 许可证

[MIT](LICENSE)
