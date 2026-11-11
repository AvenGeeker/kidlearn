describe("KidLearn diagnose engine", function()
    local Diagnose

    setup(function()
        require("commonrequire")
        package.path = "plugins/kidlearn.koplugin/?.lua;" .. package.path
        Diagnose = require("core.diagnose")
    end)

    -- Synthetic graph with the same shape Knowledge.graph() returns.
    local function make_graph(nodes, edges)
        local g = { nodes = {}, order = {}, index = {}, prereqs = {}, dependents = {}, edges = edges }
        for i, n in ipairs(nodes) do
            g.nodes[n.id] = n
            g.order[i] = n.id
            g.index[n.id] = i
            g.prereqs[n.id] = {}
            g.dependents[n.id] = {}
        end
        for _, e in ipairs(edges) do
            table.insert(g.prereqs[e.from], { id = e.to, strength = e.strength or "hard" })
            table.insert(g.dependents[e.to], { id = e.from, strength = e.strength or "hard" })
        end
        for _, list in pairs(g.prereqs) do
            table.sort(list, function(a, b)
                local ra = (a.strength == "hard" and 0 or 1) * 100000 + g.index[a.id]
                local rb = (b.strength == "hard" and 0 or 1) * 100000 + g.index[b.id]
                return ra < rb
            end)
        end
        return g
    end

    local function node(id, grade)
        return { id = id, name = "知识点" .. id, grade = grade or 1, semester = "upper" }
    end

    -- Mirrors the synced bank: q1/q2 basic, q3 standard, q4 challenge.
    local function make_bank(topic_id, count)
        local diffs = { 1, 1, 2, 3 }
        local list = {}
        for i = 1, count or 4 do
            list[i] = {
                id = topic_id .. "_q" .. i,
                topic = topic_id,
                difficulty = diffs[i] or 2,
                answer_mode = "number",
                answer = i,
                stem = "?",
                explain = "x",
            }
        end
        return list
    end

    local function new_engine(graph, banks, target, opts)
        opts = opts or {}
        return Diagnose.new{
            subject = "math",
            target = target,
            graph = graph,
            questions_fn = function(id) return banks[id] or {} end,
            judge_fn = function(q, v) return tonumber(v) == q.answer end,
            rng = opts.rng or function() return 1 end,
            limit = opts.limit,
            confirm = opts.confirm,
            max_depth = opts.max_depth,
        }
    end

    local function answer(engine, correct)
        local item = engine:next()
        assert.is_not_nil(item)
        local value = correct and item.question.answer or (item.question.answer + 100)
        return engine:submit(value), item
    end

    local function ids(list)
        local out = {}
        for _, entry in ipairs(list) do table.insert(out, entry.id) end
        return out
    end

    it("marks a topic mastered after two consecutive correct answers", function()
        local graph = make_graph({ node("A") }, {})
        local engine = new_engine(graph, { A = make_bank("A") }, "A")
        local item = engine:next()
        assert.are.equal(2, item.question.difficulty) -- standard first
        assert.are.equal(item, engine:next()) -- pending item is stable
        local r1 = answer(engine, true)
        assert.is_nil(r1.status)
        local r2 = answer(engine, true)
        assert.are.equal("mastered", r2.status)
        assert.is_nil(engine:next())
        local summary = engine:summary()
        assert.are.same({ "A" }, ids(summary.mastered))
        assert.are.equal(2, summary.asked)
        assert.is_true(summary.finished)
    end)

    it("infers ancestors mastered when the target is mastered", function()
        local graph = make_graph({ node("A", 1), node("B", 2), node("C", 3) },
            { { from = "C", to = "B" }, { from = "B", to = "A" } })
        local banks = { A = make_bank("A"), B = make_bank("B"), C = make_bank("C") }
        local engine = new_engine(graph, banks, "C")
        answer(engine, true)
        answer(engine, true)
        local summary = engine:summary()
        assert.are.same({ "A", "B", "C" }, ids(summary.mastered))
        for _, entry in ipairs(summary.mastered) do
            if entry.id == "C" then
                assert.is_false(entry.inferred)
            else
                assert.is_true(entry.inferred)
            end
        end
        assert.are.equal(0, #summary.path)
    end)

    it("marks a topic shaky when the basic confirmation is correct", function()
        local graph = make_graph({ node("A") }, {})
        local engine = new_engine(graph, { A = make_bank("A") }, "A")
        local r1 = answer(engine, false)
        assert.is_nil(r1.status)
        local item = engine:next()
        assert.are.equal(1, item.question.difficulty) -- basic confirmation
        local r2 = answer(engine, true)
        assert.are.equal("shaky", r2.status)
        local summary = engine:summary()
        assert.are.same({ "A" }, ids(summary.shaky))
        assert.are.same({ "A" }, ids(summary.path))
    end)

    it("backtracks along hard prerequisites when weak", function()
        local graph = make_graph({ node("A", 1), node("B", 2), node("C", 3) },
            { { from = "C", to = "B" }, { from = "B", to = "A" } })
        local banks = { A = make_bank("A"), B = make_bank("B"), C = make_bank("C") }
        local engine = new_engine(graph, banks, "C")
        answer(engine, false) -- C standard wrong
        answer(engine, false) -- C basic wrong -> weak, push B
        assert.are.equal("B", engine:next().topic)
        answer(engine, false) -- B wrong
        answer(engine, false) -- B weak, push A
        assert.are.equal("A", engine:next().topic)
        answer(engine, true)
        answer(engine, true) -- A mastered
        local summary = engine:summary()
        assert.are.same({ "B", "C" }, ids(summary.weak))
        assert.are.same({ "A" }, ids(summary.mastered))
        assert.are.same({ "B" }, ids(summary.roots))
        assert.are.same({ "B", "C" }, ids(summary.path))
        assert.is_true(summary.path[1].is_root)
        assert.is_true(summary.path[2].is_target)
    end)

    it("prefers hard prerequisites over earlier soft ones", function()
        local graph = make_graph({ node("S"), node("H"), node("D") },
            { { from = "D", to = "S", strength = "soft" }, { from = "D", to = "H", strength = "hard" } })
        local banks = { S = make_bank("S"), H = make_bank("H"), D = make_bank("D") }
        local engine = new_engine(graph, banks, "D")
        answer(engine, false)
        answer(engine, false) -- D weak
        assert.are.equal("H", engine:next().topic)
    end)

    it("stops at the question limit and reports unfinished scope", function()
        local nodes, edges, banks = {}, {}, {}
        for i = 1, 10 do
            local id = "T" .. i
            table.insert(nodes, node(id, i))
            banks[id] = make_bank(id)
            if i > 1 then table.insert(edges, { from = "T" .. i, to = "T" .. (i - 1) }) end
        end
        local graph = make_graph(nodes, edges)
        local engine = new_engine(graph, banks, "T10", { max_depth = 10 })
        local asked = 0
        while engine:next() and asked < 50 do
            answer(engine, false)
            asked = asked + 1
        end
        assert.are.equal(12, asked)
        local summary = engine:summary()
        assert.are.equal(12, summary.asked)
        assert.is_true(summary.limit_reached)
        assert.is_true(summary.finished) -- no more questions will be asked
    end)

    it("bounds backtracking depth", function()
        local nodes, edges, banks = {}, {}, {}
        for i = 1, 5 do
            local id = "N" .. i
            table.insert(nodes, node(id, i))
            banks[id] = make_bank(id)
            if i > 1 then table.insert(edges, { from = "N" .. i, to = "N" .. (i - 1) }) end
        end
        local graph = make_graph(nodes, edges)
        local engine = new_engine(graph, banks, "N5")
        while engine:next() do answer(engine, false) end
        local summary = engine:summary()
        -- N5(depth0) N4(1) N3(2) N2(3) are tested; N1(depth4) is out of scope.
        assert.are.same({ "N2", "N3", "N4", "N5" }, ids(summary.weak))
        for _, list in ipairs({ summary.mastered, summary.shaky, summary.untested }) do
            for _, entry in ipairs(list) do
                assert.are_not.equal("N1", entry.id)
            end
        end
    end)

    it("marks a single-question topic weak immediately when wrong", function()
        local graph = make_graph({ node("A") }, {})
        local engine = new_engine(graph, { A = make_bank("A", 1) }, "A")
        local result = answer(engine, false)
        assert.are.equal("weak", result.status)
        assert.is_nil(engine:next())
        assert.are.equal(1, engine:summary().asked)
    end)

    it("honours a custom confirm count", function()
        local graph = make_graph({ node("A") }, {})
        local engine = new_engine(graph, { A = make_bank("A") }, "A", { confirm = 1 })
        local result = answer(engine, true)
        assert.are.equal("mastered", result.status)
    end)

    it("is deterministic with a fixed rng", function()
        local function run()
            local graph = make_graph({ node("A"), node("B") },
                { { from = "B", to = "A" } })
            local banks = { A = make_bank("A"), B = make_bank("B") }
            local engine = new_engine(graph, banks, "B", { rng = function(n) return n end })
            local sequence = {}
            while engine:next() do
                local item = engine:next()
                table.insert(sequence, item.question.id)
                answer(engine, false)
            end
            return sequence
        end
        assert.are.same(run(), run())
    end)
end)
