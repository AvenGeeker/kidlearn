--[[--
Session construction and answer bookkeeping for KidLearn.
--]]--

local Bank = require("core.bank")
local MathGen = require("core.mathgen")

local Session = {}
Session.__index = Session

local SUBJECTS = { "chinese", "math" }

local function is_correct(question, value)
    if question.answer_mode == "number" then
        local n = tonumber(value)
        return n ~= nil and n == question.answer
    end
    return tonumber(value) == question.answer
end

local function choose_difficulty(rng, level)
    local roll = rng(100)
    if level <= 1 then
        return roll <= 70 and 1 or 2
    elseif level >= 3 then
        if roll <= 10 then return 1 elseif roll <= 50 then return 2 else return 3 end
    end
    if roll <= 30 then return 1 elseif roll <= 80 then return 2 else return 3 end
end

local function resolved_settings(opts)
    local settings = opts.progress and opts.progress.data.settings or {}
    return {
        grade = tonumber(opts.grade) or tonumber(settings.grade) or 2,
        semester = opts.semester or settings.semester or "upper",
        chinese_edition = opts.chinese_edition or settings.chinese_edition or "tongbian",
        math_edition = opts.math_edition or settings.math_edition or "renjiao",
    }
end

local function unit_list(subject, semester, grade, edition, chinese_bank)
    if subject == "chinese" then
        return chinese_bank and chinese_bank.units or {}
    end
    return MathGen.units(grade, edition, semester) or {}
end

local function pick_chinese(bank, unit, difficulty, recent, rng)
    local q = Bank.pick(bank, {
        unit = unit,
        difficulty = difficulty,
        recent_ids = recent,
        rng = rng,
    })
    if not q then
        q = Bank.pick(bank, { unit = unit, recent_ids = recent, rng = rng })
    end
    if not q then
        q = Bank.pick(bank, { unit = "all", rng = rng })
    end
    return q
end

