local H = dofile('tests/helpers.lua')
local T, child = H.new_set()

T["取词、标识符规范化与 Visual 公共入口"] = function()
  child.lua_func(function()
    local F = dofile(vim.env.VV_TEST_REPO .. '/tests/fixtures/translate.lua')()
    local ok = F.ok
    local buffer_map = F.buffer_map
    local buffer_virt_text = F.buffer_virt_text
    local buffer_virt_text_row = F.buffer_virt_text_row
    local Identifier = F.Identifier
    local Source = F.Source
    local Provider = F.Provider
    local Fallback = F.Fallback
    local Route = F.Route
    local Translate = F.Translate
    local DictionaryInstaller = F.DictionaryInstaller
    local fs = F.fs

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
  end)
end

T["结构化数据、presenter 去重与自定义 renderer"] = function()
  child.lua_func(function()
    local F = dofile(vim.env.VV_TEST_REPO .. '/tests/fixtures/translate.lua')()
    local ok = F.ok
    local buffer_map = F.buffer_map
    local buffer_virt_text = F.buffer_virt_text
    local buffer_virt_text_row = F.buffer_virt_text_row
    local Identifier = F.Identifier
    local Source = F.Source
    local Provider = F.Provider
    local Fallback = F.Fallback
    local Route = F.Route
    local Translate = F.Translate
    local DictionaryInstaller = F.DictionaryInstaller
    local fs = F.fs

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
  end)
end

T["缺词典自动安装后继续原请求"] = function()
  child.lua_func(function()
    local F = dofile(vim.env.VV_TEST_REPO .. '/tests/fixtures/translate.lua')()
    local ok = F.ok
    local buffer_map = F.buffer_map
    local buffer_virt_text = F.buffer_virt_text
    local buffer_virt_text_row = F.buffer_virt_text_row
    local Identifier = F.Identifier
    local Source = F.Source
    local Provider = F.Provider
    local Fallback = F.Fallback
    local Route = F.Route
    local Translate = F.Translate
    local DictionaryInstaller = F.DictionaryInstaller
    local fs = F.fs

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
  end)
end

T["等待帧位置、完成释放与关闭取消"] = function()
  child.lua_func(function()
    local F = dofile(vim.env.VV_TEST_REPO .. '/tests/fixtures/translate.lua')()
    local ok = F.ok
    local buffer_map = F.buffer_map
    local buffer_virt_text = F.buffer_virt_text
    local buffer_virt_text_row = F.buffer_virt_text_row
    local Identifier = F.Identifier
    local Source = F.Source
    local Provider = F.Provider
    local Fallback = F.Fallback
    local Route = F.Route
    local Translate = F.Translate
    local DictionaryInstaller = F.DictionaryInstaller
    local fs = F.fs

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
  end)
end

