--[[--
Local progress storage for KidLearn.

All data lives in KOReader's settings directory, so replacing the plugin folder
never removes a child's stars, streak, badges or wrong-question book.
--]]--

local AIConfig = require("core.ai_config")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local Progress = {}
Progress.__index = Progress

local SCHEMA_VERSION = 3
local DAILY_KEEP_DAYS = 90
local MAX_WRONG = 200
local MAX_RECENT_IDS = 30
local SUBJECTS = { "chinese", "math" }

local function number_or(value, default)
    return type(value) == "number" and value or default
end

local function today_key(now)
    return os.date("%Y-%m-%d", now or os.time())
end

local function day_to_time(key)
    local y, m, d = tostring(key or ""):match("^(%d+)-(%d+)-(%d+)$")
    if not y then return nil end
    return os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }
end

local function next_day_key(key)
    local t = day_to_time(key)
    if not t then return nil end
    local d = os.date("*t", t + 86400)
    return string.format("%04d-%02d-%02d", d.year, d.month, d.day)
end

local function ensure_table(parent, key)
    local value = parent[key]
    if type(value) ~= "table" then
        value = {}
        parent[key] = value
    end
    return value
end

local function ensure_counter(tbl, key)
    tbl[key] = number_or(tbl[key], 0)
end

function Progress.open(path, ai_config_path)
    local use_default_ai_config = path == nil and ai_config_path == nil
    path = path or (DataStorage:getSettingsDir() .. "/kidlearn.lua")
    local self = setmetatable({
        path = path,
        settings = LuaSettings:open(path),
    }, Progress)
    self.data = self.settings.data
    self:normalize()
    if use_default_ai_config or ai_config_path then
        self:import_ai_config(ai_config_path)
    end
    return self
end

function Progress:import_ai_config(path)
    path = path or (DataStorage:getSettingsDir() .. "/" .. AIConfig.config_file_name())
    local status, detail, changed = AIConfig.import_file(self.data.settings.ai, path)
    if status == "imported" then
        self:flush()
    elseif status == "cleared" or changed then
        self:flush()
    end
    return status, detail
end

function Progress:normalize()
    local d = self.data
    d.schema_version = SCHEMA_VERSION

    local total = ensure_table(d, "total")
    for _, key in ipairs({ "points", "answered", "correct", "sessions", "perfect_sessions", "best_combo", "wrong_cleared" }) do
        ensure_counter(total, key)
    end

    local by_subject = ensure_table(d, "by_subject")
    for _, subject in ipairs(SUBJECTS) do
        local s = ensure_table(by_subject, subject)
        ensure_counter(s, "answered")
        ensure_counter(s, "correct")
    end

    local streak = ensure_table(d, "streak")
    ensure_counter(streak, "current")
    ensure_counter(streak, "best")

    ensure_table(d, "daily")
    ensure_table(d, "wrong")
    ensure_table(d, "badges")
    local adaptive = ensure_table(d, "adaptive")
    for _, subject in ipairs(SUBJECTS) do
        local a = ensure_table(adaptive, subject)
        a.level = number_or(a.level, 2)
        if a.level < 1 then a.level = 1 elseif a.level > 3 then a.level = 3 end
        ensure_counter(a, "attempts")
        ensure_counter(a, "correct")
    end
    local settings = ensure_table(d, "settings")
    if settings.semester ~= "upper" and settings.semester ~= "lower" then
        settings.semester = "upper"
    end
    settings.daily_goal = number_or(settings.daily_goal, 10)
    if settings.retry == nil then settings.retry = true end
    settings.grade = tonumber(settings.grade) or 2
    if settings.grade < 1 then settings.grade = 1 elseif settings.grade > 6 then settings.grade = 6 end
    if type(settings.province) ~= "string" or settings.province == "" then settings.province = "other" end
    local chinese_editions = { tongbian = true }
    local math_editions = { renjiao = true, beishida = true, sujiao = true, qingdao = true, hujiao = true }
    if type(settings.chinese_edition) ~= "string" or not chinese_editions[settings.chinese_edition] then
        settings.chinese_edition = "tongbian"
    end
    if type(settings.math_edition) ~= "string" or not math_editions[settings.math_edition] then
        settings.math_edition = "renjiao"
    end
    settings.ai = AIConfig.normalize(settings.ai)

    local adaptive_by_grade = ensure_table(d, "adaptive_by_grade")
    for _, subject in ipairs(SUBJECTS) do
        local by_grade = ensure_table(adaptive_by_grade, subject)
        local key = tostring(settings.grade)
        local a = ensure_table(by_grade, key)
        if not a.level then
            local legacy = adaptive[subject]
            a.level = legacy and legacy.level or 2
            a.attempts = legacy and legacy.attempts or 0
            a.correct = legacy and legacy.correct or 0
        end
        a.level = number_or(a.level, 2)
        if a.level < 1 then a.level = 1 elseif a.level > 3 then a.level = 3 end
        ensure_counter(a, "attempts")
        ensure_counter(a, "correct")
    end

    local recent = d.recent_ids
    if type(recent) ~= "table" then
        recent = {}
        d.recent_ids = recent
    end
    while #recent > MAX_RECENT_IDS do
        table.remove(recent, 1)
    end

    self:prune_daily()
    self:trim_wrong()
    return self
