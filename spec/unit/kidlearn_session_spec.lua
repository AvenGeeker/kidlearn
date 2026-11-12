describe("KidLearn session", function()
    local DataStorage
    local Progress
    local Session
    local path

    setup(function()
        require("commonrequire")
        package.path = "plugins/kidlearn.koplugin/?.lua;" .. package.path
        DataStorage = require("datastorage")
        Progress = require("core.progress")
        Session = require("core.session")
    end)

    it("runs a perfect ten-question math session", function()
        path = DataStorage:getDataDir() .. "/kidlearn_session_spec.lua"
        os.remove(path)
        os.remove(path .. ".old")
        local progress = Progress.open(path)
        progress.data.settings.semester = "upper"
        local session, err = Session.new({
            mode = "subject",
            subject = "math",
            unit = "all",
            semester = "upper",
            plugin_path = "./plugins/kidlearn.koplugin",
            progress = progress,
            rng = math.random,
            now_fn = function() return os.time({ year = 2026, month = 11, day = 10, hour = 12 }) end,
        })
        assert.is_nil(err)
        assert.are.equal(10, session:total())
        for i = 1, 10 do
            local q = session:current()
            local result = session:submit(q.answer)
            assert.is_true(result.correct)
            if i < 10 then assert.is_true(session:advance()) end
        end
        assert.is_false(session:advance())
        local summary = session:finish()
        assert.are.equal(10, summary.correct)
        assert.is_true(summary.perfect)
        assert.is_true(summary.points >= 150)
        assert.are.equal(1, progress.data.total.perfect_sessions)
    end)

    it("runs a ten-question challenge session", function()
        local challenge_path = DataStorage:getDataDir() .. "/kidlearn_challenge_spec.lua"
        os.remove(challenge_path)
        os.remove(challenge_path .. ".old")
        local progress = Progress.open(challenge_path)
        progress.data.settings.semester = "upper"
        local session, err = Session.new({
            mode = "challenge",
            subject = "math",
            semester = "upper",
            plugin_path = "./plugins/kidlearn.koplugin",
            progress = progress,
            rng = math.random,
            now_fn = function() return os.time({ year = 2026, month = 11, day = 10, hour = 12 }) end,
        })
        assert.is_nil(err)
        assert.are.equal(10, session:total())
        local seen = {}
        for i = 1, 10 do
            local q = session:current()
            assert.is_true(q.challenge)
            assert.is_string(q.challenge_id)
            assert.is_nil(seen[q.challenge_id])
            seen[q.challenge_id] = true
            local result = session:submit(q.answer)
            assert.is_true(result.correct)
            if i < 10 then assert.is_true(session:advance()) end
        end
        assert.is_false(session:advance())
        local summary = session:finish()
        assert.is_true(summary.perfect)
    end)

    it("counts challenge rounds and first-try correct answers", function()
        local count_path = DataStorage:getDataDir() .. "/kidlearn_challenge_count_spec.lua"
        os.remove(count_path)
        os.remove(count_path .. ".old")
        os.remove(count_path .. ".pre-v5.bak")
        local progress = Progress.open(count_path)
        progress.data.settings.semester = "upper"
        local session = assert(Session.new({
            mode = "challenge",
            subject = "math",
            semester = "upper",
            plugin_path = "./plugins/kidlearn.koplugin",
            progress = progress,
            rng = math.random,
            now_fn = function() return os.time({ year = 2026, month = 11, day = 10, hour = 12 }) end,
        }))
        for i = 1, 10 do
            local q = session:current()
            assert.is_true(session:submit(q.answer).correct)
            if i < 10 then assert.is_true(session:advance()) end
        end
        session:finish()
        assert.are.equal(1, progress.data.total.challenge_sessions)
        assert.are.equal(10, progress.data.total.challenge_correct)
        local daily = progress.data.daily["2026-11-10"]
        assert.are.equal(1, daily.challenge.sessions)
        assert.are.equal(10, daily.challenge.correct)
        assert.are.equal(10, daily.challenge.answered)
        assert.are.equal(1, daily.modes.challenge)
        os.remove(count_path)
        os.remove(count_path .. ".old")
        os.remove(count_path .. ".pre-v5.bak")
    end)

    it("uses the selected grade and Chinese textbook", function()
        local grade_path = DataStorage:getDataDir() .. "/kidlearn_grade_chinese_spec.lua"
        os.remove(grade_path)
        os.remove(grade_path .. ".old")
        local progress = Progress.open(grade_path)
        progress.data.settings.grade = 6
        progress.data.settings.semester = "lower"
        local session, err = Session.new({
            mode = "subject", subject = "chinese", unit = "all",
            plugin_path = "./plugins/kidlearn.koplugin", progress = progress,
            rng = math.random,
        })
        assert.is_nil(err)
        for i = 1, session:total() do
            local q = session:current()
            assert.are.equal(6, q.grade)
            assert.are.equal("tongbian", q.edition)
            assert.are.equal("lower", q.semester)
            session:submit(q.answer)
            if i < session:total() then session:advance() end
        end
    end)

    it("uses the selected grade and math textbook", function()
        local grade_path = DataStorage:getDataDir() .. "/kidlearn_grade_math_spec.lua"
        os.remove(grade_path)
        os.remove(grade_path .. ".old")
        local progress = Progress.open(grade_path)
        progress.data.settings.grade = 5
        progress.data.settings.math_edition = "sujiao"
        local session, err = Session.new({
            mode = "subject", subject = "math", unit = "all",
            plugin_path = "./plugins/kidlearn.koplugin", progress = progress,
            rng = math.random,
        })
        assert.is_nil(err)
        for i = 1, session:total() do
            local q = session:current()
            assert.are.equal(5, q.grade)
            assert.are.equal("sujiao", q.edition)
            session:submit(q.answer)
            if i < session:total() then session:advance() end
        end
    end)

    it("keeps generated ids unique across grades", function()
        local seen = {}
        for _, grade in ipairs({ 1, 6 }) do
            local grade_path = DataStorage:getDataDir() .. "/kidlearn_cross_grade_" .. grade .. ".lua"
            os.remove(grade_path)
            os.remove(grade_path .. ".old")
            local progress = Progress.open(grade_path)
            progress.data.settings.grade = grade
            local session = Session.new({
                mode = "subject", subject = "math", unit = "all",
                plugin_path = "./plugins/kidlearn.koplugin", progress = progress,
                rng = math.random,
            })
            assert.is_not_nil(session)
            for _, q in ipairs(session.questions) do
                assert.is_nil(seen[q.id])
                seen[q.id] = true
            end
        end
    end)

    it("builds a daily challenge for the selected grade", function()
        local grade_path = DataStorage:getDataDir() .. "/kidlearn_daily_grade_spec.lua"
        os.remove(grade_path)
        os.remove(grade_path .. ".old")
        local progress = Progress.open(grade_path)
        progress.data.settings.grade = 3
        progress.data.settings.math_edition = "beishida"
        local session, err = Session.new({
            mode = "daily",
            plugin_path = "./plugins/kidlearn.koplugin",
            progress = progress,
            rng = math.random,
        })
        assert.is_nil(err)
        assert.are.equal(10, session:total())
        local subjects = {}
        for _, q in ipairs(session.questions) do
            subjects[q.subject] = true
            assert.are.equal(3, q.grade)
        end
        assert.is_true(subjects.chinese)
        assert.is_true(subjects.math)
    end)

    it("runs a grade-six challenge session with a selected edition", function()
        local grade_path = DataStorage:getDataDir() .. "/kidlearn_grade_challenge_spec.lua"
        os.remove(grade_path)
        os.remove(grade_path .. ".old")
        local progress = Progress.open(grade_path)
        progress.data.settings.grade = 6
        progress.data.settings.math_edition = "hujiao"
        local session, err = Session.new({
            mode = "challenge", subject = "math",
            plugin_path = "./plugins/kidlearn.koplugin", progress = progress,
            rng = math.random,
        })
        assert.is_nil(err)
        for i = 1, session:total() do
            local q = session:current()
            assert.is_true(q.challenge)
            assert.are.equal(6, q.grade)
            assert.are.equal("hujiao", q.edition)
            local result = session:submit(q.answer)
            assert.is_true(result.correct)
            if i < session:total() then session:advance() end
        end
    end)
end)

