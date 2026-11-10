--[[--
Prompt construction and strict validation for AI-generated wrong-question
variants.  The model output is untrusted: every question is checked and then
normalized through Bank.normalize_question before it can enter an AI bank.
--]]--

local JSON = require("json")
local Bank = require("core.bank")

local AIVariant = {}

local SUBJECT_LABEL = { chinese = "语文", math = "数学" }
local PREFIX = { "A", "B", "C", "D" }
local MAX_STEM = 900
local MAX_OPTION = 240
local MAX_EXPLAIN = 900
local MAX_PASSAGE = 3600

local function trim(value)
    if type(value) ~= "string" then return "" end
    return value:match("^%s*(.-)%s*$") or ""
end

local function option_text(item)
    if item.answer_mode == "number" then
        return tostring(item.answer) .. (item.unit_hint or "")
    end
    local index = tonumber(item.answer) or 0
    return (PREFIX[index] or "?") .. ". " .. tostring((item.options or {})[index] or "")
end

local function describe_item(item, index)
    local lines = {
        string.format("【错题%d】", index),
        string.format("学科：%s；年级：%s年级；学期：%s；教材：%s",
            SUBJECT_LABEL[item.subject] or "综合",
            tostring(item.grade or 2),
            item.semester == "lower" and "下册" or "上册",
            tostring(item.edition or "")),
        string.format("单元：%s；题型：%s；知识点：%s；难度：%s",
            tostring(item.unit_name or item.unit or ""),
            tostring(item.type or "choice"),
            tostring(item.skill or item.type or "choice"),
            tostring(item.difficulty or 2)),
    }
    if item.passage and item.passage ~= "" then
        table.insert(lines, "阅读材料（变种题沿用，不必重复输出）：")
        table.insert(lines, item.passage)
    end
    table.insert(lines, "题干：" .. tostring(item.stem or ""))
    if item.answer_mode ~= "number" and type(item.options) == "table" then
        local parts = {}
        for i, option in ipairs(item.options) do
            table.insert(parts, (PREFIX[i] or "?") .. ". " .. tostring(option))
        end
        table.insert(lines, "选项：" .. table.concat(parts, "  "))
    end
    table.insert(lines, "正确答案：" .. option_text(item))
    table.insert(lines, "解析：" .. tostring(item.explain or ""))
    return table.concat(lines, "\n")
end

