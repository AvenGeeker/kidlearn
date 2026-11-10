describe("KidLearn Chinese bank", function()
    local Bank
    local plugin_path = "./plugins/kidlearn.koplugin"

    setup(function()
        require("commonrequire")
        package.path = "plugins/kidlearn.koplugin/?.lua;" .. package.path
        Bank = require("core.bank")
    end)

    it("loads both semesters with complete unit coverage", function()
        for _, semester in ipairs({ "upper", "lower" }) do
            local bank, err = Bank.load(plugin_path, "chinese", semester)
            assert.is_nil(err)
            assert.are.equal(160, #bank.questions)
            assert.are.equal(8, #bank.units)
            for _, unit in ipairs(bank.units) do
                assert.are.equal(20, #(bank.by_unit[unit.id] or {}))
            end
        end
    end)

    it("picks a question from the requested unit and difficulty", function()
        local bank = Bank.load(plugin_path, "chinese", "upper")
        local q = Bank.pick(bank, {
            unit = "u1",
            difficulty = 1,
            recent_ids = {},
            rng = function() return 1 end,
        })
        assert.are.equal("u1", q.unit)
        assert.are.equal(1, q.difficulty)
        assert.are.equal(4, #q.options)
    end)

    it("has no duplicate ids across both semesters", function()
        local seen = {}
        for _, semester in ipairs({ "upper", "lower" }) do
            local bank = Bank.load(plugin_path, "chinese", semester)
            for _, q in ipairs(bank.questions) do
                assert.is_nil(seen[q.id])
                seen[q.id] = true
            end
        end
    end)

    it("loads a bank by grade and textbook edition", function()
        local bank, err = Bank.load(plugin_path, "chinese", 6, "lower", "tongbian")
        assert.is_nil(err)
        assert.are.equal(6, bank.grade)
        assert.are.equal("tongbian", bank.edition)
        assert.are.equal(6, #bank.units)
        assert.are.equal(120, #bank.questions)
        for _, unit in ipairs(bank.units) do
            assert.are.equal(20, #(bank.by_unit[unit.id] or {}))
        end
    end)

    it("keeps every unit equipped with a reading passage", function()
        local bank = Bank.load(plugin_path, "chinese", 3, "upper", "tongbian")
        for _, unit in ipairs(bank.units) do
            local readings = 0
            for _, q in ipairs(bank.by_unit[unit.id]) do
                if q.type == "reading" then
                    readings = readings + 1
                    assert.is_string(q.passage)
                end
            end
            assert.are.equal(2, readings)
        end
    end)
end)