describe("KidLearn knowledge-point session", function()
    local DataStorage
    local Progress
    local Session
    local Knowledge
    local path
    local plugin_path = "./plugins/kidlearn.koplugin"

    setup(function()
        require("commonrequire")
        package.path = "plugins/kidlearn.koplugin/?.lua;" .. package.path
        DataStorage = require("datastorage")
        Progress = require("core.progress")
        Session = require("core.session")
        Knowledge = require("core.knowledge")
    end)

    before_each(function()
        path = DataStorage:getDataDir() .. "/kidlearn_kp_session_spec.lua"
        os.remove(path)
        os.remove(path .. ".old")
    end)

    local function now_fn()
        return os.time({ year = 2026, month = 11, day = 10, hour = 12 })
    end

    local function fraction_question(id, topic)
        return {
            id = id,
            topic = topic,
            subject = "math",
            grade = 3,
            semester = "upper",
            unit = "u1",
            unit_name = "分数的初步认识",
            type = "knowledge",
            skill = "数与代数",
            difficulty = 1,
            answer_mode = "number",
            answer_format = "fraction",
            stem = "把一个整体平均分成 2 份，每份是多少？",
            answer = "1/2",
            explain = "平均分成 2 份，每份是 1/2。",
        }
    end

    it("runs a single-topic practice session and promotes mastery", function()
        local progress = Progress.open(path)
        local questions = Knowledge.questions_for(plugin_path, "math", "cnm_p001")
        assert.are.equal(4, #questions)
        local session, err = Session.new({
            mode = "kp",
            subject = "math",
            kp_topic = "cnm_p001",
            kp_questions = questions,
            plugin_path = plugin_path,
            progress = progress,
            rng = math.random,
            now_fn = now_fn,
        })
        assert.is_nil(err)
        assert.are.equal(4, session:total())
        for i = 1, 4 do
            local q = session:current()
            assert.is_true(session:submit(q.answer).correct)
            if i < 4 then assert.is_true(session:advance()) end
        end
        local summary = session:finish()
        assert.are.equal("kp", summary.mode)
        assert.are.equal("mastered", summary.kp_statuses["cnm_p001"])
        assert.are.equal("mastered", progress:kp_status("math", "cnm_p001"))
    end)

    it("rejects an empty knowledge session", function()
        local progress = Progress.open(path)
        local session, err = Session.new({
            mode = "kp", subject = "math", kp_questions = {},
            plugin_path = plugin_path, progress = progress,
        })
        assert.is_nil(session)
        assert.is_string(err)
    end)

    it("judges fraction answers through the knowledge judge", function()
        local progress = Progress.open(path)
        local session = Session.new({
            mode = "kp",
            subject = "math",
            kp_topic = "t",
            kp_questions = { fraction_question("t_q1", "t") },
            plugin_path = plugin_path,
            progress = progress,
            now_fn = now_fn,
        })
        assert.is_true(session:submit("0.5").correct)
        local summary = session:finish()
        assert.are.equal("mastered", summary.kp_statuses["t"])

        local other = Session.new({
            mode = "kp",
            subject = "math",
            kp_topic = "t2",
            kp_questions = { fraction_question("t2_q1", "t2") },
            plugin_path = plugin_path,
            progress = progress,
            now_fn = now_fn,
        })
        assert.is_false(other:submit("1/3").correct)
    end)

    it("reviews a fraction wrong-book snapshot with the knowledge judge", function()
        local progress = Progress.open(path)
        local q = fraction_question("cnm_p079_q2", "cnm_p079")
        progress:record_wrong(q, now_fn())
        local session = Session.new({
            mode = "wrong",
            wrong_items = progress:wrong_items(),
            plugin_path = plugin_path,
            progress = progress,
            now_fn = now_fn,
        })
        assert.are.equal(1, session:total())
        assert.is_true(session:submit("1/2").correct)
    end)

    it("writes back per-topic status for mixed knowledge sessions", function()
        local progress = Progress.open(path)
        local a1 = fraction_question("a_q1", "a")
        local a2 = fraction_question("a_q2", "a")
        local b1 = fraction_question("b_q1", "b")
        local session = Session.new({
            mode = "kp",
            subject = "math",
            kp_questions = { a1, a2, b1 },
            plugin_path = plugin_path,
            progress = progress,
            now_fn = now_fn,
        })
        assert.is_true(session:submit("1/2").correct)
        session:advance()
        assert.is_true(session:submit("0.5").correct)
        session:advance()
        assert.is_true(session:submit("1/2").correct)
        local summary = session:finish()
        assert.are.equal("mastered", summary.kp_statuses["a"])
        assert.are.equal("learning", summary.kp_statuses["b"]) -- single question, no promotion
    end)
end)
