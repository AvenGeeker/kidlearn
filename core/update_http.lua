--[[--
Incremental, non-blocking HTTP(S) GET for the KidLearn updater.

Why this exists: the release download must show a real progress bar, must
never fail just because the network is slow (NO timeouts at all), and must
stay cancellable by the user. A blocking socket.http request freezes the
whole UI, so none of that is possible with it. Instead we drive a raw
LuaSocket/LuaSec socket in non-blocking mode from short UIManager ticks —
the same technique as KOReader's frontend/httpasync.lua, which we cannot
use directly because it exposes neither byte progress nor mid-fetch
cancellation.

Between ticks the UI runs normally, so taps (including the cancel button)
are processed. There is deliberately no block/total timeout: a stalled
connection simply makes no progress until the user cancels. The only
unavoidable blocking step is DNS resolution inside sock:connect(), which
is equally true of upstream httpasync.

Testability: the scheduler and the socket/TLS factories are injectable, so
unit tests run the whole engine against scripted fake sockets without any
network or UIManager.
--]]--

local socket = require("socket")
local socket_url = require("socket.url")
local ssl = require("ssl")
local util = require("util")

local UpdateHttp = {}

--- Sentinel error string passed to the callback when the user cancels.
UpdateHttp.CANCELLED = "cancelled"

local MAX_REDIRECTS = 5
local TICK_DELAY = 0.03         -- seconds between I/O ticks
local READ_SIZE = 64 * 1024     -- bytes requested per receive() call
local TICK_BUDGET = 256 * 1024  -- max bytes read per tick before yielding

local function is_wait_error(err)
    return err == "timeout" or err == "wantread" or err == "wantwrite"
end

--- Non-blocking line read. LuaSocket's receive(pattern, prefix) prepends
-- prefix to its result, so partial data consumed on a previous timed-out
-- call is carried forward (same idiom as frontend/httpasync.lua).
local function recv_line(sock)
    local accumulated = ""
    while true do
        local res, err, partial = sock:receive("*l", accumulated)
        if err == "timeout" or err == "wantread" then
            accumulated = partial or accumulated
            coroutine.yield()
        elseif err == "wantwrite" then
            coroutine.yield()
        else
            return res, err
        end
    end
end

