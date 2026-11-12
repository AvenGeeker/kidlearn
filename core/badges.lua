--[[--
Badge definitions and unlock checks for KidLearn.
--]]--

local Badges = {}

local Cards = require("core.cards")

local function mastered_count(p)
    local n = 0
    for _, by_topic in pairs(p.data.knowledge or {}) do
        for _, entry in pairs(by_topic) do
            if type(entry) == "table" and entry.status == "mastered" then n = n + 1 end
        end
    end
    return n
end

local definitions = {
    {
        id = "first_session",
        name = "初次闯关",
        desc = "完成第一轮练习",
        target = 1,
        value = function(p) return p.data.total.sessions end,
    },
    {
        id = "correct_20",
        name = "小试牛刀",
        desc = "累计答对 20 题",
        target = 20,
        value = function(p) return p.data.total.correct end,
    },
    {
        id = "correct_100",
        name = "百题达人",
        desc = "累计答对 100 题",
        target = 100,
        value = function(p) return p.data.total.correct end,
    },
    {
        id = "perfect_session",
        name = "满分王",
        desc = "单轮 10 题全部首次答对",
        target = 1,
        value = function(p) return p.data.total.perfect_sessions end,
    },
    {
        id = "streak_3",
        name = "三日坚持",
        desc = "连续学习 3 天",
        target = 3,
        value = function(p) return p.data.streak.best end,
    },
    {
        id = "streak_7",
        name = "一周之星",
        desc = "连续学习 7 天",
        target = 7,
        value = function(p) return p.data.streak.best end,
    },
    {
        id = "chinese_50",
        name = "识字小博士",
        desc = "语文累计答对 50 题",
        target = 50,
        value = function(p) return p.data.by_subject.chinese.correct end,
    },
    {
        id = "math_50",
        name = "口算小能手",
        desc = "数学累计答对 50 题",
        target = 50,
        value = function(p) return p.data.by_subject.math.correct end,
    },
    {
        id = "combo_10",
        name = "十连对",
        desc = "连续 10 题首次答对",
        target = 10,
        value = function(p) return p.data.total.best_combo end,
    },
    {
        id = "wrong_clear_5",
        name = "错题克星",
        desc = "掌握 5 道错题",
        target = 5,
        value = function(p) return p.data.total.wrong_cleared end,
    },
    -- v5 expansion: 40 new badges, grouped by line with rising targets.
    -- The original 10 definitions above are kept byte-for-byte unchanged.
    {
        id = "points_500",
        name = "星光闪闪",
        desc = "累计获得 500 颗星星",
        target = 500,
        category = "points",
        value = function(p) return p.data.total.points end,
    },
    {
        id = "points_2000",
        name = "星星收藏家",
        desc = "累计获得 2000 颗星星",
        target = 2000,
        category = "points",
        value = function(p) return p.data.total.points end,
    },
    {
        id = "points_5000",
        name = "星空大师",
        desc = "累计获得 5000 颗星星",
        target = 5000,
        category = "points",
        value = function(p) return p.data.total.points end,
    },
    {
        id = "points_10000",
        name = "传奇星主",
        desc = "累计获得 10000 颗星星",
        target = 10000,
        category = "points",
        value = function(p) return p.data.total.points end,
    },
    {
        id = "correct_300",
        name = "答题小勇士",
        desc = "累计答对 300 题",
        target = 300,
        category = "correct",
        value = function(p) return p.data.total.correct end,
    },
    {
        id = "correct_600",
        name = "知识小达人",
        desc = "累计答对 600 题",
        target = 600,
        category = "correct",
        value = function(p) return p.data.total.correct end,
    },
    {
        id = "correct_1000",
        name = "千题学者",
        desc = "累计答对 1000 题",
        target = 1000,
        category = "correct",
        value = function(p) return p.data.total.correct end,
    },
    {
        id = "correct_2000",
        name = "学霸之星",
        desc = "累计答对 2000 题",
        target = 2000,
        category = "correct",
        value = function(p) return p.data.total.correct end,
    },
    {
        id = "sessions_30",
        name = "勤学不倦",
        desc = "完成 30 轮练习",
        target = 30,
        category = "sessions",
        value = function(p) return p.data.total.sessions end,
    },
    {
        id = "sessions_100",
        name = "百轮勇士",
        desc = "完成 100 轮练习",
        target = 100,
        category = "sessions",
        value = function(p) return p.data.total.sessions end,
    },
    {
        id = "streak_14",
        name = "半月恒心",
        desc = "连续学习 14 天",
        target = 14,
        category = "streak",
        value = function(p) return p.data.streak.best end,
    },
    {
        id = "streak_30",
        name = "月度之星",
        desc = "连续学习 30 天",
        target = 30,
        category = "streak",
        value = function(p) return p.data.streak.best end,
    },
    {
        id = "streak_60",
        name = "双月坚持",
        desc = "连续学习 60 天",
        target = 60,
        category = "streak",
        value = function(p) return p.data.streak.best end,
    },
    {
        id = "streak_100",
        name = "百日传奇",
        desc = "连续学习 100 天",
        target = 100,
        category = "streak",
        value = function(p) return p.data.streak.best end,
    },
    {
        id = "chinese_150",
        name = "识字小硕士",
        desc = "语文累计答对 150 题",
        target = 150,
        category = "subject",
        value = function(p) return p.data.by_subject.chinese.correct end,
    },
    {
        id = "chinese_300",
        name = "语文小学者",
        desc = "语文累计答对 300 题",
        target = 300,
        category = "subject",
        value = function(p) return p.data.by_subject.chinese.correct end,
    },
    {
        id = "math_150",
        name = "口算小硕士",
        desc = "数学累计答对 150 题",
        target = 150,
        category = "subject",
        value = function(p) return p.data.by_subject.math.correct end,
    },
    {
        id = "math_300",
        name = "数学小学者",
        desc = "数学累计答对 300 题",
        target = 300,
        category = "subject",
        value = function(p) return p.data.by_subject.math.correct end,
    },
    {
        id = "combo_15",
        name = "十五连对",
        desc = "连续 15 题首次答对",
        target = 15,
        category = "combo",
        value = function(p) return p.data.total.best_combo end,
    },
    {
        id = "combo_20",
        name = "二十连对",
        desc = "连续 20 题首次答对",
        target = 20,
        category = "combo",
        value = function(p) return p.data.total.best_combo end,
    },
    {
        id = "perfect_5",
        name = "满分常客",
        desc = "单轮全部首次答对 5 次",
        target = 5,
        category = "perfect",
        value = function(p) return p.data.total.perfect_sessions end,
    },
    {
        id = "perfect_10",
        name = "满分传奇",
        desc = "单轮全部首次答对 10 次",
        target = 10,
        category = "perfect",
        value = function(p) return p.data.total.perfect_sessions end,
    },
    {
        id = "wrong_clear_15",
        name = "错题清道夫",
        desc = "掌握 15 道错题",
        target = 15,
        category = "wrong",
        value = function(p) return p.data.total.wrong_cleared end,
    },
    {
        id = "wrong_clear_30",
        name = "错题终结者",
        desc = "掌握 30 道错题",
        target = 30,
        category = "wrong",
        value = function(p) return p.data.total.wrong_cleared end,
    },
    {
        id = "challenge_1",
        name = "拓展新手",
        desc = "完成 1 轮拓展挑战",
        target = 1,
        category = "challenge",
        value = function(p) return p.data.total.challenge_sessions or 0 end,
    },
    {
        id = "challenge_5",
        name = "拓展爱好者",
        desc = "完成 5 轮拓展挑战",
        target = 5,
        category = "challenge",
        value = function(p) return p.data.total.challenge_sessions or 0 end,
    },
    {
        id = "challenge_15",
        name = "拓展小达人",
        desc = "完成 15 轮拓展挑战",
        target = 15,
        category = "challenge",
        value = function(p) return p.data.total.challenge_sessions or 0 end,
    },
    {
        id = "challenge_30",
        name = "拓展高手",
        desc = "完成 30 轮拓展挑战",
        target = 30,
        category = "challenge",
        value = function(p) return p.data.total.challenge_sessions or 0 end,
    },
    {
        id = "challenge_60",
        name = "拓展大师",
        desc = "完成 60 轮拓展挑战",
        target = 60,
        category = "challenge",
        value = function(p) return p.data.total.challenge_sessions or 0 end,
    },
    {
        id = "challenge_100",
        name = "拓展传奇",
        desc = "完成 100 轮拓展挑战",
        target = 100,
        category = "challenge",
        value = function(p) return p.data.total.challenge_sessions or 0 end,
    },
    {
        id = "challenge_correct_10",
        name = "思维萌芽",
        desc = "拓展挑战累计答对 10 题",
        target = 10,
        category = "challenge",
        value = function(p) return p.data.total.challenge_correct or 0 end,
    },
    {
        id = "challenge_correct_50",
        name = "思维小火花",
        desc = "拓展挑战累计答对 50 题",
        target = 50,
        category = "challenge",
        value = function(p) return p.data.total.challenge_correct or 0 end,
    },
    {
        id = "challenge_correct_150",
        name = "思维小火焰",
        desc = "拓展挑战累计答对 150 题",
        target = 150,
        category = "challenge",
        value = function(p) return p.data.total.challenge_correct or 0 end,
    },
    {
        id = "challenge_correct_300",
        name = "思维小太阳",
        desc = "拓展挑战累计答对 300 题",
        target = 300,
        category = "challenge",
        value = function(p) return p.data.total.challenge_correct or 0 end,
    },
    {
        id = "kp_mastered_10",
        name = "知识点小收藏",
        desc = "掌握 10 个知识点",
        target = 10,
        category = "knowledge",
        value = function(p) return mastered_count(p) end,
    },
    {
        id = "kp_mastered_30",
        name = "知识点小达人",
        desc = "掌握 30 个知识点",
        target = 30,
        category = "knowledge",
        value = function(p) return mastered_count(p) end,
    },
    {
        id = "kp_mastered_60",
        name = "知识点小博士",
        desc = "掌握 60 个知识点",
        target = 60,
        category = "knowledge",
        value = function(p) return mastered_count(p) end,
    },
    {
        id = "card_s_1",
        name = "稀有卡新手",
        desc = "收集 1 张 S 级及以上卡片",
        target = 1,
        category = "cards",
        value = function(p) return Cards.owned_at_least(p, "S") end,
    },
    {
        id = "card_types_15",
        name = "集卡小行家",
        desc = "收集 15 种不同的卡片",
        target = 15,
        category = "cards",
        value = function(p) return Cards.owned_types(p) end,
    },
    {
        id = "card_sss_1",
        name = "传说收藏家",
        desc = "收集 1 张 SSS 级卡片",
        target = 1,
        category = "cards",
        value = function(p) return Cards.owned_at_least(p, "SSS") end,
    },
}

