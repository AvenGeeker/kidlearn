--[[--
Collectible card pool and daily draw logic for KidLearn.

The pool is fixed in code: card ids are permanent and never reused. Rarity is
rolled locally from the daily score plus unlocked challenge badges; the AI
subsystem only writes flavor text, never decides rarity. Each card carries
attack/defense stats and an ability line; the collection's total power adds a
capped bonus to the daily score (see core/report.lua).
--]]--

local Cards = {}

Cards.TIERS = { "R", "RR", "S", "SS", "SSS" }
local TIER_RANK = { R = 1, RR = 2, S = 3, SS = 4, SSS = 5 }

Cards.DAILY_COUNT = 3
-- S and above (including SSS) is capped per day; with 3 draws this always holds.
Cards.HIGH_TIER_DAILY_CAP = 3

local pool = {
    { id = "r01", tier = "R", name = "小麻雀", desc = "叽叽喳喳，每天早起陪你读书。", atk = 14, def = 12, ability = "早起鸟：每天清晨的第一声加油。" },
    { id = "r02", tier = "R", name = "小蚂蚁", desc = "个子小小，力气大大，坚持就是力量。", atk = 26, def = 14, ability = "小小大力士：能搬动比自己重很多的食物。" },
    { id = "r03", tier = "R", name = "小蜗牛", desc = "慢慢走，不停步，总有一天到山顶。", atk = 10, def = 26, ability = "稳步前行：再陡的坡也不停下脚步。" },
    { id = "r04", tier = "R", name = "小金鱼", desc = "摇着尾巴，把烦恼都吐成泡泡。", atk = 12, def = 16, ability = "泡泡魔法：把烦恼都吐成泡泡飞走。" },
    { id = "r05", tier = "R", name = "小瓢虫", desc = "数数身上的小圆点，今天又进步一点。", atk = 16, def = 18, ability = "数点点：背上每个圆点都是进步的小记号。" },
    { id = "r06", tier = "R", name = "小蜻蜓", desc = "飞得轻快，脑筋转得更快。", atk = 22, def = 12, ability = "急转弯：脑筋转得和飞行一样快。" },
    { id = "r07", tier = "R", name = "小刺猬", desc = "背上扎满果子，心里装满知识。", atk = 18, def = 24, ability = "果子搬运工：背上扎满果子和知识。" },
    { id = "r08", tier = "R", name = "小松鼠", desc = "把松果藏好，把知识记牢。", atk = 16, def = 20, ability = "记忆大师：藏好的松果一个都忘不了。" },
    { id = "r09", tier = "R", name = "小青蛙", desc = "呱呱呱，为每一道答对的题鼓掌。", atk = 18, def = 14, ability = "鼓掌队长：为每道答对的题呱呱喝彩。" },
    { id = "r10", tier = "R", name = "小企鹅", desc = "摇摇摆摆，也要走到终点。", atk = 12, def = 24, ability = "摇摆行者：摇摇摆摆也要走到终点。" },
    { id = "r11", tier = "R", name = "小考拉", desc = "抱抱大树，做个甜甜的梦。", atk = 10, def = 22, ability = "甜甜梦：抱抱大树，做个甜甜的梦充电。" },
    { id = "r12", tier = "R", name = "小熊猫", desc = "抱着竹子打滚，学习也要开开心心。", atk = 14, def = 18, ability = "开心果：抱着竹子打滚，学习也开心。" },
    { id = "rr01", tier = "RR", name = "小海豚", desc = "跳出水面，为你画一道彩虹。", atk = 38, def = 34, ability = "彩虹画师：跳出水面为你画一道彩虹。" },
    { id = "rr02", tier = "RR", name = "小狐狸", desc = "眼睛一转，想出一个好办法。", atk = 42, def = 30, ability = "点子王：眼睛一转就想出好办法。" },
    { id = "rr03", tier = "RR", name = "小梅花鹿", desc = "踩着梅花脚印，一步步向前。", atk = 34, def = 38, ability = "梅花步：踩着梅花脚印一步步向前。" },
    { id = "rr04", tier = "RR", name = "小猫头鹰", desc = "夜晚也睁大眼睛，爱动脑筋。", atk = 40, def = 36, ability = "夜思者：夜晚也睁大眼睛爱动脑筋。" },
    { id = "rr05", tier = "RR", name = "小海龟", desc = "游得稳，走得远，坚持就是胜利。", atk = 30, def = 50, ability = "耐力冠军：游得稳走得远，从不放弃。" },
    { id = "rr06", tier = "RR", name = "小浣熊", desc = "把问题洗一洗，答案就清楚了。", atk = 36, def = 34, ability = "清洗师：把问题洗一洗，答案就清楚。" },
    { id = "rr07", tier = "RR", name = "小袋鼠", desc = "一跳一跳，跳过一个个小困难。", atk = 44, def = 32, ability = "跳跃之星：一跳跳过一个小困难。" },
    { id = "rr08", tier = "RR", name = "小天鹅", desc = "张开翅膀，飞向更高的目标。", atk = 38, def = 36, ability = "高飞者：张开翅膀飞向更高的目标。" },
    { id = "rr09", tier = "RR", name = "小鹦鹉", desc = "把学到的知识，大声说出来。", atk = 36, def = 32, ability = "小小演说家：把学到的知识大声说出来。" },
    { id = "rr10", tier = "RR", name = "小雪豹", desc = "安静又专注，看准目标再出发。", atk = 46, def = 38, ability = "专注猎手：安静专注，看准目标再出发。" },
    { id = "s01", tier = "S", name = "小老虎", desc = "威风凛凛，难题见了绕道走。", atk = 68, def = 54, ability = "威风凛凛：难题见了都要绕道走。" },
    { id = "s02", tier = "S", name = "小雄鹰", desc = "飞得高，看得远，难题变简单。", atk = 64, def = 52, ability = "千里眼：飞得高看得远，难题变简单。" },
    { id = "s03", tier = "S", name = "小骏马", desc = "哒哒哒，向着目标全力奔跑。", atk = 66, def = 50, ability = "全力奔跑：哒哒哒向着目标冲刺。" },
    { id = "s04", tier = "S", name = "小狮子", desc = "吼一声，困难都吓跑啦。", atk = 70, def = 56, ability = "狮吼功：吼一声，困难都吓跑啦。" },
    { id = "s05", tier = "S", name = "小鲸鱼", desc = "大大的肚子里，装着大大的智慧。", atk = 56, def = 66, ability = "智慧海洋：大肚子里装着大智慧。" },
    { id = "s06", tier = "S", name = "小大象", desc = "鼻子长，记性好，学过的都记得。", atk = 58, def = 68, ability = "超级记忆：鼻子长记性好，学过都记得。" },
    { id = "s07", tier = "S", name = "小长颈鹿", desc = "伸长脖子，看到更远的风景。", atk = 54, def = 60, ability = "长脖瞭望：伸长脖子看到更远的风景。" },
    { id = "s08", tier = "S", name = "小棕熊", desc = "力气大，肯下功夫，收获满满。", atk = 66, def = 62, ability = "大力士：力气大肯下功夫，收获满满。" },
    { id = "ss01", tier = "SS", name = "小凤凰", desc = "展开火焰翅膀，照亮学习的路。", atk = 88, def = 76, ability = "火焰翅膀：展开火翅照亮学习的路。" },
    { id = "ss02", tier = "SS", name = "小麒麟", desc = "踏着祥云，把好运送给你。", atk = 80, def = 84, ability = "祥云祝福：踏着祥云把好运送给你。" },
    { id = "ss03", tier = "SS", name = "小独角兽", desc = "角上闪着星光，梦想成真。", atk = 84, def = 78, ability = "星光愿望：角上闪着星光，梦想成真。" },
    { id = "ss04", tier = "SS", name = "小青龙", desc = "呼风唤雨，难题统统让路。", atk = 90, def = 80, ability = "呼风唤雨：难题统统让路。" },
    { id = "ss05", tier = "SS", name = "小玄武", desc = "稳稳当当，知识坚如磐石。", atk = 72, def = 90, ability = "磐石守护：稳稳当当，知识坚如磐石。" },
    { id = "sss01", tier = "SSS", name = "智慧星龙", desc = "从星星上飞来的龙，把智慧洒满人间。", atk = 100, def = 92, ability = "星辰智慧：从星星上飞来，把智慧洒满人间。" },
    { id = "sss02", tier = "SSS", name = "月光麒麟", desc = "踏着月光而来，守护爱学习的孩子。", atk = 94, def = 100, ability = "月光守护：踏着月光，守护爱学习的孩子。" },
    { id = "sss03", tier = "SSS", name = "彩虹独角兽", desc = "飞过彩虹桥，把最美的祝福送给你。", atk = 96, def = 96, ability = "彩虹祝福：飞过彩虹桥，送出最美的祝福。" },
}

