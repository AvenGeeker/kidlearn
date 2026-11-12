--[[--
Collectible card pool and daily draw logic for KidLearn.

The pool is fixed in code: card ids are permanent and never reused. Rarity is
rolled locally from the daily score plus unlocked challenge badges; the AI
subsystem only writes flavor text, never decides rarity.
--]]--

local Cards = {}

Cards.TIERS = { "R", "RR", "S", "SS", "SSS" }
local TIER_RANK = { R = 1, RR = 2, S = 3, SS = 4, SSS = 5 }

Cards.DAILY_COUNT = 3
-- S and above (including SSS) is capped per day; with 3 draws this always holds.
Cards.HIGH_TIER_DAILY_CAP = 3

local pool = {
    { id = "r01", tier = "R", name = "小麻雀", desc = "叽叽喳喳，每天早起陪你读书。" },
    { id = "r02", tier = "R", name = "小蚂蚁", desc = "个子小小，力气大大，坚持就是力量。" },
    { id = "r03", tier = "R", name = "小蜗牛", desc = "慢慢走，不停步，总有一天到山顶。" },
    { id = "r04", tier = "R", name = "小金鱼", desc = "摇着尾巴，把烦恼都吐成泡泡。" },
    { id = "r05", tier = "R", name = "小瓢虫", desc = "数数身上的小圆点，今天又进步一点。" },
    { id = "r06", tier = "R", name = "小蜻蜓", desc = "飞得轻快，脑筋转得更快。" },
    { id = "r07", tier = "R", name = "小刺猬", desc = "背上扎满果子，心里装满知识。" },
    { id = "r08", tier = "R", name = "小松鼠", desc = "把松果藏好，把知识记牢。" },
    { id = "r09", tier = "R", name = "小青蛙", desc = "呱呱呱，为每一道答对的题鼓掌。" },
    { id = "r10", tier = "R", name = "小企鹅", desc = "摇摇摆摆，也要走到终点。" },
    { id = "r11", tier = "R", name = "小考拉", desc = "抱抱大树，做个甜甜的梦。" },
    { id = "r12", tier = "R", name = "小熊猫", desc = "抱着竹子打滚，学习也要开开心心。" },
    { id = "rr01", tier = "RR", name = "小海豚", desc = "跳出水面，为你画一道彩虹。" },
    { id = "rr02", tier = "RR", name = "小狐狸", desc = "眼睛一转，想出一个好办法。" },
    { id = "rr03", tier = "RR", name = "小梅花鹿", desc = "踩着梅花脚印，一步步向前。" },
    { id = "rr04", tier = "RR", name = "小猫头鹰", desc = "夜晚也睁大眼睛，爱动脑筋。" },
    { id = "rr05", tier = "RR", name = "小海龟", desc = "游得稳，走得远，坚持就是胜利。" },
    { id = "rr06", tier = "RR", name = "小浣熊", desc = "把问题洗一洗，答案就清楚了。" },
    { id = "rr07", tier = "RR", name = "小袋鼠", desc = "一跳一跳，跳过一个个小困难。" },
    { id = "rr08", tier = "RR", name = "小天鹅", desc = "张开翅膀，飞向更高的目标。" },
    { id = "rr09", tier = "RR", name = "小鹦鹉", desc = "把学到的知识，大声说出来。" },
    { id = "rr10", tier = "RR", name = "小雪豹", desc = "安静又专注，看准目标再出发。" },
    { id = "s01", tier = "S", name = "小老虎", desc = "威风凛凛，难题见了绕道走。" },
    { id = "s02", tier = "S", name = "小雄鹰", desc = "飞得高，看得远，难题变简单。" },
    { id = "s03", tier = "S", name = "小骏马", desc = "哒哒哒，向着目标全力奔跑。" },
    { id = "s04", tier = "S", name = "小狮子", desc = "吼一声，困难都吓跑啦。" },
    { id = "s05", tier = "S", name = "小鲸鱼", desc = "大大的肚子里，装着大大的智慧。" },
    { id = "s06", tier = "S", name = "小大象", desc = "鼻子长，记性好，学过的都记得。" },
    { id = "s07", tier = "S", name = "小长颈鹿", desc = "伸长脖子，看到更远的风景。" },
    { id = "s08", tier = "S", name = "小棕熊", desc = "力气大，肯下功夫，收获满满。" },
    { id = "ss01", tier = "SS", name = "小凤凰", desc = "展开火焰翅膀，照亮学习的路。" },
    { id = "ss02", tier = "SS", name = "小麒麟", desc = "踏着祥云，把好运送给你。" },
    { id = "ss03", tier = "SS", name = "小独角兽", desc = "角上闪着星光，梦想成真。" },
    { id = "ss04", tier = "SS", name = "小青龙", desc = "呼风唤雨，难题统统让路。" },
    { id = "ss05", tier = "SS", name = "小玄武", desc = "稳稳当当，知识坚如磐石。" },
    { id = "sss01", tier = "SSS", name = "智慧星龙", desc = "从星星上飞来的龙，把智慧洒满人间。" },
    { id = "sss02", tier = "SSS", name = "月光麒麟", desc = "踏着月光而来，守护爱学习的孩子。" },
    { id = "sss03", tier = "SSS", name = "彩虹独角兽", desc = "飞过彩虹桥，把最美的祝福送给你。" },
}