T["多行内容与错误按行渲染，溢出 loading 转移至 footer"] = function()
  child.lua_func(function()
    local F = dofile(vim.env.VV_TEST_REPO .. '/tests/fixtures/translate.lua')()
    local ok = F.ok
    local buffer_map = F.buffer_map
    local buffer_virt_text = F.buffer_virt_text
    local buffer_virt_text_row = F.buffer_virt_text_row
    local Identifier = F.Identifier
    local Source = F.Source
    local Provider = F.Provider
    local Fallback = F.Fallback
    local Route = F.Route
    local Translate = F.Translate
    local DictionaryInstaller = F.DictionaryInstaller
    local fs = F.fs

    -- 多行 Visual 选区以 '\n' 拼接；loading、结果、错误内容里的换行都必须按行写入 buffer
    local multiline_callback
    Translate.setup({
      provider = 'multiline',
      providers = {
        multiline = {
          translate = function(_, _, callback)
            multiline_callback = callback
            return function() end
          end,
        },
      },
      view = {
        render = function(event, context)
          if event == 'error' then return { lines = { context.error.message } } end
          return context.default_render()
        end,
      },
    })
    local function multiline_lines()
      local _, buf = require('vv-translate.view').current()
      return buf and vim.api.nvim_buf_get_lines(buf, 0, -1, false) or {}, buf
    end

    multiline_callback = nil
    local multiline_open_ok = pcall(Translate.translate_text, 'first line\nsecond line')
    local multiline_loading, multiline_buf = multiline_lines()
    local multiline_loading_row = multiline_buf and buffer_virt_text_row(multiline_buf)
    local multiline_result_ok = multiline_callback ~= nil
      and pcall(multiline_callback, nil, { content = { lines = { '第一行\n第二行' } } })
    local multiline_result = multiline_lines()
    ok(multiline_open_ok and vim.deep_equal(multiline_loading, { 'first line', 'second line', '' })
      and multiline_loading_row == 2
      and multiline_result_ok and vim.deep_equal(multiline_result, { '第一行', '第二行' }),
      '多行原文的 loading 与结果按行渲染，loading 保持在最后一行')
    Translate.close()

    multiline_callback = nil
    pcall(Translate.translate_text, 'multi\nline')
    local multiline_error_ok = multiline_callback ~= nil
      and pcall(multiline_callback, { code = 'failed', message = 'line one\nline two' }, nil)
    ok(multiline_error_ok and vim.deep_equal(multiline_lines(), { 'line one', 'line two' }),
      '多行错误消息按行渲染')
    Translate.close()

    local overflow_callback
    Translate.setup({
      provider = 'overflow',
      providers = {
        overflow = {
          translate = function(_, _, callback)
            overflow_callback = callback
            return function() end
          end,
        },
      },
    })
    local overflow_source = {}
    for i = 1, 20 do overflow_source[i] = 'line ' .. i end
    pcall(Translate.translate_text, table.concat(overflow_source, '\n'))
    local overflow_win, overflow_buf = require('vv-translate.view').current()
    local overflow_footer = overflow_win and vim.api.nvim_win_get_config(overflow_win).footer
    local overflow_in_footer = type(overflow_footer) == 'table' and #overflow_footer > 0
      and overflow_buf and buffer_virt_text(overflow_buf) == ''
    if overflow_callback then overflow_callback(nil, { text = 'done' }) end
    local cleared_footer = overflow_win and vim.api.nvim_win_get_config(overflow_win).footer
    ok(overflow_in_footer and (cleared_footer == nil or cleared_footer == '' or #cleared_footer == 0),
      '内容超过浮窗最大高度时 loading 改放 footer，结束后清理')
    Translate.close()
  end)
end

T["长双语宽窄屏重排，短文本保持单栏"] = function()
  child.lua_func(function()
    local F = dofile(vim.env.VV_TEST_REPO .. '/tests/fixtures/translate.lua')()
    local ok = F.ok
    local buffer_map = F.buffer_map
    local buffer_virt_text = F.buffer_virt_text
    local buffer_virt_text_row = F.buffer_virt_text_row
    local Identifier = F.Identifier
    local Source = F.Source
    local Provider = F.Provider
    local Fallback = F.Fallback
    local Route = F.Route
    local Translate = F.Translate
    local DictionaryInstaller = F.DictionaryInstaller
    local fs = F.fs

    -- C-11 形状：20 行原文 + 20 行译文；宽屏双栏逐行对照，窄屏译文在上、原文弱化在下，resize 后重排
    local Bilingual = require('vv-translate.presentation.bilingual')
    local pair_source, pair_translation = {}, {}
    for i = 1, 20 do
      pair_source[i] = ('Line %d is short.'):format(i)
      pair_translation[i] = ('第 %d 行很短。'):format(i)
    end
    Translate.setup({
      provider = 'bilingual',
      providers = {
        bilingual = {
          translate = function(request, _, callback)
            local translation = request.text == 'short sentence' and '短句' or table.concat(pair_translation, '\n')
            callback(nil, { content = Bilingual.render(request.text, translation) })
          end,
        },
      },
    })
    local function view_snapshot()
      local win, buf = require('vv-translate.view').current()
      if not (win and buf) then return {} end
      return {
        win = win,
        buf = buf,
        lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
        wrap = vim.api.nvim_get_option_value('wrap', { win = win }),
        height = vim.api.nvim_win_get_height(win),
      }
    end
    local function row_hl_groups(buf, row)
      local groups = {}
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, { row, 0 }, { row, -1 }, { details = true })) do
        if mark[4].hl_group then groups[mark[4].hl_group] = true end
      end
      return groups
    end

    vim.o.columns = 160
    pcall(Translate.translate_text, table.concat(pair_source, '\n'))
    local wide = view_snapshot()
    local wide_first = wide.lines and wide.lines[1] or ''
    ok(wide.win and wide.wrap == false and wide.height == 16
      and wide_first:find('Line 1 is short.', 1, true) and wide_first:find('第 1 行很短。', 1, true)
      and #wide.lines == 20,
      '宽屏长双语内容改用双栏，首行同时含原文与译文首行且不折行')

    vim.o.columns = 80
    vim.api.nvim_exec_autocmds('VimResized', {})
    local narrow = view_snapshot()
    ok(narrow.win == wide.win and narrow.wrap == true
      and narrow.lines[1] == '第 1 行很短。' and narrow.lines[22] == 'Line 1 is short.'
      and row_hl_groups(narrow.buf, 21).VVTranslateSourceMuted,
      '缩到窄屏后 VimResized 重排为译文在上、原文弱化在下')
    Translate.close()

    vim.o.columns = 160
    Translate.translate_text('short sentence')
    local short = view_snapshot()
    ok(short.win and short.wrap == true and vim.deep_equal(short.lines, { 'short sentence', '', '短句' }),
      '单栏放得下的短句即使在宽屏也保持原文在上的单栏')
    Translate.close()
    vim.o.columns = 80
  end)
