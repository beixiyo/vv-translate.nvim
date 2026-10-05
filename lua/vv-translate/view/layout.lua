-- 翻译浮窗排版：把通用展示内容转换为 buffer 行、高亮组、换行方式和窗口宽度
--
-- 只有带 sections（原文/译文分段）的内容参与双栏判定，其余内容沿用单栏 lines/highlights；
-- 双栏判定与对齐复用 vv-utils.ui_columns，本模块只负责翻译语义：哪栏是原文、放不下时单栏怎么排
local Bilingual = require('vv-translate.presentation.bilingual')
local Columns = require('vv-utils.ui_columns')
local Highlights = require('vv-translate.view.highlights')

local M = {}

-- 浮窗边框与屏幕边缘的留白
local SCREEN_MARGIN = 4
local MIN_WIDTH = 20

local MODES = { auto = true, stack = true, split = true }
local NARROW = { translation_first = true, source_first = true, translation_only = true }

local function positive_integer(value)
  return type(value) == 'number' and value >= 1 and value % 1 == 0
end

local function fail(field, expected, value)
  error(('vv-translate: view.layout.%s must be %s, got %s'):format(field, expected, vim.inspect(value)), 0)
end

---校验归一化后的 view.layout；非法时抛错
---@param layout VVTranslateViewLayoutConfig
function M.validate(layout)
  if type(layout) ~= 'table' then
    error(('vv-translate: view.layout must be a table, got %s'):format(vim.inspect(layout)), 0)
  end
  if not MODES[layout.mode] then fail('mode', "'auto', 'stack' or 'split'", layout.mode) end
  if not NARROW[layout.narrow] then
    fail('narrow', "'translation_first', 'source_first' or 'translation_only'", layout.narrow)
  end
  if not positive_integer(layout.min_column_width) then
    fail('min_column_width', 'a positive integer', layout.min_column_width)
  end
  if not positive_integer(layout.max_column_width) or layout.max_column_width < layout.min_column_width then
    fail('max_column_width', 'an integer >= min_column_width', layout.max_column_width)
  end
  if type(layout.separator) ~= 'string' then fail('separator', 'a string', layout.separator) end
end

