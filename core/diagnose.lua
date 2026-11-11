--[[--
Adaptive prerequisite diagnosis for KidLearn knowledge points.

A Lua port of the core rules from cn-math-taxonomy's diagnose/engine.js
(target mode): ask the target topic first; two consecutive correct answers
mark it mastered (and infer its ancestors mastered); a wrong answer triggers
an easier confirmation question -- correct there means "shaky", wrong means
"weak" and the engine backtracks along prerequisite edges (hard before soft,
bounded depth).  The engine is deterministic with an injected rng and takes
question/judge functions so unit tests never touch the filesystem.

Statuses: mastered / shaky / weak / unknown.  Diagnosis is assessment only:
callers decide what to persist; no scoring happens here.
--]]--

local Diagnose = {}
Diagnose.__index = Diagnose

local DEFAULT_LIMIT = 12
local DEFAULT_CONFIRM = 2
local DEFAULT_DEPTH = 3

local function count_fails(attempts)
    local fails = 0
    for _, a in ipairs(attempts or {}) do
        if not a.correct then fails = fails + 1 end
    end
    return fails
end

local function grade_rank(node)
    if not node then return 99 end
    return (tonumber(node.grade) or 99) * 2 + (node.semester == "lower" and 1 or 0)
end

function Diagnose.new(opts)
    opts = opts or {}
    assert(type(opts.graph) == "table", "diagnose requires a graph")
    assert(type(opts.target) == "string", "diagnose requires a target topic id")
    assert(type(opts.questions_fn) == "function", "diagnose requires questions_fn")
    local graph = opts.graph
    if not graph.nodes[opts.target] then return nil, "unknown target topic" end

    local limit = tonumber(opts.limit) or DEFAULT_LIMIT
    if limit < 1 then limit = DEFAULT_LIMIT end
    local confirm = tonumber(opts.confirm) or DEFAULT_CONFIRM
    if confirm < 1 then confirm = DEFAULT_CONFIRM end
    local max_depth = tonumber(opts.max_depth) or DEFAULT_DEPTH
    if max_depth < 0 then max_depth = DEFAULT_DEPTH end

    -- Scope: target plus ancestors within max_depth, topologically sorted
    -- (prerequisites first, ties keep graph source order).
    local depth = { [opts.target] = 0 }
    local queue = { opts.target }
    local scope_set = { [opts.target] = true }
    local head = 1
    while head <= #queue do
        local id = queue[head]
        head = head + 1
        local d = depth[id]
        if d < max_depth then
            for _, p in ipairs(graph.prereqs[id] or {}) do
                if not scope_set[p.id] then
                    scope_set[p.id] = true
                    depth[p.id] = d + 1
                    table.insert(queue, p.id)
                end
            end
        end
    end
    local indeg = {}
    for id in pairs(scope_set) do
        indeg[id] = 0
        for _, p in ipairs(graph.prereqs[id] or {}) do
            if scope_set[p.id] then indeg[id] = indeg[id] + 1 end
        end
    end
    local ready = {}
    for id in pairs(scope_set) do
        if indeg[id] == 0 then table.insert(ready, id) end
    end
    local order = {}
    while #ready > 0 do
        table.sort(ready, function(a, b)
            return (graph.index[a] or 0) < (graph.index[b] or 0)
        end)
        local id = table.remove(ready, 1)
        table.insert(order, id)
        for _, d in ipairs(graph.dependents[id] or {}) do
            if scope_set[d.id] then
                indeg[d.id] = indeg[d.id] - 1
                if indeg[d.id] == 0 then table.insert(ready, d.id) end
            end
        end
    end

    local self = setmetatable({
        subject = opts.subject or graph.subject,
        target = opts.target,
        graph = graph,
        questions_fn = opts.questions_fn,
        judge_fn = opts.judge_fn,
        rng = opts.rng or math.random,
        limit = limit,
        confirm = confirm,
        max_depth = max_depth,
        scope = scope_set,
        order = order,
        depth = depth,
        stack = { opts.target },
        status = {},
        attempts = {},
        answers = {},
        pending = nil,
    }, Diagnose)
    return self
end

function Diagnose:_questions(topic_id)
    local list = self.questions_fn(topic_id)
    return type(list) == "table" and list or {}
end

function Diagnose:_need_confirm(topic_id)
    local n = #self:_questions(topic_id)
    local need = math.min(self.confirm, n)
    if need < 1 then need = 1 end
    return need
end

