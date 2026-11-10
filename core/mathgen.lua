--[[--
Procedural grade-2 math questions.

Every generator returns the same question shape used by the Chinese bank.
The optional rng argument makes the generators deterministic in unit tests.
--]]--

local MathGen = {}
local Catalog = require("core.catalog")

local plugin_path = "./plugins/kidlearn.koplugin"
local decorate_question

local seq = 0
local NAMES = { "小明", "小红", "小刚", "小丽", "小华", "小军" }

local unit_names = {
    upper = {
        { id = "m1", name = "长度单位" },
        { id = "m2", name = "100以内的加法和减法" },
        { id = "m3", name = "角的初步认识" },
        { id = "m4", name = "表内乘法（一）" },
        { id = "m5", name = "观察物体（一）" },
        { id = "m6", name = "表内乘法（二）" },
        { id = "m7", name = "认识时间" },
        { id = "m8", name = "数学广角——搭配" },
    },
    lower = {
        { id = "m1", name = "数据收集整理" },
        { id = "m2", name = "表内除法（一）" },
        { id = "m3", name = "图形的运动（一）" },
        { id = "m4", name = "表内除法（二）" },
        { id = "m5", name = "混合运算" },
        { id = "m6", name = "有余数的除法" },
        { id = "m7", name = "万以内数的认识" },
        { id = "m8", name = "克和千克" },
        { id = "m9", name = "数学广角——推理" },
    },
}

local function ri(rng, a, b)
    if b < a then a, b = b, a end
    local value = a + rng(b - a + 1) - 1
    if value < a then value = a elseif value > b then value = b end
    return value
end

