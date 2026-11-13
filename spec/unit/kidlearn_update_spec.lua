describe("KidLearn update", function()
    local DataStorage
    local JSON
    local Update
    local UpdateHttp
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
        UpdateHttp = require("core.update_http")
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

    -- ------------------------------------------------------------------
    -- Test doubles for the incremental download engine: a scripted fake
    -- socket (no network) and a manual tick scheduler (no UIManager).
    -- ------------------------------------------------------------------

    local FakeSocket = {}
    FakeSocket.__index = FakeSocket

    --- Serves one raw HTTP response from a buffer. chunk_size caps bytes per
    -- receive (simulates a slow drip); stalls makes the first N BODY reads
    -- return "timeout" (simulates a stalled network that must NOT error).
    -- Header line reads never stall, so tests reach the body deterministically.
    local function fake_socket(response, opts)
        opts = opts or {}
        return setmetatable({
            buf = response,
            chunk_size = opts.chunk_size,
            stalls = opts.stalls or 0,
            handshake_waits = opts.handshake_waits or 0,
            closed = false,
            sent = {},
            timeout_value = nil,
        }, FakeSocket)
    end

    function FakeSocket:settimeout(v) self.timeout_value = v end
    function FakeSocket:connect(host, port)
        self.connect_host, self.connect_port = host, port
        return 1
    end
    function FakeSocket:send(data, i)
        self.sent[#self.sent + 1] = data:sub(i or 1)
        return #data
    end
    function FakeSocket:close() self.closed = true end
    function FakeSocket:sni(host) self.sni_host = host end
    function FakeSocket:dohandshake()
        if self.handshake_waits > 0 then
            self.handshake_waits = self.handshake_waits - 1
            return nil, "wantread"
        end
        return 1
    end
    function FakeSocket:receive(pattern, prefix)
        prefix = prefix or ""
        if self.closed then return nil, "closed" end
        if pattern == "*l" then
            local pos = self.buf:find("\n", 1, true)
            if pos then
                local line = prefix .. self.buf:sub(1, pos - 1)
                self.buf = self.buf:sub(pos + 1)
                return (line:gsub("\r$", ""))
            end
            local partial = prefix .. self.buf
            self.buf = ""
            return nil, "closed", partial ~= "" and partial or nil
        end
        if self.stalls > 0 then
            self.stalls = self.stalls - 1
            return nil, "timeout", prefix ~= "" and prefix or nil
        end
        if #self.buf == 0 then
            return nil, "closed", prefix ~= "" and prefix or nil
        end
        local take = math.min(pattern, #self.buf)
        if self.chunk_size then take = math.min(take, self.chunk_size) end
        local data = prefix .. self.buf:sub(1, take)
        self.buf = self.buf:sub(take + 1)
        return data
    end

    local function manual_scheduler()
        local queue = {}
        local sched = {}
        function sched.schedule(_, fn) queue[#queue + 1] = fn end
        function sched.unschedule(fn)
            for i = #queue, 1, -1 do
                if queue[i] == fn then table.remove(queue, i) end
            end
        end
        function sched.run(limit)
            local n = 0
            while #queue > 0 and n < (limit or 100000) do
                local fn = table.remove(queue, 1)
                fn()
                n = n + 1
            end
            return n
        end
        function sched.pending() return #queue end
        return sched
    end

    local function http_response(body, extra_headers)
        local lines = { "HTTP/1.1 200 OK", "Content-Length: " .. #body }
        for _, h in ipairs(extra_headers or {}) do lines[#lines + 1] = h end
        return table.concat(lines, "\r\n") .. "\r\n\r\n" .. body
    end

    --- Run one engine download to completion; returns ok, body_or_err, events, sock, ticks.
    local function run_engine(url, sock, opts)
        opts = opts or {}
        local sched = manual_scheduler()
        local events = {}
        local ok, result
        local handle = UpdateHttp.get({
            url = url,
            tcp = function() return sock end,
            ssl_wrap = opts.ssl_wrap or function(s) return s end,
            schedule = sched.schedule,
            unschedule = sched.unschedule,
            on_progress = function(r, t) events[#events + 1] = { r, t } end,
        }, function(o, b) ok, result = o, b end)
        if opts.before_run then opts.before_run(handle, sched) end
        local ticks = sched.run()
        return ok, result, events, sock, ticks, sched, handle
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

    describe("incremental download engine (no timeout, cancellable)", function()
        it("downloads with content-length and reports byte progress", function()
            local sock = fake_socket(http_response("hello world"), { chunk_size = 4 })
            local ok, body, events, s, _, sched = run_engine("http://example.test/file", sock)
            assert.is_true(ok)
            assert.are.equal("hello world", body)
            assert.are.equal(0, events[1][1])
            assert.are.equal(11, events[1][2])
            assert.are.equal(11, events[#events][1])
            assert.are.equal(11, events[#events][2])
            for i = 2, #events do
                assert.is_true(events[i][1] >= events[i - 1][1])
            end
            assert.is_true(s.closed)
            assert.are.equal(0, s.timeout_value) -- non-blocking: no timeout anywhere
            assert.are.equal("example.test", s.connect_host)
            assert.are.equal(80, s.connect_port)
            assert.is_truthy(s.sent[1]:find("GET /file HTTP/1.1", 1, true))
            assert.are.equal(0, sched.pending())
        end)

        it("keeps waiting through stalls instead of timing out", function()
            local sock = fake_socket(http_response("abc"), { stalls = 7, chunk_size = 1 })
            local ok, body, _, _, ticks = run_engine("http://example.test/f", sock)
            assert.is_true(ok)
            assert.are.equal("abc", body)
            assert.is_true(ticks >= 8) -- waited through every stall, never errored
        end)

        it("yields between ticks on large bodies and stays intact", function()
            local payload = string.rep("k", 300 * 1024) -- larger than one tick budget
            local sock = fake_socket(http_response(payload), { chunk_size = 8192 })
            local ok, body, events, _, ticks = run_engine("http://example.test/big", sock)
            assert.is_true(ok)
            assert.are.equal(payload, body)
            assert.is_true(ticks >= 2)
            assert.are.equal(#payload, events[#events][1])
        end)

        it("follows redirects", function()
            local s1 = fake_socket("HTTP/1.1 302 Found\r\nLocation: http://other.test/final\r\n\r\n")
            local s2 = fake_socket(http_response("payload"))
            local sockets = { s1, s2 }
            local i = 0
            local sched = manual_scheduler()
            local ok, body
            UpdateHttp.get({
                url = "http://example.test/start",
                tcp = function() i = i + 1; return sockets[i] end,
                schedule = sched.schedule,
                unschedule = sched.unschedule,
            }, function(o, b) ok, body = o, b end)
            sched.run()
            assert.is_true(ok)
            assert.are.equal("payload", body)
            assert.is_true(s1.closed)
            assert.are.equal("other.test", s2.connect_host)
        end)

        it("gives up after too many redirects", function()
            local resp = "HTTP/1.1 302 Found\r\nLocation: http://loop.test/again\r\n\r\n"
            local ok, err
            local sched = manual_scheduler()
            UpdateHttp.get({
                url = "http://loop.test/again",
                tcp = function() return fake_socket(resp) end,
                schedule = sched.schedule,
                unschedule = sched.unschedule,
            }, function(o, e) ok, err = o, e end)
            sched.run()
            assert.is_false(ok)
            assert.is_truthy(err:find("重定向", 1, true))
        end)

        it("reads chunked transfer encoding", function()
            local resp = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
                .. "5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n"
            local sock = fake_socket(resp, { chunk_size = 3 })
            local ok, body, events = run_engine("http://example.test/c", sock)
            assert.is_true(ok)
            assert.are.equal("hello world", body)
            assert.are.equal(0, events[1][2]) -- total unknown for chunked
            assert.are.equal(11, events[#events][1])
        end)

        it("reads until close when no length is declared", function()
            local resp = "HTTP/1.1 200 OK\r\n\r\nstreamed data"
            local sock = fake_socket(resp, { chunk_size = 4 })
            local ok, body = run_engine("http://example.test/s", sock)
            assert.is_true(ok)
            assert.are.equal("streamed data", body)
        end)

        it("reports HTTP errors", function()
            local sock = fake_socket("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n")
            local ok, err = run_engine("http://example.test/missing", sock)
            assert.is_false(ok)
            assert.is_truthy(err:find("404", 1, true))
        end)

        it("wraps TLS with SNI and survives handshake waits", function()
            local sock = fake_socket(http_response("secure"), { handshake_waits = 2 })
            local params
            local ok, body = run_engine("https://secure.test/file", sock, {
                ssl_wrap = function(s, p) params = p; return s end,
            })
            assert.is_true(ok)
            assert.are.equal("secure", body)
            assert.are.equal("secure.test", sock.sni_host)
            assert.are.equal(443, sock.connect_port)
            assert.are.equal("client", params.mode)
        end)

        it("cancels mid-download, closes the socket and stops ticking", function()
            local sock = fake_socket(http_response(string.rep("x", 1000)),
                { chunk_size = 10, stalls = 4 })
            local ok, err, events, s, _, sched, handle =
                run_engine("http://example.test/f", sock, {
                    before_run = function(h, sched)
                        sched.run(1) -- connect + headers, first body read stalls
                        assert.is_true(sched.pending() > 0) -- still downloading
                        h.cancel()
                    end,
                })
            assert.is_false(ok)
            assert.are.equal(UpdateHttp.CANCELLED, err)
            assert.is_true(s.closed)
            assert.are.equal(0, sched.pending())
            assert.are.equal(0, events[#events][1]) -- no body bytes arrived
            handle.cancel() -- idempotent
            assert.are.equal(UpdateHttp.CANCELLED, err)
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

        it("installs via the incremental engine with progress, no timeout", function()
            local zip_path = root .. "/release.zip"
            make_zip(zip_path, "-- NEW main\n", "1.3.1")
            local zip_bytes = read_file(zip_path)
            local snap = snapshot()
            local sock = fake_socket(http_response(zip_bytes), { chunk_size = 4096, stalls = 2 })
            local sched = manual_scheduler()
            local events, installed = {}, false
            local ok, err
            local handle = Update.download_and_install({
                plugin_path = plugin_dir,
                asset_url = "https://x/kidlearn.koplugin.zip",
                expect_version = "1.3.1",
                tcp = function() return sock end,
                ssl_wrap = function(s) return s end,
                schedule = sched.schedule,
                unschedule = sched.unschedule,
                on_progress = function(r, t) events[#events + 1] = { r, t } end,
                on_install = function() installed = true end,
            }, function(o, e) ok, err = o, e end)
            assert.is_nil(ok) -- nothing happens until ticks run
            sched.run()
            assert.is_true(ok, tostring(err))
            assert.is_true(installed)
            assert.is_truthy(handle)
            assert.are.equal(#zip_bytes, events[#events][1])
            assert.are.equal(#zip_bytes, events[#events][2])
            assert.are.equal("-- NEW main\n", read_file(plugin_dir .. "/main.lua"))
            assert.are.equal("1.3.1", Update.local_version(plugin_dir))
            assert.is_nil(lfs.attributes(plugins_dir .. "/.kidlearn_update", "mode"))
            assert.is_nil(lfs.attributes(plugins_dir .. "/.kidlearn_backup", "mode"))
            assert_data_unchanged(snap)
        end)

        it("cancel during download leaves plugin and data intact, no temp dirs", function()
            local snap = snapshot()
            local sock = fake_socket(http_response(string.rep("z", 5000)),
                { chunk_size = 64, stalls = 4 })
            local sched = manual_scheduler()
            local ok, err
            local handle = Update.download_and_install({
                plugin_path = plugin_dir,
                asset_url = "https://x/z",
                tcp = function() return sock end,
                ssl_wrap = function(s) return s end,
                schedule = sched.schedule,
                unschedule = sched.unschedule,
            }, function(o, e) ok, err = o, e end)
            sched.run(1)
            assert.is_nil(ok)
            handle.cancel()
            assert.is_false(ok)
            assert.are.equal(Update.CANCELLED, err)
            sched.run() -- no further work may happen
            assert.are.equal("-- OLD main\n", read_file(plugin_dir .. "/main.lua"))
            assert.is_nil(lfs.attributes(plugins_dir .. "/.kidlearn_update", "mode"))
            assert.is_nil(lfs.attributes(plugins_dir .. "/.kidlearn_backup", "mode"))
            assert_data_unchanged(snap)
        end)
    end)
end)
