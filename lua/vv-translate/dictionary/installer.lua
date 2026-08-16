-- 离线词典安装编排：下载、校验、安全解压并替换现有词典
local Archive = require('vv-utils.archive')
local Callback = require('vv-utils.callback')
local Download = require('vv-utils.download')
local fs = require('vv-utils.fs')
local Path = require('vv-translate.dictionary.path')
local Release = require('vv-translate.dictionary.release')

local M = {}
local install_sequence = 0

local function unique_path(parent, prefix)
  install_sequence = install_sequence + 1
  return vim.fs.joinpath(parent, table.concat({
    prefix,
    tostring(vim.fn.getpid()),
    tostring(vim.uv.hrtime()),
    tostring(install_sequence),
  }, '-'))
end

local function read_json(path)
  local ok, value = pcall(fs.load_json, path, { strict = true })
  if not ok then return nil, tostring(value) end
  if type(value) ~= 'table' then return nil, 'JSON root must be an object' end
  return value
end

local function normalize_entry(entry)
  entry = entry:gsub('\\', '/')
  while entry:sub(1, 2) == './' do entry = entry:sub(3) end
  return entry:gsub('/+$', '')
end

local function validate_entries(entries)
  for _, raw_entry in ipairs(entries or {}) do
    local entry = normalize_entry(raw_entry)
    local allowed = entry == ''
      or entry == 'dict'
      or entry == 'manifest.json'
      or entry:match('^dict/[^/]+%.json$') ~= nil
    if not allowed then return nil, 'Unexpected dictionary archive entry: ' .. raw_entry end
  end
  return true
end

local function count_dictionary_files(directory)
  local count = 0
  local scan = vim.uv.fs_scandir(directory)
  if not scan then return nil, 'Dictionary directory cannot be read' end

  while true do
    local name, kind = vim.uv.fs_scandir_next(scan)
    if not name then break end
    if kind ~= 'file' or not name:match('%.json$') then
      return nil, 'Dictionary contains an unexpected entry: ' .. name
    end
    count = count + 1
  end
  return count
end

local function validate_manifest(extracted, release_tag)
  local manifest, read_error = read_json(vim.fs.joinpath(extracted, 'manifest.json'))
  if not manifest then return nil, 'Invalid dictionary manifest: ' .. read_error end
  if manifest.schema_version ~= 1 then return nil, 'Unsupported dictionary manifest schema' end
  if type(manifest.version) ~= 'string' or not manifest.version:match('^%d+%.%d+%.%d+$') then
    return nil, 'Invalid dictionary version'
  end
  if release_tag ~= 'dict-v' .. manifest.version then
    return nil, 'Dictionary version does not match the release tag'
  end
  if type(manifest.file_count) ~= 'number' or manifest.file_count < 1 or manifest.file_count % 1 ~= 0 then
    return nil, 'Invalid dictionary file count'
  end

  local dictionary = vim.fs.joinpath(extracted, 'dict')
  if not fs.is_directory(dictionary) then return nil, 'Dictionary directory is missing from the archive' end
  local actual_count, count_error = count_dictionary_files(dictionary)
  if not actual_count then return nil, count_error end
  if actual_count ~= manifest.file_count then return nil, 'Dictionary file count does not match the manifest' end

  return manifest
end

local function verify_checksum(archive, checksum_path)
  local checksum_ok, expected = pcall(fs.read_all, checksum_path)
  if not checksum_ok then return nil, tostring(expected) end
  expected = expected:match('^%s*([0-9a-fA-F]+)')
  if not expected or #expected ~= 64 then return nil, 'Invalid dictionary checksum file' end

  local archive_ok, content = pcall(fs.read_all, archive)
  if not archive_ok then return nil, tostring(content) end
  if vim.fn.sha256(content):lower() ~= expected:lower() then return nil, 'Dictionary checksum mismatch' end
  return true
end

local function publish(extracted, manifest, destination)
  local parent = vim.fs.dirname(destination)
  local staging = unique_path(parent, '.vv-translate-dict-install')
  local backup = unique_path(parent, '.vv-translate-dict-backup')
  local had_existing = fs.exists(destination)

  local ok, publish_error = pcall(function()
    fs.copy(vim.fs.joinpath(extracted, 'dict'), staging)
    fs.save_json(vim.fs.joinpath(staging, 'manifest.json'), manifest)
    if had_existing then fs.rename(destination, backup) end
    fs.rename(staging, destination)
  end)
  if ok then
    if had_existing then pcall(fs.delete, backup) end
    return true
  end

  pcall(fs.delete, staging)
  if had_existing and fs.exists(backup) and not fs.exists(destination) then
    local restored, restore_error = pcall(fs.rename, backup, destination)
    if not restored then
      return nil, ('%s; previous dictionary remains at %s (%s)'):format(publish_error, backup, restore_error)
    end
  end
  return nil, tostring(publish_error)