---把含 '\n' 的行拆成多行（多行 Visual 选区、provider 或自定义 renderer 都可能产生），
---高亮按字节区间映射到拆分后的各行；nvim_buf_set_lines 不接受含换行的行
---@param content VVTranslateContent
---@return string[] lines
---@return VVTranslateContentHighlight[] highlights
local function split_lines(content)
  local highlights = content.highlights or {}
  local has_newline = false
  for _, line in ipairs(content.lines) do
    if line:find('\n', 1, true) then
      has_newline = true
      break
    end
  end
  if not has_newline then return content.lines, highlights end

  local lines = {}
  -- 原始行号（0-based）→ 拆分后各段的目标行号与原行内字节偏移
  local pieces_by_row = {}
  for row, line in ipairs(content.lines) do
    local pieces = {}
    local offset = 0
    for _, piece in ipairs(vim.split(line, '\n', { plain = true })) do
      lines[#lines + 1] = piece
      pieces[#pieces + 1] = { row = #lines - 1, start = offset, finish = offset + #piece }
      offset = offset + #piece + 1
    end
    pieces_by_row[row - 1] = pieces
  end

  local mapped = {}
  for _, highlight in ipairs(highlights) do
    local pieces = pieces_by_row[highlight.row]
    if not pieces then
      mapped[#mapped + 1] = highlight
    else
      for _, piece in ipairs(pieces) do
        local start_col = math.max(highlight.start_col, piece.start)
        local finish = math.min(highlight.end_col, piece.finish)
        if start_col < finish then
          mapped[#mapped + 1] = vim.tbl_extend('force', highlight, {
            row = piece.row,
            start_col = start_col - piece.start,
            end_col = finish - piece.start,
          })
        end
      end
    end
  end
  return lines, mapped
end

---单栏宽度：最长行与 max_width、屏幕宽度取小，至少 MIN_WIDTH
local function stack_width(lines, config)
  local max_width = math.max(MIN_WIDTH, math.min(config.max_width, vim.o.columns - SCREEN_MARGIN))
  local width = MIN_WIDTH
  for _, line in ipairs(lines) do
    width = math.max(width, math.min(max_width, vim.fn.strdisplaywidth(line)))
  end
  return width
end

---语义 role → 实际高亮组；未知 role 丢弃
---@return VVTranslateLayoutHighlight[]
local function role_highlights(highlights)
  local mapped = {}
  for _, highlight in ipairs(highlights) do
    local group = Highlights.group(highlight.role)
    if group then
      mapped[#mapped + 1] = {
        row = highlight.row,
        start_col = highlight.start_col,
        end_col = highlight.end_col,
        hl = group,
      }
    end
  end
  return mapped
end

local function stack(lines, highlights, config)
  return {
    mode = 'stack',
    lines = lines,
    highlights = role_highlights(highlights),
    wrap = config.wrap ~= false,
    width = stack_width(lines, config),
  }
end

---窄屏单栏：译文优先，原文弱化放在下方，或只保留译文
local function narrow_stack(sections, narrow, config)
  local blocks = { { text = sections.translation, role = 'translation' } }
  if narrow == 'translation_first' then
    blocks[2] = { text = sections.source, role = 'source_muted' }
  end
  local lines, highlights = Bilingual.stack(blocks)
  return stack(lines, highlights, config)
end

---按显示列展开 Tab：ui_columns 用 strdisplaywidth 计宽并按空格补齐，
---Tab 的实际宽度取决于所在列，不展开会让不折行的双栏分隔符错位
---@param lines string[]
---@return string[]
local function expand_tabs(lines)
  local tabstop = math.max(1, vim.o.tabstop)
  local expanded = {}
  for index, line in ipairs(lines) do
    if line:find('\t', 1, true) then
      local parts, column = {}, 0
      for _, char in ipairs(vim.fn.split(line, '\\zs')) do
        if char == '\t' then
          local spaces = tabstop - column % tabstop
          parts[#parts + 1] = string.rep(' ', spaces)
          column = column + spaces
        else
          parts[#parts + 1] = char
          column = column + vim.fn.strdisplaywidth(char)
        end
      end
      line = table.concat(parts)
    end
    expanded[index] = line
  end
  return expanded
end

---栏宽收窄到该栏最长行：不改变折行结果（短于栏宽的行本就不折），只去掉多余留白
local function fitted_width(lines, limit)
  local widest = 1
  for _, line in ipairs(lines) do widest = math.max(widest, vim.fn.strdisplaywidth(line)) end
  return math.min(limit, widest)
end

local function split(source, translation, column_width, layout)
  local widths = { fitted_width(source, column_width), fitted_width(translation, column_width) }
  local composed = Columns.compose({
    columns = {
      { sections = source, hl = Highlights.group('source') },
      { sections = translation, hl = Highlights.group('translation') },
    },
    width = widths,
    separator = layout.separator,
    align = 'sections',
  })
  return {
    mode = 'split',
    lines = composed.lines,
    highlights = composed.highlights,
    wrap = false,
    width = widths[1] + vim.fn.strdisplaywidth(layout.separator) + widths[2],
  }
end

---按内容、配置和当前屏幕宽度排版
---
---流程：无 sections → 单栏原样；mode='split' → 强制双栏；否则交给 ui_columns.decide：
---判为 split 且 mode='auto' 时双栏，单栏放得下时保持原文在上的原顺序，放不下时按 layout.narrow 排
---@param content VVTranslateContent
---@param config VVTranslateViewConfig
---@return VVTranslateLayout
function M.arrange(content, config)
  local lines, highlights = split_lines(content)
  local sections = content.sections
  if not sections then return stack(lines, highlights, config) end

  local layout = config.layout
  local source = expand_tabs(vim.split(sections.source, '\n', { plain = true }))
  local translation = expand_tabs(vim.split(sections.translation, '\n', { plain = true }))
  local available = math.max(1, vim.o.columns - SCREEN_MARGIN)
  local separator_width = vim.fn.strdisplaywidth(layout.separator)
  local column_width = math.max(1, math.min(layout.max_column_width, math.floor((available - separator_width) / 2)))

  if layout.mode == 'split' then return split(source, translation, column_width, layout) end

  local decision = Columns.decide({
    columns = { source, translation },
    available_width = available,
    max_height = config.max_height,
    stack_width = stack_width(lines, config),
    min_column_width = layout.min_column_width,
    max_column_width = layout.max_column_width,
    separator = layout.separator,
  })
  if layout.mode == 'auto' and decision.mode == 'split' then
    return split(source, translation, decision.column_width or column_width, layout)
  end
  if decision.reason == 'fits' or layout.narrow == 'source_first' then
    return stack(lines, highlights, config)
  end
  return narrow_stack(sections, layout.narrow, config)
end

return M

---@class VVTranslateLayoutHighlight
---@field row integer 从 0 开始的行号
---@field start_col integer 从 0 开始的字节列
---@field end_col integer 结尾字节列，不包含该列
---@field hl string 实际高亮组

---@class VVTranslateLayout
---@field mode 'stack'|'split'
---@field lines string[] 可直接写入 buffer 的行（不含 '\n'）
---@field highlights VVTranslateLayoutHighlight[]
---@field wrap boolean 窗口是否折行；双栏已预先折好，固定为 false
---@field width integer 窗口正文宽度
