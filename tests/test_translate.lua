-- 高信号行为测试：取词、provider 数据流、异步生命周期和浮窗交互
local pass, fail = 0, 0

local function ok(condition, message)
  if condition then
    pass = pass + 1
    print('通过：' .. message)
  else
    fail = fail + 1
    print('失败：' .. message)
  end
end

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

local identifier_cases = {
  getUserProfile = 'get user profile',
  HTTPClient = 'http client',
  getHTTPResponse2Code = 'get http response 2 code',
  user_profile = 'user profile',
  ['parse-json_data'] = 'parse json data',
  ['translate selected text'] = 'translate selected text',
}
local identifiers_correct = true
for input, expected in pairs(identifier_cases) do
  if Identifier.normalize(input) ~= expected then identifiers_correct = false end
end
ok(identifiers_correct, '标识符规范化覆盖常见代码命名和自然语言')

vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'before getUserProfile after', 'second line' })
vim.api.nvim_win_set_cursor(0, { 1, 10 })
ok(Source.word() == 'getUserProfile', 'Normal 来源读取光标下的单词')

vim.cmd('normal! 0wve')
local selected = Source.visual()
vim.cmd('normal! <Esc>')
ok(selected == 'getUserProfile' and Source.visual() == 'getUserProfile',
  'Visual 来源读取并保留精确选区')

local received
Translate.setup({
  provider = 'custom',
  providers = {
    custom = {
      translate = function(request, _, callback)
        received = request
        callback(nil, { text = '用户资料' })
      end,
    },
  },
})
vim.api.nvim_win_set_cursor(0, { 1, 10 })
Translate.translate_word()
local _, result_buf = require('vv-translate.view').current()
local result = result_buf and vim.api.nvim_buf_get_lines(result_buf, 0, -1, false)[1]
ok(received and received.text == 'get user profile' and received.kind == 'word' and result == '用户资料',
  '光标词经过规范化请求 provider 并渲染结果')
Translate.close()

local visual_request
Translate.setup({
  provider = 'visual',
  providers = {
    visual = {
      translate = function(request, _, callback)
        visual_request = request
        callback(nil, { text = 'visual result' })
      end,
    },
  },
})
vim.cmd('normal! 0wve')
Translate.translate()
vim.cmd('normal! <Esc>')
ok(visual_request and visual_request.text == 'getUserProfile' and visual_request.kind == 'selection',
  '公共入口在 Visual 模式翻译精确选区')
Translate.close()

Translate.setup({
  provider = 'structured',
  providers = {
    structured = {
      translate = function(_, _, callback)
        callback(nil, {
          data = {
            detected_language = 'en',
            translations = { '你好', '您好' },
          },
        })
      end,
    },
  },
})
Translate.translate_text('hello')
local _, structured_buf = require('vv-translate.view').current()
local structured_text = structured_buf
  and table.concat(vim.api.nvim_buf_get_lines(structured_buf, 0, -1, false), '\n')
ok(structured_text and structured_text:match('detected_language: en')
  and structured_text:match('translations:'), '通用 renderer 能展示结构化 data')
Translate.close()

local present_calls = 0
Translate.setup({
  provider = 'presented',
  providers = {
    presented = {
      translate = function(_, _, callback)
        callback(nil, { data = { translation = '由 presenter 生成' } })
        callback(nil, { data = { translation = '不应处理' } })
      end,
      present = function(result)
        present_calls = present_calls + 1
        return { lines = { result.data.translation } }
      end,
    },
  },
})
Translate.translate_text('present me')
local _, presented_buf = require('vv-translate.view').current()
local presented_text = presented_buf and vim.api.nvim_buf_get_lines(presented_buf, 0, -1, false)[1]
ok(presented_text == '由 presenter 生成' and present_calls == 1,
  'presenter 转换私有 data 且重复回调只处理一次')
Translate.close()

