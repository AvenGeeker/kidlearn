--[[--
Question-bank loading and validation for KidLearn.
--]]--

local Catalog = require("core.catalog")
local JSON = require("json")
local logger = require("logger")
local util = require("util")

local Bank = {}

local unit_cache = {}
local bank_cache = {}

local function read_json(path)
    local content, err = util.readFromFile(path, "rb")
    if not content then return nil, err or ("cannot read " .. path) end
    local ok, data = pcall(JSON.decode, content)
    if not ok or type(data) ~= "table" then
        return nil, tostring(data or "invalid JSON")
    end
    return data
end

local function normalize_options(options)
    if type(options) ~= "table" then return nil end
    local seen = {}
    for i, option in ipairs(options) do
        if type(option) ~= "string" or option == "" then return nil end
        if seen[option] then return nil end
        seen[option] = true
    end
    return options
end

local function normalize_args(subject, a, b, c)
    subject = subject or "chinese"
    local grade, semester, edition
    if a == "upper" or a == "lower" then
        -- Backwards-compatible old signature: (subject, semester[, edition])
        grade = 2
        semester = a
        edition = b
    else
        grade = tonumber(a) or 2
        semester = b or "upper"
        edition = c
    end
    if not edition or edition == "" then
        edition = subject == "chinese" and "tongbian" or "renjiao"
    end
    return grade, semester, edition
end

local function normalize_question(raw, subject, grade, semester, edition, unit_ids, unit_names)
    if type(raw) ~= "table" then return nil, "not a table" end
    if type(raw.id) ~= "string" or raw.id == "" then return nil, "missing id" end
    if type(raw.unit) ~= "string" or not unit_ids[raw.unit] then return nil, "unknown unit" end
    if type(raw.stem) ~= "string" or raw.stem == "" then return nil, "missing stem" end
    if type(raw.explain) ~= "string" or raw.explain == "" then return nil, "missing explain" end

    local difficulty = tonumber(raw.difficulty) or 1
    if difficulty < 1 then difficulty = 1 elseif difficulty > 3 then difficulty = 3 end

    local q = {
        id = raw.id,
        subject = subject,
        grade = grade,
        edition = edition,
        semester = semester,
        unit = raw.unit,
        unit_name = unit_names[raw.unit],
        type = type(raw.type) == "string" and raw.type or "choice",
        skill = type(raw.skill) == "string" and raw.skill or raw.type or "choice",
        difficulty = difficulty,
        answer_mode = raw.answer_mode == "number" and "number" or "choice",
        stem = raw.stem,
        passage = type(raw.passage) == "string" and raw.passage or nil,
        unit_hint = type(raw.unit_hint) == "string" and raw.unit_hint or nil,
        explain = raw.explain,
    }

    if q.answer_mode == "number" then
        if type(raw.answer) ~= "number" then return nil, "number answer missing" end
        q.answer = raw.answer
    else
        local options = normalize_options(raw.options)
        if not options or #options ~= 4 then return nil, "choice needs four unique options" end
        local answer = tonumber(raw.answer)
        if not answer or answer < 1 or answer > 4 or answer % 1 ~= 0 then
            return nil, "invalid answer index"
        end
        q.options = options
        q.answer = answer
    end
    return q
end

function Bank.load_units(plugin_path, subject, a, b, c)
    subject = subject or "chinese"
    local grade, semester, edition = normalize_args(subject, a, b, c)
    local key = table.concat({ plugin_path or "", subject, tostring(grade), semester, edition }, "|")
    if unit_cache[key] then return unit_cache[key] end
    local units, err = Catalog.units(plugin_path, subject, edition, grade, semester)
    if not units then return nil, err end
    unit_cache[key] = units
    return units
end

function Bank.units(plugin_path, subject, a, b, c)
    return Bank.load_units(plugin_path, subject, a, b, c)
end

function Bank.load(plugin_path, subject, a, b, c)
    subject = subject or "chinese"
    local grade, semester, edition = normalize_args(subject, a, b, c)
    local key = table.concat({ plugin_path or "", subject, tostring(grade), semester, edition }, "|")
    if bank_cache[key] then return bank_cache[key] end

    local units, units_err = Bank.load_units(plugin_path, subject, grade, semester, edition)
    if not units then return nil, units_err end

    local unit_ids = {}
    local unit_names = {}
    for _, unit in ipairs(units) do
        unit_ids[unit.id] = true
        unit_names[unit.id] = unit.name
    end

    local path, path_err = Catalog.bank_path(plugin_path, subject, edition, grade, semester)
    if not path then return nil, path_err end
    local data, err = read_json(path)
    if not data then return nil, err end
    if type(data.questions) ~= "table" then return nil, "questions missing" end

    local questions = {}
    local by_unit = {}
    for _, unit in ipairs(units) do by_unit[unit.id] = {} end
    local skipped = 0
    for _, raw in ipairs(data.questions) do
        local question, qerr = normalize_question(raw, subject, grade, semester, edition, unit_ids, unit_names)
        if question then
            table.insert(questions, question)
            table.insert(by_unit[question.unit], question)
        else
            skipped = skipped + 1
            logger.warn("KidLearn: skipped question", raw and raw.id, qerr)
        end
    end
    if #questions == 0 then return nil, "no valid questions" end
    if skipped > 0 then logger.warn("KidLearn: skipped", skipped, "invalid questions in", path) end

    local bank = {
        subject = subject,
        grade = grade,
        edition = edition,
        semester = semester,
        units = units,
        questions = questions,
        by_unit = by_unit,
        textbook = data.textbook,
        skipped = skipped,
    }
    bank_cache[key] = bank
    return bank
end

local function candidates_for(bank, opts)
    opts = opts or {}
    local unit = opts.unit
    local pool = bank.questions
    if unit and unit ~= "all" then
        pool = bank.by_unit[unit] or {}
    end
    local candidates = {}
    local fallback = {}
    for _, q in ipairs(pool) do
        if not opts.recent_ids or not opts.recent_ids[q.id] then
            table.insert(fallback, q)
            if not opts.difficulty or q.difficulty == opts.difficulty then
                table.insert(candidates, q)
            end
        end
    end
    if #candidates == 0 then candidates = fallback end
    return candidates
end

function Bank.pick(bank, opts)
    opts = opts or {}
    local candidates = candidates_for(bank, opts)
    if #candidates == 0 then
        local pool = (opts.unit and opts.unit ~= "all") and (bank.by_unit[opts.unit] or {}) or bank.questions
        candidates = pool
    end
    if #candidates == 0 then return nil end
    local rng = opts.rng or math.random
    local index = rng(#candidates)
    if index < 1 then index = 1 elseif index > #candidates then index = #candidates end
    return candidates[index]
end

function Bank.stats(bank)
    local stats = { total = #bank.questions, units = {} }
    for _, unit in ipairs(bank.units) do
        stats.units[unit.id] = { name = unit.name, count = #(bank.by_unit[unit.id] or {}) }
    end
    return stats
end

function Bank.clear_cache()
    unit_cache = {}
    bank_cache = {}
    Catalog.clear_cache()
end

Bank.normalize_question = normalize_question

return Bank
