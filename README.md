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

After installation, run `:VVTranslateDownloadDictionary` once. It downloads the latest dictionary Release, verifies its SHA-256 checksum and manifest, then installs it to `<plugin-root>/dict`. The built-in `local` provider does not require `translate-shell` or any network service while translating. No automatic update check runs at startup; run the command again whenever you want the latest dictionary.

Semantic highlights link to standard Neovim highlight groups by default, so they follow the active colorscheme and are restored after `:colorscheme` changes. Each entry under `highlights` accepts a normal `nvim_set_hl()` specification; an override replaces that semantic role's default link.

While the floating window is open, its controls temporarily take precedence in the source buffer: `<C-e>` and `<C-y>` scroll the translation, while `q` and `<Esc>` close it in Normal or Visual mode. Previous buffer-local mappings are restored when the window closes.

Loading uses `vv-utils.loading` to animate beside the query and is stopped when a result, error, or close event occurs. Loading and successful results have no title by default; errors keep a centered status title. Provider presenters and custom renderers may set `content.title` when a title carries useful information.

## Usage

- `:VVTranslate` translates the word under the cursor or the active Visual selection
- `:VVTranslateWord` translates the word under the cursor
- `:VVTranslateVisual` translates the current or most recent Visual selection
- `:VVTranslateClose` closes the floating window and cancels the current request
- `:VVTranslateDownloadDictionary` downloads and installs the latest offline dictionary

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
