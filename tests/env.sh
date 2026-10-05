# 默认不依赖业务 fixture。保留显式指定的可选源码，
# 并在隔离 HOME/工作目录前拒绝无效覆盖项
if [ -n "${VV_ICONS:-}" ]; then
  vv_test_dependency VV_ICONS vv-icons.nvim lua/vv-icons/init.lua
fi
if [ -n "${VV_BUFFERLINE:-}" ]; then
  vv_test_dependency VV_BUFFERLINE vv-bufferline.nvim lua/vv-bufferline/init.lua
fi