local render_events = {}
Translate.setup({
  provider = 'rendered',
  providers = {
    rendered = {
      translate = function(_, _, callback)
        callback(nil, { data = { value = '原始值' } })
      end,
    },
  },
  view = {
    render = function(event, context)
      render_events[#render_events + 1] = event
      if event ~= 'result' then return context.default_render() end
      return { lines = { context.result.data.value } }
    end,
  },
})
Translate.translate_text('custom view')
local _, rendered_buf = require('vv-translate.view').current()
local rendered_text = rendered_buf and vim.api.nvim_buf_get_lines(rendered_buf, 0, -1, false)[1]
ok(vim.deep_equal(render_events, { 'loading', 'result' }) and rendered_text == '原始值',
  '自定义 renderer 接收生命周期事件和完整 provider 结果')
Translate.close()

local automatic_dictionary = vim.fn.tempname() .. '-vv-translate-auto-dict'
local dictionary_module = require('vv-translate.dictionary')
local original_download_latest = dictionary_module.download_latest
local automatic_downloads = 0
dictionary_module.download_latest = function(opts, callback)
  automatic_downloads = automatic_downloads + 1
  fs.mkdir_p(opts.destination)
  fs.write_all(vim.fs.joinpath(opts.destination, 'te.json'), '{"test":{"t":"n. 测试"}}')
  callback({ ok = true, version = 'test', path = opts.destination })
  return function() end
end
Translate.setup({ providers = { ['local'] = { dictionary_path = automatic_dictionary } } })
Translate.translate_text('test')
dictionary_module.download_latest = original_download_latest
local _, offline_buf = require('vv-translate.view').current()
local offline_result = offline_buf and table.concat(vim.api.nvim_buf_get_lines(offline_buf, 0, -1, false), '\n')
ok(automatic_downloads == 1 and offline_result and offline_result:match('测试'),
  '首次翻译发现词典缺失时自动安装并继续原请求')
Translate.close()
fs.delete(automatic_dictionary)

local loading_callback
Translate.setup({
  provider = 'loading',
  providers = {
    loading = {
      translate = function(_, _, callback)
        loading_callback = callback
        return function() end
      end,
    },
  },
})
Translate.translate_text('a long sentence that exceeds a compact translation window while waiting')
local _, loading_buf = require('vv-translate.view').current()
local loading_lines = loading_buf and vim.api.nvim_buf_get_lines(loading_buf, 0, -1, false) or {}
local loading_started = loading_buf
  and buffer_virt_text(loading_buf) ~= ''
  and buffer_virt_text_row(loading_buf) == 1
  and loading_lines[2] == ''
loading_callback(nil, { text = 'done' })
ok(loading_started and buffer_virt_text(loading_buf) == '',
  'loading 在长句下方独立显示并在请求完成后清理')
Translate.close()

Translate.translate_text('close loading')
local _, closing_loading_buf = require('vv-translate.view').current()
Translate.close()
ok(not vim.api.nvim_buf_is_valid(closing_loading_buf), '关闭浮窗会清理 pending loading 资源')

local callbacks = {}
local cancellations = {}
Translate.setup({
  provider = 'delayed',
  providers = {
    delayed = {
      translate = function(request, _, callback)
        callbacks[request.text] = callback
        return function()
          cancellations[request.text] = (cancellations[request.text] or 0) + 1
        end
      end,
    },
  },
})
Translate.translate_text('first request')
Translate.translate_text('second request')
callbacks['second request'](nil, { text = '第二次结果' })
callbacks['first request'](nil, { text = '过期结果' })
local _, latest_buf = require('vv-translate.view').current()
local latest = latest_buf and vim.api.nvim_buf_get_lines(latest_buf, 0, -1, false)[1]
ok(latest == '第二次结果' and cancellations['first request'] == 1,
  '新请求取消旧请求且过期结果不能覆盖最新结果')
Translate.translate_text('closed request')
local _, closed_request_buf = require('vv-translate.view').current()
Translate.close()
callbacks['closed request'](nil, { text = '关闭后的结果' })
ok(cancellations['closed request'] == 1 and not vim.api.nvim_buf_is_valid(closed_request_buf)
  and require('vv-translate.view').current() == nil, '关闭请求会物理取消且 late callback 不能回写')

local source_buf = vim.api.nvim_get_current_buf()
local previous_q = function() end
vim.keymap.set('n', 'q', previous_q, { buffer = source_buf, desc = '原有 q 映射' })
local long_lines = {}
for index = 1, 12 do long_lines[#long_lines + 1] = ('line %d'):format(index) end
Translate.setup({
  provider = 'scrollable',
  providers = {
    scrollable = {
      translate = function(_, _, callback)
        callback(nil, { text = table.concat(long_lines, '\n') })
      end,
    },
  },
  view = { max_height = 3 },
})
Translate.translate_text('scroll')
local scroll_win = require('vv-translate.view').current()
local scroll_down = buffer_map(source_buf, 'n', '<C-e>')
local scroll_up = buffer_map(source_buf, 'n', '<C-y>')
ok(vim.api.nvim_get_option_value('wrap', { win = scroll_win }),
  '翻译浮窗默认自动换行')
local first_topline = vim.api.nvim_win_call(scroll_win, function() return vim.fn.line('w0') end)
scroll_down.callback()
local second_topline = vim.api.nvim_win_call(scroll_win, function() return vim.fn.line('w0') end)
scroll_up.callback()
local restored_topline = vim.api.nvim_win_call(scroll_win, function() return vim.fn.line('w0') end)
ok(first_topline == 1 and second_topline > first_topline and restored_topline == first_topline,
  '<C-e> 和 <C-y> 控制翻译浮窗滚动')

vim.cmd('normal! v')
vim.api.nvim_feedkeys('q', 'mx', false)
vim.wait(100, function() return require('vv-translate.view').current() == nil end)
local restored_q = buffer_map(source_buf, 'n', 'q')
ok(require('vv-translate.view').current() == nil
  and restored_q and restored_q.callback == previous_q,
  'Visual 模式 q 关闭浮窗并恢复原 buffer 映射')

vim.cmd('normal! <Esc>')
Translate.translate_text('escape')
vim.cmd('normal! v')
vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'mx', false)
vim.wait(100, function() return require('vv-translate.view').current() == nil end)
ok(require('vv-translate.view').current() == nil, 'Visual 模式 Esc 关闭翻译浮窗')
vim.keymap.del('n', 'q', { buffer = source_buf })

local function provider_error_code(name, provider)
  local code
  Provider.translate({ text = 'hello', kind = 'text' }, {
    name = name,
    providers = provider and { [name] = provider } or {},
  }, function(err) code = err and err.code end)
  return code
end

local provider_errors_correct = provider_error_code('missing') == 'provider_not_found'
  and provider_error_code('broken', {
    translate = function() error('boom') end,
  }) == 'provider_failed'
  and provider_error_code('invalid-result', {
    translate = function(_, _, callback) callback(nil, 'invalid') end,
  }) == 'invalid_provider_result'
  and provider_error_code('broken-presenter', {
    translate = function(_, _, callback) callback(nil, { data = {} }) end,
    present = function() error('boom') end,
  }) == 'provider_presenter_failed'
ok(provider_errors_correct, 'provider 路由将关键失败归一化为稳定错误码')

local routed_providers = Route.resolve({ text = 'sentence', kind = 'selection' }, {
  routes = {
    selection = function(request)
      return request.text == 'sentence' and { 'groq', 'mymemory' } or 'local'
    end,
  },
  fallback = 'local',
})
local default_providers = Route.resolve({ text = 'sentence', kind = 'text' }, {
  routes = {},
  fallback = { 'groq', 'mymemory' },
})
ok(vim.deep_equal(routed_providers, { 'groq', 'mymemory' })
  and vim.deep_equal(default_providers, { 'groq', 'mymemory' }),
  'provider route 和顶层默认值都可以声明 fallback 顺序')

local original_groq_key = vim.env.GROQ_API_KEY
vim.env.GROQ_API_KEY = nil
Translate.setup()
local default_sentence_route = Translate.get_config().routes.selection
local anonymous_sentence = default_sentence_route({ text = 'hello world', kind = 'selection' })
local identifier_route = default_sentence_route({ text = 'getUserProfile', kind = 'selection' })
vim.env.GROQ_API_KEY = 'test-key'
local keyed_sentence = default_sentence_route({ text = 'hello world', kind = 'selection' })
vim.env.GROQ_API_KEY = original_groq_key
ok(vim.deep_equal(anonymous_sentence, { 'mymemory', 'local' })
  and identifier_route == nil
  and vim.deep_equal(keyed_sentence, { 'groq', 'mymemory', 'local' }),
  '默认路由让标识符走本地、自然语言句子按可用 API 顺序回退到本地')

local fallback_order = {}
local fallback_result
Fallback.run({
  providers = { 'groq', 'mymemory' },
  run = function(provider, callback)
    fallback_order[#fallback_order + 1] = provider
    if provider == 'groq' then
      callback({ code = 'request_failed', message = 'Groq failed', provider = provider })
    else
      callback(nil, { provider = provider, text = 'fallback result' })
    end
    return function() end
  end,
}, function(err, result) fallback_result = not err and result end)
ok(vim.deep_equal(fallback_order, { 'groq', 'mymemory' })
  and fallback_result
  and fallback_result.provider == 'mymemory'
  and fallback_result.metadata.fallback.attempts[1].provider == 'groq',
  'provider fallback 在失败后按声明顺序尝试并保留失败摘要')

local Http = require('vv-utils.http')
local original_http_request = Http.request
local cloud_requests = {}
Http.request = function(opts, callback)
  cloud_requests[#cloud_requests + 1] = opts
  if opts.url:match('groq') then
    callback(nil, {
      status = 200,
      body = vim.json.encode({ choices = { { message = { content = '云端翻译' } } } }),
    })
  else
    callback(nil, {
      status = 200,
      body = vim.json.encode({
        responseStatus = 200,
        responseData = { translatedText = '临时翻译' },
      }),
    })
  end
  return function() end
end

local groq_result
Provider.translate({ text = 'cloud sentence', kind = 'text', target_language = 'Chinese' }, {
  name = 'groq',
  providers = { groq = { api_key = 'test-key' } },
}, function(err, result) groq_result = not err and result end)
local groq_payload = vim.json.decode(cloud_requests[1].body)
ok(groq_result and groq_result.text == '云端翻译'
  and vim.deep_equal(groq_result.content.lines, { 'cloud sentence', '', '云端翻译' })
  and groq_result.content.highlights[1].role == 'source'
  and groq_result.content.highlights[2].role == 'translation'
  and groq_payload.stream == false
  and groq_payload.messages[1].content:match('Chinese'),
  'Groq provider 解析非流式响应并按语义展示原文和译文')

local mymemory_result
Provider.translate({ text = 'temporary sentence', kind = 'text' }, {
  name = 'mymemory',
  providers = {
    mymemory = {
      endpoint = 'https://api.mymemory.translated.net/get?client=test',
      email = 'test+vv@example.com',
    },
  },
}, function(err, result) mymemory_result = not err and result end)
ok(mymemory_result and mymemory_result.text == '临时翻译'
  and vim.deep_equal(mymemory_result.content.lines, { 'temporary sentence', '', '临时翻译' })
  and cloud_requests[2].url:match('client=test')
  and cloud_requests[2].url:match('q=temporary%%20sentence')
  and cloud_requests[2].url:match('langpair=en%%7Czh%-CN'),
  'MyMemory provider 无需 key 即可翻译并保留原文')
ok(cloud_requests[2].url:match('de=test%%2Bvv%%40example.com'),
  'MyMemory 查询参数复用公共 URL 编码并保留 endpoint 已有 query')
Http.request = original_http_request

local fixture_root = vim.fn.tempname() .. '-vv-translate-test'
local package_root = vim.fs.joinpath(fixture_root, 'package')
local archive = vim.fs.joinpath(fixture_root, 'vv-translate-dict.tar.gz')
local checksum = archive .. '.sha256'
local release_metadata = vim.fs.joinpath(fixture_root, 'release.json')
local installed = vim.fs.joinpath(fixture_root, 'installed', 'dict')
fs.mkdir_p(vim.fs.joinpath(package_root, 'dict'))
fs.write_all(vim.fs.joinpath(package_root, 'dict', 'te.json'), '{"test":{"translation":["测试"]}}')
fs.save_json(vim.fs.joinpath(package_root, 'manifest.json'), {
  schema_version = 1,
  version = '9.9.9',
  file_count = 1,
})
local tar_result = vim.system({ 'tar', '-czf', archive, '-C', package_root, '.' }, { text = true }):wait()
fs.write_all(checksum, vim.fn.sha256(fs.read_all(archive)) .. '  vv-translate-dict.tar.gz\n')
fs.save_json(release_metadata, {
  tag_name = 'dict-v9.9.9',
  assets = {
    { name = 'vv-translate-dict.tar.gz', browser_download_url = 'file://' .. archive },
    { name = 'vv-translate-dict.tar.gz.sha256', browser_download_url = 'file://' .. checksum },
  },
})
fs.mkdir_p(installed)
fs.write_all(vim.fs.joinpath(installed, 'old.json'), '{}')

local install_result
DictionaryInstaller.install({
  metadata_url = 'file://' .. release_metadata,
  destination = installed,
}, function(result) install_result = result end)
local completed = vim.wait(10000, function() return install_result ~= nil end, 20)
local installed_manifest = completed and fs.load_json(vim.fs.joinpath(installed, 'manifest.json')) or {}
ok(tar_result.code == 0 and completed and install_result.ok
  and installed_manifest.version == '9.9.9'
  and fs.exists(vim.fs.joinpath(installed, 'te.json'))
  and not fs.exists(vim.fs.joinpath(installed, 'old.json')),
  '词典安装器真实下载、校验并解压归档后替换旧词典')
fs.delete(fixture_root)

print(('%d 通过 / %d 失败'):format(pass, fail))
if fail > 0 then vim.cmd('cquit 1') end
