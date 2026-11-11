describe("KidLearn knowledge bank", function()
    local Knowledge
    local plugin_path = "./plugins/kidlearn.koplugin"

    setup(function()
        require("commonrequire")
        package.path = "plugins/kidlearn.koplugin/?.lua;" .. package.path
        Knowledge = require("core.knowledge")
    end)

    before_each(function()
        Knowledge.clear_cache()
    end)

    it("loads a math volume with topics and normalized questions", function()
        local volume, err = Knowledge.load(plugin_path, "math", 1, "upper")
        assert.is_nil(err)
        assert.are.equal(26, #volume.topics)
        assert.are.equal(101, #volume.questions)
        assert.are.equal(4, #volume.by_topic["cnm_p001"])
        for _, q in ipairs(volume.questions) do
            assert.is_string(q.topic)
            assert.is_string(q.stem)
            assert.is_string(q.explain)
            assert.is_true(q.difficulty >= 1 and q.difficulty <= 3)
            if q.answer_mode == "choice" then
                assert.is_true(#q.options >= 3 and #q.options <= 4)
                assert.is_true(q.answer >= 1 and q.answer <= #q.options)
            else
                assert.is_not_nil(q.answer_format)
            end
        end
    end)

    it("loads a Chinese volume where every question is a 4-option choice", function()
        local volume, err = Knowledge.load(plugin_path, "chinese", 1, "upper")
        assert.is_nil(err)
        assert.are.equal(41, #volume.topics)
        assert.are.equal(164, #volume.questions)
        for _, q in ipairs(volume.questions) do
            assert.are.equal("choice", q.answer_mode)
            assert.are.equal(4, #q.options)
        end
    end)

    it("applies the e-ink exclusions but keeps every topic playable", function()
        assert.are.equal(1, #Knowledge.questions_for(plugin_path, "math", "cnm_p014"))
        assert.are.equal(2, #Knowledge.questions_for(plugin_path, "math", "cnm_p023"))
        assert.are.equal(4, #Knowledge.questions_for(plugin_path, "math", "cnm_p001"))
        assert.are.equal(0, #Knowledge.questions_for(plugin_path, "math", "cnm_p999"))
    end)

    it("exposes topic metadata for the learning card", function()
        local topic = Knowledge.topic(plugin_path, "math", "cnm_p001")
        assert.is_not_nil(topic)
        assert.are.equal("1到5各数的认识", topic.name)
        assert.is_string(topic.description)
        assert.is_true(#topic.mastery_criteria >= 2)
        assert.is_string(topic.example.question)
        assert.is_not_nil(topic.example.answer)
    end)

    it("loads the prerequisite graph hard-first and deterministically", function()
        local graph, err = Knowledge.graph(plugin_path, "math")
        assert.is_nil(err)
        assert.are.equal(284, #graph.order)
        assert.are.equal(459, #graph.edges)
        assert.are.equal(0, #graph.prereqs["cnm_p001"])
        assert.is_true(#graph.dependents["cnm_p001"] > 0)
        for _, list in pairs(graph.prereqs) do
            local seen_soft = false
            for _, p in ipairs(list) do
                if p.strength == "soft" then seen_soft = true end
                if p.strength == "hard" then assert.is_false(seen_soft) end
            end
        end
        local chinese = Knowledge.graph(plugin_path, "chinese")
        assert.are.equal(494, #chinese.order)
        assert.are.equal(656, #chinese.edges)
    end)

    it("caches volumes and graphs until cleared", function()
        local a = Knowledge.load(plugin_path, "math", 1, "upper")
        local b = Knowledge.load(plugin_path, "math", 1, "upper")
        assert.are.equal(a, b)
        Knowledge.clear_cache()
        local c = Knowledge.load(plugin_path, "math", 1, "upper")
        assert.are_not.equal(a, c)
    end)

    it("judges choice, integer, decimal and fraction answers", function()
        local choice = { answer_mode = "choice", answer = 2, options = { "a", "b", "c" } }
        assert.is_true(Knowledge.judge(choice, 2))
        assert.is_false(Knowledge.judge(choice, 1))

        local integer = { answer_mode = "number", answer_format = "integer", answer = 1000000 }
        assert.is_true(Knowledge.judge(integer, "1000000"))
        assert.is_false(Knowledge.judge(integer, 999999))

        local decimal = { answer_mode = "number", answer_format = "decimal", answer = 0.3 }
        assert.is_true(Knowledge.judge(decimal, "0.3"))
        assert.is_false(Knowledge.judge(decimal, "0.4"))

        local fraction = { answer_mode = "number", answer_format = "fraction", answer = "1/4" }
        assert.is_true(Knowledge.judge(fraction, "1/4"))
        assert.is_true(Knowledge.judge(fraction, "2/8"))
        assert.is_true(Knowledge.judge(fraction, "0.25"))
        assert.is_false(Knowledge.judge(fraction, "1/2"))
        assert.is_false(Knowledge.judge(fraction, "abc"))
        assert.is_false(Knowledge.judge(fraction, "1/0"))
    end)

    it("judges real synced fraction and decimal questions", function()
        local frac = Knowledge.questions_for(plugin_path, "math", "cnm_p079")
        local found_frac = false
        for _, q in ipairs(frac) do
            if q.answer_format == "fraction" then
                found_frac = true
                assert.is_true(Knowledge.judge(q, q.answer))
            end
        end
        assert.is_true(found_frac)
        local dec = Knowledge.questions_for(plugin_path, "math", "cnm_p093")
        local found_dec = false
        for _, q in ipairs(dec) do
            if q.answer_format == "decimal" then
                found_dec = true
                assert.is_true(Knowledge.judge(q, tostring(q.answer)))
            end
        end
        assert.is_true(found_dec)
    end)

    it("rejects malformed questions at load time", function()
        local base = {
            id = "x_q1", topic = "x", stem = "1+1?", explain = "2",
            difficulty = 1, answer_mode = "choice",
            options = { "1", "2", "3" }, answer = 2,
        }
        assert.is_not_nil(Knowledge.normalize_question(base))
        local function bad(mutate)
            local q = {}
            for k, v in pairs(base) do q[k] = v end
            mutate(q)
            assert.is_nil(Knowledge.normalize_question(q))
        end
        bad(function(q) q.stem = "" end)
        bad(function(q) q.options = { "1", "2" } end)
        bad(function(q) q.options = { "1", "2", "3", "4", "5" } end)
        bad(function(q) q.options = { "1", "1", "2" } end)
        bad(function(q) q.answer = 4 end)
        bad(function(q)
            q.answer_mode = "number"
            q.answer_format = "integer"
            q.answer = -1
        end)
        bad(function(q)
            q.answer_mode = "number"
            q.answer_format = "fraction"
            q.answer = "1/0"
        end)
    end)
end)
