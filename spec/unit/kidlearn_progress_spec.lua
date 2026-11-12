describe("KidLearn progress", function()
    local DataStorage
    local Progress
    local Badges
    local path

    setup(function()
        require("commonrequire")
        package.path = "plugins/kidlearn.koplugin/?.lua;" .. package.path
        DataStorage = require("datastorage")
        Progress = require("core.progress")
        Badges = require("core.badges")
    end)

    before_each(function()
        path = DataStorage:getDataDir() .. "/kidlearn_progress_spec.lua"
        os.remove(path)
        os.remove(path .. ".old")
        os.remove(path .. ".pre-v5.bak")
    end)

    local function question(id, subject)
        return {
            id = id or "q",
            subject = subject or "math",
            semester = "upper",
            unit = subject == "chinese" and "u1" or "m2",
            type = "math_number",
            skill = "add_sub",
            difficulty = 1,
            answer_mode = "number",
            stem = "1 + 1 = ?",
            answer = 2,
            explain = "1 + 1 = 2。",
        }
    end

    local function day(day_number, hour)
        return os.time({ year = 2026, month = 11, day = day_number, hour = hour or 12 })
    end

    it("awards points and records daily progress", function()
        local p = Progress.open(path)
        local result = p:record_answer(question("q1"), {
            attempt = 1, correct = true, combo = 1, now = day(10),
        })
        assert.are.equal(10, result.points)
        assert.are.equal(10, p.data.total.points)
        assert.are.equal(1, p.data.daily["2026-11-10"].answered)
        assert.are.equal(1, p.data.daily["2026-11-10"].correct)
    end)

    it("keeps first-try accuracy separate from a successful retry", function()
        local p = Progress.open(path)
        p:record_answer(question("q1"), { attempt = 1, correct = false, combo = 0, now = day(10) })
        assert.is_not_nil(p.data.wrong.q1)
        local result = p:record_answer(question("q1"), { attempt = 2, correct = true, now = day(10) })
        assert.are.equal(5, result.points)
        assert.are.equal(1, p.data.total.answered)
        assert.are.equal(0, p.data.total.correct)
    end)


    it("does not award combo bonuses in review mode", function()
        local p = Progress.open(path)
        local result = p:record_answer(question("review"), {
            attempt = 1, correct = true, mode = "review", combo_bonus = 20, now = day(10),
        })
        assert.are.equal(5, result.points)
    end)

    it("updates a streak after five answers on a new day", function()
        local p = Progress.open(path)
        for i = 1, 5 do
            p:record_answer(question("d1-" .. i), { attempt = 1, correct = true, combo = 1, now = day(10) })
        end
        assert.are.equal(1, p.data.streak.current)
        for i = 1, 5 do
            p:record_answer(question("d2-" .. i), { attempt = 1, correct = true, combo = 1, now = day(11) })
        end
        assert.are.equal(2, p.data.streak.current)
    end)

    it("removes a wrong item after two first-try correct answers", function()
        local p = Progress.open(path)
        p:record_answer(question("q1"), { attempt = 1, correct = false, combo = 0, now = day(10) })
        p:record_answer(question("q1"), { attempt = 1, correct = true, combo = 1, now = day(11) })
        assert.are.equal(1, p.data.wrong.q1.mastery)
        p:record_answer(question("q1"), { attempt = 1, correct = true, combo = 2, now = day(11) })
        assert.is_nil(p.data.wrong.q1)
        assert.are.equal(1, p.data.total.wrong_cleared)
    end)

    it("unlocks badges once and records a session bonus", function()
        local p = Progress.open(path)
        local breakdown = p:record_session({ perfect = true }, day(10))
        assert.are.equal(40, breakdown.total)
        local unlocked = Badges.evaluate(p)
        assert.is_true(#unlocked >= 2)
        local again = Badges.evaluate(p)
        assert.are.equal(0, #again)
    end)

    it("resets progress but keeps settings", function()
        local p = Progress.open(path)
        p.data.settings.semester = "lower"
        p.data.settings.daily_goal = 15
        p.data.settings.ai = {
            active_id = "aip-1",
            profiles = { { id = "aip-1", preset = "deepseek", api_key = "k", model = "deepseek-chat" } },
        }
        p:record_answer(question("q1"), { attempt = 1, correct = true, combo = 1, now = day(10) })
        p:reset_progress()
        assert.are.equal(0, p.data.total.points)
        assert.are.equal("lower", p.data.settings.semester)
        assert.are.equal(15, p.data.settings.daily_goal)
        assert.are.equal(1, #p.data.settings.ai.profiles)
        assert.are.equal("deepseek-chat", p.data.settings.ai.profiles[1].model)
    end)

    it("normalizes multi-grade settings and records grade metadata", function()
        local p = Progress.open(path)
        assert.are.equal(2, p.data.settings.grade)
        assert.are.equal("other", p.data.settings.province)
        assert.are.equal("tongbian", p.data.settings.chinese_edition)
        assert.are.equal("renjiao", p.data.settings.math_edition)
        local q = question("grade-q")
        q.grade = 4
        q.edition = "sujiao"
        q.unit_name = "小数的意义和性质"
        p:record_answer(q, { attempt = 1, correct = false, combo = 0, now = day(10) })
        assert.are.equal(4, p.data.wrong["grade-q"].grade)
        assert.are.equal("sujiao", p.data.wrong["grade-q"].edition)
        assert.are.equal("小数的意义和性质", p.data.wrong["grade-q"].unit_name)
    end)

    it("keeps AI metadata on a wrong variant", function()
        local p = Progress.open(path)
        local q = question("ai-wrong")
        q.ai_generated = true
        q.origin_id = "origin-1"
        q.ai_group_id = "aig-1"
        p:record_answer(q, { attempt = 1, correct = false, combo = 0, now = day(10) })
        local item = p.data.wrong["ai-wrong"]
        assert.is_true(item.ai_generated)
        assert.are.equal("origin-1", item.origin_id)
        assert.are.equal("aig-1", item.ai_group_id)
    end)

    it("keeps adaptive difficulty separate for each grade", function()
        local p = Progress.open(path)
        p.data.settings.grade = 2
        for _ = 1, 10 do
            p:record_adaptive("math", true, 2)
        end
        assert.are.equal(3, p:adaptive_level("math", 2))
        assert.are.equal(2, p:adaptive_level("math", 6))
        for _ = 1, 10 do
            p:record_adaptive("math", false, 6)
        end
        assert.are.equal(1, p:adaptive_level("math", 6))
        assert.are.equal(3, p:adaptive_level("math", 2))
    end)

    it("migrates an old archive without the new settings fields", function()
        local p = Progress.open(path)
        p.data.settings = { semester = "lower", daily_goal = 15, retry = false }
        p.data.adaptive = {
            chinese = { level = 3, attempts = 4, correct = 3 },
            math = { level = 1, attempts = 2, correct = 1 },
        }
        p.data.adaptive_by_grade = nil
        p:normalize()
        assert.are.equal(2, p.data.settings.grade)
        assert.are.equal("other", p.data.settings.province)
        assert.are.equal("tongbian", p.data.settings.chinese_edition)
        assert.are.equal("renjiao", p.data.settings.math_edition)
        assert.are.equal("lower", p.data.settings.semester)
        assert.are.equal(15, p.data.settings.daily_goal)
        assert.are.equal(false, p.data.settings.retry)
        assert.are.equal("table", type(p.data.settings.ai))
        assert.are.equal("table", type(p.data.settings.ai.profiles))
        assert.are.equal(5, p.data.schema_version)
        assert.are.equal(3, p.data.adaptive_by_grade.chinese["2"].level)
        assert.are.equal(1, p.data.adaptive_by_grade.math["2"].level)
    end)
end)

describe("KidLearn knowledge mastery", function()
    local DataStorage
    local Progress
    local path

    setup(function()
        require("commonrequire")
        package.path = "plugins/kidlearn.koplugin/?.lua;" .. package.path
        DataStorage = require("datastorage")
        Progress = require("core.progress")
    end)

    before_each(function()
        path = DataStorage:getDataDir() .. "/kidlearn_kp_progress_spec.lua"
        os.remove(path)
        os.remove(path .. ".old")
        os.remove(path .. ".pre-v5.bak")
    end)

    local function kp_question(id, topic)
        return {
            id = id,
            subject = "math",
            grade = 1,
            semester = "upper",
            unit = "u1",
            unit_name = "1到5各数的认识",
            type = "knowledge",
            skill = "数与代数",
            topic = topic,
            difficulty = 1,
            answer_mode = "number",
            answer_format = "integer",
            stem = "3 的后面一个数是几？",
            answer = 4,
            explain = "从 1 往后数，3 的后面是 4。",
        }
    end

    it("migrates a schema-3 save without knowledge data", function()
        local p = Progress.open(path)
        p.data.schema_version = 3
        p.data.knowledge = nil
        p:flush()
        local reopened = Progress.open(path)
        assert.are.equal(5, reopened.data.schema_version)
        assert.is_table(reopened.data.knowledge)
        assert.is_table(reopened.data.knowledge.math)
        assert.is_table(reopened.data.knowledge.chinese)
    end)

    it("normalizes malformed knowledge entries", function()
        local p = Progress.open(path)
        p.data.knowledge = {
            math = {
                bad = "not-a-table",
                cnm_p001 = { status = "bogus", attempts = "x", correct = 2 },
            },
        }
        p:flush()
        local reopened = Progress.open(path)
        assert.is_nil(reopened.data.knowledge.math.bad)
        local entry = reopened.data.knowledge.math.cnm_p001
        assert.are.equal("learning", entry.status)
        assert.are.equal(0, entry.attempts)
        assert.are.equal(2, entry.correct)
    end)

    it("counts first-try knowledge answers through record_answer", function()
        local p = Progress.open(path)
        p:record_answer(kp_question("cnm_p001_q1", "cnm_p001"), { attempt = 1, correct = true, now = os.time() })
        p:record_answer(kp_question("cnm_p001_q1", "cnm_p001"), { attempt = 2, correct = true, now = os.time() })
        local entry = p.data.knowledge.math.cnm_p001
        assert.are.equal(1, entry.attempts)
        assert.are.equal(1, entry.correct)
        assert.are.equal("learning", entry.status)
        assert.are.equal("learning", p:kp_status("math", "cnm_p001"))
        assert.is_nil(p:kp_status("math", "cnm_p999"))
    end)

    it("summarizes mastery across a topic list", function()
        local p = Progress.open(path)
        p:mark_kp_status("math", "a", "mastered")
        p:mark_kp_status("math", "b", "weak")
        p:mark_kp_status("math", "c", "learning")
        local counts = p:kp_summary("math", { "a", "b", "c", "d" })
        assert.are.equal(4, counts.total)
        assert.are.equal(1, counts.mastered)
        assert.are.equal(1, counts.weak)
        assert.are.equal(1, counts.learning)
        assert.are.equal(1, counts.unlearned)
    end)

    it("writes back single-topic practice results", function()
        local p = Progress.open(path)
        local statuses = p:finalize_kp_session("math", {
            { topic = "a", correct = true },
            { topic = "a", correct = true },
        }, true)
        assert.are.equal("mastered", statuses.a)
        statuses = p:finalize_kp_session("math", {
            { topic = "b", correct = false },
        }, true)
        assert.are.equal("weak", statuses.b)
        statuses = p:finalize_kp_session("math", {
            { topic = "c", correct = true },
            { topic = "c", correct = false },
        }, true)
        assert.are.equal("learning", statuses.c)
    end)

    it("needs two questions per topic in mixed sessions", function()
        local p = Progress.open(path)
        local statuses = p:finalize_kp_session("math", {
            { topic = "a", correct = true },
            { topic = "b", correct = false },
            { topic = "c", correct = true },
            { topic = "c", correct = true },
        }, false)
        assert.are.equal("learning", statuses.a) -- single correct does not promote
        assert.are.equal("weak", statuses.b)     -- single wrong is still weak
        assert.are.equal("mastered", statuses.c)
    end)

    it("snapshots topic and answer_format into the wrong book", function()
        local p = Progress.open(path)
        local q = kp_question("cnm_p079_q2", "cnm_p079")
        q.answer_mode = "number"
        q.answer_format = "fraction"
        q.answer = "1/4"
        p:record_wrong(q, os.time())
        local item = p.data.wrong["cnm_p079_q2"]
        assert.are.equal("cnm_p079", item.topic)
        assert.are.equal("fraction", item.answer_format)
        assert.are.equal("1/4", item.answer)
    end)

    it("clears knowledge on reset but keeps settings", function()
        local p = Progress.open(path)
        p.data.settings.grade = 5
        p:mark_kp_status("math", "cnm_p001", "mastered")
        p:reset_progress()
        assert.is_nil(p:kp_status("math", "cnm_p001"))
        assert.are.equal(5, p.data.settings.grade)
    end)
end)

describe("KidLearn v5 migration safety", function()
    local DataStorage
    local Progress
    local Badges
    local Cards
    local dump
    local path

    setup(function()
        require("commonrequire")
        package.path = "plugins/kidlearn.koplugin/?.lua;" .. package.path
        DataStorage = require("datastorage")
        Progress = require("core.progress")
        Badges = require("core.badges")
        Cards = require("core.cards")
        dump = require("dump")
    end)

    before_each(function()
        path = DataStorage:getDataDir() .. "/kidlearn_v5_migration_spec.lua"
        os.remove(path)
        os.remove(path .. ".old")
        os.remove(path .. ".pre-v5.bak")
    end)

    local function write_save(file_path, tbl)
        local f = assert(io.open(file_path, "wb"))
        f:write("-- fixture\nreturn " .. dump(tbl) .. "\n")
        f:close()
    end

    local function read_bytes(file_path)
        local f = io.open(file_path, "rb")
        if not f then return nil end
        local content = f:read("*a")
        f:close()
        return content
    end

    local function file_exists(file_path)
        local f = io.open(file_path, "rb")
        if f then f:close() return true end
        return false
    end

    local function v4_fixture()
        return {
            schema_version = 4,
            total = { points = 1234, answered = 200, correct = 150, sessions = 20,
                perfect_sessions = 3, best_combo = 12, wrong_cleared = 6 },
            by_subject = { chinese = { answered = 100, correct = 80 }, math = { answered = 100, correct = 70 } },
            streak = { current = 5, best = 9, last_day = "2026-11-10" },
            daily = { [os.date("%Y-%m-%d", os.time() - 86400)] = { answered = 12, correct = 10, points = 150, sessions = 2 } },
            wrong = { w1 = { id = "w1", subject = "math", stem = "1+1=?", answer = 2,
                added_at = 1, last_seen = 2, wrong_count = 1, mastery = 1 } },
            badges = {
                first_session = 1000, correct_20 = 1001, correct_100 = 1002,
                perfect_session = 1003, streak_3 = 1004, streak_7 = 1005,
                chinese_50 = 1006, math_50 = 1007, combo_10 = 1008, wrong_clear_5 = 1009,
                legacy_unknown = 1010,
            },
            adaptive = { chinese = { level = 2, attempts = 0, correct = 0 }, math = { level = 2, attempts = 0, correct = 0 } },
            adaptive_by_grade = {
                chinese = { ["2"] = { level = 3, attempts = 5, correct = 4 } },
                math = { ["2"] = { level = 2, attempts = 1, correct = 1 } },
            },
            settings = { province = "beijing", grade = 3, semester = "lower",
                chinese_edition = "tongbian", math_edition = "beishida",
                daily_goal = 15, retry = false, ai = { profiles = {} } },
            recent_ids = { "q1", "q2" },
            knowledge = {
                math = { cnm_p001 = { status = "mastered", attempts = 4, correct = 4, last_seen = 5 } },
                chinese = {},
            },
        }
    end

    it("migrates a v4 save without touching any existing data", function()
        local fixture = v4_fixture()
        write_save(path, fixture)
        local original = read_bytes(path)
        local p = Progress.open(path)
        assert.are.equal(5, p.data.schema_version)
        -- every pre-existing value survives byte-for-byte in meaning
        assert.are.equal(1234, p.data.total.points)
        assert.are.equal(200, p.data.total.answered)
        assert.are.equal(150, p.data.total.correct)
        assert.are.equal(20, p.data.total.sessions)
        assert.are.equal(3, p.data.total.perfect_sessions)
        assert.are.equal(12, p.data.total.best_combo)
        assert.are.equal(6, p.data.total.wrong_cleared)
        assert.are.equal(80, p.data.by_subject.chinese.correct)
        assert.are.equal(5, p.data.streak.current)
        assert.are.equal(9, p.data.streak.best)
        assert.are.equal("2026-11-10", p.data.streak.last_day)
        assert.are.equal(12, p.data.daily[os.date("%Y-%m-%d", os.time() - 86400)].answered)
        assert.are.equal("1+1=?", p.data.wrong.w1.stem)
        assert.are.equal(1000, p.data.badges.first_session)
        assert.are.equal(1009, p.data.badges.wrong_clear_5)
        assert.are.equal(1010, p.data.badges.legacy_unknown)
        assert.are.equal("beijing", p.data.settings.province)
        assert.are.equal(3, p.data.settings.grade)
        assert.are.equal("lower", p.data.settings.semester)
        assert.are.equal("beishida", p.data.settings.math_edition)
        assert.are.equal(15, p.data.settings.daily_goal)
        assert.are.equal(false, p.data.settings.retry)
        assert.are.equal(3, p.data.adaptive_by_grade.chinese["2"].level)
        assert.are.equal("mastered", p.data.knowledge.math.cnm_p001.status)
        assert.are.same({ "q1", "q2" }, p.data.recent_ids)
        -- new fields arrive as defaults only
        assert.are.equal(0, p.data.total.challenge_sessions)
        assert.are.equal(0, p.data.total.challenge_correct)
        assert.is_table(p.data.cards)
        assert.is_nil(next(p.data.cards))
        local daily = p.data.daily[os.date("%Y-%m-%d", os.time() - 86400)]
        assert.are.equal(0, daily.subjects.math.answered)
        assert.are.equal(0, daily.challenge.sessions)
        assert.are.equal(0, daily.kp_answered)
        assert.is_table(daily.modes)
        assert.is_table(daily.kp_topics)
        -- one-time snapshot is byte-identical to the pre-upgrade file
        assert.are.equal(original, read_bytes(path .. ".pre-v5.bak"))
        -- evaluating badges never re-locks or rewrites old unlocks
        Badges.evaluate(p)
        assert.are.equal(1000, p.data.badges.first_session)
        assert.are.equal(1010, p.data.badges.legacy_unknown)
        for _, id in ipairs({ "first_session", "correct_20", "correct_100", "perfect_session",
            "streak_3", "streak_7", "chinese_50", "math_50", "combo_10", "wrong_clear_5" }) do
            assert.is_not_nil(p.data.badges[id])
        end
    end)

    it("does not snapshot twice or drift on reopen", function()
        write_save(path, v4_fixture())
        local p = Progress.open(path)
        p:flush()
        local backup = read_bytes(path .. ".pre-v5.bak")
        local reopened = Progress.open(path)
        assert.are.equal(5, reopened.data.schema_version)
        assert.are.equal(backup, read_bytes(path .. ".pre-v5.bak"))
        assert.are.equal(1234, reopened.data.total.points)
        assert.are.equal(1010, reopened.data.badges.legacy_unknown)
        assert.are.equal("beijing", reopened.data.settings.province)
    end)

    it("skips the snapshot for a fresh install", function()
        local p = Progress.open(path)
        assert.is_false(file_exists(path .. ".pre-v5.bak"))
        p:record_answer({ id = "fresh", subject = "math", answer_mode = "number", answer = 2, stem = "1+1" },
            { attempt = 1, correct = true })
        assert.is_true(file_exists(path))
        assert.is_false(file_exists(path .. ".pre-v5.bak"))
    end)

    it("snapshots raw bytes when the main file is corrupted but .old is readable", function()
        write_save(path .. ".old", v4_fixture())
        local f = assert(io.open(path, "wb"))
        f:write("corrupted {{{")
        f:close()
        local p = Progress.open(path)
        assert.are.equal(5, p.data.schema_version)
        assert.are.equal(1234, p.data.total.points)
        assert.are.equal("corrupted {{{", read_bytes(path .. ".pre-v5.bak"))
    end)

    it("reset clears cards and challenge counters but keeps settings", function()
        local p = Progress.open(path)
        p:add_cards({ Cards.get("r01") }, 1000)
        p.data.total.challenge_sessions = 4
        p.data.settings.daily_goal = 15
        p:reset_progress()
        assert.is_nil(next(p.data.cards))
        assert.are.equal(0, p.data.total.challenge_sessions)
        assert.are.equal(0, p.data.total.challenge_correct)
        assert.are.equal(15, p.data.settings.daily_goal)
    end)

    it("records daily subject, challenge and knowledge detail on first try only", function()
        local p = Progress.open(path)
        local now = os.time({ year = 2026, month = 11, day = 10, hour = 12 })
        local cq = { id = "c1", subject = "math", challenge = true, answer_mode = "number", answer = 2, stem = "1+1" }
        p:record_answer(cq, { attempt = 1, correct = true, mode = "challenge", now = now })
        p:record_answer(cq, { attempt = 2, correct = true, mode = "challenge", now = now })
        local daily = p.data.daily["2026-11-10"]
        assert.are.equal(1, daily.subjects.math.answered)
        assert.are.equal(1, daily.subjects.math.correct)
        assert.are.equal(1, daily.challenge.answered)
        assert.are.equal(1, daily.challenge.correct)
        assert.are.equal(1, p.data.total.challenge_correct)
        local kq = { id = "k1", subject = "math", topic = "cnm_p001", answer_mode = "number", answer = 2, stem = "1+1" }
        p:record_answer(kq, { attempt = 1, correct = true, mode = "kp", now = now })
        p:record_answer(kq, { attempt = 1, correct = false, mode = "kp", now = now })
        assert.are.equal(2, daily.kp_answered)
        assert.are.equal(1, #daily.kp_topics)
        assert.are.equal("cnm_p001", daily.kp_topics[1].topic)
    end)

    it("caps the daily knowledge topic list at 20 unique entries", function()
        local p = Progress.open(path)
        local now = os.time({ year = 2026, month = 11, day = 10, hour = 12 })
        for i = 1, 25 do
            p:record_answer({ id = "t" .. i, subject = "math", topic = "topic_" .. i,
                answer_mode = "number", answer = 2, stem = "1+1" },
                { attempt = 1, correct = true, mode = "kp", now = now })
        end
        assert.are.equal(20, #p.data.daily["2026-11-10"].kp_topics)
    end)

    it("counts session modes but never counts review rounds", function()
        local p = Progress.open(path)
        local now = os.time({ year = 2026, month = 11, day = 10, hour = 12 })
        p:record_session({ mode = "challenge", perfect = false }, now)
        p:record_session({ mode = "daily", perfect = false }, now)
        p:record_session({ mode = "review", perfect = true }, now)
        local daily = p.data.daily["2026-11-10"]
        assert.are.equal(1, daily.modes.challenge)
        assert.are.equal(1, daily.modes.daily)
        assert.is_nil(daily.modes.review)
        assert.are.equal(1, p.data.total.challenge_sessions)
        assert.are.equal(1, daily.challenge.sessions)
    end)

    it("stores and reloads the daily report inside the daily entry", function()
        local p = Progress.open(path)
        local now = os.time({ year = 2026, month = 11, day = 10, hour = 12 })
        assert.is_nil(p:daily_report(now))
        p:save_daily_report({ score = 66, revealed = false, cards = {} }, now)
        local reopened = Progress.open(path)
        local report = reopened:daily_report(now)
        assert.are.equal(66, report.score)
        assert.is_false(report.revealed)
    end)
end)
