--[[--
Provider-neutral AI client for KidLearn.

Supports OpenAI-compatible chat completions, Anthropic Messages and Gemini
generateContent.  Request construction and response parsing are pure functions
so unit tests never need a live network.
--]]--

local JSON = require("json")
local logger = require("logger")
local util = require("util")

local AIHTTP = require("core.ai_http")

local AIClient = {}

local function trim(value)
    if type(value) ~= "string" then return "" end
    return value:match("^%s*(.-)%s*$") or ""
end

local function join_url(base_url, suffix)
    base_url = trim(base_url):gsub("/+$", "")
    if base_url:sub(-#suffix) == suffix then return base_url end
    return base_url .. suffix
end

local function encode_model(model)
    return (model:gsub("[^%w%-%._~]", function(char)
        return string.format("%%%02X", string.byte(char))
    end))
end

local function message_text(content)
    if type(content) == "string" then return content end
    if type(content) == "table" then
        local parts = {}
        for _, part in ipairs(content) do
            if type(part) == "string" then
                table.insert(parts, part)
            elseif type(part) == "table" and type(part.text) == "string" then
                table.insert(parts, part.text)
            end
        end
        return table.concat(parts)
    end
    return ""
end

local function provider_error(decoded)
    if type(decoded) ~= "table" then return nil end
    local err = decoded.error
    if type(err) == "table" and type(err.message) == "string" then return err.message end
    if type(err) == "string" then return err end
    if type(decoded.message) == "string" then return decoded.message end
    return nil
end

local function clean_error(message)
    message = tostring(message or ""):gsub("<[^>]+>", " ")
    message = message:gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
    if #message > 180 then message = util.fixUtf8(message:sub(1, 180), "") .. "…" end
    return message
end

local function status_error(status, decoded)
    local detail = clean_error(provider_error(decoded))
    local prefix
    if status == 401 then
        prefix = "API Key 无效或已过期"
    elseif status == 403 then
        prefix = "没有权限，Key 可能未开通该模型"
    elseif status == 404 then
        prefix = "接口地址或模型不存在"
    elseif status == 429 then
        prefix = "请求太频繁或额度不足，请稍后再试"
    elseif status == 400 then
        prefix = "服务商拒绝了请求，请检查模型名称"
    elseif status and status >= 500 then
        prefix = "AI 服务暂时不可用，请稍后再试"
    elseif status then
        prefix = "AI 请求失败（HTTP " .. tostring(status) .. "）"
    else
        prefix = "网络连接失败，请检查 Wi-Fi"
    end
    if detail ~= "" then return prefix .. "：" .. detail end
    return prefix
end

local function decode_body(body)
    if type(body) ~= "string" or body == "" then return nil end
    local ok, decoded = pcall(JSON.decode, body)
    if ok and type(decoded) == "table" then return decoded end
    return nil
end

function AIClient.build_request(profile, system_prompt, user_prompt)
    if type(profile) ~= "table" then return nil, "AI 服务配置缺失" end
    local protocol = profile.protocol
    local model = trim(profile.model)
    local headers = { ["Content-Type"] = "application/json", ["Accept"] = "application/json" }
    local body

    if protocol == "openai" then
        local url = join_url(profile.base_url, "/chat/completions")
        if trim(profile.api_key) ~= "" then
            headers["Authorization"] = "Bearer " .. trim(profile.api_key)
        end
        body = {
            model = model,
            messages = {
                { role = "system", content = system_prompt },
                { role = "user", content = user_prompt },
            },
        }
    elseif protocol == "anthropic" then
        local url = join_url(profile.base_url, "/messages")
        headers["x-api-key"] = trim(profile.api_key)
        headers["anthropic-version"] = "2023-06-01"
        body = {
            model = model,
            max_tokens = 3000,
            system = system_prompt,
            messages = {
                { role = "user", content = user_prompt },
            },
        }
        return {
            url = url,
            headers = headers,
            body = JSON.encode(body),
        }
    elseif protocol == "gemini" then
        local base = trim(profile.base_url):gsub("/+$", "")
        local url = base .. "/models/" .. encode_model(model) .. ":generateContent"
        headers["x-goog-api-key"] = trim(profile.api_key)
        body = {
            systemInstruction = {
                parts = { { text = system_prompt } },
            },
            contents = {
                { role = "user", parts = { { text = user_prompt } } },
            },
        }
        return {
            url = url,
            headers = headers,
            body = JSON.encode(body),
        }
    else
        return nil, "不支持的 AI 协议：" .. tostring(protocol)
    end

    return {
        url = join_url(profile.base_url, "/chat/completions"),
        headers = headers,
        body = JSON.encode(body),
    }
end

function AIClient.parse_response(profile, status, body, transport_error)
    if transport_error and #tostring(transport_error) > 0 then
        local detail = clean_error(transport_error)
        local lower = detail:lower()
        -- LuaSec reports an expired socket wait as "wantread"/"wantwrite".
        if lower:find("timeout", 1, true)
            or lower:find("wantread", 1, true)
            or lower:find("wantwrite", 1, true) then
            return nil, "请求超时，请稍后重试"
        end
        if lower:find("connect", 1, true) or lower:find("network", 1, true) then
            return nil, "网络连接失败，请检查 Wi-Fi"
        end
        return nil, "网络请求失败：" .. detail
    end
    local decoded = decode_body(body)
    status = tonumber(status)
    if status and status >= 400 then
        return nil, status_error(status, decoded)
    end
    if not decoded then
        return nil, "AI 返回内容不是有效 JSON"
    end

    local text = ""
    if profile.protocol == "openai" then
        local choice = decoded.choices and decoded.choices[1]
        local message = choice and choice.message
        text = message_text(message and message.content)
        if text == "" and message and type(message.refusal) == "string" then
            text = message.refusal
        end
    elseif profile.protocol == "anthropic" then
        text = message_text(decoded.content)
    elseif profile.protocol == "gemini" then
        local candidate = decoded.candidates and decoded.candidates[1]
        if candidate and candidate.content then
            text = message_text(candidate.content.parts)
        end
        if text == "" and decoded.promptFeedback and decoded.promptFeedback.blockReason then
            return nil, "AI 拒绝了这次请求：" .. tostring(decoded.promptFeedback.blockReason)
        end
    end

    text = trim(text)
    if text == "" then
        return nil, "AI 没有返回题目内容"
    end
    return text
end

--- Generate text from a configured provider.
-- @param opts { transport = function(request, callback), callback = function(text, err) }
function AIClient.generate(profile, system_prompt, user_prompt, opts)
    opts = opts or {}
    local valid, verify_err = require("core.ai_config").validate(profile)
    if not valid then
        if opts.callback then opts.callback(nil, verify_err) return end
        return nil, verify_err
    end
    local request, request_err = AIClient.build_request(profile, system_prompt, user_prompt)
    if not request then
        if opts.callback then opts.callback(nil, request_err) return end
        return nil, request_err
    end

    local transport = opts.transport or AIHTTP.request
    local function finish(status, body, transport_error)
        local text, err = AIClient.parse_response(profile, status, body, transport_error)
        if err then
            logger.warn("KidLearn AI: request failed", profile.preset, profile.model, status, err)
        end
        if opts.callback then
            opts.callback(text, err)
        end
        return text, err
    end

    if opts.callback then
        local ok, err = pcall(transport, request, function(status, body, transport_error)
            finish(status, body, transport_error)
        end)
        if not ok then
            opts.callback(nil, "网络请求失败：" .. tostring(err))
        end
        return
    end

    local ok, status, body, transport_error = pcall(transport, request)
    if not ok then return nil, "网络请求失败：" .. tostring(status) end
    return finish(status, body, transport_error)
end

function AIClient.test(profile, opts)
    opts = opts or {}
    local system = "你是连接测试助手。"
    local user = "请只回复 OK。"
    if opts.callback then
        AIClient.generate(profile, system, user, {
            transport = opts.transport,
            callback = function(text, err)
                if err then opts.callback(nil, err) else opts.callback(true) end
            end,
        })
        return
    end
    local text, err = AIClient.generate(profile, system, user, { transport = opts.transport })
    if err then return nil, err end
    return text ~= nil
end

return AIClient
