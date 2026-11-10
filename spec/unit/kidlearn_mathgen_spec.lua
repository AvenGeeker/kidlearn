describe("KidLearn math generator", function()
    local MathGen
    local Catalog

    setup(function()
        require("commonrequire")
        package.path = "plugins/kidlearn.koplugin/?.lua;" .. package.path
        MathGen = require("core.mathgen")
        Catalog = require("core.catalog")
        MathGen.set_plugin_path("./plugins/kidlearn.koplugin")
    end)

    local function rng(n)
        return math.random(n)
    end

    it("generates valid questions for every unit and difficulty", function()
        for _, semester in ipairs({ "upper", "lower" }) do
            for _, unit in ipairs(MathGen.units(semester)) do
                for difficulty = 1, 3 do
                    for _ = 1, 200 do
                        local q = MathGen.generate({
                            semester = semester,
                            unit = unit.id,
                            difficulty = difficulty,
                        }, rng)
                        assert.is_table(q)
                        assert.is_string(q.id)
                        assert.is_string(q.stem)
                        assert.is_string(q.explain)
                        assert.is_true(q.difficulty >= 1 and q.difficulty <= 3)
                        if q.answer_mode == "choice" then
                            assert.are.equal(4, #q.options)
                            assert.is_true(q.answer >= 1 and q.answer <= 4)
                            local seen = {}
                            for _, option in ipairs(q.options) do
                                assert.is_nil(seen[option])
                                seen[option] = true
                            end
                        else
                            assert.are.equal("number", q.answer_mode)
                            assert.is_number(q.answer)
                        end
                    end
                end
            end
        end
    end)

    it("generates challenge questions with curriculum competencies", function()
        for _, semester in ipairs({ "upper", "lower" }) do
            local valid_units = {}
            for _, unit in ipairs(MathGen.units(semester)) do valid_units[unit.id] = true end
            for _ = 1, 500 do
                local q = MathGen.generate_challenge({ semester = semester }, rng)
                assert.is_true(q.challenge)
                assert.are.equal("challenge", q.skill)
                assert.are.equal("math_challenge", q.type)
                assert.is_string(q.competency)
                assert.is_true(valid_units[q.unit])
                if q.answer_mode == "choice" then
                    assert.are.equal(4, #q.options)
                    assert.is_true(q.answer >= 1 and q.answer <= 4)
                else
                    assert.is_number(q.answer)
                    assert.is_true(q.answer >= 0)
                end
            end
        end
    end)

    it("builds a challenge round without repeating types", function()
        for _, semester in ipairs({ "upper", "lower" }) do
            for _ = 1, 50 do
                local plan = MathGen.challenge_plan({ semester = semester, count = 10 }, rng)
                assert.are.equal(10, #plan)
                local seen = {}
                for _, id in ipairs(plan) do
                    assert.is_nil(seen[id])
                    seen[id] = true
                end
            end
        end
    end)

    it("generates the challenge type requested by id", function()
        local q = MathGen.generate_challenge({ semester = "upper", id = "chicken_rabbit" }, rng)
        assert.are.equal("chicken_rabbit", q.challenge_id)
        assert.is_truthy(q.stem:find("鸡和兔", 1, true))
    end)

    it("includes the classic chicken-and-rabbit reasoning problem", function()
        local q = MathGen.generate_challenge({ semester = "upper", index = 1 }, rng)
        assert.is_truthy(q.stem:find("鸡和兔", 1, true))
        assert.are.equal("推理意识", q.competency)
        assert.is_number(q.answer)
    end)

    it("never produces negative arithmetic answers", function()
        for _ = 1, 2000 do
            local q = MathGen.generate({ semester = "upper", unit = "m2", difficulty = 3 }, rng)
            if q.answer_mode == "number" then
                assert.is_true(q.answer >= 0)
            end
        end
    end)

    it("generates valid questions for every edition, grade and unit", function()
        local plugin_path = "./plugins/kidlearn.koplugin"
        for _, edition in ipairs(Catalog.editions(plugin_path, "math")) do
            for _, grade in ipairs(Catalog.grades(plugin_path)) do
                for _, semester in ipairs({ "upper", "lower" }) do
                    for _, unit in ipairs(Catalog.units(plugin_path, "math", edition.id, grade, semester)) do
                        for difficulty = 1, 3 do
                            for _ = 1, 5 do
                                local q = MathGen.generate({
                                    grade = grade,
                                    edition = edition.id,
                                    semester = semester,
                                    unit = unit.id,
                                    difficulty = difficulty,
                                }, rng)
                                assert.is_table(q)
                                assert.are.equal(grade, q.grade)
                                assert.are.equal(edition.id, q.edition)
                                assert.are.equal(semester, q.semester)
                                assert.are.equal(unit.id, q.unit)
                                assert.is_string(q.unit_name)
                                assert.is_number(q.difficulty)
                                if q.answer_mode == "choice" then
                                    assert.are.equal(4, #q.options)
                                    assert.is_true(q.answer >= 1 and q.answer <= 4)
                                else
                                    assert.is_number(q.answer)
                                    assert.is_true(q.answer >= 0)
                                end
                            end
                        end
                    end
                end
            end
        end
    end)

    it("tags challenge questions with the selected grade and edition", function()
        local q = MathGen.generate_challenge({
            grade = 6, edition = "sujiao", semester = "upper", unit = "all",
        }, rng)
        assert.are.equal(6, q.grade)
        assert.are.equal("sujiao", q.edition)
        assert.is_string(q.unit_name)
        local found = false
        for _, unit in ipairs(Catalog.units("./plugins/kidlearn.koplugin", "math", "sujiao", 6, "upper")) do
            if unit.id == q.unit then found = true end
        end
        assert.is_true(found)
    end)
end)