function Badges.all()
    return definitions
end

function Badges.evaluate(progress)
    local unlocked = {}
    for _, badge in ipairs(definitions) do
        if not progress.data.badges[badge.id] then
            local value = badge.value(progress) or 0
            if value >= badge.target then
                progress.data.badges[badge.id] = os.time()
                table.insert(unlocked, badge)
            end
        end
    end
    if #unlocked > 0 then progress:flush() end
    return unlocked
end

function Badges.state(progress)
    local state = {}
    for _, badge in ipairs(definitions) do
        local unlocked_at = progress.data.badges[badge.id]
        local value = badge.value(progress) or 0
        table.insert(state, {
            id = badge.id,
            name = badge.name,
            desc = badge.desc,
            target = badge.target,
            value = math.min(value, badge.target),
            unlocked = unlocked_at ~= nil,
            unlocked_at = unlocked_at,
        })
    end
    return state
end

function Badges.count(progress)
    local n = 0
    for _, badge in ipairs(definitions) do
        if progress.data.badges[badge.id] then n = n + 1 end
    end
    return n
end

--[[--
Number of unlocked challenge-line badges; feeds the SSS draw weight.
--]]--
function Badges.challenge_unlocked(progress)
    local n = 0
    for _, badge in ipairs(definitions) do
        if badge.category == "challenge" and progress.data.badges[badge.id] then
            n = n + 1
        end
    end
    return n
end

function Badges.get(id)
    for _, badge in ipairs(definitions) do
        if badge.id == id then return badge end
    end
    return nil
end

return Badges
