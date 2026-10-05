# Changelog

## 0.2.0 - 2026-10-04

### Added

- 长双语结果自动适配宽度：宽屏双栏对照，窄屏译文优先、原文弱化
- 新增 `view.hints`（默认 `false`），在浮窗底部显示关闭与滚动按键提示
- `VVTranslateContent` 新增可选 `sections = { source, translation }`，Groq / MyMemory 默认提供；新增 `source_muted` / `VVTranslateSourceMuted` 高亮，默认链接 `Comment`

### Changed

- loading 迁移至 `vv-utils.loading` v2，内容超高时改在 footer 显示

### Fixed

- 单栏按实际折行计算高度，宽字符不再导致末尾被截
- 修复多行 Visual 翻译的换行写入错误，保留对应高亮

## 0.1.0 - 2026-08-18

### Fixed

- 翻译浮窗被外部关闭时取消请求、清理资源并归还来源 buffer 的临时 `<C-e>` / `<C-y>` 滚动映射
