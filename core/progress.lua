--[[--
Local progress storage for KidLearn.

All data lives in KOReader's settings directory, so replacing the plugin folder
never removes a child's stars, streak, badges or wrong-question book.
--]]--

local AIConfig = require("core.ai_config")
local Cards = require("core.cards")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local logger = require("logger")

local Progress = {}
Progress.__index = Progress

local SCHEMA_VERSION = 5
local DAILY_KEEP_DAYS = 90
local MAX_WRONG = 200
local MAX_RECENT_IDS = 30
local MAX_KP_TOPICS = 20
-- One-time raw snapshot taken before the first v5 write; never overwritten.
local PRE_UPGRADE_BACKUP_SUFFIX = ".pre-v5.bak"
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

-- Additive v5 daily detail. Existing counters are never removed or renamed.
local function ensure_daily_fields(entry)
    ensure_counter(entry, "answered")
    ensure_counter(entry, "correct")
    ensure_counter(entry, "points")
    ensure_counter(entry, "sessions")
    local subjects = ensure_table(entry, "subjects")
    for _, subject in ipairs(SUBJECTS) do
        local s = ensure_table(subjects, subject)
        ensure_counter(s, "answered")
        ensure_counter(s, "correct")
    end
    ensure_table(entry, "modes")
    local challenge = ensure_table(entry, "challenge")
    ensure_counter(challenge, "sessions")
    ensure_counter(challenge, "answered")
    ensure_counter(challenge, "correct")
    ensure_counter(entry, "kp_answered")
    if type(entry.kp_topics) ~= "table" then entry.kp_topics = {} end
    while #entry.kp_topics > MAX_KP_TOPICS do table.remove(entry.kp_topics, 1) end
    if entry.report ~= nil and type(entry.report) ~= "table" then entry.report = nil end
end

local function remember_kp_topic(daily, subject, topic_id)
    local key = tostring(subject) .. ":" .. tostring(topic_id)
    for _, item in ipairs(daily.kp_topics) do
        if item.key == key then return end
    end
    table.insert(daily.kp_topics, { key = key, subject = subject, topic = topic_id })
    while #daily.kp_topics > MAX_KP_TOPICS do table.remove(daily.kp_topics, 1) end
end

function Progress.open(path, ai_config_path)
    local use_default_ai_config = path == nil and ai_config_path == nil
    path = path or (DataStorage:getSettingsDir() .. "/kidlearn.lua")
    local self = setmetatable({
        path = path,
        settings = LuaSettings:open(path),
    }, Progress)
    self.data = self.settings.data
    self:backup_before_upgrade()
    self:normalize()
    if use_default_ai_config or ai_config_path then
        self:import_ai_config(ai_config_path)
    end
    return self
end