end

function Progress:prune_daily()
    local cutoff = os.time() - DAILY_KEEP_DAYS * 86400
    for key, entry in pairs(self.data.daily) do
        local ts = day_to_time(key)
        if not ts or ts < cutoff then
            self.data.daily[key] = nil
        elseif type(entry) ~= "table" then
            self.data.daily[key] = nil
        else
            ensure_counter(entry, "answered")
            ensure_counter(entry, "correct")
            ensure_counter(entry, "points")
            ensure_counter(entry, "sessions")
        end
    end
end

function Progress:trim_wrong()
    local wrong = self.data.wrong
    local count = 0
    local oldest_id, oldest_seen
    for id, item in pairs(wrong) do
        if type(item) ~= "table" then
            wrong[id] = nil
        else
            count = count + 1
            if not oldest_seen or (item.last_seen or 0) < oldest_seen then
                oldest_seen = item.last_seen or 0
                oldest_id = id
            end
        end
    end
    while count > MAX_WRONG and oldest_id do
        wrong[oldest_id] = nil
        count = count - 1
        oldest_id, oldest_seen = nil, nil
        for id, item in pairs(wrong) do
            if not oldest_seen or (item.last_seen or 0) < oldest_seen then
                oldest_seen = item.last_seen or 0
                oldest_id = id
            end
        end
    end
end

function Progress:ensure_daily(now)
    local key = today_key(now)
    local entry = ensure_table(self.data.daily, key)
    ensure_counter(entry, "answered")
    ensure_counter(entry, "correct")
    ensure_counter(entry, "points")
    ensure_counter(entry, "sessions")
    return entry, key
end

function Progress:update_streak(now)
    local _, today = self:ensure_daily(now)
    local streak = self.data.streak
    local daily = self.data.daily[today]
    if daily.answered < 5 then return end
    if streak.last_day == today then return end
    local last = streak.last_day
    if last then
        local last_ts, today_ts = day_to_time(last), day_to_time(today)
        if last_ts and today_ts and today_ts < last_ts then
            return -- Device clock moved backwards; keep existing streak.
        end
        if next_day_key(last) == today then
            streak.current = streak.current + 1
        else
            streak.current = 1
        end
    else
        streak.current = 1
    end
    streak.last_day = today
    if streak.current > streak.best then streak.best = streak.current end
end

local function adaptive_entry(self, subject, grade)
    local by_grade = ensure_table(self.data, "adaptive_by_grade")
    local subject_table = ensure_table(by_grade, subject)
    local key = tostring(grade or self.data.settings.grade or 2)
    local a = ensure_table(subject_table, key)
    if not a.level then
        local legacy = self.data.adaptive and self.data.adaptive[subject]
        a.level = legacy and legacy.level or 2
        a.attempts = 0
        a.correct = 0
    end
    return a
end

function Progress:record_adaptive(subject, correct, grade)
    local a = adaptive_entry(self, subject, grade)
    a.attempts = a.attempts + 1
    if correct then a.correct = a.correct + 1 end
    if a.attempts >= 10 then
        local accuracy = a.correct / a.attempts
        if accuracy >= 0.9 and a.level < 3 then
            a.level = a.level + 1
        elseif accuracy <= 0.5 and a.level > 1 then
            a.level = a.level - 1
        end
        a.attempts = 0
        a.correct = 0
    end
end

function Progress:remember_question(id)
    if not id then return end
    local recent = self.data.recent_ids
    for i = #recent, 1, -1 do
        if recent[i] == id then table.remove(recent, i) end
    end
    table.insert(recent, id)
    while #recent > MAX_RECENT_IDS do table.remove(recent, 1) end
end

function Progress:record_wrong(question, now)
    local id = question.id
    if not id then return end
    local item = self.data.wrong[id]
    if not item then
        item = {
            id = id,
            subject = question.subject,
            grade = question.grade,
            edition = question.edition,
            unit_name = question.unit_name,
            semester = question.semester,
            unit = question.unit,
            type = question.type,
            skill = question.skill,
            competency = question.competency,
            challenge = question.challenge,
            difficulty = question.difficulty,
            answer_mode = question.answer_mode or "choice",
            stem = question.stem,
            passage = question.passage,
            options = question.options,
            answer = question.answer,
            unit_hint = question.unit_hint,
            explain = question.explain,
            ai_generated = question.ai_generated,
            origin_id = question.origin_id,
            ai_group_id = question.ai_group_id,
            added_at = now,
            wrong_count = 0,
            mastery = 0,
        }
        self.data.wrong[id] = item
    end
    item.last_seen = now
    item.wrong_count = (item.wrong_count or 0) + 1
    item.mastery = 0
    self:trim_wrong()
