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
