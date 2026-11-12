--[[--
GitHub Release self-updater for KidLearn.

This is the second opt-in network subsystem (after AI). It is user-triggered
and manual by default; an optional startup auto-check is off by default and
only runs when already online. No background polling, no telemetry.

DATA SAFETY (hard guarantee): all user data lives in KOReader's settings
directory (kidlearn.lua / kidlearn_ai_bank.json / kidlearn_ai_config.json),
strictly outside the plugin directory. This module's write set is confined to
the plugin directory and two named sibling temp dirs (.kidlearn_update /
.kidlearn_backup). It never references the settings directory and never opens
any data file for writing, so replacing the plugin folder cannot touch learning
history. spec/unit/kidlearn_update_spec.lua proves this byte-for-byte.

Only modules already bundled with KOReader are used: ssl.https / socket.http /
ltn12 / socketutil (transport), json (release parsing), ffi/archiver (libarchive
unzip, also used by the on-device dictionary), util / ffi/util (file ops).
--]]--

local ffiutil = require("ffi/util")
local JSON = require("json")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local socketutil = require("socketutil")
local util = require("util")

local Update = {}

local DEFAULT_API_URL = "https://api.github.com/repos/AvenGeeker/kidlearn/releases/latest"
local ASSET_NAME = "kidlearn.koplugin.zip"
local TOP_DIR = "kidlearn.koplugin"
local STAGING_NAME = ".kidlearn_update"
local BACKUP_NAME = ".kidlearn_backup"
local MAX_REDIRECTS = 5

Update.DEFAULT_API_URL = DEFAULT_API_URL
Update.ASSET_NAME = ASSET_NAME

-- ---------------------------------------------------------------------------
-- Transport (blocking GET, redirect-following). Mirrors core/ai_http.lua's
-- synchronous path; on Kindle the Turbo looper is off, so AI also blocks.
-- The release zip is small (~hundreds of KB), so an in-memory body is safe and
-- keeps redirect handling simple (a file sink would capture 3xx bodies too).
-- ---------------------------------------------------------------------------

local function sync_get(url, headers, block_timeout, total_timeout)
    local http = require("socket.http")
    local https = require("ssl.https")
    local ltn12 = require("ltn12")
    local hops = 0
    while true do
        local client = url:match("^https://") and https or http
        local chunks = {}
        socketutil:set_timeout(block_timeout, total_timeout)
        local ok, one, code, resp_headers, status = pcall(client.request, {
            url = url,
            method = "GET",
            headers = headers,
            redirect = false,
            sink = ltn12.sink.table(chunks),
        })
        socketutil:reset_timeout()
        if not ok then return nil, tostring(one) end
        if one ~= 1 then return nil, tostring(code or one) end
        if not code then return nil, tostring(status or "网络请求失败") end
        if code == 301 or code == 302 or code == 303 or code == 307 or code == 308 then
            local loc = resp_headers and resp_headers["location"]
            if not loc then return nil, "重定向缺少 Location" end
            hops = hops + 1
            if hops > MAX_REDIRECTS then return nil, "重定向次数过多" end
            if loc:match("^https?://") then
                url = loc
            elseif loc:sub(1, 1) == "/" then
                url = url:match("^(https?://[^/]+)") .. loc
            else
                url = url:match("^(https?://[^/]+)") .. "/" .. loc
            end
        elseif code ~= 200 then
            return nil, "HTTP " .. tostring(code), code
        else
            return table.concat(chunks), nil, code
        end
    end
end

local default_transport = {
    get = function(url, headers, block_timeout, total_timeout)
        return sync_get(url, headers, block_timeout or 20, total_timeout or 30)
    end,
}

-- ---------------------------------------------------------------------------
-- Pure helpers (unit-tested without network).
-- ---------------------------------------------------------------------------

function Update.normalize_version(tag)
    if type(tag) ~= "string" then return "" end
    local v = tag:match("^%s*(.-)%s*$") or ""
    v = v:gsub("^[vV]", "")
    return v
end

local function split_version(v)
    v = Update.normalize_version(v)
    local core, suffix = v:match("^([0-9%.]+)(.*)$")
    if not core then core, suffix = v, "" end
    local parts = {}
    for n in core:gmatch("(%d+)") do
        table.insert(parts, tonumber(n))
    end
    return parts, suffix
end