local by_id = {}
for _, card in ipairs(pool) do by_id[card.id] = card end

-- Score bands: higher daily score shifts weight toward rarer tiers.
local BANDS = {
    { min = 90, weights = { R = 28, RR = 30, S = 28, SS = 14 } },
    { min = 70, weights = { R = 40, RR = 30, S = 22, SS = 8 } },
    { min = 40, weights = { R = 55, RR = 28, S = 14, SS = 3 } },
    { min = 0,  weights = { R = 70, RR = 22, S = 7, SS = 1 } },
}

function Cards.all()
    return pool
end

function Cards.get(id)
    return by_id[id]
end

function Cards.tier_rank(tier)
    return TIER_RANK[tier] or 0
end

function Cards.band_weights(score)
    score = tonumber(score) or 0
    for _, band in ipairs(BANDS) do
        if score >= band.min then return band.weights end
    end
    return BANDS[#BANDS].weights
end

--[[--
SSS is challenge-exclusive: weight is zero until at least one challenge badge
is unlocked, then grows with badge count and the daily score.
--]]--
function Cards.sss_weight(score, challenge_badges)
    challenge_badges = tonumber(challenge_badges) or 0
    if challenge_badges <= 0 then return 0 end
    score = tonumber(score) or 0
    if score < 0 then score = 0 end
    return challenge_badges * (1 + math.floor(score / 50))
end

local function pick_tier(weights, sss, roll)
    local acc = 0
    for _, tier in ipairs({ "R", "RR", "S", "SS" }) do
        acc = acc + weights[tier]
        if roll <= acc then return tier end
    end
    if sss > 0 and roll <= acc + sss then return "SSS" end
    return "SS"
end

--[[--
Draw the fixed daily hand. Each card rolls its tier independently, then picks
uniformly inside the tier. rng(n) must return an integer in 1..n (injectable
for tests). Duplicates are allowed and only bump the collection count.
--]]--
function Cards.draw(score, challenge_badges, rng)
    rng = rng or math.random
    score = tonumber(score) or 0
    local weights = Cards.band_weights(score)
    local sss = Cards.sss_weight(score, challenge_badges)
    local total = weights.R + weights.RR + weights.S + weights.SS + sss
    local result = {}
    local high = 0
    for _ = 1, Cards.DAILY_COUNT do
        local tier = pick_tier(weights, sss, rng(total))
        if Cards.tier_rank(tier) >= TIER_RANK.S then
            if high >= Cards.HIGH_TIER_DAILY_CAP then
                tier = "RR"
            else
                high = high + 1
            end
        end
        local candidates = {}
        for _, card in ipairs(pool) do
            if card.tier == tier then table.insert(candidates, card) end
        end
        local pick = candidates[rng(#candidates)]
        table.insert(result, { id = pick.id, tier = pick.tier, name = pick.name, desc = pick.desc })
    end
    return result
end

--[[--
Collection projection for the card book: every pool card plus any legacy
entries whose id is no longer in the pool (kept visible, never deleted).
@treturn table state list, number owned types
--]]--
function Cards.collection_state(progress)
    local owned = progress.data.cards or {}
    local state = {}
    local count = 0
    for _, card in ipairs(pool) do
        local entry = owned[card.id]
        local has = type(entry) == "table" and (entry.count or 0) > 0
        if has then count = count + 1 end
        table.insert(state, {
            id = card.id,
            tier = card.tier,
            name = (has and entry.name) or card.name,
            desc = card.desc,
            count = has and entry.count or 0,
            owned = has,
        })
    end
    for id, entry in pairs(owned) do
        if not by_id[id] and type(entry) == "table" and (entry.count or 0) > 0 then
            count = count + 1
            table.insert(state, {
                id = id,
                tier = entry.tier or "R",
                name = entry.name or id,
                desc = "",
                count = entry.count,
                owned = true,
                legacy = true,
            })
        end
    end
    return state, count
end

function Cards.owned_types(progress)
    local n = 0
    for _, entry in pairs(progress.data.cards or {}) do
        if type(entry) == "table" and (entry.count or 0) > 0 then n = n + 1 end
    end
    return n
end

-- Number of owned card types at or above the given tier (snapshot tier wins
-- for legacy cards no longer present in the pool).
function Cards.owned_at_least(progress, tier)
    local rank = TIER_RANK[tier] or 0
    local n = 0
    for id, entry in pairs(progress.data.cards or {}) do
        if type(entry) == "table" and (entry.count or 0) > 0 then
            local card = by_id[id]
            local entry_tier = (card and card.tier) or entry.tier
            if (TIER_RANK[entry_tier] or 0) >= rank then n = n + 1 end
        end
    end
    return n
end

return Cards
