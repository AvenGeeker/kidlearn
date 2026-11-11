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
        assert.are.equal(4, p.data.schema_version)
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
        assert.are.equal(4, reopened.data.schema_version)
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
