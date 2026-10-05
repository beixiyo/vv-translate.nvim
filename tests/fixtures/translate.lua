-- 翻译场景的运行时夹具，不发起请求或创建窗口。
return function()
  -- 高信号行为测试：取词、provider 数据流、异步生命周期和浮窗交互
  local function ok(condition, message) assert(condition, message) end

  local function buffer_map(buf, mode, lhs)
    local target = vim.fn.keytrans(vim.keycode(lhs))
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
      if vim.fn.keytrans(vim.keycode(mapping.lhs)) == target then return mapping end
    end
  end

  local function buffer_virt_text(buf)
    local values = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
      for _, chunk in ipairs(mark[4].virt_text or {}) do values[#values + 1] = chunk[1] end
    end
    return table.concat(values)
  end

  local function buffer_virt_text_row(buf)
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
      if mark[4].virt_text then return mark[2] end
    end
  end

  local Identifier = require('vv-translate.identifier')
  local Source = require('vv-translate.source')
  local Provider = require('vv-translate.provider')
  local Fallback = require('vv-translate.provider.fallback')
  local Route = require('vv-translate.provider.route')
  local Translate = require('vv-translate')
  local DictionaryInstaller = require('vv-translate.dictionary.installer')
  local fs = require('vv-utils.fs')
  return { ok = ok, buffer_map = buffer_map, buffer_virt_text = buffer_virt_text, buffer_virt_text_row = buffer_virt_text_row, Identifier = Identifier, Source = Source, Provider = Provider, Fallback = Fallback, Route = Route, Translate = Translate, DictionaryInstaller = DictionaryInstaller, fs = fs }
end