--[[--
Copy the raw pre-upgrade save once, before the first v5 normalize/flush.

Skipped for fresh installs (no file) and when a snapshot already exists; the
snapshot is never overwritten or auto-deleted. Failures only log a warning:
KOReader's own .old rolling backup and fsync still protect the write.
--]]--
function Progress:backup_before_upgrade()
    local version = self.data.schema_version
    if type(version) == "number" and version >= SCHEMA_VERSION then return end
    local input = io.open(self.path, "rb")
    if not input then return end
    local content = input:read("*a")
    input:close()
    if not content or content == "" then return end
    local backup_path = self.path .. PRE_UPGRADE_BACKUP_SUFFIX
    local existing = io.open(backup_path, "rb")
    if existing then
        existing:close()
        return
    end
    local output, err = io.open(backup_path, "wb")
    if not output then
        logger.warn("KidLearn: could not write pre-upgrade backup", backup_path, tostring(err))
        return
    end
    local ok, write_err = output:write(content)
    output:close()
    if not ok then
        logger.warn("KidLearn: pre-upgrade backup write failed", tostring(write_err))
    end
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
    for _, key in ipairs({ "points", "answered", "correct", "sessions", "perfect_sessions", "best_combo", "wrong_cleared", "challenge_sessions", "challenge_answered", "challenge_correct" }) do
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
    -- Repeatable card draws: progress counts answers toward the next draw,
    -- credits are earned draws not yet spent, draws is the lifetime count.
    local draw = ensure_table(d, "draw")
    ensure_counter(draw, "progress")
    ensure_counter(draw, "credits")
    ensure_counter(draw, "draws")
    -- One-time migration: an upgrade (or first install over an existing save)
    -- must not reset a child's accumulated practice to zero. When the draw
    -- ledger is still empty, convert lifetime first-try answers into credits.
    -- The seeded flag makes this idempotent; a ledger that already recorded
    -- draws/credits/progress is left untouched so nothing is double-counted.
    if not draw.seeded then
        if draw.draws == 0 and draw.credits == 0 and draw.progress == 0 then
            local answered = total.answered
            draw.credits = math.floor(answered / Cards.DRAW_ANSWERS)
            draw.progress = answered % Cards.DRAW_ANSWERS
        end
        draw.seeded = true
    end
    -- Card collection is permanent: keep every entry (including ids unknown to
    -- the current pool) so future pool changes never erase collected cards.
    local cards = ensure_table(d, "cards")
    for id, entry in pairs(cards) do
        if type(entry) ~= "table" then
            cards[id] = nil
        else
            entry.count = number_or(entry.count, 0)
            entry.first_at = number_or(entry.first_at, 0)
            entry.last_at = number_or(entry.last_at, 0)
        end
    end
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
    -- Online updater preferences (additive; old saves get defaults). The
    -- updater never writes user data; these only control check behaviour.
    if settings.update_auto_check == nil then settings.update_auto_check = false end
    if type(settings.update_api_url) ~= "string" then settings.update_api_url = "" end

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

    local knowledge = ensure_table(d, "knowledge")
    for _, subject in ipairs(SUBJECTS) do
        local by_topic = ensure_table(knowledge, subject)
        for topic_id, entry in pairs(by_topic) do
            if type(entry) ~= "table" then
                by_topic[topic_id] = nil
            else
                if entry.status ~= "learning" and entry.status ~= "mastered" and entry.status ~= "weak" then
                    entry.status = "learning"
                end
                ensure_counter(entry, "attempts")
                ensure_counter(entry, "correct")
                entry.last_seen = number_or(entry.last_seen, 0)
            end
        end
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
            ensure_daily_fields(entry)
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
    ensure_daily_fields(entry)
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
            topic = question.topic,
            answer_format = question.answer_format,
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
Knowledge-point mastery bookkeeping.

data.knowledge[subject][topic_id] = {status, attempts, correct, last_seen}.
status is "learning", "mastered" or "weak"; an absent entry means not studied.
--]]--
function Progress:kp_entry(subject, topic_id)
    local knowledge = ensure_table(self.data, "knowledge")
    local by_topic = ensure_table(knowledge, subject or "math")
    local entry = by_topic[topic_id]
    if type(entry) ~= "table" then
        entry = { status = "learning", attempts = 0, correct = 0, last_seen = 0 }
        by_topic[topic_id] = entry
    end
    return entry
end

function Progress:record_kp_answer(subject, topic_id, correct, now)
    if not topic_id then return end
    local entry = self:kp_entry(subject, topic_id)
    entry.attempts = (entry.attempts or 0) + 1
    if correct then entry.correct = (entry.correct or 0) + 1 end
    entry.last_seen = now or os.time()
end

function Progress:mark_kp_status(subject, topic_id, status, now)
    if not topic_id then return end
    if status ~= "learning" and status ~= "mastered" and status ~= "weak" then return end
    local entry = self:kp_entry(subject, topic_id)
    entry.status = status
    entry.last_seen = now or os.time()
end

function Progress:kp_status(subject, topic_id)
    local knowledge = self.data.knowledge
    local by_topic = knowledge and knowledge[subject or "math"]
    local entry = by_topic and by_topic[topic_id]
    return entry and entry.status or nil
end

function Progress:kp_summary(subject, topic_ids)
    local counts = { mastered = 0, learning = 0, weak = 0, unlearned = 0, total = 0 }
    for _, topic_id in ipairs(topic_ids or {}) do
        counts.total = counts.total + 1
        local status = self:kp_status(subject, topic_id)
        if status and counts[status] ~= nil then
            counts[status] = counts[status] + 1
        else
            counts.unlearned = counts.unlearned + 1
        end
    end
    return counts
end

