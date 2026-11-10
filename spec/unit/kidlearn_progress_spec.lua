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
        assert.are.equal(3, p.data.schema_version)
        assert.are.equal(3, p.data.adaptive_by_grade.chinese["2"].level)
        assert.are.equal(1, p.data.adaptive_by_grade.math["2"].level)
    end)
end)
