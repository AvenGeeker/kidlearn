--[[--
Full-screen KidLearn UI.

The view keeps one widget on screen and swaps its body between home, unit
selection, quiz, feedback, summary, wrong book, badges and settings. This is
much lighter on e-ink than opening a new window for every question.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local util = require("util")
local VerticalGroup = require("ui/widget/verticalgroup")

local AIBank = require("core.ai_bank")
local AIClient = require("core.ai_client")
local AIConfig = require("core.ai_config")
local AIVariant = require("core.ai_variant")
local Badges = require("core.badges")
local Bank = require("core.bank")
local Catalog = require("core.catalog")
local MathGen = require("core.mathgen")
local Progress = require("core.progress")
local Session = require("core.session")
local Widgets = require("ui/widgets")

local Screen = Device.screen
local _ = require("gettext")

local MainView = InputContainer:extend{
    covers_fullscreen = true,
}

local SUBJECT_LABEL = { chinese = "语文", math = "数学" }
local SKILL_LABEL = {
    pinyin = "拼音", measure_word = "量词", synonym = "近义词", antonym = "反义词",
    sentence = "句子", sentence_choice = "句子", word_choice = "词语", accumulation = "积累", reading = "阅读",
    challenge = "拓展",
    add_sub = "口算", table_mul = "乘法口诀", division = "除法", mixed_ops = "混合运算",
    remainder = "有余数除法", length = "长度单位", angles = "角", observe_object = "观察物体",
    time = "认识时间", combinations = "搭配", data = "数据整理", symmetry = "图形运动",
    numbers_10k = "万以内数", mass = "克和千克", reasoning = "推理",
    count_10 = "数一数", position = "位置", add_sub_5 = "5以内加减", shape = "认识图形",
    add_sub_10 = "10以内加减", numbers_20 = "20以内数", add_carry_20 = "20以内进位加",
    sub_borrow_20 = "20以内退位减", classify = "分类", numbers_100 = "100以内数",
    money = "人民币", add_sub_100_simple = "100以内加减", pattern = "找规律",
    combination = "搭配", measure = "测量", add_sub_10k = "万以内加减", times = "倍的认识",
    multi_digit_mul = "多位数乘法", rectangle_square = "长方形和正方形",
    fraction_intro = "分数初步", direction = "方向", div_multi_digit = "除法",
    statistics = "统计", two_digit_mul = "两位数乘法", area = "面积", calendar = "年月日",
    decimal_intro = "小数初步", large_numbers = "大数", area_units = "面积单位",
    angle_measure = "角的度量", three_digit_mul = "三位数乘法",
    parallelogram_trapezoid = "平行四边形和梯形", div_two_digit = "两位数除法",
    bar_chart = "条形统计图", optimization = "优化", operation_laws = "运算定律",
    decimal_meaning = "小数意义", triangle = "三角形", decimal_add_sub = "小数加减",
    average_chart = "平均数", chicken_rabbit = "鸡兔同笼", decimal_mul = "小数乘法",
    probability = "可能性", equation = "方程", polygon_area = "多边形面积",
    planting = "植树问题", factor_multiple = "因数倍数", cuboid_cube = "长方体正方体",
    fraction_meaning = "分数意义", rotation = "图形旋转", fraction_add_sub = "分数加减",
    line_chart = "折线统计图", find_defective = "找次品", fraction_mul = "分数乘法",
    fraction_div = "分数除法", ratio = "比", circle = "圆", percent = "百分数",
    pie_chart = "扇形统计图", number_shape = "数与形", negative = "负数",
    cylinder_cone = "圆柱圆锥", proportion = "比例", math_thinking = "数学思考",
    word_problem = "应用题",
    word_add = "应用题", word_sub = "应用题", word_mul = "应用题", word_div = "应用题",
    word_compare = "应用题", word_two_step = "应用题", word_length = "应用题",
    word_mass = "应用题", word_time = "应用题", word_remainder = "应用题",
}
local function truncate(text, max_chars)
    if not text then return "" end
    local max_bytes = max_chars * 3
    if #text <= max_bytes then return text end
    return util.fixUtf8(text:sub(1, max_bytes), "") .. "…"
end

local function answer_text(question)
    if question.answer_mode == "number" then
        return tostring(question.answer) .. (question.unit_hint or "")
    end
    local prefix = ({ "A. ", "B. ", "C. ", "D. " })[question.answer] or ""
    return prefix .. (question.options[question.answer] or "")
end

function MainView:init()
    self.dimen = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    self.plugin_path = self.plugin_path
    self.progress = Progress.open()
    self.state = "home"
    self.selected = nil
    self.number_input = ""
    self.feedback = nil
    self.summary = nil
    self.new_badges = {}
    if self.ai_generating == nil then self.ai_generating = false end

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    self.title_bar = TitleBar:new{
        fullscreen = true,
        width = self.dimen.w,
        align = "left",
        title = _("小小学习家"),
        title_face = Font:getFace("smalltfont", 22),
        title_h_padding = Size.padding.large,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }
    self.body = VerticalGroup:new{
        align = "center",
        width = self.dimen.w,
    }
    self.main = VerticalGroup:new{
        align = "center",
        width = self.dimen.w,
        self.title_bar,
        self.body,
    }
    self[1] = self.main
    self:render_home()
end

function MainView:paintTo(bb, x, y)
    -- The plugin is a full-screen page, not a dialog over the reader. Paint an
    -- opaque background first so the underlying reader page never shows through.
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    InputContainer.paintTo(self, bb, x, y)
end

function MainView:set_title(text)
    self.title_bar:setTitle(text)
end

function MainView:set_body(widget)
    self.body:clear()
    self.body._size = nil
    table.insert(self.body, widget)
    self.main._size = nil
    UIManager:setDirty(self, "ui")
end

function MainView:close_view()
    self.closed = true
    self.progress:flush()
    UIManager:close(self)
end

function MainView:onClose()
    if self.state == "quiz" or self.state == "feedback" then
        UIManager:show(ConfirmBox:new{
            text = _("本轮练习还没有完成，确定退出吗？\n\n已经答过的题目和星星会保存。"),
            ok_text = _("退出"),
            cancel_text = _("继续练习"),
            ok_callback = function() self:close_view() end,
        })
        return true
    end
    self:close_view()
    return true
end

function MainView:onCloseWidget()
    self.closed = true
    self.progress:flush()
end

function MainView:subject_label(subject)
    return SUBJECT_LABEL[subject] or "练习"
end

function MainView:semester_label()
    return self.progress.data.settings.semester == "lower" and "下册" or "上册"
end

local GRADE_LABEL = { "一年级", "二年级", "三年级", "四年级", "五年级", "六年级" }

function MainView:grade_label()
    local grade = tonumber(self.progress.data.settings.grade) or 2
    return GRADE_LABEL[grade] or (grade .. "年级")
end

function MainView:edition_name(subject)
    local settings = self.progress.data.settings
    local edition = subject == "chinese" and settings.chinese_edition or settings.math_edition
    return Catalog.edition_name(self.plugin_path, subject, edition or (subject == "chinese" and "tongbian" or "renjiao"))
end

function MainView:course_label()
    return string.format("%s%s · %s · %s", self:grade_label(), self:semester_label(),
        self:edition_name("chinese"), self:edition_name("math"))
end

function MainView:unit_name(question)
    if question.challenge then return "数学拓展" end
    if question.unit_name then return question.unit_name end
    local grade = tonumber(question.grade) or 2
    local semester = question.semester or self.progress.data.settings.semester
    if question.subject == "math" then
        local edition = question.edition or "renjiao"
        return MathGen.unit_name(grade, edition, semester, question.unit)
    end
    local edition = question.edition or "tongbian"
    local units = Bank.units(self.plugin_path, "chinese", grade, semester, edition) or {}
    for _, unit in ipairs(units) do
        if unit.id == question.unit then return unit.name end
    end
    return question.unit or ""
end

function MainView:get_ai_bank()
    if not self.ai_bank then self.ai_bank = AIBank.open() end
    return self.ai_bank
end

function MainView:ai_profile()
    return AIConfig.active_profile(self.progress.data.settings.ai)
end

function MainView:ai_ready()
    local profile = self:ai_profile()
    if not profile then return nil, "请先配置 AI 服务" end
    local ok, err = AIConfig.validate(profile)
    if not ok then return nil, err end
    return profile
end

function MainView:ai_status_label()
    local profile = self:ai_profile()
    if not profile then return "未配置" end
    local ok = AIConfig.validate(profile)
    if not ok then return string.format("%s · 未完成", profile.name) end
    return string.format("%s · %s", profile.name, profile.model)
end

function MainView:find_ai_profile(id)
    return AIConfig.find(self.progress.data.settings.ai, id)
end

function MainView:ensure_ai_ready(callback)
    local profile, err = self:ai_ready()
    if not profile then
        UIManager:show(InfoMessage:new{
            text = "AI 出题还没配置好：" .. tostring(err) .. "\n\n请先在设置中填写 API Key 和模型。",
            timeout = 4,
        })
        self:render_ai_settings()
        return
    end
    callback(profile)
end

function MainView:open_ai_text_input(title, value, password, on_save)
    local dialog
    dialog = InputDialog:new{
        title = title,
        input = value or "",
        text_type = password and "password" or nil,
        buttons = {
            {
                {
                    text = "取消",
                    id = "close",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = "保存",
                    callback = function()
                        local text = dialog:getInputText()
                        UIManager:close(dialog)
                        on_save(text)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function MainView:show_ai_error(message, retry)
    if retry then
        UIManager:show(ConfirmBox:new{
            text = "AI 出题失败：" .. tostring(message),
            ok_text = "重试",
            cancel_text = "返回",
            ok_callback = retry,
        })
    else
        UIManager:show(InfoMessage:new{
            text = "AI 出题失败：" .. tostring(message),
            timeout = 5,
        })
    end
end

function MainView:run_ai_test(profile)
    NetworkMgr:runWhenOnline(function()
        local loading = InfoMessage:new{ text = "正在测试 AI 服务，请稍候…" }
        UIManager:show(loading)
        UIManager:forceRePaint()
        AIClient.test(profile, {
            transport = self.ai_transport,
            callback = function(ok, err)
                UIManager:close(loading)
                if self.closed then return end
                if ok then
                    UIManager:show(InfoMessage:new{ text = "连接成功，可以开始 AI 出题了。", timeout = 4 })
                else
                    UIManager:show(InfoMessage:new{ text = "连接失败：" .. tostring(err), timeout = 6 })
                end
            end,
        })
    end)
end

function MainView:generate_ai(items, per_item)
    if self.ai_generating then
        UIManager:show(InfoMessage:new{ text = "AI 正在生成上一组变种，请稍候。", timeout = 3 })
        return
    end
    local profile, err = self:ai_ready()
    if not profile then
        self:show_ai_error(err)
        return
    end
    local system, user = AIVariant.build_prompt(items, per_item)
    if not system then
        self:show_ai_error(user)
        return
    end
    local bank = self:get_ai_bank()
    local now = os.time()
    local group_id = bank:next_group_id(now)
    NetworkMgr:runWhenOnline(function()
        if self.ai_generating then return end
        self.ai_generating = true
        local loading = InfoMessage:new{
            text = "AI 正在出变种题，请稍候…\n通常需要 10–60 秒，请不要退出。",
        }
        UIManager:show(loading)
        UIManager:forceRePaint()
        local function finish(text, request_err)
            UIManager:close(loading)
            self.ai_generating = false
            if self.closed then return end
            if request_err then
                self:show_ai_error(request_err, function() self:generate_ai(items, per_item) end)
                return
            end
            local questions, parse_err = AIVariant.parse(text, items, per_item, {
                group_id = group_id,
                now = now,
                grade = self.progress.data.settings.grade,
                semester = self.progress.data.settings.semester,
            })
            if not questions then
                self:show_ai_error(parse_err, function() self:generate_ai(items, per_item) end)
                return
            end
            local group = AIVariant.new_group(items, questions, { group_id = group_id, now = now }, profile)
            local saved, save_err = bank:add_group(group)
            if not saved then
                self:show_ai_error(save_err)
                return
            end
            self:render_ai_preview(group_id)
        end
        AIClient.generate(profile, system, user, {
            transport = self.ai_transport,
            callback = finish,
        })
    end)
end

function MainView:start_ai_single(item)
    self:ensure_ai_ready(function()
        self:generate_ai({ item }, 3)
    end)
end

function MainView:start_ai_batch()
    local wrong = self.progress:wrong_items()
    if #wrong == 0 then
        UIManager:show(InfoMessage:new{ text = "错题本还是空的，先做几道题吧。", timeout = 3 })
        return
    end
    local items = {}
    for index = 1, math.min(#wrong, 5) do table.insert(items, wrong[index]) end
    self:ensure_ai_ready(function()
        self:generate_ai(items, 2)
    end)
end

function MainView:render_home()
    self.state = "home"
    self:set_title(_("小小学习家"))
    local cw = Widgets.width()
    local total = self.progress:total()
    local today = self.progress:today()
    local streak = self.progress.data.streak.current
    local wrong_count = #self.progress:wrong_items()
    local badge_count = Badges.count(self.progress)

    local stat_width = math.floor(cw / 3)
    local stats = HorizontalGroup:new{
        align = "center",
        Widgets.stat(string.format("★ %d", total.points), "星星", stat_width),
        Widgets.stat(string.format("%d 天", streak), "连续学习", stat_width),
        Widgets.stat(string.format("%d/%d", today.answered, today.goal), "今日", stat_width),
    }
    local stats_card = Widgets.card(VerticalGroup:new{
        align = "center",
        Widgets.label(self:course_label(), {
            size = 16, color = Blitbuffer.COLOR_DARK_GRAY,
        }),
        Widgets.vspace(Size.span.vertical_default),
        stats,
        Widgets.vspace(Size.span.vertical_default),
        Widgets.progress(today.goal > 0 and today.answered / today.goal or 0, cw - 2 * Size.padding.default),
    }, { width = cw })

    local half = math.floor((cw - Size.span.horizontal_default) / 2)
    local subject_row = HorizontalGroup:new{
        align = "center",
        Widgets.button("语文练习", {
            width = half,
            height = Screen:scaleBySize(72),
            size = 24,
            callback = function() self:render_unit_select("chinese") end,
        }),
        Widgets.hspace(Size.span.horizontal_default),
        Widgets.button("数学练习", {
            width = half,
            height = Screen:scaleBySize(72),
            size = 24,
            callback = function() self:render_unit_select("math") end,
        }),
    }

    local tool_row_1 = HorizontalGroup:new{
        align = "center",
        Widgets.button(string.format("错题本（%d）", wrong_count), {
            width = half,
            callback = function() self:render_wrongbook() end,
        }),
        Widgets.hspace(Size.span.horizontal_default),
        Widgets.button("AI 题库", {
            width = half,
            callback = function() self:render_ai_bank() end,
        }),
    }
    local tool_row_2 = HorizontalGroup:new{
        align = "center",
        Widgets.button(string.format("奖章墙（%d/10）", badge_count), {
            width = half,
            callback = function() self:render_badges() end,
        }),
        Widgets.hspace(Size.span.horizontal_default),
        Widgets.button("设置", {
            width = half,
            callback = function() self:render_settings() end,
        }),
    }

    local content = VerticalGroup:new{
        align = "center",
        stats_card,
        Widgets.vspace(Size.span.vertical_large),
        Widgets.button("今日挑战：语文 5 题 + 数学 5 题", {
            width = cw,
            height = Screen:scaleBySize(68),
            size = 24,
            callback = function() self:start_session({ mode = "daily" }) end,
        }),
        Widgets.vspace(Size.span.vertical_default),
        subject_row,
        Widgets.vspace(Size.span.vertical_default),
        tool_row_1,
        Widgets.vspace(Size.span.vertical_default),
        tool_row_2,
    }
    self:set_body(content)
end

function MainView:render_unit_select(subject)
    self.state = "unit_select"
    self:set_title(self:subject_label(subject) .. "练习")
    local cw = Widgets.width()
    local settings = self.progress.data.settings
    local semester = settings.semester
    local grade = tonumber(settings.grade) or 2
    local edition = subject == "chinese" and settings.chinese_edition or settings.math_edition
    MathGen.set_plugin_path(self.plugin_path)
    local units
    if subject == "chinese" then
        units = Bank.units(self.plugin_path, "chinese", grade, semester, edition)
        if not units then
            local loaded, err = Bank.load(self.plugin_path, "chinese", grade, semester, edition)
            if not loaded then
                UIManager:show(InfoMessage:new{ text = "题库加载失败：" .. tostring(err) })
                self:render_home()
                return
            end
            units = loaded.units
        end
    else
        units = MathGen.units(grade, edition, semester) or MathGen.units(semester)
    end

    local content = VerticalGroup:new{
        align = "center",
        Widgets.label(string.format("%s%s · %s · 选择练习范围", self:grade_label(), self:semester_label(), self:edition_name(subject)), {
            size = 18, color = Blitbuffer.COLOR_DARK_GRAY,
        }),
        Widgets.vspace(Size.span.vertical_default),
        Widgets.button("综合练习（全部单元）", {
            width = cw,
            height = Screen:scaleBySize(60),
            size = 22,
            callback = function() self:start_session({ mode = "subject", subject = subject, unit = "all" }) end,
        }),
        Widgets.vspace(Size.span.vertical_default),
    }

    if subject == "math" then
        table.insert(content, Widgets.button("拓展挑战（数感 · 推理 · 几何 · 数据）", {
            width = cw,
            height = Screen:scaleBySize(60),
            size = 20,
            callback = function() self:start_session({ mode = "challenge", subject = "math", unit = "all" }) end,
        }))
        table.insert(content, Widgets.vspace(Size.span.vertical_default))
    end

    local half = math.floor((cw - Size.span.horizontal_default) / 2)
    local row
    for i, unit in ipairs(units) do
        local button = Widgets.button(unit.name, {
            width = half,
            height = Screen:scaleBySize(52),
            size = 19,
            callback = function()
                self:start_session({ mode = "subject", subject = subject, unit = unit.id })
            end,
        })
        if i % 2 == 1 then
            row = HorizontalGroup:new{ align = "center", button }
            table.insert(content, row)
            table.insert(content, Widgets.vspace(Size.span.vertical_default))
        else
            table.insert(row, Widgets.hspace(Size.span.horizontal_default))
            table.insert(row, button)
        end
    end
    table.insert(content, Widgets.button("返回首页", {
        width = cw,
        height = Screen:scaleBySize(48),
        size = 20,
        callback = function() self:render_home() end,
    }))
    self:set_body(content)
end

function MainView:start_session(opts)
    local settings = self.progress.data.settings
    local session, err = Session.new{
        mode = opts.mode,
        subject = opts.subject,
        unit = opts.unit,
        wrong_items = opts.wrong_items,
        ai_questions = opts.ai_questions,
        ai_group_id = opts.ai_group_id,
        semester = settings.semester,
        plugin_path = self.plugin_path,
        progress = self.progress,
    }
    if not session then
        UIManager:show(InfoMessage:new{
            text = "暂时不能开始练习：" .. tostring(err),
            timeout = 4,
        })
        return
    end
    self.session = session
    self.last_session_opts = opts
    self.state = "quiz"
    self.selected = nil
    self.number_input = ""
    self.feedback = nil
    self:render_quiz()
end

function MainView:quiz_title()
    if self.session.mode == "daily" then return "今日挑战" end
    if self.session.mode == "wrong" then return "错题复习" end
    if self.session.mode == "ai" then return "AI 强化" end
    if self.session.mode == "challenge" then return "数学拓展" end
    return self:subject_label(self.session.subject) .. "练习"
end

function MainView:render_header()
    local cw = Widgets.width()
    local third = math.floor(cw / 3)
    local total_points = self.progress.data.total.points
    return HorizontalGroup:new{
        align = "center",
        Widgets.center(Widgets.label(string.format("第 %d/%d 题", self.session:position(), self.session:total()), {
            size = 18, bold = true,
        }), third),
        Widgets.center(Widgets.label(string.format("连对 %d", self.session.combo), {
            size = 18, color = Blitbuffer.COLOR_DARK_GRAY,
        }), third),
        Widgets.center(Widgets.label(string.format("★ %d", total_points), {
            size = 18, bold = true,
        }), third),
    }
end

function MainView:render_question_card(question)
    local cw = Widgets.width()
    local unit_name = self:unit_name(question)
    local skill
    if question.challenge then
        skill = question.competency or "动脑"
    else
        skill = SKILL_LABEL[question.skill] or question.skill or question.type or ""
    end
    local tag = string.format("%s · %s", unit_name, skill)
    if question.ai_generated then tag = "AI 变种 · " .. tag end
    local inner_width = cw - 2 * Size.padding.large
    local parts = VerticalGroup:new{
        align = "left",
        Widgets.label(tag, { size = 16, color = Blitbuffer.COLOR_DARK_GRAY, max_width = cw - 2 * Size.padding.default }),
        Widgets.vspace(Size.span.vertical_default),
    }
    if question.passage and question.passage ~= "" then
        table.insert(parts, Widgets.card(VerticalGroup:new{
            align = "left",
            Widgets.label("读一读", { size = 16, bold = true }),
            Widgets.vspace(Size.span.vertical_default),
            Widgets.textbox(question.passage, inner_width - 2 * Size.padding.default, { size = 19 }),
        }, { width = cw - 2 * Size.padding.default }))
        table.insert(parts, Widgets.vspace(Size.span.vertical_default))
    end
    table.insert(parts, Widgets.textbox(question.stem, inner_width, {
        size = 27,
        line_height = 0.35,
    }))
    return Widgets.card(parts, { width = cw, padding = Size.padding.large })
end

function MainView:render_choice_area(question)
    local cw = Widgets.width()
    local area = VerticalGroup:new{ align = "center" }
    local prefixes = { "A. ", "B. ", "C. ", "D. " }
    for i, option in ipairs(question.options or {}) do
        table.insert(area, Widgets.choice_button(prefixes[i] .. option, cw, self.selected == i, function()
            self.selected = i
            self:render_quiz()
        end))
        if i < #question.options then
            table.insert(area, Widgets.vspace(Size.span.vertical_default))
        end
    end
    table.insert(area, Widgets.vspace(Size.span.vertical_default))
    table.insert(area, Widgets.button("确认答案", {
        width = cw,
        height = Screen:scaleBySize(58),
        size = 22,
        enabled = self.selected ~= nil,
        callback = function()
            if self.selected then self:submit_answer(self.selected) end
        end,
    }))
    return area
end

function MainView:render_keypad(question)
    local cw = Widgets.width()
    local gap = Size.span.horizontal_default
    local key_width = math.floor((cw - 2 * gap) / 3)
    local input_text = self.number_input ~= "" and self.number_input or "?"
    local display_card = Widgets.card(VerticalGroup:new{
        align = "center",
        Widgets.label("请输入答案", { size = 16, color = Blitbuffer.COLOR_DARK_GRAY }),
        Widgets.vspace(Size.span.vertical_default),
        Widgets.label(input_text, { size = 34, bold = true }),
        question.unit_hint and Widgets.label(question.unit_hint, { size = 18 }) or Widgets.vspace(0),
    }, { width = cw, padding = Size.padding.default })

    local function digit(d)
        return function()
            if #self.number_input < 5 then
                self.number_input = self.number_input .. d
                self:render_quiz()
            end
        end
    end
    local function row(keys)
        local group = HorizontalGroup:new{ align = "center" }
        for i, key in ipairs(keys) do
            if i > 1 then table.insert(group, Widgets.hspace(gap)) end
            table.insert(group, Widgets.button(key.label, {
                width = key_width,
                height = Screen:scaleBySize(58),
                size = 24,
                enabled = key.enabled ~= false,
                callback = key.callback,
            }))
        end
        return group
    end

    local area = VerticalGroup:new{
        align = "center",
        display_card,
        Widgets.vspace(Size.span.vertical_default),
        row({ { label = "1", callback = digit("1") }, { label = "2", callback = digit("2") }, { label = "3", callback = digit("3") } }),
        Widgets.vspace(Size.span.vertical_default),
        row({ { label = "4", callback = digit("4") }, { label = "5", callback = digit("5") }, { label = "6", callback = digit("6") } }),
        Widgets.vspace(Size.span.vertical_default),
        row({ { label = "7", callback = digit("7") }, { label = "8", callback = digit("8") }, { label = "9", callback = digit("9") } }),
        Widgets.vspace(Size.span.vertical_default),
        row({
            { label = "←", callback = function()
                if #self.number_input > 0 then
                    self.number_input = self.number_input:sub(1, -2)
                    self:render_quiz()
                end
            end },
            { label = "0", callback = digit("0") },
            { label = "确认", enabled = self.number_input ~= "", callback = function()
                if self.number_input ~= "" then self:submit_answer(tonumber(self.number_input)) end
            end },
        }),
    }
    return area
end

function MainView:render_quiz()
    self.state = "quiz"
    self:set_title(self:quiz_title())
    local question = self.session:current()
    local cw = Widgets.width()
    local content = VerticalGroup:new{
        align = "center",
        self:render_header(),
        Widgets.vspace(Size.span.vertical_default),
        Widgets.progress((self.session:position() - 1) / self.session:total(), cw),
        Widgets.vspace(Size.span.vertical_default),
        self:render_question_card(question),
        Widgets.vspace(Size.span.vertical_default),
    }
    if question.answer_mode == "number" then
        table.insert(content, self:render_keypad(question))
    else
        table.insert(content, self:render_choice_area(question))
    end
    self:set_body(content)
end

function MainView:submit_answer(value)
    if not self.session then return end
    self.feedback = self.session:submit(value)
    if self.feedback then
        self:render_feedback()
    end
end

function MainView:render_feedback()
    self.state = "feedback"
    self:set_title(self:quiz_title())
    local q = self.feedback.question
    local cw = Widgets.width()
    local content = VerticalGroup:new{
        align = "center",
        self:render_header(),
        Widgets.vspace(Size.span.vertical_default),
        self:render_question_card(q),
        Widgets.vspace(Size.span.vertical_default),
    }

    local feedback_parts = VerticalGroup:new{ align = "left" }
    if self.feedback.correct then
        local base_points = self.feedback.awarded - (self.feedback.combo_bonus or 0)
        table.insert(feedback_parts, Widgets.label(string.format("✓ 答对了！ +%d ★", base_points), {
            size = 24, bold = true,
        }))
        if self.feedback.combo_bonus > 0 then
            table.insert(feedback_parts, Widgets.vspace(Size.span.vertical_default))
            table.insert(feedback_parts, Widgets.label(string.format("连对 %d 题，额外 +%d ★", self.feedback.combo, self.feedback.combo_bonus), {
                size = 18, bold = true,
            }))
        end
    elseif self.feedback.can_retry then
        table.insert(feedback_parts, Widgets.label("再想想，你可以的！", { size = 24, bold = true }))
        table.insert(feedback_parts, Widgets.vspace(Size.span.vertical_default))
        table.insert(feedback_parts, Widgets.label("再试一次答对，可以得到 5 颗星星。", { size = 17, color = Blitbuffer.COLOR_DARK_GRAY }))
    else
        table.insert(feedback_parts, Widgets.label("正确答案：" .. answer_text(q), { size = 24, bold = true }))
    end
    table.insert(feedback_parts, Widgets.vspace(Size.span.vertical_default))
    if self.feedback.correct or not self.feedback.can_retry then
        table.insert(feedback_parts, Widgets.textbox(q.explain or "", cw - 4 * Size.padding.default, { size = 18 }))
    else
        table.insert(feedback_parts, Widgets.label("别着急，先自己算一算，再试一次。", {
            size = 17, color = Blitbuffer.COLOR_DARK_GRAY,
        }))
    end
    table.insert(content, Widgets.card(feedback_parts, { width = cw, padding = Size.padding.large }))
    table.insert(content, Widgets.vspace(Size.span.vertical_large))

    if self.feedback.can_retry then
        local half = math.floor((cw - Size.span.horizontal_default) / 2)
        table.insert(content, HorizontalGroup:new{
            align = "center",
            Widgets.button("再试一次", {
                width = half,
                height = Screen:scaleBySize(56),
                size = 21,
                callback = function()
                    self.session:retry()
                    self.feedback = nil
                    self.selected = nil
                    self.number_input = ""
                    self:render_quiz()
                end,
            }),
            Widgets.hspace(Size.span.horizontal_default),
            Widgets.button("看答案", {
                width = half,
                height = Screen:scaleBySize(56),
                size = 21,
                callback = function()
                    self.session:give_up()
                    self.feedback.final = true
                    self.feedback.can_retry = false
                    self:render_feedback()
                end,
            }),
        })
    else
        table.insert(content, Widgets.button("继续", {
            width = cw,
            height = Screen:scaleBySize(58),
            size = 22,
            callback = function() self:next_question() end,
        }))
    end
    self:set_body(content)
end

function MainView:next_question()
    if self.session:advance() then
        self.feedback = nil
        self.selected = nil
        self.number_input = ""
        self:render_quiz()
    else
        self:finish_session()
    end
end

function MainView:finish_session()
    self.summary = self.session:finish()
    self.new_badges = Badges.evaluate(self.progress)
    self:render_summary()
end

function MainView:render_summary()
    self.state = "summary"
    self:set_title("本轮完成")
    local cw = Widgets.width()
    local s = self.summary
    local badge_text
    if #self.new_badges > 0 then
        local names = {}
        for _, badge in ipairs(self.new_badges) do table.insert(names, badge.name) end
        badge_text = "新奖章：" .. table.concat(names, "、")
    else
        badge_text = "继续加油，下一枚奖章在等你！"
    end
    local breakdown = s.breakdown or {}
    local bonus_parts = {}
    if (breakdown.completion or 0) > 0 then table.insert(bonus_parts, "完成 +" .. breakdown.completion) end
    if (breakdown.perfect or 0) > 0 then table.insert(bonus_parts, "满分 +" .. breakdown.perfect) end
    if (breakdown.first_of_day or 0) > 0 then table.insert(bonus_parts, "今日首轮 +" .. breakdown.first_of_day) end
    local breakdown_text = string.format("答题获得 ★%d", s.points - (breakdown.total or 0))
    if #bonus_parts > 0 then
        breakdown_text = breakdown_text .. "，" .. table.concat(bonus_parts, "，")
    end
    local content = VerticalGroup:new{
        align = "center",
        Widgets.card(VerticalGroup:new{
            align = "center",
            Widgets.label(s.perfect and "满分！" or "做得不错！", { size = 30, bold = true }),
            Widgets.vspace(Size.span.vertical_default),
            Widgets.label(string.format("答对 %d/%d 题", s.correct, s.total), { size = 22 }),
            Widgets.vspace(Size.span.vertical_default),
            Widgets.label(string.format("获得 ★%d", s.points), { size = 26, bold = true }),
            Widgets.vspace(Size.span.vertical_default),
            Widgets.label(string.format("最高连对 %d 题", s.max_combo), { size = 18, color = Blitbuffer.COLOR_DARK_GRAY }),
            Widgets.vspace(Size.span.vertical_default),
            Widgets.label(breakdown_text, { size = 15, color = Blitbuffer.COLOR_DARK_GRAY }),
        }, { width = cw, padding = Size.padding.large }),
        Widgets.vspace(Size.span.vertical_large),
        Widgets.textbox(badge_text, cw, { size = 19, alignment = "center" }),
        Widgets.vspace(Size.span.vertical_large),
    }
    local half = math.floor((cw - Size.span.horizontal_default) / 2)
    table.insert(content, HorizontalGroup:new{
        align = "center",
        Widgets.button("再来一轮", {
            width = half,
            height = Screen:scaleBySize(56),
            size = 21,
            callback = function() self:start_session(self.last_session_opts or { mode = "subject", subject = self.subject or "chinese", unit = self.unit or "all" }) end,
        }),
        Widgets.hspace(Size.span.horizontal_default),
        Widgets.button("回首页", {
            width = half,
            height = Screen:scaleBySize(56),
            size = 21,
            callback = function() self:render_home() end,
        }),
    })
    if #self.progress:wrong_items() > 0 then
        table.insert(content, Widgets.vspace(Size.span.vertical_default))
        table.insert(content, Widgets.button(string.format("查看错题本（%d）", #self.progress:wrong_items()), {
            width = cw,
            size = 20,
            callback = function() self:render_wrongbook() end,
        }))
    end
    self:set_body(content)
end

function MainView:render_wrongbook()
    self.state = "wrongbook"
    self:set_title("错题本")
    local cw = Widgets.width()
    local half = math.floor((cw - Size.span.horizontal_default) / 2)
    local items = self.progress:wrong_items()
    local content = VerticalGroup:new{ align = "center" }
    if #items == 0 then
        table.insert(content, Widgets.label("还没有错题，真棒！", { size = 24, bold = true }))
        table.insert(content, Widgets.vspace(Size.span.vertical_large))
    else
        table.insert(content, Widgets.label(string.format("共 %d 道错题，先复习最久没有看的。", #items), {
            size = 18, color = Blitbuffer.COLOR_DARK_GRAY,
        }))
        table.insert(content, Widgets.vspace(Size.span.vertical_default))
        local shown = math.min(#items, 8)
        for i = #items, math.max(1, #items - shown + 1), -1 do
            local item = items[i]
            table.insert(content, Widgets.button(string.format("[%s] %s", SUBJECT_LABEL[item.subject] or "题", truncate(item.stem, 22)), {
                width = cw,
                height = Screen:scaleBySize(50),
                size = 18,
                align = "left",
                callback = function() self:render_wrong_detail(item) end,
            }))
            table.insert(content, Widgets.vspace(Size.span.vertical_default))
        end
        table.insert(content, Widgets.button("复习全部错题", {
            width = cw,
            height = Screen:scaleBySize(56),
            size = 21,
            callback = function() self:start_session({ mode = "wrong" }) end,
        }))
        table.insert(content, Widgets.vspace(Size.span.vertical_default))
        local ai_profile = self:ai_ready()
        local ai_count = math.min(#items, 5) * 2
        table.insert(content, HorizontalGroup:new{
            align = "center",
            Widgets.button(ai_profile and string.format("AI 强化（%d 题）", ai_count) or "AI 强化（先配置）", {
                width = half,
                height = Screen:scaleBySize(54),
                size = 18,
                callback = function() self:start_ai_batch() end,
            }),
            Widgets.hspace(Size.span.horizontal_default),
            Widgets.button("AI 题库", {
                width = half,
                height = Screen:scaleBySize(54),
                size = 18,
                callback = function() self:render_ai_bank(nil, function() self:render_wrongbook() end) end,
            }),
        })
        table.insert(content, Widgets.vspace(Size.span.vertical_default))
    end
    if #items == 0 then
        table.insert(content, Widgets.button("AI 题库", {
            width = cw,
            size = 20,
            callback = function() self:render_ai_bank(nil, function() self:render_wrongbook() end) end,
        }))
        table.insert(content, Widgets.vspace(Size.span.vertical_default))
    end
    table.insert(content, Widgets.button("回首页", {
        width = cw,
        size = 20,
        callback = function() self:render_home() end,
    }))
    self:set_body(content)
end

function MainView:render_wrong_detail(item)
    self.state = "wrong_detail"
    self:set_title("错题详情")
    local cw = Widgets.width()
    local content = VerticalGroup:new{
        align = "center",
        Widgets.card(VerticalGroup:new{
            align = "left",
            Widgets.label(string.format("%s · %s%s", SUBJECT_LABEL[item.subject] or "题", self:unit_name(item), item.competency and (" · " .. item.competency) or ""), { size = 16, color = Blitbuffer.COLOR_DARK_GRAY }),
            Widgets.vspace(Size.span.vertical_default),
            item.passage and Widgets.textbox(item.passage, cw - 4 * Size.padding.default, { size = 18 }) or Widgets.vspace(0),
            item.passage and Widgets.vspace(Size.span.vertical_default) or Widgets.vspace(0),
            Widgets.textbox(item.stem or "", cw - 4 * Size.padding.default, { size = 25 }),
            Widgets.vspace(Size.span.vertical_default),
            Widgets.label("正确答案：" .. answer_text(item), { size = 20, bold = true }),
            Widgets.vspace(Size.span.vertical_default),
            Widgets.textbox(item.explain or "", cw - 4 * Size.padding.default, { size = 17 }),
        }, { width = cw, padding = Size.padding.large }),
        Widgets.vspace(Size.span.vertical_large),
        Widgets.button("重做这道题", {
            width = cw,
            height = Screen:scaleBySize(56),
            size = 21,
            callback = function() self:start_session({ mode = "wrong", wrong_items = { item } }) end,
        }),
        Widgets.vspace(Size.span.vertical_default),
        Widgets.button(self:ai_ready() and "AI 出 3 道变种" or "AI 出 3 道变种（先配置）", {
            width = cw,
            height = Screen:scaleBySize(56),
            size = 21,
            callback = function() self:start_ai_single(item) end,
        }),
        Widgets.vspace(Size.span.vertical_default),
        (#self:get_ai_bank():groups(item.id) > 0) and Widgets.button(string.format("已有 AI 变种（%d 组）", #self:get_ai_bank():groups(item.id)), {
            width = cw,
            height = Screen:scaleBySize(50),
            size = 19,
            callback = function()
                self:render_ai_bank(item.id, function() self:render_wrong_detail(item) end)
            end,
        }) or Widgets.vspace(0),
        (#self:get_ai_bank():groups(item.id) > 0) and Widgets.vspace(Size.span.vertical_default) or Widgets.vspace(0),
        Widgets.button("返回错题本", {
            width = cw,
            size = 20,
            callback = function() self:render_wrongbook() end,
        }),
    }
    self:set_body(content)
end

function MainView:render_ai_settings()
    self.state = "ai_settings"
    self:set_title("AI 出题设置")
    local cw = Widgets.width()
    local ai = self.progress.data.settings.ai
    local active = AIConfig.active_profile(ai)
    local active_text = "未配置"
    if active then
        active_text = string.format("%s · %s", active.name, active.model ~= "" and active.model or "未填模型")
        if not AIConfig.validate(active) then active_text = active.name .. " · 未完成" end
    end
    if ai.config_error then active_text = "配置文件导入失败" end
    local content = VerticalGroup:new{ align = "center" }
    table.insert(content, Widgets.card(VerticalGroup:new{
        align = "left",
        Widgets.label("当前 AI 服务", { size = 16, color = Blitbuffer.COLOR_DARK_GRAY }),
        Widgets.vspace(Size.span.vertical_default),
        Widgets.label(active_text, {
            size = 21, bold = true,
        }),
        Widgets.vspace(Size.span.vertical_default),
        Widgets.textbox("AI 出题需要联网。调用时会把你选择的错题文本发送给对应服务商；API Key 会明文保存在本机（kidlearn.lua 或配置文件）中，请使用低额度 Key，并勿在共用设备上保存。也可把 kidlearn_ai_config.json 放到 koreader/settings/ 后重启，自动导入 API 地址、Key 和模型。", cw - 4 * Size.padding.default, {
            size = 15, color = Blitbuffer.COLOR_DARK_GRAY,
        }),
    }, { width = cw, padding = Size.padding.large }))
    if ai.config_error then
        table.insert(content, Widgets.vspace(Size.span.vertical_default))
        table.insert(content, Widgets.textbox("配置文件错误：" .. ai.config_error, cw - 4 * Size.padding.default, {
            size = 15, color = Blitbuffer.COLOR_DARK_GRAY,
        }))
    elseif ai.config_source then
        table.insert(content, Widgets.vspace(Size.span.vertical_default))
        table.insert(content, Widgets.textbox("当前 AI 配置来自 koreader/settings/" .. ai.config_source .. "；修改该文件后重启 KOReader 即可重新导入。", cw - 4 * Size.padding.default, {
            size = 15, color = Blitbuffer.COLOR_DARK_GRAY,
        }))
    end
    table.insert(content, Widgets.vspace(Size.span.vertical_large))

    for _, profile in ipairs(ai.profiles) do
        local prefix = profile.id == ai.active_id and "当前 · " or ""
        table.insert(content, Widgets.button(string.format("%s%s · %s", prefix, profile.name, profile.model ~= "" and profile.model or "未填模型"), {
            width = cw,
            height = Screen:scaleBySize(54),
            align = "left",
            size = 18,
            callback = function() self:render_ai_service_edit(profile.id) end,
        }))
        table.insert(content, Widgets.vspace(Size.span.vertical_default))
    end
    table.insert(content, Widgets.button("添加 AI 服务", {
        width = cw,
        height = Screen:scaleBySize(54),
        size = 19,
        callback = function() self:render_ai_preset_select() end,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_large))
    table.insert(content, Widgets.textbox("AI 生成内容仅供练习，可能有错误；每次出题都会消耗服务商 token。", cw, {
        size = 15, alignment = "center", color = Blitbuffer.COLOR_DARK_GRAY,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    table.insert(content, Widgets.button("返回设置", {
        width = cw,
        size = 20,
        callback = function() self:render_settings() end,
    }))
    local scroll = ScrollableContainer:new{
        dimen = Geom:new{ w = cw, h = math.floor(Screen:getHeight() * 0.78) },
        show_parent = self,
        content,
    }
    self:set_body(scroll)
end

function MainView:render_ai_preset_select()
    local items = {}
    for _, preset in ipairs(AIConfig.presets()) do
        table.insert(items, {
            id = preset.id,
            name = string.format("%s · %s", preset.name, preset.protocol == "openai" and "OpenAI 兼容" or preset.protocol),
        })
    end
    self:render_choice_list("添加 AI 服务", items, function(item)
        local ai = self.progress.data.settings.ai
        local profile, err = AIConfig.new_profile(item.id, ai)
        if not profile then
            UIManager:show(InfoMessage:new{ text = tostring(err), timeout = 4 })
            return
        end
        table.insert(ai.profiles, profile)
        if not ai.active_id then ai.active_id = profile.id end
        self.progress:flush()
        self:render_ai_service_edit(profile.id)
    end, function() self:render_ai_settings() end)
end

function MainView:render_ai_service_edit(profile_id)
    local profile = self:find_ai_profile(profile_id)
    if not profile then self:render_ai_settings() return end
    self.state = "ai_service_edit"
    self:set_title(profile.name)
    local cw = Widgets.width()
    local ai = self.progress.data.settings.ai
    local content = VerticalGroup:new{ align = "center" }
    table.insert(content, Widgets.card(VerticalGroup:new{
        align = "left",
        Widgets.label(profile.name, { size = 21, bold = true }),
        Widgets.vspace(Size.span.vertical_default),
        Widgets.textbox(string.format("协议：%s\n接口：%s", profile.protocol, profile.base_url ~= "" and profile.base_url or "未填写"), cw - 4 * Size.padding.default, {
            size = 15, color = Blitbuffer.COLOR_DARK_GRAY,
        }),
    }, { width = cw, padding = Size.padding.large }))
    table.insert(content, Widgets.vspace(Size.span.vertical_large))
    table.insert(content, Widgets.button("API Key：" .. AIConfig.mask_key(profile.api_key), {
        width = cw,
        height = Screen:scaleBySize(54),
        align = "left",
        size = 18,
        callback = function()
            self:open_ai_text_input("设置 API Key", profile.api_key, true, function(text)
                profile.api_key = text:match("^%s*(.-)%s*$") or ""
                self.progress:flush()
                self:render_ai_service_edit(profile.id)
            end)
        end,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    table.insert(content, Widgets.button("模型：" .. (profile.model ~= "" and profile.model or "未填写"), {
        width = cw,
        height = Screen:scaleBySize(54),
        align = "left",
        size = 18,
        callback = function()
            self:open_ai_text_input("设置模型名称", profile.model, false, function(text)
                profile.model = text:match("^%s*(.-)%s*$") or ""
                self.progress:flush()
                self:render_ai_service_edit(profile.id)
            end)
        end,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    if profile.preset == "custom" or profile.preset == "ollama" then
        table.insert(content, Widgets.button("接口地址：" .. (profile.base_url ~= "" and profile.base_url or "未填写"), {
            width = cw,
            height = Screen:scaleBySize(54),
            align = "left",
            size = 18,
            callback = function()
                self:open_ai_text_input("设置接口地址", profile.base_url, false, function(text)
                    profile.base_url = text:match("^%s*(.-)%s*$") or ""
                    self.progress:flush()
                    self:render_ai_service_edit(profile.id)
                end)
            end,
        }))
        table.insert(content, Widgets.vspace(Size.span.vertical_default))
    end
    if ai.active_id ~= profile.id then
        table.insert(content, Widgets.button("设为当前服务", {
            width = cw,
            height = Screen:scaleBySize(54),
            size = 19,
            callback = function()
                ai.active_id = profile.id
                self.progress:flush()
                self:render_ai_service_edit(profile.id)
            end,
        }))
        table.insert(content, Widgets.vspace(Size.span.vertical_default))
    end
    table.insert(content, Widgets.button("测试连接", {
        width = cw,
        height = Screen:scaleBySize(54),
        size = 19,
        callback = function() self:run_ai_test(profile) end,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    table.insert(content, Widgets.button("删除这个服务", {
        width = cw,
        height = Screen:scaleBySize(50),
        size = 18,
        callback = function()
            UIManager:show(ConfirmBox:new{
                text = "确定删除这个 AI 服务配置吗？API Key 也会一起删除。",
                ok_text = "删除",
                cancel_text = "取消",
                ok_callback = function()
                    for index = #ai.profiles, 1, -1 do
                        if ai.profiles[index].id == profile.id then table.remove(ai.profiles, index) end
                    end
                    AIConfig.normalize(ai)
                    self.progress:flush()
                    self:render_ai_settings()
                end,
            })
        end,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    table.insert(content, Widgets.button("返回 AI 设置", {
        width = cw,
        size = 20,
        callback = function() self:render_ai_settings() end,
    }))
    local scroll = ScrollableContainer:new{
        dimen = Geom:new{ w = cw, h = math.floor(Screen:getHeight() * 0.78) },
        show_parent = self,
        content,
    }
    self:set_body(scroll)
end

function MainView:render_ai_bank(origin_id, back)
    self.state = "ai_bank"
    self.ai_bank_filter = origin_id
    self.ai_bank_back = back or function() self:render_home() end
    self:set_title(origin_id and "这道题的 AI 变种" or "AI 题库")
    local cw = Widgets.width()
    local bank = self:get_ai_bank()
    local groups = bank:groups(origin_id)
    local content = VerticalGroup:new{ align = "center" }
    if #groups == 0 then
        table.insert(content, Widgets.label(origin_id and "这道题还没有 AI 变种。" or "还没有 AI 变种题。", {
            size = 22, bold = true,
        }))
        table.insert(content, Widgets.vspace(Size.span.vertical_default))
        table.insert(content, Widgets.textbox(origin_id and "回到错题详情，点「AI 出 3 道变种」生成。" or "去错题本选择一道题生成，或在错题本使用「AI 强化」。", cw, {
            size = 16, alignment = "center", color = Blitbuffer.COLOR_DARK_GRAY,
        }))
        table.insert(content, Widgets.vspace(Size.span.vertical_large))
        if not self:ai_profile() then
            table.insert(content, Widgets.button("配置 AI 服务", {
                width = cw,
                height = Screen:scaleBySize(54),
                size = 19,
                callback = function() self:render_ai_settings() end,
            }))
            table.insert(content, Widgets.vspace(Size.span.vertical_default))
        end
    else
        local total_questions = 0
        for _, group in ipairs(groups) do total_questions = total_questions + #group.questions end
        table.insert(content, Widgets.label(string.format("共 %d 组 · %d 道变种题", #groups, total_questions), {
            size = 17, color = Blitbuffer.COLOR_DARK_GRAY,
        }))
        table.insert(content, Widgets.vspace(Size.span.vertical_default))
        for _, group in ipairs(groups) do
            local origin = (group.origins or {})[1] or {}
            local date = group.created_at and group.created_at > 0 and os.date("%m-%d", group.created_at) or "--"
            table.insert(content, Widgets.button(string.format("[%s] %s · %d题 · %s", SUBJECT_LABEL[origin.subject] or "题", truncate(origin.stem, 18), #group.questions, date), {
                width = cw,
                height = Screen:scaleBySize(50),
                size = 17,
                align = "left",
                callback = function() self:render_ai_preview(group.id) end,
            }))
            table.insert(content, Widgets.vspace(Size.span.vertical_default))
        end
    end
    if #groups > 0 and not origin_id then
        table.insert(content, Widgets.button("清空 AI 题库", {
            width = cw,
            height = Screen:scaleBySize(50),
            size = 18,
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = "确定清空全部 AI 变种题吗？这不会删除错题本。",
                    ok_text = "清空",
                    cancel_text = "取消",
                    ok_callback = function()
                        bank:clear()
                        self:render_ai_bank(nil, self.ai_bank_back)
                    end,
                })
            end,
        }))
        table.insert(content, Widgets.vspace(Size.span.vertical_default))
    end
    table.insert(content, Widgets.button("返回", {
        width = cw,
        size = 20,
        callback = self.ai_bank_back,
    }))
    local scroll = ScrollableContainer:new{
        dimen = Geom:new{ w = cw, h = math.floor(Screen:getHeight() * 0.78) },
        show_parent = self,
        content,
    }
    self:set_body(scroll)
end

function MainView:render_ai_preview(group_id)
    local group = self:get_ai_bank():get_group(group_id)
    if not group then
        self:render_ai_bank(self.ai_bank_filter, self.ai_bank_back)
        return
    end
    self.state = "ai_preview"
    self.ai_preview_group_id = group.id
    self:set_title("家长预览")
    local cw = Widgets.width()
    local content = VerticalGroup:new{ align = "center" }
    table.insert(content, Widgets.textbox("AI 生成内容可能有误，请家长检查后再让孩子练习。", cw, {
        size = 16, alignment = "center", bold = true,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    local provider = group.provider or {}
    local provider_text = type(provider.name) == "string" and provider.name or "AI"
    if type(provider.model) == "string" and provider.model ~= "" then
        provider_text = provider_text .. " · " .. provider.model
    end
    local created_text = (group.created_at and group.created_at > 0) and os.date("%Y-%m-%d", group.created_at) or "未知日期"
    table.insert(content, Widgets.label(string.format("%s · %s", provider_text, created_text), {
        size = 14, color = Blitbuffer.COLOR_DARK_GRAY,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_large))

    local origin_by_id = {}
    for _, origin in ipairs(group.origins or {}) do origin_by_id[origin.id] = origin end
    for index, question in ipairs(group.questions) do
        local origin = origin_by_id[question.origin_id] or {}
        local parts = {
            align = "left",
            Widgets.label(string.format("变种 %d · 来自：%s", index, truncate(origin.stem or "", 20)), {
                size = 15, color = Blitbuffer.COLOR_DARK_GRAY,
            }),
            Widgets.vspace(Size.span.vertical_default),
        }
        if question.passage and question.passage ~= "" then
            table.insert(parts, Widgets.textbox(question.passage, cw - 4 * Size.padding.default, { size = 16 }))
            table.insert(parts, Widgets.vspace(Size.span.vertical_default))
        end
        table.insert(parts, Widgets.textbox(question.stem, cw - 4 * Size.padding.default, { size = 20 }))
        table.insert(parts, Widgets.vspace(Size.span.vertical_default))
        local prefixes = { "A. ", "B. ", "C. ", "D. " }
        for option_index, option in ipairs(question.options or {}) do
            local mark = option_index == question.answer and "✓ " or "　 "
            table.insert(parts, Widgets.textbox(mark .. prefixes[option_index] .. option, cw - 4 * Size.padding.default, { size = 17 }))
        end
        table.insert(parts, Widgets.vspace(Size.span.vertical_default))
        table.insert(parts, Widgets.label("答案：" .. answer_text(question), { size = 17, bold = true }))
        table.insert(parts, Widgets.vspace(Size.span.vertical_default))
        table.insert(parts, Widgets.textbox(question.explain or "", cw - 4 * Size.padding.default, { size = 15, color = Blitbuffer.COLOR_DARK_GRAY }))
        table.insert(content, Widgets.card(VerticalGroup:new(parts), { width = cw, padding = Size.padding.large }))
        table.insert(content, Widgets.vspace(Size.span.vertical_large))
    end

    local scroll = ScrollableContainer:new{
        dimen = Geom:new{ w = cw, h = math.floor(Screen:getHeight() * 0.62) },
        show_parent = self,
        content,
    }
    local body = VerticalGroup:new{
        align = "center",
        scroll,
        Widgets.vspace(Size.span.vertical_default),
        Widgets.button(string.format("开始练习（%d 题）", #group.questions), {
            width = cw,
            height = Screen:scaleBySize(58),
            size = 21,
            callback = function()
                self:start_session({ mode = "ai", ai_questions = group.questions, ai_group_id = group.id })
            end,
        }),
        Widgets.vspace(Size.span.vertical_default),
        Widgets.button("删除这组", {
            width = cw,
            height = Screen:scaleBySize(48),
            size = 18,
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = "确定删除这组 AI 变种题吗？",
                    ok_text = "删除",
                    cancel_text = "取消",
                    ok_callback = function()
                        self:get_ai_bank():remove_group(group.id)
                        self:render_ai_bank(self.ai_bank_filter, self.ai_bank_back)
                    end,
                })
            end,
        }),
        Widgets.vspace(Size.span.vertical_default),
        Widgets.button("返回 AI 题库", {
            width = cw,
            size = 20,
            callback = function() self:render_ai_bank(self.ai_bank_filter, self.ai_bank_back) end,
        }),
    }
    self:set_body(body)
end

function MainView:render_badges()
    self.state = "badges"
    self:set_title("奖章墙")
    local cw = Widgets.width()
    local gap = Size.span.horizontal_default
    local card_width = math.floor((cw - gap) / 2)
    local content = VerticalGroup:new{ align = "center" }
    local state = Badges.state(self.progress)
    local row
    for i, badge in ipairs(state) do
        local symbol = badge.unlocked and "★" or "☆"
        local progress_text = badge.unlocked and "已获得" or string.format("%d/%d", badge.value, badge.target)
        local card = Widgets.card(VerticalGroup:new{
            align = "center",
            Widgets.label(symbol, { size = 26, bold = true }),
            Widgets.label(badge.name, { size = 18, bold = true }),
            Widgets.textbox(badge.desc, card_width - 4 * Size.padding.default, { size = 14, alignment = "center" }),
            Widgets.label(progress_text, { size = 14, color = Blitbuffer.COLOR_DARK_GRAY }),
        }, { width = card_width, padding = Size.padding.default })
        if i % 2 == 1 then
            row = HorizontalGroup:new{ align = "center", card }
            table.insert(content, row)
            table.insert(content, Widgets.vspace(gap))
        else
            table.insert(row, Widgets.hspace(gap))
            table.insert(row, card)
        end
    end
    table.insert(content, Widgets.button("回首页", {
        width = cw,
        size = 20,
        callback = function() self:render_home() end,
    }))
    self:set_body(content)
end

function MainView:cycle_goal()
    local goal = self.progress.data.settings.daily_goal
    local values = { 5, 10, 15, 20 }
    for i, value in ipairs(values) do
        if goal == value then
            goal = values[(i % #values) + 1]
            break
        end
    end
    self.progress.data.settings.daily_goal = goal
    self.progress:flush()
end

function MainView:render_choice_list(title, items, on_select, back)
    self.state = "choice_list"
    self:set_title(title)
    local cw = Widgets.width()
    local content = VerticalGroup:new{ align = "center" }
    for _, item in ipairs(items) do
        local label = item.name
        if item.selected then label = "✓ " .. label end
        local captured = item
        table.insert(content, Widgets.button(label, {
            width = cw,
            height = Screen:scaleBySize(50),
            align = "left",
            callback = function() on_select(captured) end,
        }))
        table.insert(content, Widgets.vspace(Size.span.vertical_default))
    end
    local scroll = ScrollableContainer:new{
        dimen = Geom:new{ w = cw, h = math.floor(Screen:getHeight() * 0.66) },
        show_parent = self,
        content,
    }
    local body = VerticalGroup:new{
        align = "center",
        scroll,
        Widgets.vspace(Size.span.vertical_default),
        Widgets.button("返回", {
            width = cw,
            height = Screen:scaleBySize(48),
            size = 20,
            callback = back or function() self:render_settings() end,
        }),
    }
    self:set_body(body)
end

function MainView:render_province_select()
    local settings = self.progress.data.settings
    local items = {}
    for _, province in ipairs(Catalog.provinces(self.plugin_path)) do
        table.insert(items, {
            id = province.id,
            name = province.name,
            selected = settings.province == province.id,
        })
    end
    self:render_choice_list("选择省份", items, function(item)
        settings.province = item.id
        settings.math_edition = Catalog.recommended_math(self.plugin_path, item.id)
        self.progress:flush()
        UIManager:show(InfoMessage:new{
            text = string.format("已选择%s，数学教材推荐为%s，可在设置中修改。",
                item.name, Catalog.edition_name(self.plugin_path, "math", settings.math_edition)),
            timeout = 3,
        })
        self:render_settings()
    end)
end

function MainView:render_grade_select()
    local settings = self.progress.data.settings
    local items = {}
    for _, grade in ipairs(Catalog.grades(self.plugin_path)) do
        table.insert(items, {
            id = grade,
            name = GRADE_LABEL[grade] or (grade .. "年级"),
            selected = tonumber(settings.grade) == grade,
        })
    end
    self:render_choice_list("选择年级", items, function(item)
        settings.grade = item.id
        self.progress:flush()
        self:render_settings()
    end)
end

function MainView:render_edition_select(subject)
    local settings = self.progress.data.settings
    local current = subject == "chinese" and settings.chinese_edition or settings.math_edition
    local items = {}
    for _, edition in ipairs(Catalog.editions(self.plugin_path, subject)) do
        table.insert(items, {
            id = edition.id,
            name = edition.name,
            selected = current == edition.id,
        })
    end
    self:render_choice_list(self:subject_label(subject) .. "教材", items, function(item)
        if subject == "chinese" then
            settings.chinese_edition = item.id
        else
            settings.math_edition = item.id
        end
        self.progress:flush()
        self:render_settings()
    end)
end

function MainView:render_settings()
    self.state = "settings"
    self:set_title("设置")
    local cw = Widgets.width()
    local settings = self.progress.data.settings
    local content = VerticalGroup:new{ align = "center" }
    table.insert(content, Widgets.button(string.format("AI 出题设置：%s", self:ai_status_label()), {
        width = cw,
        height = Screen:scaleBySize(54),
        align = "left",
        callback = function() self:render_ai_settings() end,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    table.insert(content, Widgets.button(string.format("省份：%s", (Catalog.province(self.plugin_path, settings.province) or {}).name or "其他/不指定"), {
        width = cw,
        height = Screen:scaleBySize(54),
        align = "left",
        callback = function() self:render_province_select() end,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    table.insert(content, Widgets.button(string.format("年级：%s", self:grade_label()), {
        width = cw,
        height = Screen:scaleBySize(54),
        align = "left",
        callback = function() self:render_grade_select() end,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    table.insert(content, Widgets.button(string.format("语文教材：%s", self:edition_name("chinese")), {
        width = cw,
        height = Screen:scaleBySize(54),
        align = "left",
        callback = function() self:render_edition_select("chinese") end,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    table.insert(content, Widgets.button(string.format("数学教材：%s", self:edition_name("math")), {
        width = cw,
        height = Screen:scaleBySize(54),
        align = "left",
        callback = function() self:render_edition_select("math") end,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    table.insert(content, Widgets.button(string.format("学期：%s", self:semester_label()), {
        width = cw,
        height = Screen:scaleBySize(54),
        align = "left",
        callback = function()
            settings.semester = settings.semester == "upper" and "lower" or "upper"
            self.progress:flush()
            self:render_settings()
        end,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    table.insert(content, Widgets.button(string.format("每日目标：%d 题", settings.daily_goal), {
        width = cw,
        height = Screen:scaleBySize(54),
        align = "left",
        callback = function()
            self:cycle_goal()
            self:render_settings()
        end,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    table.insert(content, Widgets.button(string.format("答错可重试：%s", settings.retry ~= false and "开" or "关"), {
        width = cw,
        height = Screen:scaleBySize(54),
        align = "left",
        callback = function()
            settings.retry = settings.retry == false
            self.progress:flush()
            self:render_settings()
        end,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_large))
    table.insert(content, Widgets.button("重置学习进度", {
        width = cw,
        height = Screen:scaleBySize(54),
        align = "left",
        callback = function()
            UIManager:show(ConfirmBox:new{
                text = "确定清空所有星星、打卡、奖章和错题吗？\n\nAI 服务配置和 AI 题库会保留；这个操作不能撤销。",
                ok_text = "确定清空",
                cancel_text = "取消",
                ok_callback = function()
                    self.progress:reset_progress()
                    self:render_settings()
                end,
            })
        end,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    table.insert(content, Widgets.button("关于小小学习家", {
        width = cw,
        height = Screen:scaleBySize(54),
        align = "left",
        callback = function()
            local chinese = Bank.load(self.plugin_path, "chinese",
                tonumber(settings.grade) or 2, settings.semester, settings.chinese_edition)
            UIManager:show(InfoMessage:new{
                text = string.format(
                    "小小学习家 v1.2\n%s · %s · %s\n\n语文题库：%d 题\n数学题库：程序生成，无限题\n\n学习记录和 AI 题库只保存在本机；只有你主动使用 AI 出题时，所选错题会发送给对应服务商。",
                    self:grade_label(), self:semester_label(), self:edition_name("math"),
                    chinese and #chinese.questions or 0
                ),
                timeout = 6,
            })
        end,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_large))
    table.insert(content, Widgets.button("回首页", {
        width = cw,
        size = 20,
        callback = function() self:render_home() end,
    }))
    local scroll = ScrollableContainer:new{
        dimen = Geom:new{ w = cw, h = math.floor(Screen:getHeight() * 0.78) },
        show_parent = self,
        content,
    }
    self:set_body(scroll)
end

return MainView
