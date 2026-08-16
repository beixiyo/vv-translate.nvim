# vv-translate.nvim 开发约定

本插件负责从 Neovim 获取待翻译文本、规范化代码标识符、调度翻译 provider 并展示结果

- `source.lua` 只负责取词和选区，不修改寄存器或编辑状态
- `identifier.lua` 只负责代码标识符规范化，不决定何时翻译
- `provider/init.lua` 只负责 provider 解析、调用和统一结果/错误边界
- `provider/local/` 按加载、格式化和翻译策略拆分内置离线 provider
- `presentation/` 定义 provider presenter 与 view renderer 共享的内容契约
- `view/` 按浮窗生命周期、loading、输入转发、通用默认 renderer、buffer 渲染和语义高亮拆分，不发起翻译
- `init.lua` 组合策略，并负责取消过期请求

公共配置保持 provider 可替换；第三方云端 provider 通过通用请求、结果和错误对象接入，不得在路由层硬编码服务商策略

Provider 的 `data` 保留服务端完整结果，`present` 只负责转换为通用展示内容；`view.render` 只负责最终展示策略，不负责请求或资源生命周期

所有用户可能看到的通知、标题和错误使用英文；源码注释、类型说明和测试描述使用中文
