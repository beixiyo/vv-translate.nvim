<div align="center">

# vv-translate.nvim

Offline-first translation for code identifiers and visual selections in Neovim

[English](README.md) | [中文](README.zh-CN.md)

</div>

## Features

- Translates the word under the cursor in Normal mode
- Translates the exact selection in Visual mode
- Splits `camelCase`, `PascalCase`, `snake_case`, `kebab-case`, and uppercase abbreviations
- Uses a downloadable English-Chinese dictionary without network access during translation
- Loads dictionary shards on demand and prevents stale requests from replacing newer results
- Supports custom synchronous or asynchronous translation providers

## Requirements

- Neovim 0.12+
- [vv-utils.nvim](https://github.com/beixiyo/vv-utils.nvim)
- `curl` (`curl.exe` on Windows)

## Installation

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

## Configuration

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

On the first translation, a missing dictionary is downloaded automatically from the latest Release, verified with its SHA-256 checksum and manifest, and installed to `<plugin-root>/dict`. The built-in `local` provider does not require `translate-shell` or any network service after that. No update check runs at startup; use `:VVTranslateDownloadDictionary` whenever you want to update or reinstall it manually.

While the floating window is open, its controls temporarily take precedence in the source buffer: `<C-e>` and `<C-y>` scroll the translation, while `q` and `<Esc>` close it in Normal or Visual mode. Previous buffer-local mappings are restored when the window closes.

## Usage

- `:VVTranslate` translates the word under the cursor or the active Visual selection
- `:VVTranslateWord` translates the word under the cursor
- `:VVTranslateVisual` translates the current or most recent Visual selection
- `:VVTranslateClose` closes the floating window and cancels the current request
- `:VVTranslateDownloadDictionary` downloads and installs the latest offline dictionary

## Sentence translation

By default, a single English word or code identifier uses the local dictionary. Natural-language selections and direct text requests use Groq when `GROQ_API_KEY` is available, otherwise MyMemory, and finally fall back to the local dictionary after API errors or timeouts:

```text
word / getUserProfile  -> local
sentence with key      -> groq -> mymemory -> local
sentence without key   -> mymemory -> local
```

No routing configuration is required. Override the defaults when you want a different order or content-aware policy:

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

Create a free Groq key at [Groq Console](https://console.groq.com/keys), then expose it before starting Neovim:

```sh
export GROQ_API_KEY='gsk_...'
```

The Groq provider uses a non-streaming Chat Completions request and reads `GROQ_API_KEY` by default. `api_key` may also be a string or a function. The default model is `qwen/qwen3.6-27b` and the default target is Simplified Chinese.

MyMemory works anonymously without a key. Its official limit is 5,000 characters per day and 500 bytes per request. Setting `MYMEMORY_EMAIL` raises the documented daily limit to 50,000 characters. Text sent to either cloud provider leaves the local machine; configure a route only when that is acceptable. See the [MyMemory API specification](https://mymemory.translated.net/doc/spec.php) and [usage limits](https://mymemory.translated.net/doc/usagelimits.php).

Each route accepts a provider name, an ordered provider array, or a function receiving the complete request and returning either form. Arrays are tried from left to right whenever a provider returns an error; success and cancellation stop the chain. The top-level `provider` accepts a string or array and is used only when no route matches or a route function returns `nil`—it is not appended to an explicit route array. A successful fallback records prior failures in `result.metadata.fallback.attempts`. `translate_text()` accepts the same forms as a one-off `provider` override.

An ordered array explicitly authorizes sending the same text to later services after an earlier failure. Use only providers whose privacy behavior you accept.

## Custom providers

Providers receive a structured request and may complete synchronously or asynchronously. Results may expose simple `text`, ready-to-render `content`, arbitrary structured `data`, or any combination of them. A provider can return an optional idempotent cancellation function.

```lua
require('vv-translate').setup({
  provider = 'example',
  providers = {
    example = {
      endpoint = 'https://example.com/translate',
      translate = function(request, config, callback)
        -- Start an HTTP request with request.text and config.endpoint
        local response = {
          detected_language = 'en',
          translations = { { text = 'translated text' } },
        }
        callback(nil, {
          provider = 'example',
          data = {
            detected_language = 'en',
            translations = response.translations,
          },
        })

        return function()
          -- Cancel the pending request
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

The request contains `text`, `kind`, and optional `source_language`, `target_language`, and `metadata` fields. Errors use `{ code, message, provider?, cause? }`; `message` must be suitable for display to users.

`present(result, context)` is optional. It converts provider-specific `data` into common `{ title?, lines, highlights? }` content. Without a presenter, the default renderer uses `content`, then `text`, and finally renders arbitrary `data` as a readable nested key-value list. Other provider-specific fields remain available on `result` for a custom renderer.

## Custom rendering

Use `view.render` to customize loading, result, and error content while retaining the built-in floating-window lifecycle, cancellation, sizing, and cleanup:

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

The renderer receives the original request and the complete provider result or error. Calling `context.default_render()` delegates any event to the generic renderer.

Provider-specific authentication, transport, retry, response parsing, and presentation belong to the provider itself. The core selects a provider, enforces a single callback result, provides generic rendering, and protects the UI from stale requests.

## Offline dictionary

The downloadable offline dictionary is adapted from the MIT-licensed [w88975/code-translate-vscode](https://github.com/w88975/code-translate-vscode) project at commit `e280dbb1cad87c848f99c17fcd31d63050d395b4`. Thanks to its author and contributors.

## License

[MIT](LICENSE)
