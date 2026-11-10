--[[--
Badge definitions and unlock checks for KidLearn.
--]]--

local Badges = {}

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

function Badges.get(id)
    for _, badge in ipairs(definitions) do
        if badge.id == id then return badge end
    end
    return nil
end

return Badges