local by_id = {}
for _, card in ipairs(pool) do by_id[card.id] = card end

-- Legacy cards no longer in the pool keep a modest default power so old
-- collections never lose value.
local LEGACY_ATK, LEGACY_DEF, LEGACY_ABILITY = 10, 10, "神秘旧卡"

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
            atk = card.atk,
            def = card.def,
            ability = card.ability,
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
                atk = LEGACY_ATK,
                def = LEGACY_DEF,
                ability = LEGACY_ABILITY,
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

--[[--
Stats for one card id: attack, defense and ability text. Pool cards use their
own values; legacy ids fall back to the modest default. Stats are derived from
the pool (like desc), so no save migration is needed.
--]]--
function Cards.stats(id)
    local card = by_id[id]
    if card then return card.atk, card.def, card.ability end
    return LEGACY_ATK, LEGACY_DEF, LEGACY_ABILITY
end

--[[--
Total attack/defense of the collection. Each owned type counts once
(duplicates only bump the count). Feeds the daily score bonus.
@treturn number total attack, number total defense
--]]--
function Cards.collection_power(progress)
    local atk, def = 0, 0
    for id, entry in pairs(progress.data.cards or {}) do
        if type(entry) == "table" and (entry.count or 0) > 0 then
            local a, d = Cards.stats(id)
            atk = atk + a
            def = def + d
        end
    end
    return atk, def
end

return Cards
