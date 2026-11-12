describe("KidLearn update", function()
    local DataStorage
    local JSON
    local Update
    local Archiver
    local ffiutil
    local util
    local lfs

    setup(function()
        require("commonrequire")
        package.path = "plugins/kidlearn.koplugin/?.lua;" .. package.path
        DataStorage = require("datastorage")
        JSON = require("json")
        Update = require("core.update")
        Archiver = require("ffi/archiver")
        ffiutil = require("ffi/util")
        util = require("util")
        lfs = require("libs/libkoreader-lfs")
    end)

    local function read_file(path)
        local fh = io.open(path, "rb")
        if not fh then return nil end
        local data = fh:read("*a")
        fh:close()
        return data
    end

    local function write_file(path, content)
        local fh = assert(io.open(path, "wb"))
        fh:write(content)
        fh:close()
    end

    describe("version comparison", function()
        it("normalizes tags", function()
            assert.are.equal("1.3.0", Update.normalize_version("v1.3.0"))
            assert.are.equal("2.0", Update.normalize_version("V2.0"))
            assert.are.equal("1.3", Update.normalize_version(" 1.3 "))
            assert.are.equal("", Update.normalize_version(nil))
        end)

        it("compares dot components numerically", function()
            assert.are.equal(1, Update.compare_versions("1.10.0", "1.9.0"))
            assert.are.equal(-1, Update.compare_versions("1.9.0", "1.10.0"))
            assert.are.equal(0, Update.compare_versions("1.3", "1.3.0"))
            assert.are.equal(1, Update.compare_versions("2.0", "1.99"))
            assert.are.equal(0, Update.compare_versions("1.3.0", "1.3.0"))
        end)

        it("ranks a plain release above a pre-release", function()
            assert.are.equal(1, Update.compare_versions("1.3.0", "1.3.0-beta"))
            assert.are.equal(-1, Update.compare_versions("1.3.0-beta", "1.3.0"))
        end)

        it("decides whether a remote tag is newer", function()
            assert.is_true(Update.is_newer("v1.3.1", "1.3.0"))
            assert.is_false(Update.is_newer("v1.3.0", "1.3.0"))
            assert.is_false(Update.is_newer("v1.2.9", "1.3.0"))
        end)

        it("reads the installed version from _meta.lua", function()
            -- Derive the expectation from the same single source of truth so
            -- version bumps do not stale this assertion.
            local meta = dofile("plugins/kidlearn.koplugin/_meta.lua")
            assert.are.equal(meta.version, Update.local_version("plugins/kidlearn.koplugin"))
            assert.are.equal("0.0.0", Update.local_version("/no/such/plugin"))
        end)
    end)

    describe("parse_release", function()
        local function release_json(assets, tag)
            return JSON.encode({ tag_name = tag or "v1.3.1", body = "notes", assets = assets })
        end

        it("picks the plugin zip asset among several", function()
            local r = assert(Update.parse_release(release_json({
                { name = "other.zip", browser_download_url = "https://x/other" },
                { name = "kidlearn.koplugin.zip", browser_download_url = "https://x/kidlearn", size = 123 },
            })))
            assert.are.equal("v1.3.1", r.tag)
            assert.are.equal("1.3.1", r.version)
            assert.are.equal("https://x/kidlearn", r.asset_url)
            assert.are.equal(123, r.asset_size)
        end)

        it("errors when the zip asset is missing", function()
            local r, err = Update.parse_release(release_json({
                { name = "other.zip", browser_download_url = "https://x" },
            }))
            assert.is_nil(r)
            assert.is_truthy(err)
        end)

        it("errors on malformed or empty JSON", function()
            assert.is_nil(Update.parse_release("{not json"))
            assert.is_nil(Update.parse_release(""))
        end)
    end)

    describe("sanitize_entry_path", function()
        it("accepts paths under the plugin folder", function()
            assert.are.equal("kidlearn.koplugin/main.lua", Update.sanitize_entry_path("kidlearn.koplugin/main.lua"))
            assert.are.equal("kidlearn.koplugin/core/x.lua", Update.sanitize_entry_path("kidlearn.koplugin/core/x.lua"))
            assert.are.equal("kidlearn.koplugin/", Update.sanitize_entry_path("kidlearn.koplugin/"))
        end)

        it("rejects traversal, absolute, backslash and wrong prefix", function()
            assert.is_nil(Update.sanitize_entry_path("../etc/passwd"))
            assert.is_nil(Update.sanitize_entry_path("kidlearn.koplugin/../evil"))
            assert.is_nil(Update.sanitize_entry_path("/abs/path"))
            assert.is_nil(Update.sanitize_entry_path("kidlearn.koplugin\\evil"))
            assert.is_nil(Update.sanitize_entry_path("other/main.lua"))
            assert.is_nil(Update.sanitize_entry_path(""))
        end)
    end)

    describe("check with a fake transport", function()
        local function fake_transport(body, err)
            return { get = function() return body, err end }
        end
        local function body(tag)
            return JSON.encode({
                tag_name = tag,
                assets = { { name = "kidlearn.koplugin.zip", browser_download_url = "https://x/z" } },
            })
        end

        it("reports an available update", function()
            local result
            Update.check({ local_version = "1.3.0", transport = fake_transport(body("v1.3.1")) },
                function(r) result = r end)
            assert.is_true(result.available)
            assert.are.equal("v1.3.1", result.tag)
            assert.are.equal("1.3.0", result.current)
        end)

        it("reports up to date", function()
            local result
            Update.check({ local_version = "1.3.0", transport = fake_transport(body("v1.3.0")) },
                function(r) result = r end)
            assert.is_false(result.available)
        end)

        it("reports a transport error", function()
            local result
            Update.check({ local_version = "1.3.0", transport = fake_transport(nil, "boom") },
                function(r) result = r end)
            assert.are.equal("boom", result.error)
        end)
    end)

    describe("download_and_install keeps user data byte-identical", function()
        local root, settings_dir, plugins_dir, plugin_dir
        local data_files

        local function make_zip(path, main_content, meta_version)
            local w = Archiver.Writer:new()
            assert(w:open(path, "zip"))
            w:setZipCompression("store")
            assert(w:addFileFromMemory("kidlearn.koplugin/main.lua", main_content))
            assert(w:addFileFromMemory("kidlearn.koplugin/_meta.lua",
                'return { version = "' .. meta_version .. '" }\n'))
            assert(w:addFileFromMemory("kidlearn.koplugin/data/note.txt", "content\n"))
            w:close()
        end

        local function snapshot()
            local snap = {}
            for _, p in ipairs(data_files) do snap[p] = read_file(p) end
            return snap
        end

        local function assert_data_unchanged(snap)
            for _, p in ipairs(data_files) do
                assert.are.equal(snap[p], read_file(p), "user data file changed: " .. p)
            end
        end

        before_each(function()
            root = DataStorage:getDataDir() .. "/kidlearn_update_spec"
            ffiutil.purgeDir(root)
            settings_dir = root .. "/settings"
            plugins_dir = root .. "/plugins"
            plugin_dir = plugins_dir .. "/kidlearn.koplugin"
            assert(util.makePath(settings_dir))
            assert(util.makePath(plugin_dir))
            write_file(plugin_dir .. "/main.lua", "-- OLD main\n")
            write_file(plugin_dir .. "/_meta.lua", 'return { version = "1.3.0" }\n')
            -- User data lives in settings, outside the plugin dir (sentinels).
            data_files = {
                settings_dir .. "/kidlearn.lua",
                settings_dir .. "/kidlearn_ai_bank.json",
                settings_dir .. "/kidlearn_ai_config.json",
            }
            write_file(data_files[1], "-- sentinel progress: stars=42\n")
            write_file(data_files[2], '{"sentinel":"ai-bank"}\n')
            write_file(data_files[3], '{"sentinel":"ai-config"}\n')
        end)

        after_each(function()
            ffiutil.purgeDir(root)
        end)

        it("installs new code, cleans temp dirs, leaves data untouched", function()
            local zip_path = root .. "/release.zip"
            make_zip(zip_path, "-- NEW main\n", "1.3.1")
            local zip_bytes = read_file(zip_path)
            local snap = snapshot()
            local ok, err
            Update.download_and_install({
                plugin_path = plugin_dir,
                asset_url = "https://x/kidlearn.koplugin.zip",
                expect_version = "1.3.1",
                transport = { get = function() return zip_bytes end },
            }, function(o, e) ok, err = o, e end)
            assert.is_true(ok, tostring(err))
            assert.are.equal("-- NEW main\n", read_file(plugin_dir .. "/main.lua"))
            assert.are.equal("1.3.1", Update.local_version(plugin_dir))
            assert.is_nil(lfs.attributes(plugins_dir .. "/.kidlearn_update", "mode"))
            assert.is_nil(lfs.attributes(plugins_dir .. "/.kidlearn_backup", "mode"))
            assert_data_unchanged(snap)
        end)

        it("keeps plugin and data intact on a corrupt package", function()
            local snap = snapshot()
            local ok, err
            Update.download_and_install({
                plugin_path = plugin_dir,
                asset_url = "https://x/z",
                transport = { get = function() return "this is not a zip" end },
            }, function(o, e) ok, err = o, e end)
            assert.is_false(ok)
            assert.is_truthy(err)
            assert.are.equal("-- OLD main\n", read_file(plugin_dir .. "/main.lua"))
            assert.is_nil(lfs.attributes(plugins_dir .. "/.kidlearn_update", "mode"))
            assert_data_unchanged(snap)
        end)

        it("rejects a package missing main.lua and keeps data intact", function()
            local zip_path = root .. "/bad.zip"
            local w = Archiver.Writer:new()
            assert(w:open(zip_path, "zip"))
            w:setZipCompression("store")
            assert(w:addFileFromMemory("kidlearn.koplugin/_meta.lua", 'return { version = "1.3.1" }\n'))
            w:close()
            local snap = snapshot()
            local ok
            Update.download_and_install({
                plugin_path = plugin_dir,
                asset_url = "https://x/z",
                transport = { get = function() return read_file(zip_path) end },
            }, function(o) ok = o end)
            assert.is_false(ok)
            assert.are.equal("-- OLD main\n", read_file(plugin_dir .. "/main.lua"))
            assert_data_unchanged(snap)
        end)

        it("refuses a symlinked development install and keeps data intact", function()
            local link_path = plugins_dir .. "/kidlearn_link.koplugin"
            os.execute("ln -s '" .. plugin_dir .. "' '" .. link_path .. "'")
            assert.are.equal("link", lfs.symlinkattributes(link_path, "mode"))
            local snap = snapshot()
            local ok, err
            Update.download_and_install({
                plugin_path = link_path,
                asset_url = "https://x/z",
                transport = { get = function() return "unused" end },
            }, function(o, e) ok, err = o, e end)
            assert.is_false(ok)
            assert.is_truthy(err)
            assert.are.equal("-- OLD main\n", read_file(plugin_dir .. "/main.lua"))
            assert_data_unchanged(snap)
        end)
    end)
end)
