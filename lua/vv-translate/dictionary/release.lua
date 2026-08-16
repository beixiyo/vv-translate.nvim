-- GitHub 词典 Release 契约解析，不负责网络请求和安装
local M = {}

M.metadata_url = 'https://api.github.com/repos/beixiyo/vv-translate.nvim/releases/latest'
M.archive_asset = 'vv-translate-dict.tar.gz'
M.checksum_asset = 'vv-translate-dict.tar.gz.sha256'

local function find_asset(metadata, name)
  for _, asset in ipairs(metadata.assets or {}) do
    if asset.name == name and type(asset.browser_download_url) == 'string' then
      return asset.browser_download_url
    end
  end
end

---解析最新版 Release 中的词典资产
---@param metadata table
---@param opts? VVTranslateDictionaryReleaseOptions
---@return VVTranslateDictionaryRelease? release
---@return string? error
function M.parse(metadata, opts)
  opts = opts or {}
  if type(metadata) ~= 'table' or type(metadata.tag_name) ~= 'string' then
    return nil, 'Invalid GitHub release metadata'
  end

  local archive_name = opts.archive_asset or M.archive_asset
  local checksum_name = opts.checksum_asset or M.checksum_asset
  local archive_url = find_asset(metadata, archive_name)
  local checksum_url = find_asset(metadata, checksum_name)
  if not archive_url then return nil, 'Dictionary archive is missing from the latest release' end
  if not checksum_url then return nil, 'Dictionary checksum is missing from the latest release' end

  return {
    tag = metadata.tag_name,
    archive_url = archive_url,
    checksum_url = checksum_url,
  }
end

return M

---@class VVTranslateDictionaryReleaseOptions
---@field archive_asset? string 归档资产名称
---@field checksum_asset? string SHA-256 资产名称

---@class VVTranslateDictionaryRelease
---@field tag string Release tag
---@field archive_url string 归档下载地址
---@field checksum_url string SHA-256 下载地址
