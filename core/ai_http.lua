--[[--
HTTP POST transport for the optional KidLearn AI features.

Uses only modules already bundled with KOReader.  When the Turbo looper is
available the request runs asynchronously; otherwise it falls back to the
blocking LuaSocket/LuaSec path used by other KOReader plugins.
--]]--

local http = require("socket.http")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local logger = require("logger")
local socketutil = require("socketutil")
local UIManager = require("ui/uimanager")

local AIHTTP = {}

local CONNECT_TIMEOUT = 20
local TOTAL_TIMEOUT = 90

local function sync_request(request)
    local client = request.url:match("^https://") and https or http
    local chunks = {}
    socketutil:set_timeout(CONNECT_TIMEOUT, TOTAL_TIMEOUT)
    local ok, one, code, _headers, status = pcall(client.request, {
        url = request.url,
        method = "POST",
        headers = request.headers,
        source = ltn12.source.string(request.body),
        sink = ltn12.sink.table(chunks),
    })
    socketutil:reset_timeout()
    if not ok then return nil, nil, tostring(one) end
    if one ~= 1 then return nil, nil, tostring(code or one) end
    if not code then return nil, nil, tostring(status or "网络请求失败") end
    return code, table.concat(chunks), nil
end

local function can_use_turbo()
    if not UIManager.initLooper then return false end
    local ok = pcall(require, "turbo")
    return ok
end

local function async_request(request, callback)
    UIManager:initLooper()
    local finished = false
    local watchdog
    local function finish(status, body, err)
        if finished then return end
        finished = true
        if watchdog then
            local pending = watchdog
            watchdog = nil
            UIManager:unschedule(pending)
        end
        UIManager:resetInputTimeout()
        callback(status, body, err)
    end
    watchdog = function() finish(nil, nil, "请求超时") end
    UIManager:scheduleIn(TOTAL_TIMEOUT + 10, watchdog)
    UIManager.looper:add_callback(function()
        UIManager:setInputTimeout()
        local turbo = require("turbo")
        local ssl = require("ssl")
        local ca_path
        if ssl.get_system_ca then
            local ca_ok, path = pcall(ssl.get_system_ca)
            if ca_ok then ca_path = path end
        end
        local client = turbo.async.HTTPClient({
            verify_ca = ca_path ~= nil,
            ca_path = ca_path,
        })
        local res = coroutine.yield(client:fetch(request.url, {
            method = "POST",
            body = request.body,
            request_timeout = TOTAL_TIMEOUT,
            connect_timeout = CONNECT_TIMEOUT,
            allow_redirects = false,
            on_headers = function(headers)
                for key, value in pairs(request.headers) do
                    headers:add(key, value)
                end
            end,
        }))
        if not res then
            finish(nil, nil, "网络请求失败")
        elseif res.error and (not res.code or res.code < 0) then
            finish(nil, nil, tostring(res.error))
        else
            finish(res.code, res.body, nil)
        end
    end)
end

--- Send a POST request.
-- @param request { url, headers, body }
-- @param callback optional function(status, body, err); when omitted the call
-- is synchronous and returns status, body, err.
function AIHTTP.request(request, callback)
    if not callback then
        return sync_request(request)
    end
    if can_use_turbo() then
        local ok, err = pcall(async_request, request, callback)
        if ok then return end
        logger.warn("KidLearn AI: async request failed, falling back", err)
    end
    local status, body, err = sync_request(request)
    callback(status, body, err)
end

return AIHTTP
