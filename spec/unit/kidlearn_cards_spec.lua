describe("KidLearn cards and daily report", function()
    local DataStorage
    local Progress
    local Badges
    local Cards
    local Report
    local path

    setup(function()
        require("commonrequire")
        package.path = "plugins/kidlearn.koplugin/?.lua;" .. package.path
        DataStorage = require("datastorage")
        Progress = require("core.progress")
        Badges = require("core.badges")
        Cards = require("core.cards")
        Report = require("core.report")
    end)

    before_each(function()
        path = DataStorage:getDataDir() .. "/kidlearn_cards_spec.lua"
        os.remove(path)
        os.remove(path .. ".old")
        os.remove(path .. ".pre-v5.bak")
    end)

    local function day(day_number)
        return os.time({ year = 2026, month = 11, day = day_number, hour = 12 })
    end

    local function question(id)
        return {
            id = id or "q",
            subject = "math",
            semester = "upper",
            unit = "m2",
            type = "math_number",
            skill = "add_sub",
            difficulty = 1,
            answer_mode = "number",
            stem = "1 + 1 = ?",
            answer = 2,
            explain = "1 + 1 = 2。",
        }
    end

    it("has a fixed pool of 38 unique cards with the planned tier counts", function()
        local pool = Cards.all()
        assert.are.equal(38, #pool)
        local counts = { R = 0, RR = 0, S = 0, SS = 0, SSS = 0 }
        local seen = {}
        for _, card in ipairs(pool) do
            assert.is_nil(seen[card.id])
            seen[card.id] = true
            counts[card.tier] = counts[card.tier] + 1
            assert.is_true(#card.name > 0)
            assert.is_true(#card.desc > 0)
        end
        assert.are.equal(12, counts.R)
        assert.are.equal(10, counts.RR)
        assert.are.equal(8, counts.S)
        assert.are.equal(5, counts.SS)
        assert.are.equal(3, counts.SSS)
    end)

    it("uses the planned score bands and SSS weight formula", function()
        assert.are.equal(70, Cards.band_weights(39).R)
        assert.are.equal(55, Cards.band_weights(40).R)
        assert.are.equal(40, Cards.band_weights(70).R)
        assert.are.equal(28, Cards.band_weights(90).R)
        assert.are.equal(0, Cards.sss_weight(100, 0))
        assert.are.equal(10, Cards.sss_weight(49, 10))
        assert.are.equal(20, Cards.sss_weight(50, 10))
        assert.are.equal(30, Cards.sss_weight(100, 10))
        assert.are.equal(0, Cards.luck_level(99, 24))
        assert.are.equal(2, Cards.luck_level(100, 25))
        assert.are.equal(20, Cards.luck_level(100000, 100000))
    end)

    it("raises SS and SSS weights with lifetime practice and challenge volume", function()
        local base = Cards.weights(100, 10, {})
        assert.are.equal(14, base.SS)
        assert.are.equal(30, base.SSS)
        -- 500 answers (+5) and 100 challenge answers (+4) = 9 luck.
        local lucky = Cards.weights(100, 10, { total_answered = 500, challenge_answered = 100 })
        assert.are.equal(23, lucky.SS)
        assert.are.equal(34, lucky.SSS)
        -- Luck is capped, and SSS still stays out without challenge badges.
        local capped = Cards.weights(0, 0, { total_answered = 100000, challenge_answered = 100000 })
        assert.are.equal(21, capped.SS)
        assert.are.equal(0, capped.SSS)
    end)

    it("never draws SSS without challenge badges", function()
        for score = 0, 100, 10 do
            for _ = 1, 30 do
                local cards = Cards.draw(score, 0, math.random)
                assert.are.equal(3, #cards)
                for _, card in ipairs(cards) do
                    assert.are_not.equal("SSS", card.tier)
                    assert.is_not_nil(Cards.get(card.id))
                end
            end
        end
    end)

    it("draws SSS with challenge badges and keeps at most 3 high-tier cards", function()
        -- rng(n) = n always lands on the last weight bucket: SSS when enabled.
        local cards = Cards.draw(100, 10, function(n) return n end)
        assert.are.equal(3, #cards)
        local high = 0
        for _, card in ipairs(cards) do
            assert.are.equal("SSS", card.tier)
            if Cards.tier_rank(card.tier) >= Cards.tier_rank("S") then high = high + 1 end
        end
        assert.is_true(high <= 3)
        -- Without badges the same roll lands on SS, never SSS.
        local no_sss = Cards.draw(100, 0, function(n) return n end)
        for _, card in ipairs(no_sss) do assert.are.equal("SS", card.tier) end
    end)

    it("scores an empty day as zero and a full day as 100", function()
        local p = Progress.open(path)
        assert.are.equal(0, Report.score(p, day(10)).score)
        local daily = p:ensure_daily(day(10))
        daily.answered = 10
        daily.correct = 10
        daily.sessions = 3
        daily.challenge.sessions = 2
        daily.kp_answered = 5
        p.data.streak.current = 7
        local info = Report.score(p, day(10))
        assert.are.equal(100, info.score)
        assert.are.equal(30, info.parts.goal)
        assert.are.equal(30, info.parts.accuracy)
        assert.are.equal(15, info.parts.sessions)
        assert.are.equal(10, info.parts.challenge)
        assert.are.equal(5, info.parts.kp)
        assert.are.equal(10, info.parts.streak)
    end)

    it("scores a partial day with the exact formula", function()
        local p = Progress.open(path)
        local daily = p:ensure_daily(day(10))
        daily.answered = 5
        daily.correct = 5
        daily.sessions = 1
        -- goal 10: 15 + accuracy 30 + rounds 5 = 50
        assert.are.equal(50, Report.score(p, day(10)).score)
    end)

    it("parses a valid AI report and strips code fences", function()
        local parsed = Report.parse('{"summary":"今天真棒","card_words":["一","二","三"]}', 3)
        assert.are.equal("今天真棒", parsed.summary)
        assert.are.same({ "一", "二", "三" }, parsed.card_words)
        local fenced = Report.parse('```json\n{"summary":"好","card_words":["a","b","c"]}\n```', 3)
        assert.are.equal("好", fenced.summary)
    end)

    it("rejects bad JSON, wrong word counts and overlong text", function()
        assert.is_nil(Report.parse("not json", 3))
        assert.is_nil(Report.parse('{"summary":"","card_words":["a","b","c"]}', 3))
        assert.is_nil(Report.parse('{"summary":"好","card_words":["a","b"]}', 3))
        assert.is_nil(Report.parse('{"summary":"好","card_words":["a","b",""]}', 3))
        local long_summary = string.rep("好", 401)
        assert.is_nil(Report.parse('{"summary":"' .. long_summary .. '","card_words":["a","b","c"]}', 3))
        local long_word = string.rep("福", 81)
        assert.is_nil(Report.parse('{"summary":"好","card_words":["' .. long_word .. '","b","c"]}', 3))
        local ok = Report.parse('{"summary":"' .. string.rep("好", 400) .. '","card_words":["a","b","c"]}', 3)
        assert.is_not_nil(ok)
    end)

    it("builds an offline report with card descriptions as blessings", function()
        local p = Progress.open(path)
        p:record_answer(question("q1"), { attempt = 1, correct = true, now = day(10) })
        p:record_session({ mode = "subject", perfect = false }, day(10))
        local stats = Report.stats(p, day(10), "./plugins/kidlearn.koplugin")
        local cards = Cards.draw(50, 0, function(n) return 1 end)
        local offline = Report.offline(stats, cards)
        assert.is_true(#offline.summary > 0)
        assert.are.equal(3, #offline.card_words)
        assert.are.equal(cards[1].desc, offline.card_words[1])
        assert.is_true(offline.summary:find("1 轮", 1, true) ~= nil)
    end)

    it("accumulates duplicate cards with name/tier snapshots", function()
        local p = Progress.open(path)
        local card = Cards.get("r01")
        p:add_cards({ card, card }, 1000)
        assert.are.equal(2, p.data.cards.r01.count)
        assert.are.equal(card.name, p.data.cards.r01.name)
        assert.are.equal("R", p.data.cards.r01.tier)
        assert.are.equal(1000, p.data.cards.r01.first_at)
        p:add_cards({ card }, 2000)
        assert.are.equal(3, p.data.cards.r01.count)
        assert.are.equal(1000, p.data.cards.r01.first_at)
        assert.are.equal(2000, p.data.cards.r01.last_at)
        assert.are.equal(1, Cards.owned_types(p))
        assert.are.equal(0, Cards.owned_at_least(p, "S"))
        p:add_cards({ Cards.get("sss01") }, 3000)
        assert.are.equal(1, Cards.owned_at_least(p, "S"))
        assert.are.equal(1, Cards.owned_at_least(p, "SSS"))
    end)

    it("creates and persists a daily report with the draw committed first", function()
        local p = Progress.open(path)
        p:record_answer(question("q1"), { attempt = 1, correct = true, now = day(10) })
        local report = Report.create(p, { now = day(10), rng = function(n) return 1 end })
        assert.are.equal(3, #report.cards)
        assert.is_false(report.ai)
        assert.is_false(report.revealed)
        assert.is_true(report.score > 0)
        -- rng = 1 always picks tier R card r01: three duplicates, one type.
        assert.are.equal(3, p.data.cards.r01.count)
        assert.are.equal(1, Cards.owned_types(p))
        local stored = p:daily_report(day(10))
        assert.are.equal(report.score, stored.score)
        assert.are.equal(report.created_at, stored.created_at)
        local reopened = Progress.open(path)
        assert.are.equal(report.score, reopened:daily_report(day(10)).score)
    end)

    it("unlocks challenge badges which then enable the SSS weight", function()
        local p = Progress.open(path)
        assert.are.equal(0, Badges.challenge_unlocked(p))
        local challenge_q = question("c1")
        challenge_q.challenge = true
        p:record_answer(challenge_q, { attempt = 1, correct = true, now = day(10) })
        assert.are.equal(1, p.data.total.challenge_answered)
        p:record_session({ mode = "challenge", perfect = false }, day(10))
        assert.are.equal(1, p.data.total.challenge_sessions)
        assert.are.equal(1, p.data.daily["2026-11-10"].challenge.sessions)
        assert.are.equal(1, p.data.daily["2026-11-10"].modes.challenge)
        Badges.evaluate(p)
        assert.is_not_nil(p.data.badges.challenge_1)
        assert.are.equal(1, Badges.challenge_unlocked(p))
        assert.is_true(Cards.sss_weight(90, Badges.challenge_unlocked(p)) > 0)
    end)

    it("unlocks card collection badges from the permanent collection", function()
        local p = Progress.open(path)
        p:add_cards({ Cards.get("s01") }, 1000)
        local unlocked = Badges.evaluate(p)
        assert.is_not_nil(p.data.badges.card_s_1)
        assert.is_true(#unlocked >= 1)
        p:add_cards({ Cards.get("sss01") }, 2000)
        Badges.evaluate(p)
        assert.is_not_nil(p.data.badges.card_sss_1)
    end)

    it("keeps legacy card entries visible in the collection state", function()
        local p = Progress.open(path)
        p.data.cards["retired01"] = { count = 2, first_at = 1, last_at = 2, name = "旧卡片", tier = "S" }
        local state, owned = Cards.collection_state(p)
        assert.are.equal(39, #state)
        assert.are.equal(1, owned)
        local found
        for _, item in ipairs(state) do
            if item.id == "retired01" then found = item end
        end
        assert.is_not_nil(found)
        assert.is_true(found.legacy)
        assert.are.equal("旧卡片", found.name)
        assert.are.equal(1, Cards.owned_at_least(p, "S"))
    end)

    it("gives every card tier-scaled stats and an ability line", function()
        local ranges = { R = { 10, 30 }, RR = { 30, 50 }, S = { 50, 70 }, SS = { 70, 90 }, SSS = { 90, 100 } }
        for _, card in ipairs(Cards.all()) do
            local range = ranges[card.tier]
            assert.is_not_nil(range)
            assert.are.equal("number", type(card.atk))
            assert.are.equal("number", type(card.def))
            assert.is_true(card.atk >= range[1] and card.atk <= range[2])
            assert.is_true(card.def >= range[1] and card.def <= range[2])
            assert.are.equal("string", type(card.ability))
            assert.is_true(#card.ability > 0)
            local atk, def, ability = Cards.stats(card.id)
            assert.are.equal(card.atk, atk)
            assert.are.equal(card.def, def)
            assert.are.equal(card.ability, ability)
        end
        local atk, def, ability = Cards.stats("no_such_card")
        assert.are.equal(10, atk)
        assert.are.equal(10, def)
        assert.are.equal("神秘旧卡", ability)
    end)

    it("sums collection power once per owned type with legacy defaults", function()
        local p = Progress.open(path)
        local atk, def = Cards.collection_power(p)
        assert.are.equal(0, atk)
        assert.are.equal(0, def)
        local sparrow, ant = Cards.get("r01"), Cards.get("r02")
        p:add_cards({
            { id = sparrow.id, tier = sparrow.tier, name = sparrow.name, desc = sparrow.desc },
            { id = ant.id, tier = ant.tier, name = ant.name, desc = ant.desc },
        }, day(10))
        atk, def = Cards.collection_power(p)
        assert.are.equal(sparrow.atk + ant.atk, atk)
        assert.are.equal(sparrow.def + ant.def, def)
        -- Duplicates only bump the count, never the power.
        p:add_cards({ { id = sparrow.id, tier = sparrow.tier, name = sparrow.name, desc = sparrow.desc } }, day(10))
        local atk2, def2 = Cards.collection_power(p)
        assert.are.equal(atk, atk2)
        assert.are.equal(def, def2)
        -- Legacy ids outside the pool contribute the modest default.
        p:add_cards({ { id = "legacy_x", tier = "R", name = "旧卡", desc = "" } }, day(10))
        local atk3, def3 = Cards.collection_power(p)
        assert.are.equal(atk + 10, atk3)
        assert.are.equal(def + 10, def3)
        -- collection_state exposes stats for the detail page.
        for _, row in ipairs(Cards.collection_state(p)) do
            if row.id == "r01" then
                assert.are.equal(sparrow.atk, row.atk)
                assert.are.equal(sparrow.ability, row.ability)
            elseif row.id == "legacy_x" then
                assert.are.equal(10, row.atk)
                assert.are.equal("神秘旧卡", row.ability)
            end
        end
    end)

    it("keeps the collection bonus at zero for a tiny collection", function()
        local p = Progress.open(path)
        local card = Cards.get("r01")
        p:add_cards({ { id = card.id, tier = card.tier, name = card.name, desc = card.desc } }, day(10))
        assert.are.equal(0, Report.score(p, day(10)).parts.collection)
    end)

    it("adds a capped collection bonus to the daily score", function()
        local p = Progress.open(path)
        local drawn, power = {}, 0
        for _, card in ipairs(Cards.all()) do
            if card.tier == "SSS" or card.tier == "SS" or card.tier == "S" then
                table.insert(drawn, { id = card.id, tier = card.tier, name = card.name, desc = card.desc })
                power = power + card.atk + card.def
            end
        end
        p:add_cards(drawn, day(10))
        local expected = math.min(10, math.floor(power / 200))
        assert.is_true(expected > 0)
        local info = Report.score(p, day(10))
        assert.are.equal(expected, info.parts.collection)
        -- Empty day: the score is the collection bonus alone.
        assert.are.equal(expected, info.score)
        -- A full day stays capped at 100 even with the bonus.
        local daily = p:ensure_daily(day(10))
        daily.answered = 10
        daily.correct = 10
        daily.sessions = 3
        daily.challenge.sessions = 2
        daily.kp_answered = 5
        p.data.streak.current = 7
        assert.are.equal(100, Report.score(p, day(10)).score)
        -- The offline template mentions the bonus.
        local stats = Report.stats(p, day(10))
        assert.are.equal(power, stats.collection_power)
        assert.are.equal(expected, stats.collection_bonus)
        local offline = Report.offline(stats, {})
        assert.is_truthy(offline.summary:find("收藏力量", 1, true))
    end)

    it("earns one draw per 20 practice answers and spends credits on demand", function()
        local p = Progress.open(path)
        assert.are.equal(0, p:draw_status().credits)
        assert.are.equal(Cards.DRAW_ANSWERS, p:draw_status().need)
        for i = 1, Cards.DRAW_ANSWERS - 1 do
            p:record_answer(question("d" .. i), { attempt = 1, correct = true, now = day(10) })
        end
        assert.are.equal(0, p:draw_status().credits)
        assert.are.equal(Cards.DRAW_ANSWERS - 1, p:draw_status().progress)
        p:record_answer(question("d-last"), { attempt = 1, correct = true, now = day(10) })
        assert.are.equal(1, p:draw_status().credits)
        assert.are.equal(0, p:draw_status().progress)
        -- Wrong-book review and second attempts never earn draws.
        p:record_answer(question("r1"), { attempt = 1, correct = true, mode = "review", now = day(10) })
        p:record_answer(question("d-last"), { attempt = 2, correct = true, now = day(10) })
        assert.are.equal(1, p:draw_status().credits)
        assert.is_true(p:spend_draw())
        assert.are.equal(0, p:draw_status().credits)
        assert.are.equal(1, p:draw_status().draws)
        assert.is_false(p:spend_draw())
    end)
end)