function AIVariant.build_prompt(items, per_item)
    if type(items) ~= "table" or #items == 0 then return nil, "没有可生成变种的错题" end
    per_item = tonumber(per_item) or 3
    if per_item < 1 then per_item = 1 end
    local total = #items * per_item
    local system = table.concat({
        "你是小学语文和数学老师，负责根据孩子做错的题目生成强化练习。",
        "你只输出严格 JSON，不输出 Markdown、代码围栏、解释或额外文字。",
        "题目必须适合题目标注的年级，答案唯一，不能出现个人信息、网址、广告、暴力或吓唬孩子的内容。",
    }, "\n")

    local lines = {
        string.format("请为下面 %d 道错题各生成 %d 道变种题，共 %d 道。", #items, per_item, total),
        "要求：",
        "1. 变种题必须考查同一知识点、保持原难度，不能照抄原题。",
        "2. 数学和字词题要更换数字、词语或情境；阅读题沿用原阅读材料，只改变提问角度和选项。",
        "3. 每题必须有 4 个互不相同的选项，answer 是 1 到 4 的整数。",
        "4. explain 用 4 到 100 字说明为什么，适合标注年级的孩子阅读。",
        "5. 若原题有阅读材料，可省略 passage（程序会沿用原材料）；若你改写材料，则必须返回完整 passage。",
        "6. 每道变种题必须带 origin，值是原错题的编号（从 1 开始）。",
        "",
        "只输出这个 JSON 结构：",
        '{"questions":[{"origin":1,"stem":"题干","options":["选项1","选项2","选项3","选项4"],"answer":1,"explain":"解析","passage":"可选"}]}',
        "",
        "错题如下：",
    }
    for index, item in ipairs(items) do
        table.insert(lines, describe_item(item, index))
        table.insert(lines, "")
    end
    return system, table.concat(lines, "\n")
end

local function extract_json(text)
    text = trim(text)
    text = text:gsub("^```[%w_%-]*%s*", ""):gsub("%s*```%s*$", "")
    local start = text:find("{", 1, true)
    if not start then return nil end
    local finish
    for i = #text, start, -1 do
        if text:sub(i, i) == "}" then finish = i break end
    end
    if not finish then return nil end
    return text:sub(start, finish)
end

local function normalize_key(text)
    return trim(text):lower():gsub("%s+", "")
end

local function valid_options(options)
    if type(options) ~= "table" or #options ~= 4 then return nil end
    local seen = {}
    local cleaned = {}
    for i = 1, 4 do
        local option = trim(options[i])
        if option == "" or #option > MAX_OPTION then return nil end
        if seen[option] then return nil end
        seen[option] = true
        cleaned[i] = option
    end
    return cleaned
end

function AIVariant.parse(text, items, per_item, meta)
    if type(items) ~= "table" or #items == 0 then return nil, "没有可生成变种的错题" end
    meta = meta or {}
    per_item = tonumber(per_item) or 3
    local expected = #items * per_item
    local json_text = extract_json(text)
    if not json_text then return nil, "AI 返回内容里找不到题目 JSON，请重试" end
    local ok, decoded = pcall(JSON.decode, json_text)
    if not ok or type(decoded) ~= "table" then return nil, "AI 返回的 JSON 无法解析，请重试" end
    local raw_questions = decoded.questions or decoded
    if type(raw_questions) ~= "table" or #raw_questions ~= expected then
        return nil, string.format("AI 返回的题目数量不对（需要 %d 道），请重试", expected)
    end

    local questions = {}
    local seen_stems = {}
    local counts = {}
    for index, raw in ipairs(raw_questions) do
        if type(raw) ~= "table" then return nil, "AI 返回了无效题目，请重试" end
        local origin_index = tonumber(raw.origin) or (expected == per_item and 1 or nil)
        local origin = origin_index and items[origin_index]
        if not origin then return nil, "AI 返回的题目来源编号无效，请重试" end

        local stem = trim(raw.stem)
        if stem == "" or #stem > MAX_STEM then return nil, string.format("第 %d 道变种题干无效", index) end
        local key = normalize_key(stem)
        if key == normalize_key(origin.stem) then return nil, "AI 变种不能照抄原题，请重试" end
        if seen_stems[key] then return nil, "AI 返回了重复题目，请重试" end
        seen_stems[key] = true

        local options = valid_options(raw.options)
        if not options then return nil, string.format("第 %d 道变种的四个选项无效", index) end
        local answer = tonumber(raw.answer)
        if not answer or answer < 1 or answer > 4 or answer % 1 ~= 0 then
            return nil, string.format("第 %d 道变种答案序号无效", index)
        end
        local explain = trim(raw.explain)
        if explain == "" or #explain > MAX_EXPLAIN then
            return nil, string.format("第 %d 道变种解析无效", index)
        end
        local passage = trim(raw.passage)
        if passage == "" then passage = trim(origin.passage) end
        if origin.passage and origin.passage ~= "" and passage == "" then
            return nil, string.format("第 %d 道变种缺少阅读材料", index)
        end
        if #passage > MAX_PASSAGE then return nil, string.format("第 %d 道变种阅读材料过长", index) end

        local unit = origin.unit or "ai"
        local unit_name = origin.unit_name or "AI 变种"
        local normalized, normalize_err = Bank.normalize_question({
            id = string.format("%s-q%d", tostring(meta.group_id or "aig"), index),
            unit = unit,
            type = origin.type or "choice",
            skill = origin.skill or origin.type or "choice",
            difficulty = origin.difficulty or 2,
            answer_mode = "choice",
            stem = stem,
            passage = passage ~= "" and passage or nil,
            options = options,
            answer = answer,
            explain = explain,
        }, origin.subject or "chinese", origin.grade or meta.grade or 2,
            origin.semester or meta.semester or "upper",
            origin.edition or meta.edition,
            { [unit] = true }, { [unit] = unit_name })
        if not normalized then
            return nil, string.format("第 %d 道变种无效：%s", index, tostring(normalize_err))
        end
        normalized.ai_generated = true
        normalized.origin_id = origin.id
        normalized.ai_group_id = meta.group_id
        normalized.created_at = meta.now
        normalized.competency = origin.competency
        normalized.challenge = origin.challenge
        table.insert(questions, normalized)
        counts[origin_index] = (counts[origin_index] or 0) + 1
    end

    for i = 1, #items do
        if (counts[i] or 0) ~= per_item then
            return nil, "AI 没有为每道错题生成足够变种，请重试"
        end
    end
    return questions
end

function AIVariant.new_group(items, questions, meta, profile)
    local origins = {}
    for _, item in ipairs(items) do
        table.insert(origins, {
            id = item.id,
            subject = item.subject,
            grade = item.grade,
            unit = item.unit,
            unit_name = item.unit_name,
            stem = item.stem,
            type = item.type,
        })
    end
    return {
        id = meta.group_id,
        created_at = meta.now,
        provider = {
            preset = profile and profile.preset or nil,
            name = profile and profile.name or nil,
            model = profile and profile.model or nil,
        },
        origins = origins,
        questions = questions,
    }
end

return AIVariant