--- Compare two version strings. Returns 1 if a>b, -1 if a<b, 0 if equal.
-- Numeric dot components are compared numerically (1.10 > 1.9); missing
-- components count as 0 (1.3 == 1.3.0). With an equal numeric core, a plain
-- release outranks a suffixed pre-release (1.3.0 > 1.3.0-beta).
function Update.compare_versions(a, b)
    local pa, sa = split_version(a)
    local pb, sb = split_version(b)
    local n = math.max(#pa, #pb)
    for i = 1, n do
        local x = pa[i] or 0
        local y = pb[i] or 0
        if x > y then return 1 elseif x < y then return -1 end
    end
    if sa == "" and sb ~= "" then return 1 end
    if sa ~= "" and sb == "" then return -1 end
    if sa == sb then return 0 end
    return sa < sb and -1 or 1
end

function Update.is_newer(remote_tag, local_version)
    return Update.compare_versions(remote_tag, local_version) > 0
end

--- Parse a GitHub "releases/latest" JSON body and pick the plugin zip asset.
function Update.parse_release(text)
    if type(text) ~= "string" or text == "" then
        return nil, "空的 Release 响应"
    end
    local ok, data = pcall(JSON.decode, text)
    if not ok or type(data) ~= "table" then
        return nil, "Release 响应不是有效 JSON"
    end
    local tag = data.tag_name
    if type(tag) ~= "string" or tag == "" then
        return nil, "Release 缺少 tag_name"
    end
    local asset
    if type(data.assets) == "table" then
        for _, a in ipairs(data.assets) do
            if type(a) == "table" and a.name == ASSET_NAME then
                asset = a
                break
            end
        end
    end
    if not asset then
        return nil, "Release 没有 " .. ASSET_NAME .. " 附件"
    end
    local url = asset.browser_download_url
    if type(url) ~= "string" or url == "" then
        return nil, "附件缺少下载地址"
    end
    return {
        tag = tag,
        version = Update.normalize_version(tag),
        notes = type(data.body) == "string" and data.body or "",
        asset_url = url,
        asset_name = asset.name,
        asset_size = tonumber(asset.size) or 0,
    }
end

--- Validate one zip entry path. Rejects absolute paths, ".." traversal,
-- backslashes, and anything outside the single top-level plugin folder.
-- The top-level directory entry itself ("kidlearn.koplugin/") is allowed.
function Update.sanitize_entry_path(path)
    if type(path) ~= "string" or path == "" then return nil end
    if path:find("\\", 1, true) then return nil end
    if path:sub(1, 1) == "/" then return nil end
    for comp in path:gmatch("[^/]+") do
        if comp == ".." then return nil end
    end
    local trimmed = path:gsub("/+$", "")
    if trimmed == TOP_DIR then
        return path
    end
    if path:sub(1, #TOP_DIR + 1) ~= TOP_DIR .. "/" then return nil end
    if #path <= #TOP_DIR + 1 then return nil end
    return path
end

--- Read the installed version from the plugin's _meta.lua (single source).
function Update.local_version(plugin_path)
    if type(plugin_path) ~= "string" then return "0.0.0" end
    local ok, meta = pcall(dofile, plugin_path .. "/_meta.lua")
    if ok and type(meta) == "table" and type(meta.version) == "string" and meta.version ~= "" then
        return meta.version
    end
    return "0.0.0"
end

-- ---------------------------------------------------------------------------
-- Check for a newer release. Synchronous; invokes callback inline with either
-- { available, tag, version, notes, asset_url, asset_size, current } or
-- { error, current }. opts: { api_url?, local_version?, transport? }.
-- ---------------------------------------------------------------------------

function Update.check(opts, callback)
    opts = opts or {}
    local transport = opts.transport or default_transport
    local api_url = opts.api_url
    if type(api_url) ~= "string" or api_url == "" then api_url = DEFAULT_API_URL end
    local current = opts.local_version or "0.0.0"
    local headers = {
        ["User-Agent"] = "KidLearn-Updater/" .. current,
        ["Accept"] = "application/vnd.github+json",
    }
    local body, err = transport.get(api_url, headers, 20, 30)
    if not body then
        callback({ error = err or "网络请求失败", current = current })
        return
    end
    local release, perr = Update.parse_release(body)
    if not release then
        callback({ error = perr, current = current })
        return
    end
    release.current = current
    release.available = Update.is_newer(release.tag, current)
    callback(release)
end

-- ---------------------------------------------------------------------------
-- Download + install. Synchronous; callback(ok, err, info). Every write is
-- confined to the plugin dir and the two named temp dirs; the settings dir is
-- never touched. opts: { plugin_path, asset_url, expect_version?, transport? }.
-- ---------------------------------------------------------------------------

function Update.download_and_install(opts, callback)
    opts = opts or {}
    local transport = opts.transport or default_transport
    local plugin_path = opts.plugin_path
    local asset_url = opts.asset_url
    if type(plugin_path) ~= "string" or plugin_path == "" then
        callback(false, "缺少插件目录")
        return
    end
    if type(asset_url) ~= "string" or asset_url == "" then
        callback(false, "缺少下载地址")
        return
    end

    -- Guard: refuse symlinked / development installs (e.g. test_plugin.sh link).
    local sym = lfs.symlinkattributes(plugin_path)
    if sym and sym.mode == "link" then
        callback(false, "当前是开发版（符号链接）安装，请手动更新插件目录。")
        return
    end
    local real = ffiutil.realpath(plugin_path)
    if not real or lfs.attributes(real, "mode") ~= "directory" then
        callback(false, "无法定位插件目录")
        return
    end
    local parent = ffiutil.dirname(real)
    local staging = parent .. "/" .. STAGING_NAME
    local backup = parent .. "/" .. BACKUP_NAME

    -- Clean leftovers from a previous interrupted attempt (named temp dirs only).
    if util.pathExists(staging) then ffiutil.purgeDir(staging) end
    if util.pathExists(backup) then ffiutil.purgeDir(backup) end

    local ok, err = util.makePath(staging)
    if not ok then
        callback(false, "无法创建暂存目录（目录可能不可写）：" .. tostring(err))
        return
    end

    local function fail(message)
        if util.pathExists(staging) then ffiutil.purgeDir(staging) end
        logger.warn("KidLearn update:", message)
        callback(false, message)
    end

    -- Download (in-memory; the release zip is small).
    local body, derr = transport.get(asset_url, { ["User-Agent"] = "KidLearn-Updater" }, 20, 180)
    if not body then
        fail("下载更新失败：" .. tostring(derr))
        return
    end
    local zip_path = staging .. "/update.zip"
    local fh, ferr = io.open(zip_path, "wb")
    if not fh then
        fail("无法写入暂存文件：" .. tostring(ferr))
        return
    end
    fh:write(body)
    fh:close()

    -- Extract with libarchive. Read each file to memory and write it ourselves
    -- to a sanitized destination: this keeps normal file permissions (the
    -- libarchive disk writer would otherwise drop read bits) and means
    -- libarchive never writes to disk paths directly.
    local Archiver = require("ffi/archiver")
    local arc = Archiver.Reader:new()
    if not arc:open(zip_path) then
        fail("无法打开更新包：" .. tostring(arc.err))
        return
    end
    local extracted = staging .. "/" .. TOP_DIR
    for entry in arc:iterate() do
        local rel = Update.sanitize_entry_path(entry.path)
        if not rel then
            arc:close()
            fail("更新包含不安全路径：" .. tostring(entry.path))
            return
        end
        local dest = staging .. "/" .. rel
        if entry.mode == "directory" then
            local mok, merr = util.makePath(dest)
            if not mok then arc:close(); fail("创建目录失败：" .. tostring(merr)); return end
        elseif entry.mode == "file" then
            local mok, merr = util.makePath(ffiutil.dirname(dest))
            if not mok then arc:close(); fail("创建目录失败：" .. tostring(merr)); return end
            local content = arc:extractToMemory(entry.path)
            if not content then
                arc:close()
                fail("解压失败：" .. tostring(arc.err))
                return
            end
            local fh, ferr = io.open(dest, "wb")
            if not fh then
                arc:close()
                fail("写入更新文件失败：" .. tostring(ferr))
                return
            end
            fh:write(content)
            fh:close()
        else
            arc:close()
            fail("更新包含不支持的条目类型：" .. tostring(entry.mode))
            return
        end
    end
    arc:close()

    -- Validate the extracted plugin before touching the installed one.
    if lfs.attributes(extracted .. "/main.lua", "mode") ~= "file"
        or lfs.attributes(extracted .. "/_meta.lua", "mode") ~= "file" then
        fail("更新包结构不正确（缺少 main.lua / _meta.lua）")
        return
    end
    if opts.expect_version then
        local got = Update.local_version(extracted)
        if got ~= Update.normalize_version(opts.expect_version) then
            fail("更新包版本与 Release 不一致")
            return
        end
    end

    -- Swap with rollback. rename is atomic on the same filesystem; staging is a
    -- sibling of the plugin dir, so both renames stay on one filesystem.
    local rok, rerr = os.rename(real, backup)
    if not rok then
        fail("无法备份当前插件（目录可能不可写）：" .. tostring(rerr))
        return
    end
    local mok, merr = os.rename(extracted, real)
    if not mok then
        os.rename(backup, real) -- roll back to the previous code
        fail("无法安装新插件，已回滚：" .. tostring(merr))
        return
    end

    -- Success: remove old-code backup and staging (named temp dirs only).
    ffiutil.purgeDir(backup)
    ffiutil.purgeDir(staging)
    callback(true, nil, { plugin_path = real })
end

return Update