end

function Progress:record_mastery(question)
    local id = question.id
    local item = id and self.data.wrong[id]
    if not item then return false end
    item.mastery = (item.mastery or 0) + 1
    item.last_seen = os.time()
    if item.mastery >= 2 then
        self.data.wrong[id] = nil
        self.data.total.wrong_cleared = self.data.total.wrong_cleared + 1
        return true
    end
    return false
end

--[[--
Record one answer attempt.

@tparam table question Normalized question object.
@tparam table opts {
    attempt = 1|2, correct = boolean, mode = "normal"|"review",
    combo = number, combo_bonus = number, now = timestamp
}
@treturn table {points = number, removed_from_wrong = boolean}
--]]--
function Progress:record_answer(question, opts)
    opts = opts or {}
    local now = opts.now or os.time()
    local attempt = opts.attempt or 1
    local correct = opts.correct and true or false
    local mode = opts.mode or "normal"
    local subject = question.subject or "chinese"
    local daily = self:ensure_daily(now)
    local by_subject = ensure_table(self.data.by_subject, subject)
    ensure_counter(by_subject, "answered")
    ensure_counter(by_subject, "correct")

    local points = 0
    local removed_from_wrong = false

    if attempt == 1 then
        self.data.total.answered = self.data.total.answered + 1
        by_subject.answered = by_subject.answered + 1
        daily.answered = daily.answered + 1
        if correct then
            self.data.total.correct = self.data.total.correct + 1
            by_subject.correct = by_subject.correct + 1
            daily.correct = daily.correct + 1
        end
        self:record_adaptive(subject, correct, question.grade)
        if correct then
            removed_from_wrong = self:record_mastery(question)
        else
            self:record_wrong(question, now)
        end
        self:remember_question(question.id)
        self:update_streak(now)
    end

    if correct then
        if mode == "review" then
            points = attempt == 1 and 5 or 2
        else
            points = attempt == 1 and 10 or 5
        end
    end
    if attempt == 1 and opts.combo_bonus and mode ~= "review" then
        points = points + opts.combo_bonus
    end

    self.data.total.points = self.data.total.points + points
    daily.points = daily.points + points
    if opts.combo and opts.combo > self.data.total.best_combo then
        self.data.total.best_combo = opts.combo
    end

    self:flush()
    return { points = points, removed_from_wrong = removed_from_wrong }
end

--[[--
Record a completed, non-review session.
@treturn table point breakdown
--]]--
function Progress:record_session(summary, now)
    summary = summary or {}
    if summary.mode == "review" then
        return { completion = 0, perfect = 0, first_of_day = 0, total = 0 }
    end
    local daily = self:ensure_daily(now)
    local breakdown = { completion = 10, perfect = 0, first_of_day = 0 }
    if summary.perfect then
        breakdown.perfect = 20
    end
    if daily.sessions == 0 then
        breakdown.first_of_day = 10
    end
    local total = breakdown.completion + breakdown.perfect + breakdown.first_of_day
    breakdown.total = total
    self.data.total.points = self.data.total.points + total
    daily.points = daily.points + total
    self.data.total.sessions = self.data.total.sessions + 1
    daily.sessions = daily.sessions + 1
    if summary.perfect then
        self.data.total.perfect_sessions = self.data.total.perfect_sessions + 1
    end
    self:flush()
    return breakdown
end

function Progress:today(now)
    local daily = self:ensure_daily(now)
    local goal = self.data.settings.daily_goal
    return {
        answered = daily.answered,
        correct = daily.correct,
        points = daily.points,
        sessions = daily.sessions,
        goal = goal,
        done = daily.answered >= goal,
    }
end

function Progress:total()
    return self.data.total
end

function Progress:settings()
    return self.data.settings
end

function Progress:adaptive_level(subject, grade)
    local a = adaptive_entry(self, subject, grade)
    return a and a.level or 2
end

function Progress:is_recent(id)
    for _, value in ipairs(self.data.recent_ids) do
        if value == id then return true end
    end
    return false
end

function Progress:wrong_items()
    local items = {}
    for _, item in pairs(self.data.wrong) do
        table.insert(items, item)
    end
    table.sort(items, function(a, b)
        return (a.last_seen or 0) < (b.last_seen or 0)
    end)
    return items
end

function Progress:reset_progress()
    local settings = self.data.settings
    local new_data = { settings = settings }
    self.data = new_data
    self.settings.data = new_data
    self:normalize()
    self:flush()
end

function Progress:flush()
    self.settings:flush()
end

return Progress
