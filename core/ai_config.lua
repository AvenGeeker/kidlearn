--[[--
AI provider presets and persisted service configuration for KidLearn.

Only connection metadata lives here.  Prompts, HTTP and generated content are
kept in separate modules so the rest of the plugin stays usable offline.
--]]--

local JSON = require("json")

local AIConfig = {}

local CONFIG_FILE_NAME = "kidlearn_ai_config.json"

local PRESETS = {
    {
        id = "openai", name = "OpenAI", protocol = "openai",
        base_url = "https://api.openai.com/v1", model_hint = "gpt-4o-mini",
        requires_key = true,
    },
    {
        id = "deepseek", name = "DeepSeek", protocol = "openai",
        base_url = "https://api.deepseek.com/v1", model_hint = "deepseek-chat",
        requires_key = true,
    },
    {
        id = "qwen", name = "通义千问", protocol = "openai",
        base_url = "https://dashscope.aliyuncs.com/compatible-mode/v1",
        model_hint = "qwen-plus", requires_key = true,
    },
    {
        id = "kimi", name = "Kimi", protocol = "openai",
        base_url = "https://api.moonshot.cn/v1", model_hint = "moonshot-v1-8k",
        requires_key = true,
    },
    {
        id = "zhipu", name = "智谱 GLM", protocol = "openai",
        base_url = "https://open.bigmodel.cn/api/paas/v4", model_hint = "glm-4-flash",
        requires_key = true,
    },
    {
        id = "doubao", name = "豆包/火山方舟", protocol = "openai",
        base_url = "https://ark.cn-beijing.volces.com/api/v3",
        model_hint = "推理接入点 ID", requires_key = true,
    },
    {
        id = "gemini", name = "Google Gemini", protocol = "gemini",
        base_url = "https://generativelanguage.googleapis.com/v1beta",
        model_hint = "gemini-2.0-flash", requires_key = true,
    },
    {
        id = "claude", name = "Anthropic Claude", protocol = "anthropic",
        base_url = "https://api.anthropic.com/v1", model_hint = "claude-3-5-haiku-latest",
        requires_key = true,
    },
    {
        id = "siliconflow", name = "硅基流动", protocol = "openai",
        base_url = "https://api.siliconflow.cn/v1",
        model_hint = "Qwen/Qwen2.5-7B-Instruct", requires_key = true,
    },
    {
        id = "openrouter", name = "OpenRouter", protocol = "openai",
        base_url = "https://openrouter.ai/api/v1", model_hint = "openai/gpt-4o-mini",
        requires_key = true,
    },
    {
        id = "ollama", name = "Ollama（局域网）", protocol = "openai",
        base_url = "", model_hint = "qwen2.5:7b",
        requires_key = false, base_url_editable = true,
    },
    {
        id = "custom", name = "自定义 OpenAI 兼容", protocol = "openai",
        base_url = "", model_hint = "", requires_key = false,
    },
}

local preset_by_id = {}
for _, preset in ipairs(PRESETS) do preset_by_id[preset.id] = preset end

local function trim(value)
    if type(value) ~= "string" then return "" end
    return value:match("^%s*(.-)%s*$") or ""
end

