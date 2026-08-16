#!/bin/sh

set -eu

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
plugin_root=$(CDPATH= cd -- "$tests_dir/.." && pwd)
vendors=$(CDPATH= cd -- "$plugin_root/.." && pwd)

exec nvim --headless -u NONE \
  --cmd "set runtimepath^=$plugin_root" \
  --cmd "set runtimepath^=$vendors/vv-utils.nvim" \
  -l "$tests_dir/test_translate.lua"

