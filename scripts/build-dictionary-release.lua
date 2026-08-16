-- 构建词典 Release 资产，归档格式与运行时安装器共享同一 manifest 契约
local uv = vim.uv

local offset = arg[1] == '--' and 1 or 0
local dictionary = arg[1 + offset]
local output = arg[2 + offset]
local version = arg[3 + offset]
if not dictionary or not output or not version then
  error('Usage: nvim -l scripts/build-dictionary-release.lua <dict> <archive> <version>')
end
if not version:match('^%d+%.%d+%.%d+$') then error('version must use x.y.z format') end

dictionary = vim.fs.abspath(dictionary)
output = vim.fs.abspath(output)
local staging = vim.fn.tempname() .. '-vv-translate-release'

local function mkdir_p(path)
  if uv.fs_stat(path) then return end
  mkdir_p(vim.fs.dirname(path))
  local ok, mkdir_error = uv.fs_mkdir(path, 493)
  if not ok and not tostring(mkdir_error):match('EEXIST') then error(mkdir_error) end
end

local function delete(path)
  local stat = uv.fs_lstat(path)
  if not stat then return end
  if stat.type ~= 'directory' then
    assert(uv.fs_unlink(path))
    return
  end
  local scan = assert(uv.fs_scandir(path))
  while true do
    local name = uv.fs_scandir_next(scan)
    if not name then break end
    delete(vim.fs.joinpath(path, name))
  end
  assert(uv.fs_rmdir(path))
end

local function read(path)
  local fd = assert(uv.fs_open(path, 'r', 420))
  local stat = assert(uv.fs_fstat(fd))
  local content = assert(uv.fs_read(fd, stat.size, 0))
  assert(uv.fs_close(fd))
  return content
end

local function write(path, content)
  mkdir_p(vim.fs.dirname(path))
  local fd = assert(uv.fs_open(path, 'w', 420))
  assert(uv.fs_write(fd, content, 0))
  assert(uv.fs_close(fd))
end

local function copy_dictionary(source, destination)
  mkdir_p(destination)
  local count = 0
  local scan = assert(uv.fs_scandir(source))
  while true do
    local name, kind = uv.fs_scandir_next(scan)
    if not name then break end
    if kind ~= 'file' or not name:match('%.json$') then
      error('Unexpected dictionary entry: ' .. name)
    end
    write(vim.fs.joinpath(destination, name), read(vim.fs.joinpath(source, name)))
    count = count + 1
  end
  return count
end

local tar = vim.fn.exepath('tar')
if tar == '' then tar = vim.fn.exepath('bsdtar') end
if tar == '' then error('tar or bsdtar is required') end

mkdir_p(staging)
mkdir_p(vim.fs.dirname(output))
local file_count = copy_dictionary(dictionary, vim.fs.joinpath(staging, 'dict'))
local manifest = {
  schema_version = 1,
  version = version,
  file_count = file_count,
  source = {
    repository = 'w88975/code-translate-vscode',
    commit = 'e280dbb1cad87c848f99c17fcd31d63050d395b4',
  },
}
write(vim.fs.joinpath(staging, 'manifest.json'), vim.json.encode(manifest))

-- macOS bsdtar 会把 AppleDouble 元数据写进归档，污染运行时 manifest 契约
local result = vim.system({ tar, '-czf', output, '-C', staging, '.' }, {
  text = true,
  env = { COPYFILE_DISABLE = '1' },
}):wait()
delete(staging)
if result.code ~= 0 then error(vim.trim(result.stderr ~= '' and result.stderr or result.stdout)) end

local checksum = vim.fn.sha256(read(output))
write(output .. '.sha256', checksum .. '  ' .. vim.fs.basename(output) .. '\n')
print(('Built %s (%d dictionary files)'):format(output, file_count))