end

---下载并安装最新版离线词典
---@param opts? VVTranslateDictionaryInstallOptions
---@param callback fun(result: VVTranslateDictionaryInstallResult)
---@return fun() cancel 取消当前下载或解压阶段，幂等
function M.install(opts, callback)
  opts = opts or {}
  local finish, disable_callback = Callback.limit(callback)
  local cancelled = false
  local cancel_phase
  local temp_root = vim.fn.tempname() .. '-vv-translate'
  local metadata_path = vim.fs.joinpath(temp_root, 'release.json')
  local archive_path = vim.fs.joinpath(temp_root, opts.archive_asset or Release.archive_asset)
  local checksum_path = vim.fs.joinpath(temp_root, opts.checksum_asset or Release.checksum_asset)
  local extracted = vim.fs.joinpath(temp_root, 'extracted')

  local function cleanup()
    if fs.exists(temp_root) then pcall(fs.delete, temp_root) end
  end

  local function complete(result)
    cleanup()
    finish(result)
  end

  local function fail(code, message)
    complete({ ok = false, code = code, message = message })
  end

  local function cancel()
    if cancelled then return end
    cancelled = true
    disable_callback()
    if cancel_phase then pcall(cancel_phase) end
    vim.defer_fn(cleanup, 100)
  end

  local prepared, prepare_error = pcall(function()
    fs.mkdir_p(temp_root)
    fs.mkdir_p(extracted)
  end)
  if not prepared then
    fail('prepare_failed', tostring(prepare_error))
    return cancel
  end

  cancel_phase = Download.file({
    url = opts.metadata_url or Release.metadata_url,
    destination = metadata_path,
  }, function(metadata_download)
    if cancelled then return end
    if not metadata_download.ok then
      fail(metadata_download.code or 'metadata_download_failed', metadata_download.message or 'Failed to download release metadata')
      return
    end

    local metadata, metadata_error = read_json(metadata_path)
    if not metadata then
      fail('invalid_release_metadata', metadata_error)
      return
    end
    local release, release_error = Release.parse(metadata, opts)
    if not release then
      fail('invalid_release_metadata', release_error)
      return
    end

    cancel_phase = Download.file({ url = release.archive_url, destination = archive_path }, function(archive_download)
      if cancelled then return end
      if not archive_download.ok then
        fail(archive_download.code or 'archive_download_failed', archive_download.message or 'Failed to download dictionary archive')
        return
      end

      cancel_phase = Download.file({ url = release.checksum_url, destination = checksum_path }, function(checksum_download)
        if cancelled then return end
        if not checksum_download.ok then
          fail(checksum_download.code or 'checksum_download_failed', checksum_download.message or 'Failed to download dictionary checksum')
          return
        end

        local verified, verify_error = verify_checksum(archive_path, checksum_path)
        if not verified then
          fail('checksum_failed', verify_error)
          return
        end

        cancel_phase = Archive.extract({ archive = archive_path, destination = extracted }, function(extract_result)
          if cancelled then return end
          if not extract_result.ok then
            fail(extract_result.code or 'extract_failed', extract_result.message or 'Failed to extract dictionary archive')
            return
          end

          local entries_valid, entries_error = validate_entries(extract_result.entries)
          if not entries_valid then
            fail('invalid_archive_layout', entries_error)
            return
          end
          local manifest, manifest_error = validate_manifest(extracted, release.tag)
          if not manifest then
            fail('invalid_manifest', manifest_error)
            return
          end

          local destination = opts.destination or Path.install_dir()
          local published, publish_error = publish(extracted, manifest, destination)
          if not published then
            fail('publish_failed', publish_error)
            return
          end
          complete({ ok = true, version = manifest.version, path = destination, tag = release.tag })
        end)
      end)
    end)
  end)

  return cancel
end

return M

---@class VVTranslateDictionaryInstallOptions: VVTranslateDictionaryReleaseOptions
---@field metadata_url? string GitHub Release 元数据地址
---@field destination? string 词典安装目录

---@class VVTranslateDictionaryInstallResult
---@field ok boolean
---@field code? string 稳定失败类型
---@field message? string 英文用户可见错误
---@field version? string 已安装词典版本
---@field path? string 已安装路径
---@field tag? string 对应 Release tag