--[[--
Pick the next unused question for a topic.
First attempt prefers standard (2) then basic (1); while unbeaten prefer
challenge (3) to confirm mastery; after a failure prefer basic, then the
first question's difficulty, then easier, then the easiest left.
--]]--
function Diagnose:_pick_question(topic_id, attempt)
    local all = self:_questions(topic_id)
    local tried = {}
    for _, a in ipairs(self.attempts[topic_id] or {}) do tried[a.qid] = true end
    local pool = {}
    for _, q in ipairs(all) do
        if not tried[q.id] then table.insert(pool, q) end
    end
    if #pool == 0 then return nil end

    local function filter_rank(list, rank)
        local hit = {}
        for _, q in ipairs(list) do
            if q.difficulty == rank then table.insert(hit, q) end
        end
        if #hit > 0 then return hit end
        return nil
    end

    local had_fail = count_fails(self.attempts[topic_id]) > 0
    local tier
    if attempt <= 1 then
        tier = filter_rank(pool, 2) or filter_rank(pool, 1) or pool
    elseif not had_fail then
        tier = filter_rank(pool, 3) or filter_rank(pool, 2) or filter_rank(pool, 1) or pool
    else
        local first_qid = (self.attempts[topic_id][1] or {}).qid
        local r0 = 2
        for _, q in ipairs(all) do
            if q.id == first_qid then r0 = q.difficulty break end
        end
        tier = filter_rank(pool, 1) or filter_rank(pool, r0)
        if not tier then
            local easier = {}
            for _, q in ipairs(pool) do
                if q.difficulty < r0 then table.insert(easier, q) end
            end
            if #easier > 0 then
                tier = easier
            else
                local lo = 4
                for _, q in ipairs(pool) do
                    if q.difficulty < lo then lo = q.difficulty end
                end
                tier = filter_rank(pool, lo) or pool
            end
        end
    end
    local index = self.rng(#tier)
    if index < 1 then index = 1 elseif index > #tier then index = #tier end
    return tier[index]
end

--[[--
Next item to answer: {topic, question, attempt} or nil when finished.
Repeated calls without submit return the same item.
--]]--
function Diagnose:next()
    if self.pending then return self.pending end
    if #self.answers >= self.limit then return nil end
    local i = 1
    while i <= #self.stack do
        local id = self.stack[i]
        if self.status[id] then
            table.remove(self.stack, i)
        else
            local attempt = #(self.attempts[id] or {}) + 1
            local q = self:_pick_question(id, attempt)
            if q then
                self.pending = { topic = id, question = q, attempt = attempt }
                return self.pending
            end
            -- Exhausted the bank: a topic that failed without confirmation is weak.
            if count_fails(self.attempts[id]) > 0 then
                self.status[id] = { s = "weak", src = "unconfirmed" }
            end
            table.remove(self.stack, i)
        end
    end
    return nil
end

function Diagnose:_infer_ancestors(topic_id)
    local visiting = {}
    local function walk(id)
        if visiting[id] then return end
        visiting[id] = true
        for _, p in ipairs(self.graph.prereqs[id] or {}) do
            if not self.status[p.id] then
                self.status[p.id] = { s = "mastered", src = "inferred" }
            end
            walk(p.id)
        end
    end
    walk(topic_id)
end

function Diagnose:_push_prereqs(topic_id)
    local d = self.depth[topic_id] or 0
    if d >= self.max_depth then return end
    local push = {}
    local pushed = {}
    for _, p in ipairs(self.graph.prereqs[topic_id] or {}) do
        local has_questions = #self:_questions(p.id) > 0
        if has_questions and not self.status[p.id] and not pushed[p.id] then
            table.insert(push, p.id)
            pushed[p.id] = true
            local nd = d + 1
            if not self.depth[p.id] or self.depth[p.id] > nd then
                self.depth[p.id] = nd
            end
        end
    end
    if #push == 0 then return end
    local rest = {}
    for _, id in ipairs(self.stack) do
        if not pushed[id] then table.insert(rest, id) end
    end
    self.stack = {}
    for _, id in ipairs(push) do table.insert(self.stack, id) end
    for _, id in ipairs(rest) do table.insert(self.stack, id) end
end

--[[--
Record the answer for the pending item.
@treturn table {correct, topic, status, hint}
--]]--
function Diagnose:submit(value)
    local item = self.pending
    if not item then return nil end
    self.pending = nil
    local q = item.question
    local topic_id = item.topic
    local correct
    if self.judge_fn then
        correct = self.judge_fn(q, value) and true or false
    else
        correct = tonumber(value) == q.answer
    end

    table.insert(self.answers, { topic = topic_id, qid = q.id, correct = correct })
    self.attempts[topic_id] = self.attempts[topic_id] or {}
    table.insert(self.attempts[topic_id], { qid = q.id, correct = correct })
    local attempts = self.attempts[topic_id]
    local fails = count_fails(attempts)
    local corrects = #attempts - fails
    local hint

    if correct then
        if fails == 0 and corrects >= self:_need_confirm(topic_id) then
            self.status[topic_id] = { s = "mastered", src = "direct" }
            self:_infer_ancestors(topic_id)
            hint = "这个知识点掌握啦！"
        elseif fails > 0 then
            self.status[topic_id] = { s = "shaky", src = "direct" }
            hint = "答对了，不过这个知识点还有点不稳。"
        else
            hint = "答对了，再来一题确认一下。"
        end
    else
        local attempt = #attempts + 1
        if fails == 1 and self:_pick_question(topic_id, attempt) then
            hint = "没关系，再来一道更基础的试试。"
        else
            self.status[topic_id] = { s = "weak", src = "direct" }
            self:_push_prereqs(topic_id)
            if #self.stack > 0 and self.stack[1] ~= topic_id then
                hint = "这个知识点有点薄弱，我们先去看看它的基础知识。"
            else
                hint = "这个知识点有点薄弱，建议先学一学。"
            end
        end
    end

    local st = self.status[topic_id]
    return {
        correct = correct,
        topic = topic_id,
        status = st and st.s or nil,
        hint = hint,
    }
end

function Diagnose:_status_of(id)
    local st = self.status[id]
    if st then return st.s end
    if count_fails(self.attempts[id]) > 0 then return "weak" end
    return "unknown"
end

--[[--
Diagnosis summary: status lists, root causes and a learning path.
The path contains weak roots and shaky topics plus their dependents inside
the scope, excluding mastered topics, ordered by grade then prerequisite
order (low grades first).
--]]--
function Diagnose:summary()
    local graph = self.graph
    local ids = {}
    local seen = {}
    for _, id in ipairs(self.order) do
        if not seen[id] then seen[id] = true; table.insert(ids, id) end
    end
    for id in pairs(self.status) do
        if not seen[id] then seen[id] = true; table.insert(ids, id) end
    end
    for id in pairs(self.attempts) do
        if not seen[id] then seen[id] = true; table.insert(ids, id) end
    end
    local topo_pos = {}
    for i, id in ipairs(self.order) do topo_pos[id] = i end
    table.sort(ids, function(a, b)
        local ga, gb = grade_rank(graph.nodes[a]), grade_rank(graph.nodes[b])
        if ga ~= gb then return ga < gb end
        return (topo_pos[a] or graph.index[a] or 0) < (topo_pos[b] or graph.index[b] or 0)
    end)

    local mastered, shaky, weak, untested = {}, {}, {}, {}
    local status_map = {}
    for _, id in ipairs(ids) do
        local s = self:_status_of(id)
        status_map[id] = s
        local node = graph.nodes[id] or {}
        local entry = {
            id = id,
            name = node.name or id,
            grade = node.grade,
            semester = node.semester,
            status = s,
            inferred = (self.status[id] or {}).src == "inferred",
            asked = #(self.attempts[id] or {}),
        }
        if s == "mastered" then table.insert(mastered, entry)
        elseif s == "shaky" then table.insert(shaky, entry)
        elseif s == "weak" then table.insert(weak, entry)
        else table.insert(untested, entry) end
    end

    -- Root causes: weak topics without a weak prerequisite.
    local roots = {}
    for _, entry in ipairs(weak) do
        local has_weak_prereq = false
        for _, p in ipairs(graph.prereqs[entry.id] or {}) do
            if status_map[p.id] == "weak" then has_weak_prereq = true break end
        end
        if not has_weak_prereq then table.insert(roots, entry) end
    end
    local root_set = {}
    for _, entry in ipairs(roots) do root_set[entry.id] = true end

    -- Learning path: reach from roots + shaky through dependents within scope.
    local reach = {}
    local queue = {}
    for _, entry in ipairs(roots) do
        reach[entry.id] = true
        table.insert(queue, entry.id)
    end
    for _, entry in ipairs(shaky) do
        if not reach[entry.id] then
            reach[entry.id] = true
            table.insert(queue, entry.id)
        end
    end
    local head = 1
    while head <= #queue do
        local id = queue[head]
        head = head + 1
        for _, d in ipairs(graph.dependents[id] or {}) do
            if self.scope[d.id] and not reach[d.id] then
                reach[d.id] = true
                table.insert(queue, d.id)
            end
        end
    end
    local path = {}
    for _, id in ipairs(ids) do
        if reach[id] and status_map[id] ~= "mastered" then
            local node = graph.nodes[id] or {}
            table.insert(path, {
                id = id,
                name = node.name or id,
                grade = node.grade,
                semester = node.semester,
                status = status_map[id],
                is_root = root_set[id] or false,
                is_target = id == self.target,
            })
        end
    end

    local finished = self:next() == nil
    local pending = false
    for _, id in ipairs(self.stack) do
        if not self.status[id] and #self:_questions(id) > 0 then pending = true break end
    end
    return {
        subject = self.subject,
        target = self.target,
        asked = #self.answers,
        limit = self.limit,
        finished = finished,
        limit_reached = #self.answers >= self.limit and pending,
        mastered = mastered,
        shaky = shaky,
        weak = weak,
        untested = untested,
        roots = roots,
        path = path,
    }
end

return Diagnose
