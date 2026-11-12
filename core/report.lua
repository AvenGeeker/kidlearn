--[[--
Daily learning report for KidLearn.

Scoring and the card draw are fully local and reproducible; the AI subsystem
only polishes the summary text and card blessings. The report is committed to
the daily save entry (offline template first) before any network request, so a
failed or absent AI call never loses the draw. Model output is untrusted and
validated strictly, mirroring core/ai_variant.lua.
--]]--

local JSON = require("json")
local Badges = require("core.badges")
local Cards = require("core.cards")
local Knowledge = require("core.knowledge")

local Report = {}

local SUBJECT_LABEL = { chinese = "语文", math = "数学" }
local MODE_LABEL = {
    daily = "今日挑战", subject = "单科练习", challenge = "拓展挑战",
    wrong = "错题复习", ai = "AI 变种练习", kp = "知识点学习",
}
local MAX_SUMMARY_CHARS = 400
local MAX_WORD_CHARS = 80

local function trim(value)
    if type(value) ~= "string" then return "" end
    return value:match("^%s*(.-)%s*$") or ""
end

-- UTF-8 character count without the Lua 5.2 utf8 library.
local function char_len(text)
    local _, count = text:gsub("[^\128-\191]", "")
    return count
end

function Report.grade_label(score)
    score = tonumber(score) or 0
    if score >= 90 then return "超赞" end
    if score >= 75 then return "很棒" end
    if score >= 60 then return "不错" end
    return "继续加油"
end

--[[--
Local daily score, 0..100.

30 goal completion + 30 first-try accuracy + 15 rounds (max 3)
+ 10 challenge rounds (max 2) + 5 knowledge answers (max 5)
+ 10 streak (max 7 days). The sum is rounded once.
--]]--
function Report.score(progress, now)
    local daily = progress:ensure_daily(now)
    local settings = progress.data.settings
    local goal = tonumber(settings.daily_goal) or 10
    local answered = daily.answered or 0
    local correct = daily.correct or 0
    local sessions = daily.sessions or 0
    local challenge_sessions = daily.challenge and daily.challenge.sessions or 0
    local kp_answered = daily.kp_answered or 0
    local streak = progress.data.streak.current or 0

    local goal_part = goal > 0 and 30 * math.min(answered / goal, 1) or 0
    local accuracy_part = answered > 0 and 30 * correct / answered or 0
    local raw = goal_part + accuracy_part
        + 5 * math.min(sessions, 3)
        + 5 * math.min(challenge_sessions, 2)
        + math.min(kp_answered, 5)
        + 10 * math.min(streak, 7) / 7
    local score = math.floor(raw + 0.5)
    if score < 0 then score = 0 elseif score > 100 then score = 100 end
    return {
        score = score,
        parts = {
            goal = math.floor(goal_part + 0.5),
            accuracy = math.floor(accuracy_part + 0.5),
            sessions = 5 * math.min(sessions, 3),
            challenge = 5 * math.min(challenge_sessions, 2),
            kp = math.min(kp_answered, 5),
            streak = math.floor(10 * math.min(streak, 7) / 7 + 0.5),
        },
    }
end

--[[--
Aggregate today's facts for the prompt and the offline template. Only
aggregate stats and topic names are exposed; never keys or personal data.
--]]--
function Report.stats(progress, now, plugin_path)
    local daily = progress:ensure_daily(now)
    local settings = progress.data.settings
    local subjects = {}
    for _, subject in ipairs({ "chinese", "math" }) do
        local s = daily.subjects and daily.subjects[subject]
        subjects[subject] = { answered = s and s.answered or 0, correct = s and s.correct or 0 }
    end
    local modes = {}
    for mode, count in pairs(daily.modes or {}) do modes[mode] = count end
    local topics = {}
    for _, item in ipairs(daily.kp_topics or {}) do
        local name = item.topic
        if plugin_path then
            local graph = Knowledge.graph(plugin_path, item.subject)
            local node = graph and graph.nodes and graph.nodes[item.topic]
            if node and node.name then name = node.name end
        end
        table.insert(topics, { subject = item.subject, name = name })
    end
    return {
        date = os.date("%Y-%m-%d", now or os.time()),
        grade = settings.grade,
        goal = settings.daily_goal,
        answered = daily.answered or 0,
        correct = daily.correct or 0,
        points = daily.points or 0,
        sessions = daily.sessions or 0,
        subjects = subjects,
        modes = modes,
        challenge = {
            sessions = daily.challenge and daily.challenge.sessions or 0,
            answered = daily.challenge and daily.challenge.answered or 0,
            correct = daily.challenge and daily.challenge.correct or 0,
        },
        kp_answered = daily.kp_answered or 0,
        topics = topics,
        streak = progress.data.streak.current or 0,
    }
end

