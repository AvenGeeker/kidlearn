--[[--
Long-term AI variant bank for KidLearn.

Stored outside kidlearn.lua so answering normal questions never rewrites a
large JSON document.  Groups are written only when variants are added or
removed.
--]]--

local DataStorage = require("datastorage")
local JSON = require("json")
local logger = require("logger")
local util = require("util")

local AIBank = {}
AIBank.__index = AIBank

local VERSION = 1

local function default_path()
    return DataStorage:getSettingsDir() .. "/kidlearn_ai_bank.json"
end

local function empty_data()
    return { version = VERSION, next_seq = 1, groups = {} }
end

local function normalize_group(raw)
    if type(raw) ~= "table" or type(raw.id) ~= "string" or raw.id == "" then return nil end
    if type(raw.questions) ~= "table" or #raw.questions == 0 then return nil end
    local group = {
        id = raw.id,
        created_at = tonumber(raw.created_at) or 0,
        provider = type(raw.provider) == "table" and raw.provider or {},
        origins = type(raw.origins) == "table" and raw.origins or {},
        questions = {},
    }
    for _, question in ipairs(raw.questions) do
        if type(question) == "table" and type(question.id) == "string" then
            table.insert(group.questions, question)
        end
    end
    if #group.questions == 0 then return nil end
    return group
end

local function normalize_data(data)
    if type(data) ~= "table" then data = empty_data() end
    if type(data.groups) ~= "table" then data.groups = {} end
    local groups = {}
    local max_seq = 0
    for _, raw in ipairs(data.groups) do
        local group = normalize_group(raw)
        if group then
            table.insert(groups, group)
            local seq = tonumber(group.id:match("^aig%-%d+%-(%d+)$"))
            if seq and seq > max_seq then max_seq = seq end
        end
    end
    data.version = VERSION
    data.groups = groups
    data.next_seq = math.max(tonumber(data.next_seq) or 1, max_seq + 1)
    return data
end

local function load_data(path)
    local content = util.readFromFile(path, "rb")
    if not content then return empty_data() end
    local ok, decoded = pcall(JSON.decode, content)
    if not ok or type(decoded) ~= "table" then
        logger.warn("KidLearn AI: corrupt AI bank, preserving backup", path)
        os.remove(path .. ".bad")
        os.rename(path, path .. ".bad")
        return empty_data()
    end
    return normalize_data(decoded)
end

function AIBank.open(path)
    path = path or default_path()
    local self = setmetatable({ path = path }, AIBank)
    self.data = load_data(path)
    return self
end

function AIBank:save()
    local encoded = JSON.encode(self.data)
    if type(encoded) ~= "string" then return nil, "AI 题库编码失败" end
    local tmp = self.path .. ".tmp"
    local ok, err = util.writeToFile(encoded, tmp, true, false, true)
    if not ok then return nil, tostring(err or "AI 题库写入失败") end
    local renamed = os.rename(tmp, self.path)
    if not renamed then
        ok, err = util.writeToFile(encoded, self.path, true, false, true)
        os.remove(tmp)
        if not ok then return nil, tostring(err or "AI 题库写入失败") end
    end
    return true
end

function AIBank:next_group_id(now)
    local seq = tonumber(self.data.next_seq) or 1
    self.data.next_seq = seq + 1
    return string.format("aig-%d-%d", now or os.time(), seq)
end

function AIBank:add_group(group)
    if type(group) ~= "table" then return nil, "AI 题库分组无效" end
    group.id = group.id or self:next_group_id()
    group.created_at = group.created_at or os.time()
    table.insert(self.data.groups, 1, group)
    local ok, err = self:save()
    if not ok then return nil, err end
    return group
end

function AIBank:get_group(id)
    for _, group in ipairs(self.data.groups) do
        if group.id == id then return group end
    end
    return nil
end

function AIBank:remove_group(id)
    for index, group in ipairs(self.data.groups) do
        if group.id == id then
            table.remove(self.data.groups, index)
            return self:save()
        end
    end
    return nil, "没有找到这组 AI 变种"
end

function AIBank:clear()
    self.data.groups = {}
    return self:save()
end

function AIBank:groups(origin_id)
    local groups = {}
    for _, group in ipairs(self.data.groups) do
        local include = not origin_id
        if origin_id then
            for _, origin in ipairs(group.origins or {}) do
                if origin.id == origin_id then include = true break end
            end
        end
        if include then table.insert(groups, group) end
    end
    table.sort(groups, function(a, b)
        if (a.created_at or 0) == (b.created_at or 0) then return a.id > b.id end
        return (a.created_at or 0) > (b.created_at or 0)
    end)
    return groups
end

function AIBank:count_questions()
    local count = 0
    for _, group in ipairs(self.data.groups) do count = count + #(group.questions or {}) end
    return count
end

return AIBank