end

T["双栏 Tab 展开与单栏 CJK 真实折行高度"] = function()
  child.lua_func(function()
    local F = dofile(vim.env.VV_TEST_REPO .. '/tests/fixtures/translate.lua')()
    local ok = F.ok
    local buffer_map = F.buffer_map
    local buffer_virt_text = F.buffer_virt_text
    local buffer_virt_text_row = F.buffer_virt_text_row
    local Identifier = F.Identifier
    local Source = F.Source
    local Provider = F.Provider
    local Fallback = F.Fallback
    local Route = F.Route
    local Translate = F.Translate
    local DictionaryInstaller = F.DictionaryInstaller
    local fs = F.fs

    local Bilingual = require('vv-translate.presentation.bilingual')
    local function view_snapshot()
      local win, buf = require('vv-translate.view').current()
      if not (win and buf) then return {} end
      return {
        win = win,
        buf = buf,
        lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
        wrap = vim.api.nvim_get_option_value('wrap', { win = win }),
        height = vim.api.nvim_win_get_height(win),
      }
    end
    local function row_hl_groups(buf, row)
      local groups = {}
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, { row, 0 }, { row, -1 }, { details = true })) do
        if mark[4].hl_group then groups[mark[4].hl_group] = true end
      end
      return groups
    end

    -- 双栏不折行：Tab 的显示宽度取决于所在列，未展开时右栏 Tab 比 ui_columns 计算的更宽，行尾被窗口截掉
    Translate.setup({
      provider = 'tabbed',
      providers = {
        tabbed = {
          translate = function(request, _, callback)
            callback(nil, { content = Bilingual.render(request.text, 'ab\tcd\n\tef') })
          end,
        },
      },
      view = { layout = { mode = 'split' } },
    })
    vim.o.columns = 160
    Translate.translate_text('x\tsource\nline two')
    local tabbed = view_snapshot()
    local tabbed_fits = tabbed.win ~= nil
    for _, line in ipairs(tabbed.lines or {}) do
      if line:find('\t', 1, true)
        or vim.fn.strdisplaywidth(line) > vim.api.nvim_win_get_width(tabbed.win) then
        tabbed_fits = false
      end
    end
    ok(tabbed_fits, '双栏展开 Tab，渲染行宽不超过浮窗宽度')
    Translate.close()
    vim.o.columns = 80

    -- 宽字符整字换行：71 宽窗口每行只放 35 个汉字，71 个汉字占 3 行；按显示宽度估算只有 2 行
    local cjk_text = string.rep('汉', 71)
    Translate.setup({
      provider = 'cjk',
      providers = {
        cjk = { translate = function(_, _, callback) callback(nil, { text = cjk_text }) end },
      },
      view = { max_width = 71 },
    })
    Translate.translate_text('cjk')
    local cjk = view_snapshot()
    ok(cjk.win and vim.api.nvim_win_get_width(cjk.win) == 71 and cjk.height == 3
      and cjk.height == vim.api.nvim_win_text_height(cjk.win, {}).all,
      '单栏 CJK 内容按真实窗口折行高度设置浮窗高度')
    Translate.close()
  end)
end