function Report.offline(stats, cards)
    local lines = {}
    table.insert(lines, string.format("今天完成了 %d 轮练习，回答 %d 道题，首次答对 %d 道，收获 %d 颗星星。",
        stats.sessions, stats.answered, stats.correct, stats.points))
    local subject_parts = {}
    for _, subject in ipairs({ "chinese", "math" }) do
        local s = stats.subjects[subject]
        if s.answered > 0 then
            table.insert(subject_parts, string.format("%s答对 %d/%d", SUBJECT_LABEL[subject], s.correct, s.answered))
        end
    end
    if #subject_parts > 0 then
        table.insert(lines, "其中" .. table.concat(subject_parts, "，") .. "。")
    end
    if stats.challenge.sessions > 0 then
        table.insert(lines, string.format("拓展挑战完成 %d 轮，答对 %d 题，脑筋越动越灵活！",
            stats.challenge.sessions, stats.challenge.correct))
    end
    if #stats.topics > 0 then
        local names = {}
        for i = 1, math.min(#stats.topics, 5) do table.insert(names, stats.topics[i].name) end
        table.insert(lines, "还学习了知识点：" .. table.concat(names, "、") .. "。")
    end
    if stats.streak > 0 then
        table.insert(lines, string.format("已经连续学习 %d 天，坚持就是进步！", stats.streak))
    end
    table.insert(lines, "明天继续加油，小卡片们都在等你！")
    local words = {}
    for _, card in ipairs(cards or {}) do table.insert(words, card.desc or "") end
    return { summary = table.concat(lines, ""), card_words = words }
end

function Report.build_prompt(stats, score, cards)
    local system = table.concat({
        "你是小学学习助手，负责为孩子总结一天的学习情况。",
        "你只输出严格 JSON，不输出 Markdown、代码围栏、解释或额外文字。",
        "文案必须积极鼓励、适合小学生阅读，不能出现负面、吓唬孩子的内容，不能出现个人信息、网址或广告。",
    }, "\n")
    local lines = {
        string.format("今天是 %s，孩子读 %s 年级，今日评分 %d 分（满分 100）。",
            stats.date, tostring(stats.grade), tonumber(score) or 0),
        string.format("答题：共 %d 道，首次答对 %d 道；完成 %d 轮练习；获得 %d 颗星星；每日目标 %s 题。",
            stats.answered, stats.correct, stats.sessions, stats.points, tostring(stats.goal)),
    }
    for _, subject in ipairs({ "chinese", "math" }) do
        local s = stats.subjects[subject]
        if s.answered > 0 then
            table.insert(lines, string.format("%s：回答 %d 道，首次答对 %d 道。", SUBJECT_LABEL[subject], s.answered, s.correct))
        end
    end
    local mode_parts = {}
    for mode, count in pairs(stats.modes) do
        if count > 0 then
            table.insert(mode_parts, string.format("%s %d 轮", MODE_LABEL[mode] or mode, count))
        end
    end
    if #mode_parts > 0 then
        table.insert(lines, "玩法：" .. table.concat(mode_parts, "，") .. "。")
    end
    if stats.challenge.sessions > 0 then
        table.insert(lines, string.format("拓展挑战：完成 %d 轮，答对 %d/%d 题。",
            stats.challenge.sessions, stats.challenge.correct, stats.challenge.answered))
    end
    if #stats.topics > 0 then
        local names = {}
        for _, topic in ipairs(stats.topics) do table.insert(names, topic.name) end
        table.insert(lines, "学过的知识点：" .. table.concat(names, "、") .. "。")
    end
    if stats.streak > 0 then
        table.insert(lines, string.format("已连续学习 %d 天。", stats.streak))
    end
    table.insert(lines, "今天抽到的卡片（按顺序）：")
    for index, card in ipairs(cards or {}) do
        table.insert(lines, string.format("%d. 【%s】%s", index, card.tier, card.name))
    end
    table.insert(lines, "")
    table.insert(lines, "请写一段 80 到 200 字的总结（summary）：夸夸孩子今天的努力和进步，再给一句明天的鼓励。")
    table.insert(lines, "再为每张卡片写一句不超过 40 字的祝福语（card_words），按卡片顺序，结合今天的表现。")
    table.insert(lines, "只输出这个 JSON 结构：")
    table.insert(lines, '{"summary":"总结","card_words":["卡片1祝福","卡片2祝福","卡片3祝福"]}')
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

--[[--
Validate the AI report payload. Returns nil, err on any violation so the
caller can fall back to the offline template.
--]]--
function Report.parse(text, card_count)
    card_count = tonumber(card_count) or Cards.DAILY_COUNT
    local payload = extract_json(text)
    if not payload then return nil, "AI 返回内容不是 JSON" end
    local ok, decoded = pcall(JSON.decode, payload)
    if not ok or type(decoded) ~= "table" then return nil, "AI 返回内容无法解析" end
    local summary = trim(decoded.summary)
    if summary == "" then return nil, "AI 没有返回总结" end
    if char_len(summary) > MAX_SUMMARY_CHARS then return nil, "AI 总结过长" end
    local words = decoded.card_words
    if type(words) ~= "table" or #words ~= card_count then return nil, "AI 祝福语数量不对" end
    local cleaned = {}
    for i = 1, card_count do
        local word = trim(words[i])
        if word == "" then return nil, "AI 祝福语为空" end
        if char_len(word) > MAX_WORD_CHARS then return nil, "AI 祝福语过长" end
        cleaned[i] = word
    end
    return { summary = summary, card_words = cleaned }
end

--[[--
Create today's report: score locally, draw cards, commit the offline version
to the save first, then return it for optional AI polishing.
@tparam table opts { now, rng, plugin_path }
--]]--
function Report.create(progress, opts)
    opts = opts or {}
    local now = opts.now or os.time()
    local score_info = Report.score(progress, now)
    local challenge_badges = Badges.challenge_unlocked(progress)
    local cards = Cards.draw(score_info.score, challenge_badges, opts.rng)
    progress:add_cards(cards, now)
    local stats = Report.stats(progress, now, opts.plugin_path)
    local offline = Report.offline(stats, cards)
    local report = {
        score = score_info.score,
        parts = score_info.parts,
        cards = cards,
        summary = offline.summary,
        card_words = offline.card_words,
        ai = false,
        revealed = false,
        created_at = now,
    }
    progress:save_daily_report(report, now)
    return report
end

return Report