--[[--
Write back per-topic mastery after a knowledge-point practice session.

@tparam string subject
@tparam table results list of {topic, correct} first-try outcomes
@tparam boolean single_topic dedicated one-topic practice: any question count
  can promote to mastered; mixed sessions need >=2 questions per topic.
@treturn table topic_id -> status
--]]--
function Progress:finalize_kp_session(subject, results, single_topic, now)
    local by_topic = {}
    local order = {}
    for _, r in ipairs(results or {}) do
        if r.topic then
            if not by_topic[r.topic] then
                by_topic[r.topic] = { total = 0, correct = 0 }
                table.insert(order, r.topic)
            end
            by_topic[r.topic].total = by_topic[r.topic].total + 1
            if r.correct then by_topic[r.topic].correct = by_topic[r.topic].correct + 1 end
        end
    end
    local statuses = {}
    for _, topic_id in ipairs(order) do
        local agg = by_topic[topic_id]
        local status
        if single_topic or agg.total >= 2 then
            if agg.correct == agg.total then status = "mastered"
            elseif agg.correct == 0 then status = "weak"
            else status = "learning" end
        else
            status = agg.correct == 0 and "weak" or "learning"
        end
        self:mark_kp_status(subject, topic_id, status, now)
        statuses[topic_id] = status
    end
    self:flush()
    return statuses
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
        -- Earn draw credits from real practice (not wrong-book review), so
        -- repeated draws cannot be farmed by re-answering the same questions.
        if mode ~= "review" then
            local draw = self.data.draw
            draw.progress = draw.progress + 1
            if draw.progress >= Cards.DRAW_ANSWERS then
                draw.progress = draw.progress - Cards.DRAW_ANSWERS
                draw.credits = draw.credits + 1
            end
        end
        if correct then
            self.data.total.correct = self.data.total.correct + 1
            by_subject.correct = by_subject.correct + 1
            daily.correct = daily.correct + 1
        end
        self:record_adaptive(subject, correct, question.grade)
        if question.topic then
            self:record_kp_answer(subject, question.topic, correct, now)
        end
        if correct then
            removed_from_wrong = self:record_mastery(question)
        else
            self:record_wrong(question, now)
        end
        self:remember_question(question.id)
        self:update_streak(now)

        local subject_daily = daily.subjects[subject]
        if not subject_daily then
            subject_daily = { answered = 0, correct = 0 }
            daily.subjects[subject] = subject_daily
        end
        subject_daily.answered = subject_daily.answered + 1
        if correct then subject_daily.correct = subject_daily.correct + 1 end
        if question.challenge then
            self.data.total.challenge_answered = self.data.total.challenge_answered + 1
            daily.challenge.answered = daily.challenge.answered + 1
            if correct then
                daily.challenge.correct = daily.challenge.correct + 1
                self.data.total.challenge_correct = self.data.total.challenge_correct + 1
            end
        end
        if mode == "kp" then
            daily.kp_answered = daily.kp_answered + 1
            if question.topic then
                remember_kp_topic(daily, subject, question.topic)
            end
        end
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
    local mode = summary.mode or "subject"
    daily.modes[mode] = (daily.modes[mode] or 0) + 1
    if mode == "challenge" then
        self.data.total.challenge_sessions = self.data.total.challenge_sessions + 1
        daily.challenge.sessions = daily.challenge.sessions + 1
    end
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

--[[--
Add drawn cards to the permanent collection.

Entries keep a name/tier snapshot from the first acquisition so later pool
changes never alter already-collected cards. Duplicates only bump the count.
--]]--
function Progress:add_cards(cards, now)
    now = now or os.time()
    local collection = ensure_table(self.data, "cards")
    for _, card in ipairs(cards or {}) do
        if card.id then
            local entry = collection[card.id]
            if type(entry) ~= "table" then
                entry = { count = 0, first_at = now, name = card.name, tier = card.tier }
                collection[card.id] = entry
            end
            entry.count = number_or(entry.count, 0) + 1
            entry.last_at = now
        end
    end
    self:flush()
end

--[[--
Current draw state: answers accumulated toward the next draw, available draw
credits and the lifetime draw count.
--]]--
function Progress:draw_status()
    local draw = self.data.draw
    return {
        progress = draw.progress,
        credits = draw.credits,
        draws = draw.draws,
        need = Cards.DRAW_ANSWERS,
        remaining = Cards.DRAW_ANSWERS - draw.progress,
    }
end

--[[--
Spend one earned draw credit. Returns true when a credit was consumed.
--]]--
function Progress:spend_draw()
    local draw = self.data.draw
    if draw.credits <= 0 then return false end
    draw.credits = draw.credits - 1
    draw.draws = draw.draws + 1
    self:flush()
    return true
end

function Progress:daily_report(now)
    local daily = self:ensure_daily(now)
    return daily.report
end

function Progress:save_daily_report(report, now)
    local daily, key = self:ensure_daily(now)
    daily.report = report
    self:flush()
    return key
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