T["新请求取消旧任务，关闭物理取消且迟到结果不回写"] = function()
  child.lua_func(function()
    local F = dofile(vim.env.VV_TEST_REPO .. '/tests/fixtures/translate.lua')()
    local ok = F.ok
    local buffer_map = F.buffer_map
    local buffer_virt_text = F.buffer_virt_text
    local buffer_virt_text_row = F.buffer_virt_text_row
    local Identifier = F.Identifier
    local Source = F.Source
    local Provider = F.Provider
    local Fallback = F.Fallback
    local Route = F.Route
    local Translate = F.Translate
    local DictionaryInstaller = F.DictionaryInstaller
    local fs = F.fs

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
  end)
end

T["浮窗滚动、Visual 关闭与外部关闭归还原映射"] = function()
  child.lua_func(function()
    local F = dofile(vim.env.VV_TEST_REPO .. '/tests/fixtures/translate.lua')()
    local ok = F.ok
    local buffer_map = F.buffer_map
    local buffer_virt_text = F.buffer_virt_text
    local buffer_virt_text_row = F.buffer_virt_text_row
    local Identifier = F.Identifier
    local Source = F.Source
    local Provider = F.Provider
    local Fallback = F.Fallback
    local Route = F.Route
    local Translate = F.Translate
    local DictionaryInstaller = F.DictionaryInstaller
    local fs = F.fs

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

    Translate.translate_text('closed externally')
    local external_close_win, external_close_buf = require('vv-translate.view').current()
    vim.api.nvim_win_close(external_close_win, true)
    vim.wait(100, function() return require('vv-translate.view').current() == nil end)
    ok(require('vv-translate.view').current() == nil
      and not vim.api.nvim_buf_is_valid(external_close_buf)
      and not buffer_map(source_buf, 'n', '<C-e>')
      and not buffer_map(source_buf, 'n', '<C-y>'),
      '浮窗被外部关闭时归还滚动映射')

    vim.cmd('normal! <Esc>')
    Translate.translate_text('escape')
    vim.cmd('normal! v')
    vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'mx', false)
    vim.wait(100, function() return require('vv-translate.view').current() == nil end)
    ok(require('vv-translate.view').current() == nil, 'Visual 模式 Esc 关闭翻译浮窗')
    vim.keymap.del('n', 'q', { buffer = source_buf })
  end)
end

T["错误归一化、默认路由与有序 fallback 保留失败摘要"] = function()
  child.lua_func(function()
    local F = dofile(vim.env.VV_TEST_REPO .. '/tests/fixtures/translate.lua')()
    local ok = F.ok
    local buffer_map = F.buffer_map
    local buffer_virt_text = F.buffer_virt_text
    local buffer_virt_text_row = F.buffer_virt_text_row
    local Identifier = F.Identifier
    local Source = F.Source
    local Provider = F.Provider
    local Fallback = F.Fallback
    local Route = F.Route
    local Translate = F.Translate
    local DictionaryInstaller = F.DictionaryInstaller
    local fs = F.fs

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
  end)
end

T["Groq 和 MyMemory 协议解析、语义展示与 URL 编码"] = function()
  child.lua_func(function()
    local F = dofile(vim.env.VV_TEST_REPO .. '/tests/fixtures/translate.lua')()
    local ok = F.ok
    local buffer_map = F.buffer_map
    local buffer_virt_text = F.buffer_virt_text
    local buffer_virt_text_row = F.buffer_virt_text_row
    local Identifier = F.Identifier
    local Source = F.Source
    local Provider = F.Provider
    local Fallback = F.Fallback
    local Route = F.Route
    local Translate = F.Translate
    local DictionaryInstaller = F.DictionaryInstaller
    local fs = F.fs

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
  end)
end

T["本地归档真实校验与安装替换旧词典"] = function()
  child.lua_func(function()
    local F = dofile(vim.env.VV_TEST_REPO .. '/tests/fixtures/translate.lua')()
    local ok = F.ok
    local buffer_map = F.buffer_map
    local buffer_virt_text = F.buffer_virt_text
    local buffer_virt_text_row = F.buffer_virt_text_row
    local Identifier = F.Identifier
    local Source = F.Source
    local Provider = F.Provider
    local Fallback = F.Fallback
    local Route = F.Route
    local Translate = F.Translate
    local DictionaryInstaller = F.DictionaryInstaller
    local fs = F.fs

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
  end)
end

return T
