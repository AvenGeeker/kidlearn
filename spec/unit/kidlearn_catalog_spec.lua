describe("KidLearn textbook catalog", function()
    local Catalog
    local Bank
    local MathGen
    local plugin_path = "./plugins/kidlearn.koplugin"

    setup(function()
        require("commonrequire")
        package.path = "plugins/kidlearn.koplugin/?.lua;" .. package.path
        Catalog = require("core.catalog")
        Bank = require("core.bank")
        MathGen = require("core.mathgen")
        MathGen.set_plugin_path(plugin_path)
    end)

    it("has all provinces, grades and editions", function()
        local provinces = Catalog.provinces(plugin_path)
        assert.is_true(#provinces >= 32)
        local ids = {}
        for _, province in ipairs(provinces) do
            assert.is_nil(ids[province.id])
            ids[province.id] = true
        end
        assert.are.equal(6, #Catalog.grades(plugin_path))
        assert.are.equal(1, #Catalog.editions(plugin_path, "chinese"))
        assert.are.equal(5, #Catalog.editions(plugin_path, "math"))
    end)

    it("maps provinces to a recommended math edition", function()
        assert.are.equal("sujiao", Catalog.recommended_math(plugin_path, "jiangsu"))
        assert.are.equal("qingdao", Catalog.recommended_math(plugin_path, "shandong"))
        assert.are.equal("hujiao", Catalog.recommended_math(plugin_path, "shanghai"))
        assert.are.equal("renjiao", Catalog.recommended_math(plugin_path, "beijing"))
        assert.are.equal("renjiao", Catalog.recommended_math(plugin_path, "other"))
    end)

    it("has non-empty math units for every edition, grade and semester", function()
        for _, edition in ipairs(Catalog.editions(plugin_path, "math")) do
            for _, grade in ipairs(Catalog.grades(plugin_path)) do
                for _, semester in ipairs({ "upper", "lower" }) do
                    local units = Catalog.units(plugin_path, "math", edition.id, grade, semester)
                    assert.is_table(units, edition.id .. " g" .. grade .. " " .. semester)
                    assert.is_true(#units > 0)
                    local seen = {}
                    for _, unit in ipairs(units) do
                        assert.is_nil(seen[unit.id])
                        seen[unit.id] = true
                        assert.is_string(unit.name)
                        assert.is_table(unit.skills)
                        assert.is_true(#unit.skills > 0)
                    end
                end
            end
        end
    end)

    it("loads every Chinese semester bank with complete unit coverage", function()
        local seen_ids = {}
        for _, grade in ipairs(Catalog.grades(plugin_path)) do
            for _, semester in ipairs({ "upper", "lower" }) do
                local bank, err = Bank.load(plugin_path, "chinese", grade, semester, "tongbian")
                assert.is_nil(err)
                assert.are.equal(grade, bank.grade)
                assert.are.equal("tongbian", bank.edition)
                for _, unit in ipairs(bank.units) do
                    assert.are.equal(20, #(bank.by_unit[unit.id] or {}))
                end
                for _, q in ipairs(bank.questions) do
                    assert.is_nil(seen_ids[q.id])
                    seen_ids[q.id] = true
                    assert.is_string(q.unit_name)
                    if q.type == "reading" then
                        assert.is_string(q.passage)
                        assert.is_true(#q.passage > 10)
                    end
                end
            end
        end
    end)

    it("generates a valid question for every catalog skill", function()
        local seen = {}
        for _, edition in ipairs(Catalog.editions(plugin_path, "math")) do
            for _, grade in ipairs(Catalog.grades(plugin_path)) do
                for _, semester in ipairs({ "upper", "lower" }) do
                    for _, unit in ipairs(Catalog.units(plugin_path, "math", edition.id, grade, semester)) do
                        for _, skill in ipairs(unit.skills) do
                            if not seen[skill] then
                                seen[skill] = true
                                local q = MathGen.skill_question(skill, {
                                    grade = grade,
                                    edition = edition.id,
                                    semester = semester,
                                    unit = unit.id,
                                    difficulty = (grade % 3) + 1,
                                }, math.random)
                                assert.is_table(q)
                                assert.are.equal(grade, q.grade)
                                assert.are.equal(edition.id, q.edition)
                                assert.is_string(q.stem)
                                assert.is_string(q.explain)
                                if q.answer_mode == "choice" then
                                    assert.are.equal(4, #q.options)
                                    assert.is_true(q.answer >= 1 and q.answer <= 4)
                                else
                                    assert.is_number(q.answer)
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end)