--- Read the response body, reporting (received, total) progress; total is 0
-- when the size is unknown (chunked / read-until-close). Yields whenever the
-- socket would block or the per-tick byte budget is spent, so the UI stays
-- responsive. Returns body or nil, err.
local function read_body(sock, resp_headers, on_progress)
    local transfer_encoding = resp_headers["transfer-encoding"]
    local chunked = transfer_encoding and transfer_encoding:lower():find("chunked", 1, true)
    local total = (not chunked) and tonumber(resp_headers["content-length"]) or 0
    if on_progress then on_progress(0, total) end

    local chunks = {}
    local received = 0
    local budget = TICK_BUDGET

    local function push(data)
        if not data or #data == 0 then return end
        chunks[#chunks + 1] = data
        received = received + #data
        budget = budget - #data
        if on_progress then on_progress(received, total) end
        if budget <= 0 then
            budget = TICK_BUDGET
            coroutine.yield()
        end
    end

    -- Read exactly `remaining` bytes, tolerating partial reads.
    local function read_exact(remaining)
        while remaining > 0 do
            local chunk, err, partial = sock:receive(math.min(remaining, READ_SIZE))
            if chunk then
                push(chunk)
                remaining = remaining - #chunk
            elseif is_wait_error(err) then
                push(partial)
                if partial then remaining = remaining - #partial end
                coroutine.yield()
            elseif err == "closed" then
                return nil, "下载不完整：连接提前关闭"
            else
                return nil, "下载中断：" .. tostring(err)
            end
        end
        return true
    end

    if chunked then
        while true do
            local line = recv_line(sock)
            if not line then break end
            local hex = line:match("^%x+")
            local size = hex and tonumber(hex, 16)
            if not size or size == 0 then break end
            local ok, err = read_exact(size)
            if not ok then return nil, err end
            recv_line(sock) -- trailing CRLF after each chunk
        end
    elseif total > 0 then
        local ok, err = read_exact(total)
        if not ok then return nil, err end
    else
        -- No size declared: read until the server closes the connection.
        while true do
            local chunk, err, partial = sock:receive(READ_SIZE)
            if chunk then
                push(chunk)
            elseif err == "closed" then
                push(partial)
                break
            elseif is_wait_error(err) then
                push(partial)
                coroutine.yield()
            else
                return nil, "下载中断：" .. tostring(err)
            end
        end
    end
    return table.concat(chunks)
end

--- Worker coroutine: connect -> TLS -> request -> headers -> body, following
-- redirects. Yields whenever I/O would block; returns (ok, body_or_err).
local function worker(opts, state, tcp, ssl_wrap, on_progress)
    local url = opts.url
    local headers = opts.headers or {}
    if type(url) ~= "string" or url == "" then
        return false, "无效的下载地址"
    end

    for _ = 0, MAX_REDIRECTS do
        local parsed = socket_url.parse(url)
        if not parsed or not parsed.host then
            return false, "无效的下载地址"
        end
        if parsed.path then
            -- Encode invalid path chars (e.g. spaces) while keeping "/" and "%".
            parsed.path = util.urlEncode(parsed.path, "/%%")
            url = socket_url.build(parsed)
        end
        local host = parsed.host
        local port = parsed.port or (parsed.scheme == "https" and 443 or 80)
        local path = parsed.path or "/"
        if parsed.query then path = path .. "?" .. parsed.query end

        -- Non-blocking connect. NOTE: hostname resolution inside connect()
        -- is synchronous (getaddrinfo) and cannot be made incremental here.
        local sock = tcp()
        if not sock then return false, "无法创建网络连接" end
        sock:settimeout(0)
        state.sock = sock
        while true do
            local res, err = sock:connect(host, port)
            if res or err == "already connected" then break end
            if err == "timeout" or err == "Operation already in progress" then
                coroutine.yield()
            else
                return false, "连接失败：" .. tostring(err)
            end
        end

        if parsed.scheme == "https" then
            local wrapped, werr = ssl_wrap(sock, {
                mode = "client",
                protocol = "any",
                verify = "none",
                options = { "all", "no_sslv2", "no_sslv3" },
            })
            if not wrapped then
                return false, "TLS 初始化失败：" .. tostring(werr)
            end
            sock = wrapped
            state.sock = sock
            sock:settimeout(0)
            if sock.sni then sock:sni(host) end
            while true do
                local res, err = sock:dohandshake()
                if res then break end
                if err == "wantread" or err == "wantwrite" then
                    coroutine.yield()
                else
                    return false, "TLS 握手失败：" .. tostring(err)
                end
            end
        end

        local req_lines = {
            string.format("GET %s HTTP/1.1", path),
            string.format("Host: %s", parsed.port and (host .. ":" .. parsed.port) or host),
            "User-Agent: KidLearn-Updater",
        }
        for k, v in pairs(headers) do
            req_lines[#req_lines + 1] = string.format("%s: %s", k, v)
        end
        req_lines[#req_lines + 1] = "Connection: close"
        req_lines[#req_lines + 1] = ""
        req_lines[#req_lines + 1] = ""
        local req = table.concat(req_lines, "\r\n")
        local i, n = 1, #req
        while i <= n do
            local res, err, last = sock:send(req, i)
            if err == "timeout" or err == "wantwrite" then
                if last then i = last + 1 end
                coroutine.yield()
            elseif err == "wantread" then
                coroutine.yield()
            elseif err then
                return false, "发送请求失败：" .. tostring(err)
            else
                i = res + 1
            end
        end

        -- Status line + headers.
        local status_line
        local resp_headers = {}
        while true do
            local line, lerr = recv_line(sock)
            if not line then
                return false, "读取响应失败：" .. tostring(lerr)
            end
            if line == "" then break end
            if not status_line then
                status_line = line
            else
                local k, v = line:match("^(.-):%s*(.*)")
                if k then resp_headers[k:lower()] = v end
            end
        end
        local code = status_line and tonumber(status_line:match("HTTP/%d%.%d%s+(%d%d%d)"))
        if not code then return false, "无法解析服务器响应" end

        if code >= 300 and code < 400 then
            local loc = resp_headers["location"]
            sock:close()
            state.sock = nil
            if not loc then return false, "重定向缺少 Location" end
            url = socket_url.absolute(url, loc)
            -- continue with the next hop
        elseif code ~= 200 then
            return false, "HTTP " .. tostring(code)
        else
            local body, berr = read_body(sock, resp_headers, on_progress)
            if not body then return false, berr end
            return true, body
        end
    end
    return false, "重定向次数过多"
end

--- Start an incremental GET. Returns a handle with cancel().
-- opts: {
--   url            string (required)
--   headers        table  extra request headers
--   on_progress    function(received, total)  total=0 when unknown
--   schedule       function(delay, fn)  tick scheduler (default UIManager)
--   unschedule     function(fn)         (default UIManager)
--   tcp            function() -> socket (default socket.tcp; tests inject)
--   ssl_wrap       function(sock, params) -> tls socket (default ssl.wrap)
-- }
-- callback(ok, body_or_err); on user cancel err == UpdateHttp.CANCELLED.
-- The callback always fires asynchronously (first tick is scheduled), and
-- exactly once. No timeout is ever applied.
function UpdateHttp.get(opts, callback)
    opts = opts or {}
    local schedule = opts.schedule or function(delay, fn)
        require("ui/uimanager"):scheduleIn(delay, fn)
    end
    local unschedule = opts.unschedule or function(fn)
        require("ui/uimanager"):unschedule(fn)
    end
    local tcp = opts.tcp or socket.tcp
    local ssl_wrap = opts.ssl_wrap or ssl.wrap

    local state = { finished = false, sock = nil }
    local tick

    local function finish(ok, body_or_err)
        if state.finished then return end
        state.finished = true
        unschedule(tick)
        if state.sock then
            pcall(function() state.sock:close() end)
            state.sock = nil
        end
        callback(ok, body_or_err)
    end

    local co = coroutine.create(function()
        return worker(opts, state, tcp, ssl_wrap, opts.on_progress)
    end)

    tick = function()
        if state.finished then return end
        local ok, a, b = coroutine.resume(co)
        if state.finished then return end
        if not ok then
            finish(false, tostring(a))
        elseif coroutine.status(co) == "dead" then
            finish(a, b)
        else
            schedule(TICK_DELAY, tick)
        end
    end

    schedule(0, tick)

    return {
        cancel = function()
            finish(false, UpdateHttp.CANCELLED)
        end,
    }
end

return UpdateHttp