local function math_skill_for(units, unit_id, attempt)
    for _, unit in ipairs(units) do
        if unit.id == unit_id and type(unit.skills) == "table" and #unit.skills > 0 then
            return unit.skills[((attempt - 1) % #unit.skills) + 1]
        end
    end
    return nil
end

local function build_subject(opts)
    local resolved = resolved_settings(opts)
    local subject = opts.subject or "chinese"
    local semester = resolved.semester
    local grade = resolved.grade
    local rng = opts.rng or math.random
    local questions = {}
    local recent = {}
    local level = opts.progress and opts.progress:adaptive_level(subject, grade) or 2
    for _, id in ipairs(opts.progress.data.recent_ids) do recent[id] = true end

    if opts.plugin_path then MathGen.set_plugin_path(opts.plugin_path) end

    if subject == "chinese" then
        local bank, err = Bank.load(opts.plugin_path, "chinese", grade, semester, resolved.chinese_edition)
        if not bank then return nil, err end
        local units = unit_list("chinese", semester, grade, resolved.chinese_edition, bank)
        if #units == 0 then return nil, "语文题库为空" end
        local unit = opts.unit
        if not unit or unit == "all" then
            for i = 1, 10 do
                local u = units[((i - 1) % #units) + 1]
                local q = pick_chinese(bank, u.id, choose_difficulty(rng, level), recent, rng)
                if q then
                    table.insert(questions, q)
                    recent[q.id] = true
                end
            end
        else
            for i = 1, 10 do
                local q = pick_chinese(bank, unit, choose_difficulty(rng, level), recent, rng)
                if q then
                    table.insert(questions, q)
                    recent[q.id] = true
                end
            end
        end
    else
        local units = unit_list("math", semester, grade, resolved.math_edition)
        if #units == 0 then return nil, "数学题库为空" end
        local unit = opts.unit
        for i = 1, 10 do
            local q
            if (not unit or unit == "all") and i == 6 then
                q = MathGen.generate_word_problem({
                    semester = semester,
                    grade = grade,
                    edition = resolved.math_edition,
                    difficulty = choose_difficulty(rng, level),
                }, rng)
            elseif (not unit or unit == "all") and (i == 4 or i == 8) then
                q = MathGen.generate_challenge({
                    semester = semester,
                    grade = grade,
                    edition = resolved.math_edition,
                    unit = "all",
                }, rng)
            else
                local u = (unit and unit ~= "all") and unit or units[((i - 1) % #units) + 1].id
                q = MathGen.generate({
                    semester = semester,
                    grade = grade,
                    edition = resolved.math_edition,
                    unit = u,
                    skill = math_skill_for(units, u, i),
                    difficulty = choose_difficulty(rng, level),
                }, rng)
            end
            table.insert(questions, q)
        end
    end

    if #questions == 0 then return nil, "没有可用题目" end
    return questions
end

local function build_daily(opts)
    local resolved = resolved_settings(opts)
    local semester = resolved.semester
    local grade = resolved.grade
    local rng = opts.rng or math.random
    local level_chinese = opts.progress and opts.progress:adaptive_level("chinese", grade) or 2
    local level_math = opts.progress and opts.progress:adaptive_level("math", grade) or 2
    if opts.plugin_path then MathGen.set_plugin_path(opts.plugin_path) end
    local chinese_bank, err = Bank.load(opts.plugin_path, "chinese", grade, semester, resolved.chinese_edition)
    if not chinese_bank then return nil, err end
    local recent = {}
    for _, id in ipairs(opts.progress.data.recent_ids) do recent[id] = true end

    local chinese_units = unit_list("chinese", semester, grade, resolved.chinese_edition, chinese_bank)
    local math_units = unit_list("math", semester, grade, resolved.math_edition)
    if #chinese_units == 0 or #math_units == 0 then return nil, "题库为空" end
    local chinese, math_questions = {}, {}
    for i = 1, 5 do
        local u = chinese_units[((i - 1) % #chinese_units) + 1]
        local q = pick_chinese(chinese_bank, u.id, choose_difficulty(rng, level_chinese), recent, rng)
        if q then
            table.insert(chinese, q)
            recent[q.id] = true
        end
        if i == 4 then
            table.insert(math_questions, MathGen.generate_word_problem({
                semester = semester,
                grade = grade,
                edition = resolved.math_edition,
                difficulty = choose_difficulty(rng, level_math),
            }, rng))
        elseif i == 5 then
            table.insert(math_questions, MathGen.generate_challenge({
                semester = semester,
                grade = grade,
                edition = resolved.math_edition,
                unit = "all",
            }, rng))
        else
            local u = math_units[((i - 1) % #math_units) + 1].id
            table.insert(math_questions, MathGen.generate({
                semester = semester,
                grade = grade,
                edition = resolved.math_edition,
                unit = u,
                skill = math_skill_for(math_units, u, i),
                difficulty = choose_difficulty(rng, level_math),
            }, rng))
        end
    end

    local questions = {}
    for i = 1, 5 do
        if chinese[i] then table.insert(questions, chinese[i]) end
        if math_questions[i] then table.insert(questions, math_questions[i]) end
    end
    return questions
end

local function build_challenge(opts)
    local resolved = resolved_settings(opts)
    local semester = resolved.semester
    local grade = resolved.grade
    local rng = opts.rng or math.random
    if opts.plugin_path then MathGen.set_plugin_path(opts.plugin_path) end
    local questions = {}
    local plan = MathGen.challenge_plan({
        semester = semester,
        unit = opts.unit,
        count = 10,
        grade = grade,
    }, rng)
    for _, id in ipairs(plan) do
        local q = MathGen.generate_challenge({
            semester = semester,
            grade = grade,
            edition = resolved.math_edition,
            unit = opts.unit,
            id = id,
        }, rng)
        q.grade = grade
        q.edition = resolved.math_edition
        table.insert(questions, q)
    end
    return questions
end

local function build_wrong(opts)
    local items = opts.wrong_items or opts.progress:wrong_items()
    local questions = {}
    for i = 1, math.min(#items, 10) do
        table.insert(questions, items[i])
    end
    return questions
end

function Session.new(opts)
    opts = opts or {}
    local resolved = resolved_settings(opts)
    local mode = opts.mode or "subject"
    local questions, err
    if mode == "daily" then
        questions, err = build_daily(opts)
    elseif mode == "challenge" then
        questions = build_challenge(opts)
    elseif mode == "wrong" then
        questions = build_wrong(opts)
    elseif mode == "ai" then
        questions = opts.ai_questions or {}
        if #questions == 0 then questions = nil; err = "没有 AI 变种题" end
    else
        questions, err = build_subject(opts)
    end
    if not questions then return nil, err end
    if #questions == 0 then return nil, "没有可用题目" end

    return setmetatable({
        mode = mode,
        subject = opts.subject or (mode == "challenge" and "math" or nil),
        unit = opts.unit,
        grade = resolved.grade,
        semester = resolved.semester,
        questions = questions,
        index = 1,
        attempt = 1,
        combo = 0,
        max_combo = 0,
        first_try_correct = 0,
        answered = 0,
        points = 0,
        progress = opts.progress,
        retry_enabled = opts.progress.data.settings.retry ~= false,
        now_fn = opts.now_fn or os.time,
    }, Session)
end

function Session:current()
    return self.questions[self.index]
end

function Session:total()
    return #self.questions
end

function Session:position()
    return self.index
end

function Session:submit(value)
    local q = self:current()
    if not q then return nil end
    local correct = is_correct(q, value)
    local now = self.now_fn()
    local points_result
    local combo_bonus = 0

    if self.attempt == 1 then
        self.answered = self.answered + 1
        if correct then
            self.first_try_correct = self.first_try_correct + 1
            if self.mode ~= "review" then
                self.combo = self.combo + 1
                if self.combo == 3 then combo_bonus = 5
                elseif self.combo == 5 then combo_bonus = 10
                elseif self.combo == 10 then combo_bonus = 20 end
                if self.combo > self.max_combo then self.max_combo = self.combo end
            end
        else
            self.combo = 0
        end
        points_result = self.progress:record_answer(q, {
            attempt = 1,
            correct = correct,
            mode = self.mode,
            combo = self.combo,
            combo_bonus = combo_bonus,
            now = now,
        })
    else
        points_result = self.progress:record_answer(q, {
            attempt = 2,
            correct = correct,
            mode = self.mode,
            now = now,
        })
    end

    local awarded = points_result and points_result.points or 0
    self.points = self.points + awarded
    local final = correct or self.attempt >= 2 or not self.retry_enabled
    return {
        question = q,
        correct = correct,
        attempt = self.attempt,
        final = final,
        can_retry = not correct and not final,
        points = awarded,
        combo = self.combo,
        combo_bonus = combo_bonus,
        awarded = awarded,
    }
end

function Session:retry()
    if self.attempt >= 2 then return false end
    self.attempt = 2
    return true
end

function Session:give_up()
    self.attempt = 2
end

function Session:advance()
    self.index = self.index + 1
    self.attempt = 1
    return self.index <= #self.questions
end

function Session:finish()
    local perfect = self.first_try_correct == #self.questions
    local breakdown = self.progress:record_session({
        mode = self.mode,
        perfect = perfect,
        total = #self.questions,
        correct = self.first_try_correct,
    }, self.now_fn())
    self.points = self.points + (breakdown and breakdown.total or 0)
    return {
        mode = self.mode,
        total = #self.questions,
        answered = self.answered,
        correct = self.first_try_correct,
        points = self.points,
        max_combo = self.max_combo,
        perfect = perfect,
        breakdown = breakdown or {},
    }
end

Session.is_correct = is_correct
Session.SUBJECTS = SUBJECTS

return Session