local function first_string(...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if type(value) == "string" and trim(value) ~= "" then return trim(value) end
    end
    return ""
end

local function read_file(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    return content
end

local function content_digest(content)
    local hash = 5381
    for index = 1, #content do
        hash = (hash * 33 + content:byte(index)) % 4294967296
    end
    return string.format("%08x", hash)
end

function AIConfig.presets()
    return PRESETS
end

function AIConfig.preset(id)
    return preset_by_id[id]
end

function AIConfig.next_profile_id(ai)
    local used = {}
    for _, profile in ipairs((ai and ai.profiles) or {}) do
        if type(profile.id) == "string" then used[profile.id] = true end
    end
    local seq = 1
    while used["aip-" .. tostring(seq)] do seq = seq + 1 end
    return "aip-" .. tostring(seq)
end

function AIConfig.new_profile(preset_id, ai)
    local preset = preset_by_id[preset_id]
    if not preset then return nil, "未知 AI 服务预设" end
    return {
        id = AIConfig.next_profile_id(ai),
        preset = preset.id,
        name = preset.name,
        protocol = preset.protocol,
        base_url = preset.base_url,
        api_key = "",
        model = preset.model_hint or "",
    }
end

local function normalize_profile(raw, used_ids)
    if type(raw) ~= "table" then return nil end
    local preset = preset_by_id[raw.preset]
    if not preset then return nil end
    local id = trim(raw.id)
    if id == "" or used_ids[id] then
        local seq = 1
        while used_ids["aip-" .. tostring(seq)] do seq = seq + 1 end
        id = "aip-" .. tostring(seq)
    end
    used_ids[id] = true
    local base_url = preset.base_url
    local saved_url = trim(raw.base_url)
    local keeps_saved_url = preset.id == "custom" or preset.base_url_editable or raw.base_url_custom
    if keeps_saved_url and saved_url ~= "" then base_url = saved_url end
    return {
        id = id,
        preset = preset.id,
        name = trim(raw.name) ~= "" and trim(raw.name) or preset.name,
        protocol = preset.protocol,
        base_url = base_url,
        api_key = type(raw.api_key) == "string" and raw.api_key or "",
        model = trim(raw.model) ~= "" and trim(raw.model) or preset.model_hint or "",
        base_url_custom = keeps_saved_url and saved_url ~= "" and true or nil,
    }
end

function AIConfig.normalize(ai)
    if type(ai) ~= "table" then ai = {} end
    if type(ai.profiles) ~= "table" then ai.profiles = {} end
    local profiles = {}
    local used_ids = {}
    for _, raw in ipairs(ai.profiles) do
        local profile = normalize_profile(raw, used_ids)
        if profile then table.insert(profiles, profile) end
    end
    ai.profiles = profiles
    local active
    for _, profile in ipairs(profiles) do
        if profile.id == ai.active_id then active = profile break end
    end
    if not active then active = profiles[1] end
    ai.active_id = active and active.id or nil
    return ai
end

function AIConfig.find(ai, id)
    ai = AIConfig.normalize(ai)
    for _, profile in ipairs(ai.profiles) do
        if profile.id == id then return profile end
    end
    return nil
end

function AIConfig.active_profile(ai)
    ai = AIConfig.normalize(ai)
    return AIConfig.find(ai, ai.active_id)
end

local function parse_imported(raw)
    if type(raw) ~= "table" then return nil, "配置文件内容必须是 JSON 对象" end
    local raw_profiles = raw.profiles
    if type(raw_profiles) ~= "table" then raw_profiles = { raw } end
    if #raw_profiles == 0 then return nil, "配置文件里没有 AI 服务" end

    local imported = { profiles = {}, active_id = nil }
    for index, item in ipairs(raw_profiles) do
        if type(item) ~= "table" then
            return nil, string.format("第 %d 个服务格式不正确", index)
        end
        local preset_id = first_string(item.preset, item.provider, item.provider_id, "custom")
        local preset = preset_by_id[preset_id]
        if not preset then
            return nil, string.format("第 %d 个服务的预设未知：%s", index, preset_id)
        end
        local api_key = first_string(item.api_key, item.key)
        if preset.requires_key and api_key == "" then
            return nil, string.format("第 %d 个服务缺少 API Key", index)
        end
        local model = first_string(item.model, item.model_name)
        if model == "" then
            return nil, string.format("第 %d 个服务缺少模型名称", index)
        end
        local base_url = first_string(item.base_url, item.api_url, item.endpoint)
        if base_url == "" then base_url = preset.base_url end
        if base_url == "" then
            return nil, string.format("第 %d 个服务缺少接口地址", index)
        end
        table.insert(imported.profiles, {
            id = first_string(item.id),
            preset = preset.id,
            name = first_string(item.name, preset.name),
            protocol = preset.protocol,
            base_url = base_url,
            base_url_custom = base_url ~= preset.base_url or nil,
            api_key = api_key,
            model = model,
        })
    end

    AIConfig.normalize(imported)
    for index, profile in ipairs(imported.profiles) do
        local ok, err = AIConfig.validate(profile)
        if not ok then
            return nil, string.format("第 %d 个服务：%s", index, err)
        end
    end

    local active = raw.active_id or raw.active
    local active_id
    if type(active) == "number" and imported.profiles[active] then
        active_id = imported.profiles[active].id
    elseif type(active) == "string" and trim(active) ~= "" then
        active = trim(active)
        for _, profile in ipairs(imported.profiles) do
            if profile.id == active or profile.name == active then
                active_id = profile.id
                break
            end
        end
    end
    if active_id then imported.active_id = active_id end
    return imported
end

function AIConfig.import_file(ai, path)
    if type(ai) ~= "table" then ai = {} end
    local content = read_file(path)
    if not content then
        if ai.config_digest then
            ai.config_digest = nil
            ai.config_source = nil
            ai.config_error = nil
            return "cleared"
        end
        return "missing"
    end
    local digest = content_digest(content)
    if ai.config_digest == digest then return "unchanged" end

    local ok, raw = pcall(JSON.decode, content)
    if not ok or type(raw) ~= "table" then
        local err = "配置文件不是有效的 JSON 对象"
        local changed = ai.config_error ~= err
        ai.config_error = err
        return nil, err, changed
    end
    local imported, err = parse_imported(raw)
    if not imported then
        local changed = ai.config_error ~= err
        ai.config_error = err
        return nil, err, changed
    end

    ai.profiles = imported.profiles
    ai.active_id = imported.active_id
    ai.config_digest = digest
    ai.config_source = CONFIG_FILE_NAME
    ai.config_error = nil
    return "imported", #imported.profiles
end

function AIConfig.config_file_name()
    return CONFIG_FILE_NAME
end

function AIConfig.validate(profile)
    if type(profile) ~= "table" then return nil, "请先添加 AI 服务" end
    local preset = preset_by_id[profile.preset]
    if not preset then return nil, "AI 服务预设无效，请重新添加" end
    local protocols = { openai = true, anthropic = true, gemini = true }
    if not protocols[profile.protocol] then return nil, "AI 服务协议无效，请重新添加" end
    if trim(profile.model) == "" then return nil, "请填写模型名称" end
    if trim(profile.base_url) == "" then return nil, "请填写接口地址" end
    if not profile.base_url:match("^https?://") then
        return nil, "接口地址必须以 http:// 或 https:// 开头"
    end
    if preset.requires_key and trim(profile.api_key) == "" then
        return nil, "请填写 API Key"
    end
    return true
end

function AIConfig.mask_key(key)
    key = trim(key)
    if key == "" then return "未填写" end
    if #key <= 4 then return "••••" end
    return "••••" .. key:sub(-4)
end

return AIConfig