local function pick(rng, list)
    return list[ri(rng, 1, #list)]
end

local function shuffle(rng, list)
    for i = #list, 2, -1 do
        local j = ri(rng, 1, i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

local function build_choice(correct, distractors, rng)
    local options = { correct }
    local seen = { [correct] = true }
    for _, value in ipairs(distractors) do
        if #options >= 4 then break end
        if not seen[value] then
            seen[value] = true
            table.insert(options, value)
        end
    end
    local fallbacks = { "以上都不对", "无法确定", "其他答案", "都不正确" }
    for _, value in ipairs(fallbacks) do
        if #options >= 4 then break end
        if not seen[value] then
            seen[value] = true
            table.insert(options, value)
        end
    end
    local guard = 0
    while #options < 4 and guard < 20 do
        guard = guard + 1
        local value = "其他" .. guard
        if not seen[value] then
            seen[value] = true
            table.insert(options, value)
        end
    end
    shuffle(rng, options)
    local answer = 1
    for i, value in ipairs(options) do
        if value == correct then answer = i end
    end
    return options, answer
end

local function next_id(unit, skill)
    seq = seq + 1
    return string.format("math:%s:%s:%d:%d", unit, skill, os.time(), seq)
end

local function number_q(semester, unit, skill, difficulty, stem, answer, explain, unit_hint)
    return {
        id = next_id(unit, skill),
        subject = "math",
        semester = semester,
        unit = unit,
        type = "math_number",
        skill = skill,
        difficulty = difficulty,
        answer_mode = "number",
        stem = stem,
        answer = answer,
        unit_hint = unit_hint,
        explain = explain,
    }
end

local function choice_q(semester, unit, skill, difficulty, stem, correct, distractors, explain, rng)
    local options, answer = build_choice(correct, distractors, rng)
    return {
        id = next_id(unit, skill),
        subject = "math",
        semester = semester,
        unit = unit,
        type = "math_choice",
        skill = skill,
        difficulty = difficulty,
        answer_mode = "choice",
        stem = stem,
        options = options,
        answer = answer,
        explain = explain,
    }
end

local function add_sub(rng, difficulty)
    local a, b, answer, symbol
    if difficulty == 1 then
        a = ri(rng, 11, 39)
        b = ri(rng, 11, 39)
        if a + b > 99 then b = 99 - a end
    elseif difficulty == 2 then
        a = ri(rng, 16, 68)
        b = ri(rng, 7, 29)
        if a + b > 99 then b = 99 - a end
    else
        a = ri(rng, 23, 79)
        b = ri(rng, 18, 58)
        if a + b > 100 then b = 100 - a end
    end
    if rng(2) == 1 then
        symbol, answer = "+", a + b
    else
        if b > a then a, b = b, a end
        symbol, answer = "-", a - b
    end
    return number_q("upper", "m2", "add_sub", difficulty,
        string.format("%d %s %d = ？", a, symbol, b), answer,
        string.format("%d %s %d = %d。", a, symbol, b, answer))
end

local function table_mul(rng, difficulty, unit, min_factor, max_factor)
    local a, b
    if difficulty == 1 then
        a = ri(rng, min_factor, math.min(max_factor, 5))
        b = ri(rng, 2, 5)
    elseif difficulty == 2 then
        a = ri(rng, min_factor, max_factor)
        b = ri(rng, 2, 6)
    else
        a = ri(rng, min_factor, max_factor)
        b = ri(rng, 2, 9)
    end
    local answer = a * b
    return number_q("upper", unit, "table_mul", difficulty,
        string.format("%d × %d = ？", a, b), answer,
        string.format("%d × %d = %d，想口诀：%d%d得%d。", a, b, answer, a, b, answer))
end

local function division(rng, difficulty, unit, max_factor)
    local b = ri(rng, 2, difficulty == 1 and 5 or max_factor)
    local q = ri(rng, 2, difficulty == 1 and 5 or max_factor)
    if difficulty == 3 and rng(2) == 1 then
        b = ri(rng, 6, 9)
        q = ri(rng, 2, 9)
    end
    local a = b * q
    return number_q("lower", unit, "division", difficulty,
        string.format("%d ÷ %d = ？", a, b), q,
        string.format("%d ÷ %d = %d，因为 %d × %d = %d。", a, b, q, b, q, a))
end

local function mixed_ops(rng, difficulty)
    local a, b, c, answer, text, explain
    if difficulty == 1 then
        a = ri(rng, 8, 30)
        b = ri(rng, 2, 5)
        c = ri(rng, 2, 5)
        answer = a + b * c
        text = string.format("%d + %d × %d = ？", a, b, c)
        explain = string.format("先算乘法：%d × %d = %d，再算加法：%d + %d = %d。", b, c, b * c, a, b * c, answer)
    elseif difficulty == 2 then
        a = ri(rng, 2, 6)
        b = ri(rng, 2, 6)
        c = ri(rng, 2, 20)
        answer = a * b + c
        text = string.format("%d × %d + %d = ？", a, b, c)
        explain = string.format("先算乘法：%d × %d = %d，再算加法：%d + %d = %d。", a, b, a * b, a * b, c, answer)
    else
        a = ri(rng, 2, 9)
        b = ri(rng, 2, 9)
        c = ri(rng, 2, 9)
        if rng(2) == 1 then
            answer = (a + b) * c
            text = string.format("(%d + %d) × %d = ？", a, b, c)
            explain = string.format("先算括号：%d + %d = %d，再算乘法：%d × %d = %d。", a, b, a + b, a + b, c, answer)
        else
            c = ri(rng, 2, math.min(9, a * b))
            answer = a * b - c
            text = string.format("%d × %d - %d = ？", a, b, c)
            explain = string.format("先算乘法：%d × %d = %d，再算减法：%d - %d = %d。", a, b, a * b, a * b, c, answer)
        end
    end
    return number_q("lower", "m5", "mixed_ops", difficulty, text, answer, explain)
end

local function remainder_q(rng, difficulty)
    local b = ri(rng, 2, 9)
    local q = ri(rng, 2, 9)
    local r = ri(rng, 1, b - 1)
    local a = b * q + r
    if difficulty <= 2 then
        local ask_remainder = difficulty == 2
        local answer = ask_remainder and r or q
        local label = ask_remainder and "余数" or "商"
        return number_q("lower", "m6", "remainder", difficulty,
            string.format("%d ÷ %d 的%s是多少？", a, b, label), answer,
            string.format("%d ÷ %d = %d……%d，所以%s是%d。", a, b, q, r, label, answer))
    end
    local correct = string.format("%d……%d", q, r)
    local distractors = {
        string.format("%d……%d", q + 1, r),
        string.format("%d……%d", q - 1, r),
        string.format("%d……%d", q + 2, r),
    }
    return choice_q("lower", "m6", "remainder", difficulty,
        string.format("%d ÷ %d = ？", a, b), correct, distractors,
        string.format("%d ÷ %d = %d……%d。", a, b, q, r), rng)
end

local function length_q(rng, difficulty)
    if difficulty == 1 then
        local meters = ri(rng, 1, 5)
        local answer = meters * 100
        return number_q("upper", "m1", "length", difficulty,
            string.format("%d 米 = ？ 厘米", meters), answer,
            string.format("1 米 = 100 厘米，所以 %d 米 = %d 厘米。", meters, answer), "厘米")
    elseif difficulty == 2 then
        local meters = ri(rng, 4, 9)
        local answer = meters * 100
        return number_q("upper", "m1", "length", difficulty,
            string.format("%d 米 = ？ 厘米", meters), answer,
            string.format("1 米 = 100 厘米，%d 米就是 %d 个 100 厘米。", meters, meters), "厘米")
    end
    local a = ri(rng, 8, 20)
    local b = ri(rng, 2, a - 1)
    local answer = a - b
    return number_q("upper", "m1", "length", difficulty,
        string.format("一根绳子长 %d 米，剪去 %d 米，还剩多少米？", a, b), answer,
        string.format("%d - %d = %d（米）。", a, b, answer), "米")
end

local function angles_q(rng, difficulty)
    if difficulty == 1 then
        local n = rng(2) == 1 and 3 or 4
        local stem = n == 3 and "一个三角形有几个角？" or "一个长方形有几个直角？"
        return number_q("upper", "m3", "angles", difficulty, stem, n,
            n == 3 and "三角形有 3 个角。" or "长方形有 4 个直角。")
    end
    if difficulty == 2 then
        return choice_q("upper", "m3", "angles", difficulty,
            "三角尺上最大的角是什么角？", "直角",
            { "锐角", "钝角", "平角" }, "三角尺上有一个直角，它是最大的角。", rng)
    end
    return choice_q("upper", "m3", "angles", difficulty,
        "一个角的两条边张开得越大，这个角就（ ）。", "越大",
        { "越小", "不变", "和边张开的大小无关" }, "角的大小与两条边张开的程度有关，张开得越大，角越大。", rng)
end

local function observe_q(rng, difficulty)
    if difficulty == 1 then
        return choice_q("upper", "m5", "observe_object", difficulty,
            "从正面看一个正方体，看到的是什么图形？", "正方形",
            { "长方形", "三角形", "圆" }, "正方体的每个面都是正方形，从正面看到的是正方形。", rng)
    elseif difficulty == 2 then
        return choice_q("upper", "m5", "observe_object", difficulty,
            "从上面看一个圆柱，看到的是什么图形？", "圆",
            { "正方形", "长方形", "三角形" }, "圆柱的上面是一个圆。", rng)
    end
    return choice_q("upper", "m5", "observe_object", difficulty,
        "从不同方向观察同一个物体，看到的形状可能（ ）。", "不同",
        { "都相同", "一定相同", "完全一样" }, "从不同方向观察，看到的形状可能不同。", rng)
end

local function time_q(rng, difficulty)
    local h = ri(rng, 1, 11)
    if difficulty == 1 then
        return number_q("upper", "m7", "time", difficulty,
            string.format("时针指向 %d，分针指向 12，是几时？", h), h,
            string.format("分针指向 12，时针指向 %d，就是 %d 时。", h, h), "时")
    elseif difficulty == 2 then
        if rng(2) == 1 then
            return number_q("upper", "m7", "time", difficulty,
                "分针指向 6，是多少分？", 30,
                "分针指向 6，走了 30 个小格，就是 30 分。", "分")
        end
        local h2 = h + 1
        return number_q("upper", "m7", "time", difficulty,
            string.format("从 %d 时到 %d 时，经过了几个小时？", h, h2), 1,
            string.format("%d 时到 %d 时经过了 1 小时。", h, h2), "小时")
    end
    local duration = ri(rng, 1, 3)
    h = ri(rng, 1, 9)
    local end_hour = h + duration
    return number_q("upper", "m7", "time", difficulty,
        string.format("小明 %d 时开始看书，看了 %d 小时，几时结束？", h, duration), end_hour,
        string.format("%d + %d = %d，所以 %d 时结束。", h, duration, h + duration, end_hour), "时")
end

local function combinations_q(rng, difficulty)
    local a = ri(rng, 2, difficulty == 1 and 3 or 5)
    local b = ri(rng, 2, difficulty == 1 and 3 or 4)
    local answer = a * b
    return number_q("upper", "m8", "combinations", difficulty,
        string.format("有 %d 件上衣和 %d 条裤子，一件上衣配一条裤子，一共有几种搭配？", a, b), answer,
        string.format("%d × %d = %d，一共有 %d 种搭配。", a, b, answer, answer), "种")
end

local function data_q(rng, difficulty)
    local apple = ri(rng, 6, 9)
    local banana = ri(rng, 2, apple - 2)
    local orange = ri(rng, 3, apple - 1)
    if orange == banana then
        orange = banana == 3 and 4 or 3
    end
    if difficulty == 1 then
        local answer = apple - banana
        return number_q("lower", "m1", "data", difficulty,
            string.format("调查结果：喜欢苹果的有 %d 人，喜欢香蕉的有 %d 人，喜欢橘子的有 %d 人。喜欢苹果的比喜欢香蕉的多几人？", apple, banana, orange), answer,
            string.format("%d - %d = %d（人）。", apple, banana, answer), "人")
    elseif difficulty == 2 then
        local total = apple + banana + orange
        return number_q("lower", "m1", "data", difficulty,
            string.format("调查结果：喜欢苹果的有 %d 人，喜欢香蕉的有 %d 人，喜欢橘子的有 %d 人。一共有多少人参加调查？", apple, banana, orange), total,
            string.format("%d + %d + %d = %d（人）。", apple, banana, orange, total), "人")
    end
    local correct = "苹果"
    local most = apple
    if banana > most then most, correct = banana, "香蕉" end
    if orange > most then most, correct = orange, "橘子" end
    return choice_q("lower", "m1", "data", difficulty,
        string.format("调查结果：喜欢苹果的有 %d 人，喜欢香蕉的有 %d 人，喜欢橘子的有 %d 人。喜欢哪种水果的人最多？", apple, banana, orange), correct,
        { "香蕉", "橘子", "一样多" }, string.format("比较三个数，%d 最大，所以喜欢%s的人最多。", most, correct), rng)
end

local function symmetry_q(rng, difficulty)
    if difficulty == 1 then
        return choice_q("lower", "m3", "symmetry", difficulty,
            "推拉窗的运动是（ ）。", "平移",
            { "旋转", "对称", "平移和旋转" }, "推拉窗沿直线移动，是平移现象。", rng)
    elseif difficulty == 2 then
        return choice_q("lower", "m3", "symmetry", difficulty,
            "钟表指针的运动是（ ）。", "旋转",
            { "平移", "对称", "平移和旋转" }, "钟表指针绕着中心转动，是旋转现象。", rng)
    end
    return choice_q("lower", "m3", "symmetry", difficulty,
        "下面哪个图形一定是轴对称图形？", "正方形",
        { "平行四边形", "一般梯形", "不规则四边形" }, "正方形沿对边中点连线或对角线对折后能完全重合，是轴对称图形。", rng)
end

local function numbers_10k_q(rng, difficulty)
    if difficulty == 1 then
        local thousands = ri(rng, 1, 9)
        local hundreds = ri(rng, 1, 9)
        local tens = ri(rng, 1, 9)
        local ones = ri(rng, 1, 9)
        local answer = thousands * 1000 + hundreds * 100 + tens * 10 + ones
        return number_q("lower", "m7", "numbers_10k", difficulty,
            string.format("%d 个千、%d 个百、%d 个十和 %d 个一组成的数是多少？", thousands, hundreds, tens, ones), answer,
            string.format("这个数是 %d。", answer))
    elseif difficulty == 2 then
        return choice_q("lower", "m7", "numbers_10k", difficulty,
            "读作“三千零五”的数是（ ）。", "3005",
            { "3050", "3500", "30005" }, "三千零五写作 3005，中间的 0 要读出来。", rng)
    end
    return choice_q("lower", "m7", "numbers_10k", difficulty,
        "与 2999 相邻的两个数是（ ）。", "2998 和 3000",
        { "2998 和 2999", "3000 和 3001", "2990 和 3000" }, "2999 前面是 2998，后面是 3000。", rng)
end

local function mass_q(rng, difficulty)
    if difficulty == 1 then
        return number_q("lower", "m8", "mass", difficulty,
            "1 千克 = ？ 克", 1000,
            "1 千克 = 1000 克。", "克")
    elseif difficulty == 2 then
        local bags = rng(2) == 1 and 2 or 4
        local grams = 500
        local answer = bags * grams / 1000
        return number_q("lower", "m8", "mass", difficulty,
            string.format("一袋盐重 500 克，%d 袋重多少千克？", bags), answer,
            string.format("500 × %d = %d（克），%d 克 = %d 千克。", bags, bags * grams, bags * grams, answer), "千克")
    end
    return choice_q("lower", "m8", "mass", difficulty,
        "一个苹果大约重 200（ ）。", "克",
        { "千克", "米", "厘米" }, "一个苹果大约重 200 克，用“克”作单位。", rng)
end

local function reasoning_q(rng, difficulty)
    if difficulty == 1 then
        return choice_q("lower", "m9", "reasoning", difficulty,
            "小明、小红、小刚分别拿苹果、香蕉、橘子。小明不拿苹果，小红拿香蕉，小刚拿什么？", "苹果",
            { "香蕉", "橘子", "苹果和香蕉" }, "小红拿香蕉，小明不拿苹果，所以小明拿橘子，小刚拿苹果。", rng)
    elseif difficulty == 2 then
        return choice_q("lower", "m9", "reasoning", difficulty,
            "甲、乙、丙三人中，甲比乙高，乙比丙高，谁最高？", "甲",
            { "乙", "丙", "一样高" }, "甲比乙高，乙又比丙高，所以甲最高。", rng)
    end
    return choice_q("lower", "m9", "reasoning", difficulty,
        "三个小朋友排队，小明不在最前面，小红在小明后面，谁在最前面？", "小刚",
        { "小明", "小红", "不能确定" }, "小明不在最前面，小红在小明后面，所以小明排第二，小红排第三，小刚排第一。", rng)
end

local function word_problem(rng, difficulty, unit, semester)
    semester = semester == "lower" and "lower" or "upper"
    local name = pick(rng, NAMES)
    local name2 = pick(rng, NAMES)
    while name2 == name do name2 = pick(rng, NAMES) end
    local allowed = semester == "lower" and { 1, 2, 3, 4, 5, 6, 8, 10 } or { 1, 2, 3, 5, 7, 9 }
    local kind = pick(rng, allowed)
    local default_units = semester == "lower"
        and { [1] = "m5", [2] = "m5", [3] = "m5", [4] = "m2", [5] = "m5", [6] = "m5", [8] = "m8", [10] = "m6" }
        or { [1] = "m2", [2] = "m2", [3] = "m4", [5] = "m2", [7] = "m1", [9] = "m7" }
    local qunit = unit or default_units[kind]
    if kind == 1 then
        local a = ri(rng, 12, difficulty == 1 and 30 or 60)
        local b = ri(rng, 5, difficulty == 1 and 20 or 35)
        local answer = a + b
        return number_q(semester, qunit, "word_add", difficulty,
            string.format("%s有 %d 个苹果，妈妈又买了 %d 个，一共有多少个？", name, a, b), answer,
            string.format("%d + %d = %d（个）。", a, b, answer), "个")
    elseif kind == 2 then
        local a = ri(rng, 20, 80)
        local b = ri(rng, 3, a - 5)
        local answer = a - b
        return number_q(semester, qunit, "word_sub", difficulty,
            string.format("树上有 %d 只小鸟，飞走了 %d 只，还剩多少只？", a, b), answer,
            string.format("%d - %d = %d（只）。", a, b, answer), "只")
    elseif kind == 3 then
        local a = ri(rng, 2, 9)
        local b = ri(rng, 2, difficulty == 1 and 5 or 9)
        local answer = a * b
        return number_q(semester, qunit, "word_mul", difficulty,
            string.format("每盒有 %d 支铅笔，%d 盒一共有多少支？", a, b), answer,
            string.format("%d × %d = %d（支）。", a, b, answer), "支")
    elseif kind == 4 then
        local b = ri(rng, 2, 9)
        local q = ri(rng, 2, 9)
        local a = b * q
        return number_q(semester, qunit, "word_div", difficulty,
            string.format("有 %d 个苹果，平均分给 %d 个小朋友，每人分几个？", a, b), q,
            string.format("%d ÷ %d = %d（个）。", a, b, q), "个")
    elseif kind == 5 then
        local a = ri(rng, 20, 90)
        local b = ri(rng, 5, 30)
        local answer = a + b
        return number_q(semester, qunit, "word_compare", difficulty,
            string.format("%s有 %d 元，%s比%s多 %d 元，%s有多少元？", name, a, name2, name, b, name2), answer,
            string.format("%d + %d = %d（元）。", a, b, answer), "元")
    elseif kind == 6 then
        local a = ri(rng, 30, 90)
        local b = ri(rng, 5, 25)
        local c = ri(rng, 4, 20)
        local answer = a - b + c
        return number_q(semester, qunit, "word_two_step", difficulty,
            string.format("商店有 %d 个球，上午卖出 %d 个，下午又运来 %d 个，现在有多少个？", a, b, c), answer,
            string.format("%d - %d + %d = %d（个）。", a, b, c, answer), "个")
    elseif kind == 7 then
        local a = ri(rng, 10, 30)
        local b = ri(rng, 2, a - 1)
        local answer = a - b
        return number_q(semester, qunit, "word_length", difficulty,
            string.format("一根绳子长 %d 米，剪去 %d 米，还剩多少米？", a, b), answer,
            string.format("%d - %d = %d（米）。", a, b, answer), "米")
    elseif kind == 8 then
        local a = ri(rng, 2, 9)
        local b = ri(rng, 2, 5)
        local answer = a * b
        return number_q(semester, qunit, "word_mass", difficulty,
            string.format("一袋大米重 %d 千克，%d 袋重多少千克？", a, b), answer,
            string.format("%d × %d = %d（千克）。", a, b, answer), "千克")
    elseif kind == 9 then
        local h = ri(rng, 1, 9)
        local d = ri(rng, 1, 3)
        local answer = h + d
        return number_q(semester, qunit, "word_time", difficulty,
            string.format("%s从 %d 时开始写作业，写了 %d 小时，几时完成？", name, h, d), answer,
            string.format("%d + %d = %d，所以 %d 时完成。", h, d, answer, answer), "时")
    else
        local b = ri(rng, 2, 9)
        local q = ri(rng, 2, 6)
        local r = ri(rng, 1, b - 1)
        local a = b * q + r
        local correct = string.format("%d 盘，还剩 %d 个", q, r)
        local distractors = {
            string.format("%d 盘，还剩 %d 个", q + 1, r),
            string.format("%d 盘，还剩 %d 个", q - 1, r),
            string.format("%d 盘，还剩 %d 个", q + 2, r),
        }
        return choice_q(semester, qunit, "word_remainder", difficulty,
            string.format("有 %d 个苹果，每 %d 个装一盘，能装几盘，还剩几个？", a, b), correct, distractors,
            string.format("%d ÷ %d = %d……%d，所以能装 %d 盘，还剩 %d 个。", a, b, q, r, q, r), rng)
    end
end

--[[--
拓展题：不只练计算，还练数感、量感、推理、几何直观、数据意识和应用意识。
这些题会出现在综合练习、今日挑战和单独的“数学拓展”模式中。
--]]--

local challenge_units = {
    upper = {
        chicken_rabbit = "m8",
        queue_problem = "m2",
        cycle_pattern = "m6",
        planting = "m1",
        move_more_less = "m2",
        number_sense = "m2",
        estimate = "m2",
        pattern = "m6",
        symbol_reasoning = "m2",
        geometry_sticks = "m5",
        combination_cards = "m8",
        data_reasoning = "m2",
        measure_estimate = "m1",
        time_planning = "m7",
        balance_reasoning = "m6",
        real_world_plan = "m2",
        multi_step = "m2",
    },
    lower = {
        chicken_rabbit = "m9",
        queue_problem = "m5",
        cycle_pattern = "m4",
        planting = "m5",
        move_more_less = "m5",
        number_sense = "m7",
        estimate = "m5",
        pattern = "m4",
        symbol_reasoning = "m9",
        geometry_sticks = "m3",
        combination_cards = "m9",
        data_reasoning = "m1",
        measure_estimate = "m8",
        time_planning = "m5",
        balance_reasoning = "m9",
        real_world_plan = "m5",
        multi_step = "m5",
    },
}

local function mark_challenge(q, competency)
    q.type = "math_challenge"
    q.skill = "challenge"
    q.difficulty = 3
    q.challenge = true
    q.competency = competency
    return q
end

local function challenge_chicken_rabbit(rng, semester, unit)
    local total = ri(rng, 4, 8)
    local rabbits = ri(rng, 1, total - 1)
    local chickens = total - rabbits
    local legs = chickens * 2 + rabbits * 4
    local ask_rabbit = rng(2) == 1
    local answer = ask_rabbit and rabbits or chickens
    return mark_challenge(number_q(semester, unit, "challenge", 3,
        string.format("笼子里有鸡和兔共 %d 只，一共有 %d 条腿。%s有几只？", total, legs, ask_rabbit and "兔" or "鸡"), answer,
        string.format("假设全是鸡，%d 只鸡有 %d 条腿，少了 %d 条。每只兔比鸡多 2 条腿，%d ÷ 2 = %d，所以兔有 %d 只，鸡有 %d 只。", total, total * 2, legs - total * 2, legs - total * 2, rabbits, rabbits, chickens)), "推理意识")
end

local function challenge_queue_problem(rng, semester, unit)
    local front = ri(rng, 2, 5)
    local back = ri(rng, 2, 5)
    local answer = front + back + 1
    return mark_challenge(number_q(semester, unit, "challenge", 3,
        string.format("小明排队，前面有 %d 人，后面有 %d 人，这一队一共有几人？", front, back), answer,
        string.format("%d + %d + 1 = %d（人），别忘了小明自己。", front, back, answer)), "推理意识")
end

local function challenge_cycle_pattern(rng, semester, unit)
    local n = ri(rng, 8, 15)
    local colors = { "红", "黄", "蓝" }
    local idx = ((n - 1) % 3) + 1
    local answer = colors[idx]
    return mark_challenge(choice_q(semester, unit, "challenge", 3,
        string.format("按红、黄、蓝、红、黄、蓝……的顺序排列，第 %d 个是什么颜色？", n), answer,
        { "红", "黄", "蓝", "绿" },
        string.format("每 3 个颜色一组，第 %d 个是下一组里的第 %d 个，所以是%s色。", n, idx, answer), rng), "推理意识")
end

local function challenge_planting(rng, semester, unit)
    local spacing = rng(2) == 1 and 2 or 5
    local trees = ri(rng, 3, 5)
    local length = spacing * (trees - 1)
    return mark_challenge(number_q(semester, unit, "challenge", 3,
        string.format("一条小路长 %d 米，每隔 %d 米种一棵树，两端都种，一共种几棵？", length, spacing), trees,
        string.format("%d ÷ %d = %d 个间隔，两端都种，棵数比间隔数多 1，所以一共种 %d 棵。", length, spacing, trees - 1, trees)), "应用意识")
end

local function challenge_move_more_less(rng, semester, unit)
    local xiaoming = ri(rng, 10, 18)
    local give = ri(rng, 2, math.floor((xiaoming - 1) / 2))
    local answer = xiaoming - 2 * give
    return mark_challenge(number_q(semester, unit, "challenge", 3,
        string.format("小明有 %d 张卡片，给小红 %d 张后两人一样多，小红原来有几张？", xiaoming, give), answer,
        string.format("小明给出 %d 张后剩 %d 张，这时小红也有 %d 张，所以小红原来有 %d - %d = %d（张）。", give, xiaoming - give, xiaoming - give, xiaoming - give, give, answer)), "应用意识")
end

local function challenge_number_sense(rng, semester, unit)
    local correct = ri(rng, 94, 98)
    return mark_challenge(choice_q(semester, unit, "challenge", 3,
        "下面哪个数最接近 100？", tostring(correct), { tostring(85), tostring(108), tostring(125) },
        string.format("%d 和 100 相差 %d，是选项里最接近 100 的数。", correct, 100 - correct), rng), "数感")
end

local function challenge_estimate(rng, semester, unit)
    local a = ri(rng, 38, 49)
    local b = ri(rng, 21, 39)
    local sum = a + b
    local rounded = math.floor((sum + 5) / 10) * 10
    return mark_challenge(choice_q(semester, unit, "challenge", 3,
        string.format("估算：%d + %d 大约等于多少？", a, b), tostring(rounded),
        { tostring(rounded - 10), tostring(rounded + 10), tostring(rounded + 20) },
        string.format("%d + %d = %d，最接近整十数 %d。", a, b, sum, rounded), rng), "数感")
end

local function challenge_pattern(rng, semester, unit)
    local start = ri(rng, 2, 5)
    local step = ri(rng, 2, 5)
    local terms = {}
    for i = 0, 3 do
        table.insert(terms, tostring(start + step * i))
    end
    local answer = start + step * 4
    return mark_challenge(number_q(semester, unit, "challenge", 3,
        string.format("找规律：%s，（ ）。", table.concat(terms, "，")), answer,
        string.format("每次增加 %d，所以下一个数是 %d。", step, answer)), "推理意识")
end

local function challenge_symbol_reasoning(rng, semester, unit)
    local triangle = ri(rng, 3, 8)
    local circle = ri(rng, 1, triangle - 1)
    return mark_challenge(number_q(semester, unit, "challenge", 3,
        string.format("△ + △ = %d，○ + △ = %d，○ = ？", triangle * 2, triangle + circle), circle,
        string.format("△ = %d，因为 %d + %d = %d；○ = %d - %d = %d。", triangle, triangle, triangle, triangle * 2, triangle + circle, triangle, circle)), "推理意识")
end

local function challenge_geometry_sticks(rng, semester, unit)
    return mark_challenge(number_q(semester, unit, "challenge", 3,
        "用小棒摆 2 个正方形，最少需要几根小棒？", 7,
        "两个正方形共用一条边，4 + 4 - 1 = 7（根）。"), "几何直观")
end

local function challenge_combination_cards(rng, semester, unit)
    return mark_challenge(number_q(semester, unit, "challenge", 3,
        "用 1、2、3 三张数字卡片，每次取两张组成两位数，能组成几个不同的两位数？", 6,
        "可以组成 12、13、21、23、31、32，共 6 个。要有顺序地思考。"), "创新意识")
end

local function challenge_data_reasoning(rng, semester, unit)
    local soccer = ri(rng, 6, 9)
    local basketball = ri(rng, 3, soccer - 1)
    local pingpong = ri(rng, 4, 9)
    if rng(2) == 1 then
        local answer = soccer - basketball
        return mark_challenge(number_q(semester, unit, "challenge", 3,
            string.format("调查结果：喜欢足球的有 %d 人，喜欢篮球的有 %d 人，喜欢乒乓球的有 %d 人。喜欢足球的比喜欢篮球的多几人？", soccer, basketball, pingpong), answer,
            string.format("%d - %d = %d（人）。先看清每个项目的数据，再比较。", soccer, basketball, answer), "人"), "数据意识")
    end
    local total = soccer + basketball + pingpong
    return mark_challenge(number_q(semester, unit, "challenge", 3,
        string.format("调查结果：喜欢足球的有 %d 人，喜欢篮球的有 %d 人，喜欢乒乓球的有 %d 人。一共有多少人参加调查？", soccer, basketball, pingpong), total,
        string.format("%d + %d + %d = %d（人）。把三部分数据合起来。", soccer, basketball, pingpong, total), "人"), "数据意识")
end

local function challenge_measure_estimate(rng, semester, unit)
    return mark_challenge(choice_q(semester, unit, "challenge", 3,
        "教室的门高约 2（ ）。", "米", { "厘米", "分米", "千米" },
        "教室的门高大约 2 米，用“米”作单位比较合适。", rng), "量感")
end

local function challenge_time_planning(rng, semester, unit)
    local hour = ri(rng, 6, 8)
    return mark_challenge(number_q(semester, unit, "challenge", 3,
        string.format("小明 %d 时 30 分起床，%d 时出发，经过了多长时间？", hour, hour + 1), 30,
        string.format("%d 时 30 分到 %d 时，经过了 30 分。", hour, hour + 1), "分"), "应用意识")
end

local function challenge_balance_reasoning(rng, semester, unit)
    local oranges = ri(rng, 2, 3)
    local strawberries = ri(rng, 2, 4)
    local answer = oranges * strawberries
    return mark_challenge(number_q(semester, unit, "challenge", 3,
        string.format("1 个苹果 = %d 个橘子，1 个橘子 = %d 颗草莓，1 个苹果 = 几颗草莓？", oranges, strawberries), answer,
        string.format("1 个苹果 = %d 个橘子，每个橘子又等于 %d 颗草莓，所以 %d × %d = %d（颗）。", oranges, strawberries, oranges, strawberries, answer), "颗"), "推理意识")
end

local function challenge_real_world_plan(rng, semester, unit)
    local money = ri(rng, 15, 20)
    local book = ri(rng, 6, 9)
    local pen = ri(rng, 3, math.min(5, money - book - 1))
    local answer = money - book - pen
    return mark_challenge(number_q(semester, unit, "challenge", 3,
        string.format("小明带了 %d 元，买一本 %d 元的书和一支 %d 元的笔，还剩多少元？", money, book, pen), answer,
        string.format("%d - %d - %d = %d（元）。先算一共花了多少，再算还剩多少。", money, book, pen, answer), "元"), "应用意识")
end

local function challenge_multi_step(rng, semester, unit)
    local boxes = ri(rng, 2, 3)
    local per_box = ri(rng, 4, 6)
    local given = ri(rng, 2, 5)
    local answer = boxes * per_box - given
    return mark_challenge(number_q(semester, unit, "challenge", 3,
        string.format("小明有 %d 盒彩笔，每盒 %d 支，送给同学 %d 支，还剩多少支？", boxes, per_box, given), answer,
        string.format("先算一共有 %d × %d = %d（支），再算还剩 %d - %d = %d（支）。", boxes, per_box, boxes * per_box, boxes * per_box, given, answer), "支"), "应用意识")
end

local challenge_generators = {
    { id = "chicken_rabbit", competency = "推理意识", fn = challenge_chicken_rabbit },
    { id = "queue_problem", competency = "推理意识", fn = challenge_queue_problem },
    { id = "cycle_pattern", competency = "推理意识", fn = challenge_cycle_pattern },
    { id = "planting", competency = "应用意识", fn = challenge_planting },
    { id = "move_more_less", competency = "应用意识", fn = challenge_move_more_less },
    { id = "number_sense", competency = "数感", fn = challenge_number_sense },
    { id = "estimate", competency = "数感", fn = challenge_estimate },
    { id = "pattern", competency = "推理意识", fn = challenge_pattern },
    { id = "symbol_reasoning", competency = "推理意识", fn = challenge_symbol_reasoning },
    { id = "geometry_sticks", competency = "几何直观", fn = challenge_geometry_sticks },
    { id = "combination_cards", competency = "创新意识", fn = challenge_combination_cards },
    { id = "data_reasoning", competency = "数据意识", fn = challenge_data_reasoning },
    { id = "measure_estimate", competency = "量感", fn = challenge_measure_estimate },
    { id = "time_planning", competency = "应用意识", fn = challenge_time_planning },
    { id = "balance_reasoning", competency = "推理意识", fn = challenge_balance_reasoning },
    { id = "real_world_plan", competency = "应用意识", fn = challenge_real_world_plan },
    { id = "multi_step", competency = "应用意识", fn = challenge_multi_step },
}

local function challenge_candidates(semester, unit)
    local candidates = {}
    for _, item in ipairs(challenge_generators) do
        local item_unit = challenge_units[semester][item.id]
        if not unit or unit == "all" or unit == item_unit then
            table.insert(candidates, { item = item, unit = item_unit })
        end
    end
    if #candidates == 0 then
        for _, item in ipairs(challenge_generators) do
            table.insert(candidates, { item = item, unit = challenge_units[semester][item.id] })
        end
    end
    return candidates
end

--[[--
Build a round plan of challenge generator ids.

Types are shuffled without repetition: a type is not repeated until every
matching type has been used. If `count` is larger than the number of matching
generators (for example a unit that only has two challenge types), the
shuffled order repeats to fill the round.

@tparam table opts { semester = "upper"|"lower", unit = string|nil, count = number }
@tparam function rng Optional random function, injectable for deterministic tests.
@treturn table List of generator ids.
--]]--
function MathGen.challenge_plan(opts, rng)
    opts = opts or {}
    rng = rng or math.random
    local semester = opts.semester == "lower" and "lower" or "upper"
    local candidates = challenge_candidates(semester, opts.unit)
    local count = opts.count or #candidates
    local order = {}
    for i = 1, #candidates do order[i] = i end
    for i = #order, 2, -1 do
        local j = ri(rng, 1, i)
        order[i], order[j] = order[j], order[i]
    end
    local plan = {}
    for i = 1, count do
        local candidate = candidates[order[((i - 1) % #order) + 1]]
        table.insert(plan, candidate.item.id)
    end
    return plan
end

function MathGen.generate_challenge(opts, rng)
    opts = opts or {}
    rng = rng or math.random
    local semester = opts.semester == "lower" and "lower" or "upper"
    local candidates = challenge_candidates(semester, opts.unit)
    local chosen
    if opts.id then
        for _, candidate in ipairs(candidates) do
            if candidate.item.id == opts.id then
                chosen = candidate
                break
            end
        end
    end
    if not chosen and opts.index then
        chosen = candidates[((opts.index - 1) % #candidates) + 1]
    end
    if not chosen then
        chosen = pick(rng, candidates)
    end
    local q = chosen.item.fn(rng, semester, chosen.unit)
    local grade = tonumber(opts.grade) or 2
    local edition = opts.edition or "renjiao"
    if grade ~= 2 or edition ~= "renjiao" then
        local units = Catalog.units(plugin_path, "math", edition, grade, semester)
        if units and #units > 0 then
            local valid = units[1].id
            for _, unit in ipairs(units) do
                if unit.id == chosen.unit then valid = chosen.unit end
            end
            q.unit = valid
        end
    end
    q.competency = chosen.item.competency
    q.challenge_id = chosen.item.id
    q.grade = grade
    q.edition = edition
    q.unit_name = MathGen.unit_name(grade, edition, semester, q.unit)
    return decorate_question(q, {
        grade = grade, edition = edition, semester = semester,
    }, q.unit, q.unit_name)
end


local generators = {
    upper = {
        m1 = length_q,
        m2 = add_sub,
        m3 = angles_q,
        m4 = function(rng, d) return table_mul(rng, d, "m4", 2, 5) end,
        m5 = observe_q,
        m6 = function(rng, d) return table_mul(rng, d, "m6", 6, 9) end,
        m7 = time_q,
        m8 = combinations_q,
    },
    lower = {
        m1 = data_q,
        m2 = function(rng, d) return division(rng, d, "m2", 6) end,
        m3 = symmetry_q,
        m4 = function(rng, d) return division(rng, d, "m4", 9) end,
        m5 = mixed_ops,
        m6 = remainder_q,
        m7 = numbers_10k_q,
        m8 = mass_q,
        m9 = reasoning_q,
    },
}

function MathGen.units(semester)
    return unit_names[semester] or unit_names.upper
end

function MathGen.unit_name(semester, unit)
    for _, item in ipairs(MathGen.units(semester)) do
        if item.id == unit then return item.name end
    end
    return unit
end

function MathGen.generate(opts, rng)
    opts = opts or {}
    rng = rng or math.random
    local semester = opts.semester == "lower" and "lower" or "upper"
    local unit = opts.unit
    local units = MathGen.units(semester)
    if not unit or unit == "all" then
        unit = pick(rng, units).id
    end
    local generator = generators[semester][unit]
    if not generator then
        -- Fall back to a general word problem if a unit id is unknown.
        return word_problem(rng, opts.difficulty or 2, nil, semester)
    end
    local difficulty = tonumber(opts.difficulty) or 2
    if difficulty < 1 then difficulty = 1 elseif difficulty > 3 then difficulty = 3 end
    return generator(rng, difficulty)
end

function MathGen.generate_word_problem(opts, rng)
    opts = opts or {}
    rng = rng or math.random
    local semester = opts.semester == "lower" and "lower" or "upper"
    local difficulty = tonumber(opts.difficulty) or 2
    if difficulty < 1 then difficulty = 1 elseif difficulty > 3 then difficulty = 3 end
    return word_problem(rng, difficulty, nil, semester)
end


-- ---------------------------------------------------------------------------
-- Grade 1-6 catalog-driven generator
-- ---------------------------------------------------------------------------
-- The original grade-2 generators above are kept for backwards compatibility.
-- The functions below use a skill registry so every textbook edition can bind
-- its units to a grade-appropriate question family.

local concept_geometry = {
    { "长方形有几条边？", "4条", { "3条", "5条", "6条" }, "长方形有4条边。" },
    { "正方形有几条边？", "4条", { "3条", "5条", "6条" }, "正方形有4条边。" },
    { "三角形有几个角？", "3个", { "2个", "4个", "5个" }, "三角形有3个角。" },
    { "下面哪个图形没有角？", "圆", { "三角形", "长方形", "正方形" }, "圆没有角。" },
    { "钟面上时针走一大格是多长时间？", "1小时", { "1分钟", "5分钟", "半小时" }, "时针走一大格是1小时。" },
    { "三角尺上最大的角是什么角？", "直角", { "锐角", "钝角", "平角" }, "三角尺上最大的角是直角。" },
    { "教室的门通常是哪个形状？", "长方形", { "三角形", "圆形", "正方形" }, "教室的门通常是长方形。" },
    { "一个正方体有几个面？", "6个", { "4个", "5个", "8个" }, "正方体有6个面。" },
    { "下面哪个图形是轴对称图形？", "长方形", { "平行四边形", "任意三角形", "不规则四边形" }, "长方形是轴对称图形。" },
    { "地图上通常上面表示哪个方向？", "北", { "南", "东", "西" }, "地图上通常上北下南。" },
    { "一个平角是多少度？", "180度", { "90度", "360度", "45度" }, "平角是180度。" },
    { "一个直角是多少度？", "90度", { "45度", "180度", "360度" }, "直角是90度。" },
}

local concept_position = {
    { "小明坐在小红的左边，小红坐在小明的哪边？", "右边", { "左边", "前面", "后面" }, "左右相对，小红在小明的右边。" },
    { "排队时，小刚前面有3人，他排第几？", "第4", { "第3", "第5", "第2" }, "前面3人，加上小刚自己是第4。" },
    { "书架从上往下数，第二层在哪里？", "上面第二层", { "最下面", "最上面", "第三层" }, "从上往下数第二层就是上面第二层。" },
    { "小丽在小华后面，小华在小丽哪边？", "前面", { "后面", "左边", "右边" }, "前后相对，小华在小丽前面。" },
    { "面向北方，右手边是哪个方向？", "东", { "西", "南", "北" }, "面向北时，右手指向东。" },
    { "面向东方，后面是哪个方向？", "西", { "东", "南", "北" }, "东和西相对。" },
    { "教室里，讲台通常在同学们的哪边？", "前面", { "后面", "左边", "右边" }, "讲台通常在教室前面。" },
    { "把书放在桌子上面，书在桌子的哪里？", "上面", { "下面", "里面", "后面" }, "书放在桌子上面。" },
}

local concept_data = {
    { "统计班里同学最喜欢的水果，最适合用什么方法？", "调查记录", { "猜一猜", "闭眼想", "不做记录" }, "统计需要先调查并记录数据。" },
    { "条形统计图能清楚地看出什么？", "数量的多少", { "天气冷热", "声音大小", "颜色深浅" }, "条形统计图能直观看出数量多少。" },
    { "一组数据是2、4、6，平均数是多少？", "4", { "2", "6", "12" }, "（2+4+6）÷3=4。" },
    { "折线统计图最适合表示什么？", "数量的变化趋势", { "只表示总数", "表示颜色", "表示方向" }, "折线统计图能反映数量增减变化。" },
    { "扇形统计图能表示什么？", "各部分占整体的百分比", { "具体数量", "长度", "温度" }, "扇形统计图表示部分与整体的关系。" },
    { "抛一枚硬币，正面朝上的可能性大吗？", "和反面一样大", { "一定正面", "一定反面", "正面更大" }, "硬币正反面可能性相同。" },
    { "把5个苹果平均分给5人，每人几个？", "1个", { "2个", "5个", "0个" }, "5÷5=1。" },
    { "记录一周每天的最高气温，适合用什么统计图？", "折线统计图", { "条形统计图", "扇形统计图", "统计表" }, "折线统计图适合表示气温变化。" },
}

local concept_reasoning = {
    { "按规律填空：1、3、5、7、（ ）。", "9", { "8", "10", "11" }, "每次增加2，所以是9。" },
    { "按规律填空：2、4、8、16、（ ）。", "32", { "20", "24", "30" }, "每次乘2，所以是32。" },
    { "3件上衣和2条裤子，一共有几种搭配？", "6种", { "5种", "3种", "2种" }, "3×2=6种。" },
    { "鸡和兔共5只，腿共14条，鸡有几只？", "3只", { "2只", "4只", "5只" }, "假设全是鸡有10条腿，多4条，每只兔多2条，所以兔2只，鸡3只。" },
    { "在一条路的一边每隔5米栽一棵树，20米长的小路（两端都栽）要栽几棵？", "5棵", { "4棵", "6棵", "3棵" }, "20÷5=4段，两端都栽要4+1=5棵。" },
    { "有9个零件，其中1个较轻，用天平至少称几次能找出？", "2次", { "1次", "3次", "9次" }, "把9个分成3、3、3，两次可以找出。" },
    { "小明有3张数字卡片1、2、3，能组成几个不同的两位数？", "6个", { "3个", "4个", "9个" }, "3×2=6个。" },
    { "烧水要8分钟，洗茶杯要2分钟，找茶叶要1分钟，最少几分钟能泡茶？", "9分钟", { "11分钟", "8分钟", "10分钟" }, "烧水的同时洗茶杯、找茶叶，共8+1=9分钟。" },
}

local concept_measure = {
    { "1米等于多少厘米？", "100厘米", { "10厘米", "1000厘米", "50厘米" }, "1米=100厘米。" },
    { "1千克等于多少克？", "1000克", { "100克", "10克", "500克" }, "1千克=1000克。" },
    { "1小时等于多少分钟？", "60分钟", { "30分钟", "100分钟", "24分钟" }, "1小时=60分钟。" },
    { "1元等于多少角？", "10角", { "100角", "5角", "1角" }, "1元=10角。" },
    { "1平方分米等于多少平方厘米？", "100平方厘米", { "10平方厘米", "1000平方厘米", "10000平方厘米" }, "1平方分米=100平方厘米。" },
    { "一年通常有多少个月？", "12个月", { "10个月", "11个月", "13个月" }, "一年有12个月。" },
    { "平年二月有多少天？", "28天", { "29天", "30天", "31天" }, "平年二月有28天。" },
    { "从上午8时到中午12时，经过了多长时间？", "4小时", { "3小时", "5小时", "8小时" }, "12-8=4小时。" },
}

local concept_numbers = {
    { "36里面的3表示什么？", "3个十", { "3个一", "3个百", "3个千" }, "36的3在十位上，表示3个十。" },
    { "一个数由5个千、2个百和7个一组成，这个数是多少？", "5207", { "5270", "5027", "5720" }, "5个千是5000，2个百是200，7个一是7，合起来是5207。" },
    { "比999多1的数是多少？", "1000", { "998", "999", "10000" }, "999+1=1000。" },
    { "最大的三位数是多少？", "999", { "100", "900", "1000" }, "最大的三位数是999。" },
    { "0.5表示几个十分之一？", "5个", { "1个", "10个", "50个" }, "0.5表示5个十分之一。" },
    { "1/2和0.5相比，哪个大？", "一样大", { "1/2大", "0.5大", "无法比较" }, "1/2=0.5。" },
    { "负数中，-3和-5哪个大？", "-3大", { "-5大", "一样大", "无法比较" }, "负数越接近0越大，所以-3大。" },
    { "12和18的最大公因数是多少？", "6", { "2", "3", "12" }, "12和18的最大公因数是6。" },
}

local concept_general = {
    { "下面哪个算式的结果最大？", "8+7", { "9+5", "6+8", "7+7" }, "8+7=15，其他分别是14、14、14。" },
    { "小明有10元，买笔用了3元，还剩多少元？", "7元", { "6元", "8元", "13元" }, "10-3=7元。" },
    { "一盒彩笔有12支，3盒一共有多少支？", "36支", { "24支", "15支", "30支" }, "12×3=36支。" },
    { "把24个苹果平均放进4个篮子，每篮几个？", "6个", { "4个", "8个", "12个" }, "24÷4=6个。" },
    { "一个数的3倍是18，这个数是多少？", "6", { "3", "9", "15" }, "18÷3=6。" },
    { "5个小朋友每人有2颗糖，一共有几颗？", "10颗", { "7颗", "8颗", "12颗" }, "5×2=10颗。" },
    { "一根绳子长20米，剪去6米，还剩多少米？", "14米", { "12米", "16米", "26米" }, "20-6=14米。" },
    { "妈妈买了3千克苹果，每千克5元，一共多少元？", "15元", { "8元", "10元", "20元" }, "3×5=15元。" },
}

local function choice_from(bank, rng, difficulty, unit, semester, skill)
    local item = bank[ri(rng, 1, #bank)]
    return choice_q(semester, unit, skill, difficulty, item[1], item[2], item[3], item[4], rng)
end

local function gen_add_sub(lo, hi, max_total)
    return function(rng, difficulty, unit, semester, skill)
        local a = ri(rng, lo, hi)
        local b = ri(rng, lo, hi)
        local subtract = difficulty >= 2 and rng(2) == 1
        if subtract then
            if a < b then a, b = b, a end
            local answer = a - b
            return number_q(semester, unit, skill, difficulty,
                string.format("%d - %d = ?", a, b), answer,
                string.format("%d - %d = %d。", a, b, answer))
        end
        if a + b > max_total then b = max_total - a end
        if b < 0 then b = 0 end
        local answer = a + b
        return number_q(semester, unit, skill, difficulty,
            string.format("%d + %d = ?", a, b), answer,
            string.format("%d + %d = %d。", a, b, answer))
    end
end

local function gen_add_carry(rng, difficulty, unit, semester, skill)
    local a = ri(rng, 5, 9)
    local b = ri(rng, 5, 9)
    local answer = a + b
    return number_q(semester, unit, skill, difficulty,
        string.format("%d + %d = ?", a, b), answer,
        string.format("%d + %d = %d。", a, b, answer))
end

local function gen_sub_borrow(rng, difficulty, unit, semester, skill)
    local a = ri(rng, 11, 18)
    local b = ri(rng, 2, 9)
    if b >= a then b = a - 1 end
    local answer = a - b
    return number_q(semester, unit, skill, difficulty,
        string.format("%d - %d = ?", a, b), answer,
        string.format("%d - %d = %d。", a, b, answer))
end

local function gen_mul_table(rng, difficulty, unit, semester, skill)
    local lo, hi = 2, 9
    if difficulty == 1 then hi = 5 elseif difficulty == 3 then lo = 6 end
    local a = ri(rng, lo, hi)
    local b = ri(rng, lo, hi)
    local answer = a * b
    return number_q(semester, unit, skill, difficulty,
        string.format("%d × %d = ?", a, b), answer,
        string.format("%d × %d = %d。", a, b, answer))
end

local function gen_div_table(rng, difficulty, unit, semester, skill)
    local a = ri(rng, 2, 9)
    local b = ri(rng, 2, 9)
    local product = a * b
    return number_q(semester, unit, skill, difficulty,
        string.format("%d ÷ %d = ?", product, a), b,
        string.format("%d ÷ %d = %d。", product, a, b))
end

local function gen_mixed(rng, difficulty, unit, semester, skill)
    local a = ri(rng, 2, 9)
    local b = ri(rng, 2, 9)
    local c = ri(rng, 2, 20)
    local answer = a + b * c
    return number_q(semester, unit, skill, difficulty,
        string.format("%d + %d × %d = ?", a, b, c), answer,
        string.format("先算乘法：%d × %d = %d，再算加法：%d + %d = %d。", b, c, b * c, a, b * c, answer))
end

local function gen_remainder(rng, difficulty, unit, semester, skill)
    local b = ri(rng, 3, 9)
    local q = ri(rng, 2, 9)
    local r = ri(rng, 1, b - 1)
    local a = b * q + r
    return number_q(semester, unit, skill, difficulty,
        string.format("%d ÷ %d 的余数是多少？", a, b), r,
        string.format("%d ÷ %d = %d……%d，余数是%d。", a, b, q, r, r))
end

local function gen_multi_digit_mul(rng, difficulty, unit, semester, skill)
    local a = ri(rng, 12, 999)
    local b = ri(rng, 2, 9)
    local answer = a * b
    return number_q(semester, unit, skill, difficulty,
        string.format("%d × %d = ?", a, b), answer,
        string.format("%d × %d = %d。", a, b, answer))
end

local function gen_two_digit_mul(rng, difficulty, unit, semester, skill)
    local a = ri(rng, 12, 99)
    local b = ri(rng, 12, 99)
    local answer = a * b
    return number_q(semester, unit, skill, difficulty,
        string.format("%d × %d = ?", a, b), answer,
        string.format("%d × %d = %d。", a, b, answer))
end

local function gen_three_digit_mul(rng, difficulty, unit, semester, skill)
    local a = ri(rng, 100, 999)
    local b = ri(rng, 10, 99)
    local answer = a * b
    return number_q(semester, unit, skill, difficulty,
        string.format("%d × %d = ?", a, b), answer,
        string.format("%d × %d = %d。", a, b, answer))
end

local function gen_div_multi(rng, difficulty, unit, semester, skill)
    local b = ri(rng, 2, 9)
    local q = ri(rng, 20, 999)
    local a = b * q
    return number_q(semester, unit, skill, difficulty,
        string.format("%d ÷ %d = ?", a, b), q,
        string.format("%d ÷ %d = %d。", a, b, q))
end

local function gen_div_two(rng, difficulty, unit, semester, skill)
    local b = ri(rng, 10, 99)
    local q = ri(rng, 10, 99)
    local a = b * q
    return number_q(semester, unit, skill, difficulty,
        string.format("%d ÷ %d = ?", a, b), q,
        string.format("%d ÷ %d = %d。", a, b, q))
end

local function gen_decimal_add(rng, difficulty, unit, semester, skill)
    local a = ri(rng, 10, 900) / 10
    local b = ri(rng, 10, 900) / 10
    local answer = math.floor((a + b) * 10 + 0.5) / 10
    local correct = string.format("%.1f", answer)
    return choice_q(semester, unit, skill, difficulty,
        string.format("%.1f + %.1f = ?", a, b), correct,
        { string.format("%.1f", answer + 0.1), string.format("%.1f", answer + 1), string.format("%.1f", math.max(0, answer - 0.1)) },
        string.format("%.1f + %.1f = %.1f。", a, b, answer), rng)
end

local function gen_decimal_mul(rng, difficulty, unit, semester, skill)
    local a = ri(rng, 10, 99) / 10
    local b = ri(rng, 2, 9)
    local answer = math.floor(a * b * 10 + 0.5) / 10
    local correct = string.format("%.1f", answer)
    return choice_q(semester, unit, skill, difficulty,
        string.format("%.1f × %d = ?", a, b), correct,
        { string.format("%.1f", answer + 0.1), string.format("%.1f", answer + 1), string.format("%.1f", math.max(0, answer - 0.1)) },
        string.format("%.1f × %d = %.1f。", a, b, answer), rng)
end

local function gen_decimal_div(rng, difficulty, unit, semester, skill)
    local b = ri(rng, 2, 9)
    local q = ri(rng, 10, 99) / 10
    local a = math.floor(b * q * 10 + 0.5) / 10
    local correct = string.format("%.1f", q)
    return choice_q(semester, unit, skill, difficulty,
        string.format("%.1f ÷ %d = ?", a, b), correct,
        { string.format("%.1f", q + 0.1), string.format("%.1f", q + 1), string.format("%.1f", math.max(0, q - 0.1)) },
        string.format("%.1f ÷ %d = %.1f。", a, b, q), rng)
end

local function gen_fraction_add(rng, difficulty, unit, semester, skill)
    local d = ri(rng, 4, 12)
    local a = ri(rng, 1, d - 1)
    local b = ri(rng, 1, d - a)
    local answer = (a + b) .. "/" .. d
    return choice_q(semester, unit, skill, difficulty,
        string.format("%d/%d + %d/%d = ?", a, d, b, d),
        answer, { (a + b + 1) .. "/" .. d, (a + b) .. "/" .. (d + 1), a .. "/" .. d },
        string.format("同分母分数相加，分母不变，分子相加：%d/%d + %d/%d = %s。", a, d, b, d, answer), rng)
end

local function gen_fraction_mul(rng, difficulty, unit, semester, skill)
    local a = ri(rng, 1, 5)
    local b = ri(rng, 1, 5)
    local c = ri(rng, 2, 6)
    local d = ri(rng, 2, 6)
    local answer = (a * c) .. "/" .. (b * d)
    return choice_q(semester, unit, skill, difficulty,
        string.format("%d/%d × %d/%d = ?", a, b, c, d),
        answer, { (a * c + 1) .. "/" .. (b * d), (a * c) .. "/" .. (b * d + 1), (a + c) .. "/" .. (b + d) },
        string.format("分数相乘，分子乘分子，分母乘分母，结果是 %s。", answer), rng)
end

local function gen_fraction_div(rng, difficulty, unit, semester, skill)
    local a = ri(rng, 1, 5)
    local b = ri(rng, 2, 6)
    local c = ri(rng, 1, 5)
    local d = ri(rng, 2, 6)
    local answer = (a * d) .. "/" .. (b * c)
    return choice_q(semester, unit, skill, difficulty,
        string.format("%d/%d ÷ %d/%d = ?", a, b, c, d),
        answer, { (a * d + 1) .. "/" .. (b * c), (a * d) .. "/" .. (b * c + 1), (a + d) .. "/" .. (b + c) },
        string.format("除以一个分数等于乘它的倒数，结果是 %s。", answer), rng)
end

local function gen_percent(rng, difficulty, unit, semester, skill)
    local p = ri(rng, 1, 9) * 10
    local n = ri(rng, 2, 20) * 10
    local answer = math.floor(n * p / 100)
    return number_q(semester, unit, skill, difficulty,
        string.format("%d的%d%%是多少？", n, p), answer,
        string.format("%d × %d%% = %d。", n, p, answer))
end

local function gcd(a, b)
    while b ~= 0 do a, b = b, a % b end
    return a
end

local function gen_ratio(rng, difficulty, unit, semester, skill)
    local a = ri(rng, 1, 9)
    local b = ri(rng, 1, 9)
    local g = gcd(a, b)
    local ra, rb = a / g, b / g
    local k = ri(rng, 2, 9)
    local answer = ra .. ":" .. rb
    return choice_q(semester, unit, skill, difficulty,
        string.format("把 %d:%d 化成最简整数比。", a * k, b * k),
        answer, { (a * k) .. ":" .. (b * k), (ra + 1) .. ":" .. rb, ra .. ":" .. (rb + 1) },
        string.format("前项和后项同时除以%d，得到 %s。", g * k, answer), rng)
end

local function gen_proportion(rng, difficulty, unit, semester, skill)
    local a = ri(rng, 1, 5)
    local b = a * ri(rng, 1, 5)
    local c = ri(rng, 1, 5)
    local x = b * c / a
    return number_q(semester, unit, skill, difficulty,
        string.format("如果 %d:%d = %d:x，那么 x 是多少？", a, b, c), x,
        string.format("%d:%d = %d:%d，所以 x=%d。", a, b, c, x, x))
end

local function gen_equation(rng, difficulty, unit, semester, skill)
    local x = ri(rng, 2, 30)
    local a = ri(rng, 2, 20)
    local answer = x
    return number_q(semester, unit, skill, difficulty,
        string.format("x + %d = %d，x 是多少？", a, x + a), answer,
        string.format("x = %d - %d = %d。", x + a, a, answer))
end

local function gen_area(rng, difficulty, unit, semester, skill)
    local a = ri(rng, 3, 20)
    local b = ri(rng, 2, 15)
    local answer = a * b
    return number_q(semester, unit, skill, difficulty,
        string.format("一个长方形长%d米，宽%d米，面积是多少平方米？", a, b), answer,
        string.format("长方形面积=长×宽=%d×%d=%d平方米。", a, b, answer), "平方米")
end

local function gen_circle(rng, difficulty, unit, semester, skill)
    local r = ri(rng, 1, 9)
    local answer = math.floor(3.14 * r * r * 100 + 0.5) / 100
    local correct = string.format("%.2f", answer)
    return choice_q(semester, unit, skill, difficulty,
        string.format("一个圆的半径是%d厘米，面积是多少平方厘米？（π取3.14）", r), correct,
        { string.format("%.2f", answer + 3.14), string.format("%.2f", answer + 6.28), string.format("%.2f", math.max(0, answer - 3.14)) },
        string.format("圆面积=πr²=3.14×%d×%d=%.2f平方厘米。", r, r, answer), rng)
end

local function gen_volume(rng, difficulty, unit, semester, skill)
    local a = ri(rng, 2, 10)
    local b = ri(rng, 2, 10)
    local c = ri(rng, 2, 10)
    local answer = a * b * c
    return number_q(semester, unit, skill, difficulty,
        string.format("一个长方体长%d厘米、宽%d厘米、高%d厘米，体积是多少立方厘米？", a, b, c), answer,
        string.format("长方体体积=长×宽×高=%d×%d×%d=%d立方厘米。", a, b, c, answer), "立方厘米")
end

local function gen_angle(rng, difficulty, unit, semester, skill)
    local a = ri(rng, 10, 80)
    local answer = 90 - a
    return number_q(semester, unit, skill, difficulty,
        string.format("一个锐角是%d度，它的余角是多少度？", a), answer,
        string.format("余角=90°-%d°=%d°。", a, answer), "度")
end

local function gen_unit_convert(rng, difficulty, unit, semester, skill)
    local n = ri(rng, 2, 9)
    local answer = n * 100
    return number_q(semester, unit, skill, difficulty,
        string.format("%d米等于多少厘米？", n), answer,
        string.format("1米=100厘米，%d米=%d厘米。", n, answer), "厘米")
end

local function gen_time(rng, difficulty, unit, semester, skill)
    local a = ri(rng, 1, 11)
    local b = ri(rng, a + 1, 12)
    local answer = b - a
    return number_q(semester, unit, skill, difficulty,
        string.format("从上午%d时到中午%d时，经过了几小时？", a, b), answer,
        string.format("%d-%d=%d小时。", b, a, answer), "小时")
end

local function gen_money(rng, difficulty, unit, semester, skill)
    local a = ri(rng, 5, 20)
    local b = ri(rng, 1, a - 1)
    local answer = a - b
    return number_q(semester, unit, skill, difficulty,
        string.format("小明有%d元，买文具用了%d元，还剩多少元？", a, b), answer,
        string.format("%d-%d=%d元。", a, b, answer), "元")
end

local function gen_count(rng, difficulty, unit, semester, skill)
    local n = ri(rng, 1, 10)
    return number_q(semester, unit, skill, difficulty,
        string.format("盘子里有%d个苹果，用数字表示是几？", n), n,
        string.format("%d个苹果用数字%d表示。", n, n))
end

local function gen_place_value(rng, difficulty, unit, semester, skill)
    local n = ri(rng, 10, 9999)
    local place, label = 1, "个"
    if difficulty == 2 then place, label = 10, "十"
    elseif difficulty == 3 then place, label = 100, "百" end
    local digit = math.floor(n / place) % 10
    return number_q(semester, unit, skill, difficulty,
        string.format("%d的%s位数字是几？", n, label), digit,
        string.format("%d的%s位是%d。", n, label, digit))
end

local function gen_factor(rng, difficulty, unit, semester, skill)
    local a = ri(rng, 2, 12)
    local b = ri(rng, 2, 12)
    local answer = a * b / gcd(a, b)
    return number_q(semester, unit, skill, difficulty,
        string.format("%d和%d的最小公倍数是多少？", a, b), answer,
        string.format("%d和%d的最大公因数是%d，最小公倍数是%d。", a, b, gcd(a, b), answer))
end

local function gen_negative(rng, difficulty, unit, semester, skill)
    local a = ri(rng, 1, 9)
    local b = ri(rng, a + 1, 12)
    return number_q(semester, unit, skill, difficulty,
        string.format("-%d 和 -%d 哪个大？请填较大的数（不带负号）。", a, b), a,
        string.format("负数越接近0越大，所以-%d大于-%d。", a, b))
end

local function gen_average(rng, difficulty, unit, semester, skill)
    local a = 3 * ri(rng, 1, 8)
    local b = 3 * ri(rng, 1, 8)
    local c = 3 * ri(rng, 1, 8)
    local answer = (a + b + c) / 3
    return number_q(semester, unit, skill, difficulty,
        string.format("三个数%d、%d、%d的平均数是多少？", a, b, c), answer,
        string.format("(%d+%d+%d)÷3=%d。", a, b, c, answer))
end

local function gen_operation_laws(rng, difficulty, unit, semester, skill)
    local a = ri(rng, 2, 9)
    local b = ri(rng, 2, 9)
    local c = ri(rng, 2, 9)
    local answer = a * (b + c)
    return number_q(semester, unit, skill, difficulty,
        string.format("%d × (%d + %d) = ?", a, b, c), answer,
        string.format("先算括号：%d+%d=%d，再算乘法：%d×%d=%d。", b, c, b + c, a, b + c, answer))
end

local function gen_word_problem_generic(rng, difficulty, unit, semester, skill)
    local a = ri(rng, 2, 20)
    local b = ri(rng, 2, 10)
    local answer = a * b
    return number_q(semester, unit, skill, difficulty,
        string.format("每盒有%d支铅笔，%d盒一共有多少支？", a, b), answer,
        string.format("%d×%d=%d支。", a, b, answer), "支")
end

local skill_generators = {
    count_10 = gen_count,
    position = function(rng, d, unit, sem, grade, skill) return choice_from(concept_position, rng, d, unit, sem, skill) end,
    add_sub_5 = gen_add_sub(1, 4, 5),
    shape = function(rng, d, unit, sem, grade, skill) return choice_from(concept_geometry, rng, d, unit, sem, skill) end,
    add_sub_10 = gen_add_sub(1, 9, 10),
    numbers_20 = gen_place_value,
    time = gen_time,
    add_carry_20 = gen_add_carry,
    sub_borrow_20 = gen_sub_borrow,
    classify = function(rng, d, unit, sem, grade, skill) return choice_from(concept_data, rng, d, unit, sem, skill) end,
    numbers_100 = gen_place_value,
    money = gen_money,
    add_sub_100_simple = gen_add_sub(10, 50, 100),
    pattern = function(rng, d, unit, sem, grade, skill) return choice_from(concept_reasoning, rng, d, unit, sem, skill) end,
    combination = function(rng, d, unit, sem, grade, skill) return choice_from(concept_reasoning, rng, d, unit, sem, skill) end,
    length = function(rng, d, unit, sem, grade, skill) return choice_from(concept_measure, rng, d, unit, sem, skill) end,
    add_sub_100 = gen_add_sub(10, 90, 100),
    angle = function(rng, d, unit, sem, grade, skill) return choice_from(concept_geometry, rng, d, unit, sem, skill) end,
    mul_table = gen_mul_table,
    observe = function(rng, d, unit, sem, grade, skill) return choice_from(concept_geometry, rng, d, unit, sem, skill) end,
    div_table = gen_div_table,
    symmetry = function(rng, d, unit, sem, grade, skill) return choice_from(concept_geometry, rng, d, unit, sem, skill) end,
    mixed_ops = gen_mixed,
    remainder = gen_remainder,
    numbers_10k = gen_place_value,
    mass = function(rng, d, unit, sem, grade, skill) return choice_from(concept_measure, rng, d, unit, sem, skill) end,
    reasoning = function(rng, d, unit, sem, grade, skill) return choice_from(concept_reasoning, rng, d, unit, sem, skill) end,
    add_sub_10k = gen_add_sub(100, 4000, 9999),
    measure = function(rng, d, unit, sem, grade, skill) return choice_from(concept_measure, rng, d, unit, sem, skill) end,
    times = function(rng, d, unit, sem, grade, skill) return choice_from(concept_reasoning, rng, d, unit, sem, skill) end,
    multi_digit_mul = gen_multi_digit_mul,
    rectangle_square = function(rng, d, unit, sem, grade, skill) return choice_from(concept_geometry, rng, d, unit, sem, skill) end,
    fraction_intro = function(rng, d, unit, sem, grade, skill) return choice_from(concept_numbers, rng, d, unit, sem, skill) end,
    direction = function(rng, d, unit, sem, grade, skill) return choice_from(concept_position, rng, d, unit, sem, skill) end,
    div_multi_digit = gen_div_multi,
    statistics = function(rng, d, unit, sem, grade, skill) return choice_from(concept_data, rng, d, unit, sem, skill) end,
    two_digit_mul = gen_two_digit_mul,
    area = gen_area,
    calendar = function(rng, d, unit, sem, grade, skill) return choice_from(concept_measure, rng, d, unit, sem, skill) end,
    decimal_intro = function(rng, d, unit, sem, grade, skill) return choice_from(concept_numbers, rng, d, unit, sem, skill) end,
    large_numbers = gen_place_value,
    area_units = function(rng, d, unit, sem, grade, skill) return choice_from(concept_measure, rng, d, unit, sem, skill) end,
    angle_measure = gen_angle,
    three_digit_mul = gen_three_digit_mul,
    parallelogram_trapezoid = function(rng, d, unit, sem, grade, skill) return choice_from(concept_geometry, rng, d, unit, sem, skill) end,
    div_two_digit = gen_div_two,
    bar_chart = function(rng, d, unit, sem, grade, skill) return choice_from(concept_data, rng, d, unit, sem, skill) end,
    optimization = function(rng, d, unit, sem, grade, skill) return choice_from(concept_reasoning, rng, d, unit, sem, skill) end,
    operation_laws = gen_operation_laws,
    decimal_meaning = function(rng, d, unit, sem, grade, skill) return choice_from(concept_numbers, rng, d, unit, sem, skill) end,
    triangle = function(rng, d, unit, sem, grade, skill) return choice_from(concept_geometry, rng, d, unit, sem, skill) end,
    decimal_add_sub = gen_decimal_add,
    average_chart = gen_average,
    chicken_rabbit = function(rng, d, unit, sem, grade, skill) return choice_from(concept_reasoning, rng, d, unit, sem, skill) end,
    decimal_mul = gen_decimal_mul,
    decimal_div = gen_decimal_div,
    probability = function(rng, d, unit, sem, grade, skill) return choice_from(concept_data, rng, d, unit, sem, skill) end,
    equation = gen_equation,
    polygon_area = gen_area,
    planting = function(rng, d, unit, sem, grade, skill) return choice_from(concept_reasoning, rng, d, unit, sem, skill) end,
    factor_multiple = gen_factor,
    cuboid_cube = gen_volume,
    fraction_meaning = function(rng, d, unit, sem, grade, skill) return choice_from(concept_numbers, rng, d, unit, sem, skill) end,
    rotation = function(rng, d, unit, sem, grade, skill) return choice_from(concept_geometry, rng, d, unit, sem, skill) end,
    fraction_add_sub = gen_fraction_add,
    line_chart = function(rng, d, unit, sem, grade, skill) return choice_from(concept_data, rng, d, unit, sem, skill) end,
    find_defective = function(rng, d, unit, sem, grade, skill) return choice_from(concept_reasoning, rng, d, unit, sem, skill) end,
    fraction_mul = gen_fraction_mul,
    fraction_div = gen_fraction_div,
    ratio = gen_ratio,
    circle = gen_circle,
    percent = gen_percent,
    pie_chart = function(rng, d, unit, sem, grade, skill) return choice_from(concept_data, rng, d, unit, sem, skill) end,
    number_shape = function(rng, d, unit, sem, grade, skill) return choice_from(concept_reasoning, rng, d, unit, sem, skill) end,
    negative = gen_negative,
    cylinder_cone = function(rng, d, unit, sem, grade, skill) return choice_from(concept_geometry, rng, d, unit, sem, skill) end,
    proportion = gen_proportion,
    math_thinking = function(rng, d, unit, sem, grade, skill) return choice_from(concept_reasoning, rng, d, unit, sem, skill) end,
    word_problem = gen_word_problem_generic,
}

local function generic_skill_question(skill, grade, edition, semester, unit, difficulty, rng)
    local fn = skill_generators[skill] or function(r, d, u, s, g, k)
        return choice_from(concept_general, r, d, u, s, k or "word_problem")
    end
    local q = fn(rng, difficulty, unit, semester, grade, skill)
    q.grade = grade
    q.edition = edition
    q.unit_name = nil
    return q
end

function decorate_question(q, opts, unit, unit_name)
    if not q then return q end
    q.grade = opts.grade or 2
    q.edition = opts.edition or (opts.subject == "chinese" and "tongbian" or "renjiao")
    q.semester = opts.semester or "upper"
    q.unit = unit or q.unit
    q.unit_name = unit_name
    seq = seq + 1
    local sem_letter = q.semester == "lower" and "l" or "u"
    q.id = string.format("math-%s-g%d%s-%s-%s-%d-%d", q.edition, q.grade, sem_letter, q.unit or "all", q.skill or "q", os.time(), seq)
    return q
end

function MathGen.generic_units(grade, edition, semester)
    local units = Catalog.units(plugin_path, "math", edition or "renjiao", grade or 2, semester or "upper")
    return units
end

function MathGen.skill_question(skill, opts, rng)
    opts = opts or {}
    rng = rng or math.random
    local grade = tonumber(opts.grade) or 2
    local edition = opts.edition or "renjiao"
    local semester = opts.semester == "lower" and "lower" or "upper"
    local unit = opts.unit or "m1"
    local difficulty = tonumber(opts.difficulty) or 2
    if difficulty < 1 then difficulty = 1 elseif difficulty > 3 then difficulty = 3 end
    local q = generic_skill_question(skill, grade, edition, semester, unit, difficulty, rng)
    return decorate_question(q, { grade = grade, edition = edition, semester = semester },
        unit, MathGen.unit_name(grade, edition, semester, unit))
end


function MathGen.set_plugin_path(path)
    if type(path) == "string" and path ~= "" then plugin_path = path end
end

function MathGen.units(a, b, c)
    if type(a) == "number" then
        local units = Catalog.units(plugin_path, "math", b or "renjiao", a, c or "upper")
        if units then return units end
        return unit_names[c or "upper"] or unit_names.upper
    end
    local semester = a or "upper"
    return unit_names[semester] or unit_names.upper
end

function MathGen.unit_name(a, b, c, d)
    if type(a) == "number" then
        local unit = Catalog.find_unit(plugin_path, "math", b or "renjiao", a, c or "upper", d)
        return unit and unit.name or d
    end
    for _, item in ipairs(MathGen.units(a)) do
        if item.id == b then return item.name end
    end
    return b
end

local function catalog_unit(opts, semester)
    local grade = tonumber(opts.grade) or 2
    local edition = opts.edition or "renjiao"
    local units = Catalog.units(plugin_path, "math", edition, grade, semester)
    if not units then return nil end
    local unit = opts.unit
    if not unit or unit == "all" then
        unit = pick(opts.rng or math.random, units).id
    end
    for _, item in ipairs(units) do
        if item.id == unit then return item, grade, edition end
    end
    return nil
end

function MathGen.generate(opts, rng)
    opts = opts or {}
    rng = rng or math.random
    local semester = opts.semester == "lower" and "lower" or "upper"
    local grade = tonumber(opts.grade) or 2
    local edition = opts.edition or "renjiao"
    local difficulty = tonumber(opts.difficulty) or 2
    if difficulty < 1 then difficulty = 1 elseif difficulty > 3 then difficulty = 3 end

    if grade == 2 and edition == "renjiao" then
        local unit = opts.unit
        local units = MathGen.units(semester)
        if not unit or unit == "all" then
            unit = pick(rng, units).id
        end
        local generator = generators[semester][unit]
        if generator then
            local q = generator(rng, difficulty)
            return decorate_question(q, {
                grade = 2, edition = "renjiao", semester = semester,
            }, unit, MathGen.unit_name(semester, unit))
        end
    end

    local unit_meta, resolved_grade, resolved_edition = catalog_unit({
        unit = opts.unit, grade = grade, edition = edition, rng = rng,
    }, semester)
    if not unit_meta then
        return decorate_question(word_problem(rng, difficulty, nil, semester),
            { grade = grade, edition = edition, semester = semester }, nil)
    end
    local skills = unit_meta.skills or { "word_problem" }
    local skill = opts.skill or skills[ri(rng, 1, #skills)]
    local q = generic_skill_question(skill, resolved_grade, resolved_edition, semester, unit_meta.id, difficulty, rng)
    return decorate_question(q, {
        grade = resolved_grade, edition = resolved_edition, semester = semester,
    }, unit_meta.id, unit_meta.name)
end

function MathGen.generate_word_problem(opts, rng)
    opts = opts or {}
    rng = rng or math.random
    local semester = opts.semester == "lower" and "lower" or "upper"
    local difficulty = tonumber(opts.difficulty) or 2
    if difficulty < 1 then difficulty = 1 elseif difficulty > 3 then difficulty = 3 end
    local grade = tonumber(opts.grade) or 2
    local edition = opts.edition or "renjiao"
    if grade == 2 and edition == "renjiao" then
        local q = word_problem(rng, difficulty, nil, semester)
        return decorate_question(q, {
            grade = 2, edition = "renjiao", semester = semester,
        }, q.unit, MathGen.unit_name(2, "renjiao", semester, q.unit))
    end
    local q = gen_word_problem_generic(rng, difficulty, opts.unit or "m1", semester, "word_problem")
    return decorate_question(q, { grade = grade, edition = edition, semester = semester }, opts.unit or "m1")
end

return MathGen
