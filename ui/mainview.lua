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
local Cards = require("core.cards")
local Catalog = require("core.catalog")
local Diagnose = require("core.diagnose")
local Knowledge = require("core.knowledge")
local MathGen = require("core.mathgen")
local Progress = require("core.progress")
local Report = require("core.report")
local Session = require("core.session")
local Update = require("core.update")
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
-- Title-bar back navigation: parent page for each state (default: home).
-- Second-level pages go straight back to the home page; deeper pages step
-- up one level (e.g. knowledge card -> knowledge list -> home).
local BACK_PARENT = {
    unit_select = "home",
    kp_subject = "home",
    kp_select = "home",
    kp_learn = "kp_select",
    wrongbook = "home",
    wrong_detail = "wrongbook",
    badges = "home",
    daily_report = "home",
    settings = "home",
    ai_settings = "settings",
    ai_service_edit = "ai_settings",
    ai_preview = "ai_bank",
    summary = "home",
    diagnose_result = "kp_select",
}

local KP_STATUS_MARK = { mastered = "★", learning = "●", weak = "▲" }
local KP_STATUS_LABEL = { mastered = "已掌握", learning = "继续加油", weak = "需要加强" }

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
    self._back_shown = false
    self._current_title = _("小小学习家")
    self.selected = nil
    self.number_input = ""
    self.feedback = nil
    self.summary = nil
    self.new_badges = {}
    if self.ai_generating == nil then self.ai_generating = false end
    if self.ai_polishing == nil then self.ai_polishing = false end

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
    self:_maybe_auto_check_update()
end

function MainView:paintTo(bb, x, y)
    -- The plugin is a full-screen page, not a dialog over the reader. Paint an
    -- opaque background first so the underlying reader page never shows through.
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    InputContainer.paintTo(self, bb, x, y)
end

function MainView:set_title(text)
    self._current_title = text
    self.title_bar:setTitle(text)
    self:update_back_button()
end

--[[--
Show a persistent back button in the title bar on every non-home page.
TitleBar fixes its icon layout at init, so rebuild it when the back button
appears or disappears (page transitions already repaint the whole screen).
--]]--
function MainView:update_back_button()
    local want_back = self.state ~= "home"
    if want_back == self._back_shown then return end
    self._back_shown = want_back
    self.title_bar = TitleBar:new{
        fullscreen = true,
        width = self.dimen.w,
        align = "left",
        title = self._current_title,
        title_face = Font:getFace("smalltfont", 22),
        title_h_padding = Size.padding.large,
        left_icon = want_back and "chevron.left" or nil,
        left_icon_tap_callback = function() self:onBack() end,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }
    self.main[1] = self.title_bar
    self.main._size = nil
end

--[[--
Title-bar back: leave the current page without exiting the plugin.
Active practice/diagnosis sessions ask for confirmation first; answers
already given stay saved.
--]]--
function MainView:onBack()
    local state = self.state
    if state == "home" then return end
    if state == "quiz" or state == "feedback"
        or state == "diagnose_quiz" or state == "diagnose_feedback" then
        UIManager:show(ConfirmBox:new{
            text = _("本轮练习还没有完成，确定返回吗？\n\n已经答过的题目和星星会保存。"),
            ok_text = _("返回"),
            cancel_text = _("继续练习"),
            ok_callback = function()
                self.session = nil
                self.diagnose = nil
                self:render_home()
            end,
        })
        return
    end
    if state == "ai_bank" then
        local back = self.ai_bank_back
        self.ai_bank_back = nil
        if back then back() else self:render_home() end
        return
    end
    if state == "choice_list" then
        local back = self.choice_list_back
        self.choice_list_back = nil
        if back then back() else self:render_settings() end
        return
    end
    if state == "cards" then
        self:leave_cards()
        return
    end
    local parent = BACK_PARENT[state] or "home"
    if parent == "kp_select" then
        self:render_kp_select(self.kp_subject or self.diagnose_subject or "math")
    elseif parent == "wrongbook" then
        self:render_wrongbook()
    elseif parent == "settings" then
        self:render_settings()
    elseif parent == "ai_settings" then
        self:render_ai_settings()
    elseif parent == "ai_bank" then
        self:render_ai_bank()
    else
        self:render_home()
    end
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
    if self.state == "quiz" or self.state == "feedback"
        or self.state == "diagnose_quiz" or self.state == "diagnose_feedback" then
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
            text = "AI 正在出变种题，请稍候…\n通常需要 10–120 秒，请不要退出。",
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
        Widgets.button(string.format("奖章墙（%d/%d）", badge_count, #Badges.all()), {
            width = half,
            callback = function() self:render_badges() end,
        }),
        Widgets.hspace(Size.span.horizontal_default),
        Widgets.button("设置", {
            width = half,
            callback = function() self:render_settings() end,
        }),
    }
    local tool_row_3 = HorizontalGroup:new{
        align = "center",
        Widgets.button(self.progress:daily_report() and "今日总结 ✓" or "每日总结", {
            width = half,
            callback = function() self:open_daily_report() end,
        }),
        Widgets.hspace(Size.span.horizontal_default),
        Widgets.button("集卡册", {
            width = half,
            callback = function() self:render_cards() end,
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
        Widgets.button("知识点学习", {
            width = cw,
            height = Screen:scaleBySize(60),
            size = 22,
            callback = function() self:render_kp_subject() end,
        }),
        Widgets.vspace(Size.span.vertical_default),
        tool_row_1,
        Widgets.vspace(Size.span.vertical_default),
        tool_row_2,
        Widgets.vspace(Size.span.vertical_default),
        tool_row_3,
    }
    local available = Screen:getHeight() - self.title_bar:getSize().h - 2 * Size.padding.fullscreen
    if content:getSize().h > available then
        self:set_body(ScrollableContainer:new{
            dimen = Geom:new{ w = cw, h = available },
            show_parent = self,
            content,
        })
    else
        self:set_body(content)
    end
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
        kp_questions = opts.kp_questions,
        kp_topic = opts.kp_topic,
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
    self.last_kp_topic = opts.kp_topic
    self.last_kp_subject = opts.subject
    self.diagnose = nil
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
    if self.session.mode == "kp" then return "知识点练习" end
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

function MainView:rerender_input()
    if self.diagnose and self.state == "diagnose_quiz" then
        self:render_diagnose_quiz()
    else
        self:render_quiz()
    end
end

function MainView:render_choice_area(question)
    local cw = Widgets.width()
    local area = VerticalGroup:new{ align = "center" }
    local prefixes = { "A. ", "B. ", "C. ", "D. " }
    for i, option in ipairs(question.options or {}) do
        table.insert(area, Widgets.choice_button(prefixes[i] .. option, cw, self.selected == i, function()
            self.selected = i
            self:rerender_input()
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
    local format = question.answer_format
    local extended = format == "decimal" or format == "fraction"
    -- Knowledge questions may need up to 8 chars (e.g. 1000000 or 11/12);
    -- legacy generated questions keep the original 5-char integer limit.
    local max_len = format and 8 or 5
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
            if #self.number_input < max_len then
                self.number_input = self.number_input .. d
                self:rerender_input()
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
    local function backspace()
        if #self.number_input > 0 then
            self.number_input = self.number_input:sub(1, -2)
            self:rerender_input()
        end
    end
    local function confirm()
        if self.number_input == "" then return end
        if extended then
            local input = self.number_input
            local valid
            if format == "fraction" then
                local num, den = input:match("^(%d+)/(%d+)$")
                if num then
                    valid = tonumber(den) ~= 0
                else
                    valid = tonumber(input) ~= nil
                end
            else
                valid = tonumber(input) ~= nil
            end
            if not valid then
                UIManager:show(InfoMessage:new{
                    text = format == "fraction" and "请输入分数（如 1/2）或小数" or "请输入小数（如 0.5）",
                    timeout = 3,
                })
                return
            end
            self:submit_answer(input)
        else
            self:submit_answer(tonumber(self.number_input))
        end
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
    }
    if extended then
        local has_dot = self.number_input:find(".", 1, true) ~= nil
        local has_slash = self.number_input:find("/", 1, true) ~= nil
        table.insert(area, row({
            { label = ".", enabled = not has_dot and not has_slash, callback = digit(".") },
            { label = "/", enabled = format == "fraction" and not has_slash and not has_dot and self.number_input ~= "", callback = digit("/") },
            { label = "←", callback = backspace },
        }))
        table.insert(area, Widgets.vspace(Size.span.vertical_default))
        table.insert(area, row({
            { label = "0", callback = digit("0") },
            { label = "清空", callback = function()
                self.number_input = ""
                self:rerender_input()
            end },
            { label = "确认", enabled = self.number_input ~= "", callback = confirm },
        }))
    else
        table.insert(area, row({
            { label = "←", callback = backspace },
            { label = "0", callback = digit("0") },
            { label = "确认", enabled = self.number_input ~= "", callback = confirm },
        }))
    end
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
    if self.diagnose and self.state == "diagnose_quiz" then
        self:diagnose_submit(value)
        return
    end
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
    if s.mode == "kp" and s.kp_statuses then
        local kp_line
        if self.last_kp_topic and s.kp_statuses[self.last_kp_topic] then
            local graph = Knowledge.graph(self.plugin_path, self.last_kp_subject or "math")
            local node = graph and graph.nodes[self.last_kp_topic]
            local name = node and node.name or self.last_kp_topic
            kp_line = string.format("知识点「%s」：%s", name,
                KP_STATUS_LABEL[s.kp_statuses[self.last_kp_topic]] or "")
        else
            local mastered, learning, weak = 0, 0, 0
            for _, status in pairs(s.kp_statuses) do
                if status == "mastered" then mastered = mastered + 1
                elseif status == "weak" then weak = weak + 1
                else learning = learning + 1 end
            end
            kp_line = string.format("本轮知识点：已掌握 %d · 学习中 %d · 薄弱 %d", mastered, learning, weak)
        end
        table.insert(content, Widgets.textbox(kp_line, cw, { size = 19, alignment = "center" }))
        table.insert(content, Widgets.vspace(Size.span.vertical_default))
    end
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
    if s.mode == "kp" and self.last_kp_subject then
        table.insert(content, Widgets.vspace(Size.span.vertical_default))
        table.insert(content, Widgets.button("返回知识点", {
            width = cw,
            size = 20,
            callback = function()
                if self.last_kp_topic then
                    self:render_kp_learn(self.last_kp_subject, self.last_kp_topic)
                else
                    self:render_kp_select(self.last_kp_subject)
                end
            end,
        }))
    end
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

function MainView:render_badges(page)
    self.state = "badges"
    self:set_title("奖章墙")
    local cw = Widgets.width()
    local gap = Size.span.horizontal_default
    local card_width = math.floor((cw - gap) / 2)
    local half = math.floor((cw - gap) / 2)
    local all = Badges.state(self.progress)
    local per_page = 10
    local total_pages = math.max(1, math.ceil(#all / per_page))
    page = tonumber(page) or self.badge_page or 1
    if page < 1 then page = 1 elseif page > total_pages then page = total_pages end
    self.badge_page = page
    local content = VerticalGroup:new{ align = "center" }
    table.insert(content, Widgets.label(string.format("第 %d/%d 页 · 已解锁 %d/%d",
        page, total_pages, Badges.count(self.progress), #all), {
        size = 16, color = Blitbuffer.COLOR_DARK_GRAY,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    local first = (page - 1) * per_page + 1
    local last = math.min(first + per_page - 1, #all)
    local row
    for i = first, last do
        local badge = all[i]
        local symbol = badge.unlocked and "★" or "☆"
        local progress_text = badge.unlocked and "已获得" or string.format("%d/%d", badge.value, badge.target)
        local card = Widgets.card(VerticalGroup:new{
            align = "center",
            Widgets.label(symbol, { size = 26, bold = true }),
            Widgets.label(badge.name, { size = 18, bold = true }),
            Widgets.textbox(badge.desc, card_width - 4 * Size.padding.default, { size = 14, alignment = "center" }),
            Widgets.label(progress_text, { size = 14, color = Blitbuffer.COLOR_DARK_GRAY }),
        }, { width = card_width, padding = Size.padding.default })
        if (i - first) % 2 == 0 then
            row = HorizontalGroup:new{ align = "center", card }
            table.insert(content, row)
            table.insert(content, Widgets.vspace(gap))
        else
            table.insert(row, Widgets.hspace(gap))
            table.insert(row, card)
        end
    end
    local nav = HorizontalGroup:new{ align = "center" }
    if page > 1 then
        table.insert(nav, Widgets.button("上一页", {
            width = half, size = 20,
            callback = function() self:render_badges(page - 1) end,
        }))
    else
        table.insert(nav, Widgets.hspace(half))
    end
    table.insert(nav, Widgets.hspace(gap))
    if page < total_pages then
        table.insert(nav, Widgets.button("下一页", {
            width = half, size = 20,
            callback = function() self:render_badges(page + 1) end,
        }))
    else
        table.insert(nav, Widgets.hspace(half))
    end
    table.insert(content, nav)
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
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

-- ---------------------------------------------------------------------------
-- Daily report, card draw and card collection
-- ---------------------------------------------------------------------------

function MainView:report_parts_text(report)
    local parts = report.parts or {}
    return string.format("目标 %d/30 · 正确率 %d/30 · 轮次 %d/15 · 挑战 %d/10 · 知识点 %d/5 · 连续 %d/10",
        parts.goal or 0, parts.accuracy or 0, parts.sessions or 0,
        parts.challenge or 0, parts.kp or 0, parts.streak or 0)
end

function MainView:open_daily_report()
    local report = self.progress:daily_report()
    if report then
        self:render_daily_report()
        return
    end
    if self.progress:today().answered < 1 then
        UIManager:show(InfoMessage:new{
            text = "今天还没做题哦。先做几道题，再来领取今日总结和卡片奖励吧！",
            timeout = 4,
        })
        return
    end
    Report.create(self.progress, { plugin_path = self.plugin_path })
    local new_badges = Badges.evaluate(self.progress)
    self:render_daily_report()
    if #new_badges > 0 then
        local names = {}
        for _, badge in ipairs(new_badges) do table.insert(names, badge.name) end
        UIManager:show(InfoMessage:new{ text = "新奖章：" .. table.concat(names, "、"), timeout = 4 })
    end
    if self:ai_ready() then
        self:polish_daily_report()
    end
end

function MainView:render_daily_report()
    self.state = "daily_report"
    self:set_title("每日总结")
    local cw = Widgets.width()
    local report = self.progress:daily_report()
    if not report then
        self:render_home()
        return
    end
    local content = VerticalGroup:new{ align = "center" }
    table.insert(content, Widgets.card(VerticalGroup:new{
        align = "center",
        Widgets.label(os.date("%Y年%m月%d日", report.created_at or os.time()), {
            size = 16, color = Blitbuffer.COLOR_DARK_GRAY,
        }),
        Widgets.vspace(Size.span.vertical_default),
        Widgets.label(string.format("%d 分", report.score or 0), { size = 40, bold = true }),
        Widgets.label(Report.grade_label(report.score), { size = 22, bold = true }),
        Widgets.vspace(Size.span.vertical_default),
        Widgets.textbox(self:report_parts_text(report), cw - 4 * Size.padding.default, {
            size = 14, alignment = "center",
        }),
    }, { width = cw, padding = Size.padding.large }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    local stats = Report.stats(self.progress, nil, self.plugin_path)
    table.insert(content, Widgets.textbox(string.format("答题 %d · 答对 %d · 星星 %d · 轮次 %d",
        stats.answered, stats.correct, stats.points, stats.sessions), cw, { size = 16, alignment = "center" }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    table.insert(content, Widgets.label(report.ai and "AI 总结" or "离线总结", {
        size = 15, color = Blitbuffer.COLOR_DARK_GRAY,
    }))
    table.insert(content, Widgets.textbox(report.summary or "", cw, { size = 18 }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    if not report.revealed then
        table.insert(content, Widgets.button(string.format("翻开今日卡片（%d 张）", #(report.cards or {})), {
            width = cw,
            height = Screen:scaleBySize(64),
            size = 22,
            callback = function()
                report.revealed = true
                self.progress:save_daily_report(report)
                self:render_daily_report()
            end,
        }))
    else
        for index, card in ipairs(report.cards or {}) do
            local word = (report.card_words or {})[index] or card.desc or ""
            table.insert(content, Widgets.card(VerticalGroup:new{
                align = "center",
                Widgets.label(string.format("【%s】%s", card.tier or "?", card.name or ""), { size = 20, bold = true }),
                Widgets.textbox(word, cw - 4 * Size.padding.default, { size = 15, alignment = "center" }),
            }, { width = cw }))
            table.insert(content, Widgets.vspace(Size.span.vertical_default))
        end
    end
    if not report.ai and self:ai_ready() then
        table.insert(content, Widgets.button("AI 润色总结", {
            width = cw, size = 20,
            callback = function() self:polish_daily_report() end,
        }))
        table.insert(content, Widgets.vspace(Size.span.vertical_default))
    end
    table.insert(content, Widgets.button("查看集卡册", {
        width = cw, size = 20,
        callback = function() self:render_cards(true) end,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    table.insert(content, Widgets.button("回首页", {
        width = cw, size = 20,
        callback = function() self:render_home() end,
    }))
    local scroll = ScrollableContainer:new{
        dimen = Geom:new{ w = cw, h = math.floor(Screen:getHeight() * 0.78) },
        show_parent = self,
        content,
    }
    self:set_body(scroll)
end

function MainView:show_report_ai_error(message)
    UIManager:show(ConfirmBox:new{
        text = "AI 总结失败：" .. tostring(message) .. "\n\n离线总结和卡片不受影响。",
        ok_text = "重试",
        cancel_text = "看离线版",
        ok_callback = function() self:polish_daily_report() end,
    })
end

function MainView:polish_daily_report()
    if self.ai_polishing then
        UIManager:show(InfoMessage:new{ text = "AI 正在写上一份总结，请稍候。", timeout = 3 })
        return
    end
    local report = self.progress:daily_report()
    if not report then return end
    local profile, err = self:ai_ready()
    if not profile then
        UIManager:show(InfoMessage:new{
            text = "AI 还没配置好：" .. tostring(err) .. "\n\n可以先看离线总结，或到设置里配置 AI 服务。",
            timeout = 5,
        })
        return
    end
    local stats = Report.stats(self.progress, nil, self.plugin_path)
    local system, user = Report.build_prompt(stats, report.score, report.cards)
    NetworkMgr:runWhenOnline(function()
        if self.ai_polishing then return end
        self.ai_polishing = true
        local loading = InfoMessage:new{
            text = "AI 正在写今日总结，请稍候…\n通常需要 10–60 秒，请不要退出。",
        }
        UIManager:show(loading)
        UIManager:forceRePaint()
        local function finish(text, request_err)
            UIManager:close(loading)
            self.ai_polishing = false
            if self.closed then return end
            if request_err then
                self:show_report_ai_error(request_err)
                return
            end
            local parsed, parse_err = Report.parse(text, #(report.cards or {}))
            if not parsed then
                self:show_report_ai_error(parse_err)
                return
            end
            report.summary = parsed.summary
            report.card_words = parsed.card_words
            report.ai = true
            self.progress:save_daily_report(report)
            if self.state == "daily_report" then
                self:render_daily_report()
            end
        end
        AIClient.generate(profile, system, user, {
            transport = self.ai_transport,
            callback = finish,
        })
    end)
end

function MainView:render_cards(from_report)
    self.state = "cards"
    self.cards_back = from_report and "daily_report" or "home"
    self:set_title("集卡册")
    local cw = Widgets.width()
    local gap = Size.span.horizontal_default
    local card_width = math.floor((cw - gap) / 2)
    local state, owned = Cards.collection_state(self.progress)
    local content = VerticalGroup:new{ align = "center" }
    table.insert(content, Widgets.label(string.format("已收集 %d/%d", owned, #state), { size = 18, bold = true }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    for _, tier in ipairs({ "SSS", "SS", "S", "RR", "R" }) do
        local group = {}
        for _, card in ipairs(state) do
            if card.tier == tier then table.insert(group, card) end
        end
        if #group > 0 then
            local owned_in_tier = 0
            for _, card in ipairs(group) do
                if card.owned then owned_in_tier = owned_in_tier + 1 end
            end
            table.insert(content, Widgets.label(string.format("%s 级（%d/%d）", tier, owned_in_tier, #group), {
                size = 17, bold = true,
            }))
            table.insert(content, Widgets.vspace(Size.span.vertical_default))
            local row
            for i, card in ipairs(group) do
                local cell = Widgets.card(VerticalGroup:new{
                    align = "center",
                    Widgets.label(card.owned and card.name or "？？？", { size = 17, bold = card.owned }),
                    Widgets.label(card.owned and string.format("×%d", card.count) or "未收集", {
                        size = 13, color = Blitbuffer.COLOR_DARK_GRAY,
                    }),
                }, { width = card_width, padding = Size.padding.default })
                if i % 2 == 1 then
                    row = HorizontalGroup:new{ align = "center", cell }
                    table.insert(content, row)
                    table.insert(content, Widgets.vspace(gap))
                else
                    table.insert(row, Widgets.hspace(gap))
                    table.insert(row, cell)
                end
            end
            table.insert(content, Widgets.vspace(Size.span.vertical_default))
        end
    end
    table.insert(content, Widgets.button("返回", {
        width = cw, size = 20,
        callback = function() self:leave_cards() end,
    }))
    local scroll = ScrollableContainer:new{
        dimen = Geom:new{ w = cw, h = math.floor(Screen:getHeight() * 0.78) },
        show_parent = self,
        content,
    }
    self:set_body(scroll)
end

function MainView:leave_cards()
    local back = self.cards_back
    self.cards_back = nil
    if back == "daily_report" then
        self:render_daily_report()
    else
        self:render_home()
    end
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
    self.choice_list_back = back or function() self:render_settings() end
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
            callback = self.choice_list_back,
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

-- ---------------------------------------------------------------------------
-- Online update (opt-in, user-triggered; user data lives outside the plugin dir).
-- ---------------------------------------------------------------------------

function MainView:check_update()
    if self.update_busy then
        UIManager:show(InfoMessage:new{ text = "正在处理上一个更新请求，请稍候。", timeout = 3 })
        return
    end
    NetworkMgr:runWhenOnline(function()
        if self.closed then return end
        self.update_busy = true
        local loading = InfoMessage:new{ text = "正在检查更新…" }
        UIManager:show(loading)
        UIManager:forceRePaint()
        local settings = self.progress.data.settings
        Update.check({
            api_url = settings.update_api_url,
            local_version = Update.local_version(self.plugin_path),
        }, function(result)
            UIManager:close(loading)
            self.update_busy = false
            if self.closed then return end
            if result.error then
                UIManager:show(InfoMessage:new{ text = "检查更新失败：" .. tostring(result.error), timeout = 6 })
                return
            end
            if not result.available then
                UIManager:show(InfoMessage:new{ text = string.format("已是最新版本 v%s。", result.current), timeout = 4 })
                return
            end
            self:prompt_install_update(result)
        end)
    end)
end

function MainView:prompt_install_update(release)
    -- Show only the first line of the release notes as a short summary; the
    -- full notes can be very long and ConfirmBox is not scrollable.
    local summary = (release.notes or ""):match("^[^\n]*") or ""
    summary = summary:gsub("^#+%s*", "")
    local text = string.format("发现新版本 %s（当前 v%s）。", release.tag, release.current)
    if summary ~= "" then
        text = text .. "\n\n" .. summary
    end
    text = text .. "\n\n升级只替换插件程序，你的星星、打卡、错题本等学习记录完全不受影响。是否下载并升级？"
    UIManager:show(ConfirmBox:new{
        text = text,
        ok_text = "升级",
        cancel_text = "稍后",
        ok_callback = function() self:install_update(release) end,
    })
end

function MainView:install_update(release)
    if self.update_busy then return end
    NetworkMgr:runWhenOnline(function()
        if self.closed then return end
        self.update_busy = true
        local loading = InfoMessage:new{ text = "正在下载并安装更新，请稍候…\n请不要退出。" }
        UIManager:show(loading)
        UIManager:forceRePaint()
        Update.download_and_install({
            plugin_path = self.plugin_path,
            asset_url = release.asset_url,
            expect_version = release.version,
        }, function(ok, err)
            UIManager:close(loading)
            self.update_busy = false
            if self.closed then return end
            if not ok then
                UIManager:show(InfoMessage:new{
                    text = "升级失败：" .. tostring(err) .. "\n\n你的学习记录不受影响。",
                    timeout = 8,
                })
                return
            end
            UIManager:show(ConfirmBox:new{
                text = "升级完成！需要重启 KOReader 才能生效。\n\n你的学习记录完全保留。立即重启？",
                ok_text = "重启",
                cancel_text = "稍后",
                ok_callback = function()
                    self.progress:flush()
                    UIManager:restartKOReader()
                end,
                cancel_callback = function()
                    UIManager:show(InfoMessage:new{ text = "好的，下次启动 KOReader 时生效。", timeout = 4 })
                end,
            })
        end)
    end)
end

function MainView:_maybe_auto_check_update()
    if self._update_auto_checked then return end
    self._update_auto_checked = true
    local settings = self.progress.data.settings
    if not settings.update_auto_check then return end
    UIManager:scheduleIn(2, function()
        if self.closed then return end
        -- Auto-check is silent and only runs when already online; never prompt
        -- to enable Wi-Fi on startup.
        if not NetworkMgr:isConnected() then return end
        Update.check({
            api_url = settings.update_api_url,
            local_version = Update.local_version(self.plugin_path),
        }, function(result)
            if self.closed then return end
            if result.error or not result.available then return end
            self:prompt_install_update(result)
        end)
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
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    table.insert(content, Widgets.textbox(string.format("当前版本：v%s", Update.local_version(self.plugin_path)), cw, { size = 18 }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    table.insert(content, Widgets.button("检查更新", {
        width = cw,
        height = Screen:scaleBySize(54),
        align = "left",
        callback = function() self:check_update() end,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    table.insert(content, Widgets.button(string.format("启动时自动检查更新：%s", settings.update_auto_check and "开" or "关"), {
        width = cw,
        height = Screen:scaleBySize(54),
        align = "left",
        callback = function()
            settings.update_auto_check = not settings.update_auto_check
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
                    "小小学习家 v%s\n%s · %s · %s\n\n语文题库：%d 题\n数学题库：程序生成，无限题\n\n学习记录和 AI 题库只保存在本机；只有你主动使用 AI 出题或检查更新时才会联网，更新只替换插件程序，不影响学习记录。",
                    Update.local_version(self.plugin_path),
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

-- ---------------------------------------------------------------------------
-- Knowledge-point learning (synced from cn-math-taxonomy, CC BY-NC 4.0)
-- ---------------------------------------------------------------------------

local function kp_volume_label(grade, semester)
    grade = tonumber(grade) or 1
    return string.format("%s%s", GRADE_LABEL[grade] or (grade .. "年级"),
        semester == "lower" and "下册" or "上册")
end

local function kp_status_mark(status)
    return KP_STATUS_MARK[status]
end

local function kp_topic_button_text(name, status)
    local mark = kp_status_mark(status)
    if mark then return mark .. " " .. name end
    return name
end

-- Same difficulty curve as core/session.lua, kept local to avoid coupling.
local function kp_choose_difficulty(rng, level)
    local roll = rng(100)
    if level <= 1 then
        return roll <= 70 and 1 or 2
    elseif level >= 3 then
        if roll <= 10 then return 1 elseif roll <= 50 then return 2 else return 3 end
    end
    if roll <= 30 then return 1 elseif roll <= 80 then return 2 else return 3 end
end

function MainView:render_kp_subject()
    self.state = "kp_subject"
    self:set_title("知识点学习")
    self.selected = nil
    self.number_input = ""
    self.feedback = nil
    local cw = Widgets.width()
    local half = math.floor((cw - Size.span.horizontal_default) / 2)
    local content = VerticalGroup:new{
        align = "center",
        Widgets.textbox("按课标知识点先学后练；诊断会沿先修关系找到薄弱的基础知识。", cw, {
            size = 18, color = Blitbuffer.COLOR_DARK_GRAY,
        }),
        Widgets.vspace(Size.span.vertical_large),
        HorizontalGroup:new{
            align = "center",
            Widgets.button("语文知识点", {
                width = half,
                height = Screen:scaleBySize(72),
                size = 24,
                callback = function() self:render_kp_select("chinese") end,
            }),
            Widgets.hspace(Size.span.horizontal_default),
            Widgets.button("数学知识点", {
                width = half,
                height = Screen:scaleBySize(72),
                size = 24,
                callback = function() self:render_kp_select("math") end,
            }),
        },
        Widgets.vspace(Size.span.vertical_large),
        Widgets.button("返回首页", {
            width = cw,
            size = 20,
            callback = function() self:render_home() end,
        }),
    }
    self:set_body(content)
end

function MainView:render_kp_select(subject)
    self.state = "kp_select"
    self.kp_subject = subject
    self:set_title(self:subject_label(subject) .. "知识点")
    self.selected = nil
    self.number_input = ""
    self.feedback = nil
    local cw = Widgets.width()
    local settings = self.progress.data.settings
    local grade = tonumber(settings.grade) or 2
    local semester = settings.semester
    local volume, err = Knowledge.load(self.plugin_path, subject, grade, semester)
    if not volume then
        UIManager:show(InfoMessage:new{ text = "知识点题库加载失败：" .. tostring(err), timeout = 4 })
        self:render_home()
        return
    end
    local topic_ids = {}
    for _, topic in ipairs(volume.topics) do table.insert(topic_ids, topic.id) end
    local counts = self.progress:kp_summary(subject, topic_ids)
    local reference = subject == "math" and "课标知识点 · 人教参考" or "课标知识点 · 统编参考"

    local content = VerticalGroup:new{
        align = "center",
        Widgets.label(string.format("%s · %s", kp_volume_label(grade, semester), reference), {
            size = 17, color = Blitbuffer.COLOR_DARK_GRAY,
        }),
        Widgets.vspace(Size.span.vertical_default),
        Widgets.label(string.format("已掌握 %d/%d　★已掌握 ●学习中 ▲薄弱", counts.mastered, counts.total), {
            size = 16, color = Blitbuffer.COLOR_DARK_GRAY,
        }),
        Widgets.vspace(Size.span.vertical_default),
        Widgets.button("全册综合（10 题）", {
            width = cw,
            height = Screen:scaleBySize(56),
            size = 21,
            callback = function() self:start_kp_mixed(subject) end,
        }),
        Widgets.vspace(Size.span.vertical_default),
    }

    local half = math.floor((cw - Size.span.horizontal_default) / 2)
    for _, unit in ipairs(volume.units) do
        local unit_topics = {}
        for _, topic in ipairs(volume.topics) do
            if topic.unit == unit.id then table.insert(unit_topics, topic) end
        end
        if #unit_topics > 0 then
            table.insert(content, Widgets.label(unit.name, {
                size = 18, bold = true, max_width = cw,
            }))
            table.insert(content, Widgets.vspace(Size.span.vertical_default))
            local row
            for i, topic in ipairs(unit_topics) do
                local status = self.progress:kp_status(subject, topic.id)
                local button = Widgets.button(kp_topic_button_text(topic.name, status), {
                    width = half,
                    height = Screen:scaleBySize(52),
                    size = 18,
                    callback = function() self:render_kp_learn(subject, topic.id) end,
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
            table.insert(content, Widgets.vspace(Size.span.vertical_default))
        end
    end
    table.insert(content, Widgets.button("返回首页", {
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

function MainView:render_kp_learn(subject, topic_id)
    self.state = "kp_learn"
    self.kp_subject = subject
    self.selected = nil
    self.number_input = ""
    self.feedback = nil
    local topic = Knowledge.topic(self.plugin_path, subject, topic_id)
    if not topic then
        UIManager:show(InfoMessage:new{ text = "没有找到这个知识点", timeout = 3 })
        self:render_kp_select(subject)
        return
    end
    self:set_title(topic.name)
    local cw = Widgets.width()
    local inner_width = cw - 2 * Size.padding.large
    local graph = Knowledge.graph(self.plugin_path, subject)
    local node = graph and graph.nodes[topic_id] or {}
    local questions = Knowledge.questions_for(self.plugin_path, subject, topic_id)
    local status = self.progress:kp_status(subject, topic_id)
    local status_text = status and KP_STATUS_LABEL[status] or "未学"

    local example_explain
    for _, q in ipairs(questions) do
        if q.id == topic_id .. "_q1" then example_explain = q.explain break end
    end

    local learn_parts = VerticalGroup:new{
        align = "left",
        Widgets.label(string.format("%s · %s · %s", topic.domain or "",
            kp_volume_label(node.grade, node.semester), status_text), {
            size = 16, color = Blitbuffer.COLOR_DARK_GRAY,
        }),
        Widgets.vspace(Size.span.vertical_default),
        Widgets.textbox(topic.description or "", inner_width, { size = 20 }),
        Widgets.vspace(Size.span.vertical_default),
        Widgets.label("掌握标准", { size = 18, bold = true }),
    }
    for _, criterion in ipairs(topic.mastery_criteria or {}) do
        table.insert(learn_parts, Widgets.textbox("· " .. criterion, inner_width, { size = 18 }))
    end
    local example = topic.example or {}
    if example.question and example.question ~= "" then
        table.insert(learn_parts, Widgets.vspace(Size.span.vertical_default))
        table.insert(learn_parts, Widgets.label("例题", { size = 18, bold = true }))
        table.insert(learn_parts, Widgets.textbox(example.question, inner_width, { size = 19 }))
        table.insert(learn_parts, Widgets.label("参考答案：" .. tostring(example.answer or ""), { size = 18, bold = true }))
        if example_explain then
            table.insert(learn_parts, Widgets.textbox(example_explain, inner_width, { size = 17, color = Blitbuffer.COLOR_DARK_GRAY }))
        end
    end

    local content = VerticalGroup:new{
        align = "center",
        Widgets.card(learn_parts, { width = cw, padding = Size.padding.large }),
        Widgets.vspace(Size.span.vertical_default),
    }

    local prereqs = Knowledge.prereqs(self.plugin_path, subject, topic_id)
    if #prereqs > 0 then
        table.insert(content, Widgets.label("先修知识点（先学这些更容易）", {
            size = 17, color = Blitbuffer.COLOR_DARK_GRAY,
        }))
        table.insert(content, Widgets.vspace(Size.span.vertical_default))
        for _, p in ipairs(prereqs) do
            local pnode = graph and graph.nodes[p.id]
            local pstatus = self.progress:kp_status(subject, p.id)
            local label = kp_topic_button_text(pnode and pnode.name or p.id, pstatus)
            if p.strength == "soft" then label = label .. "（建议）" end
            table.insert(content, Widgets.button(label, {
                width = cw,
                height = Screen:scaleBySize(48),
                size = 18,
                callback = function() self:render_kp_learn(subject, p.id) end,
            }))
            table.insert(content, Widgets.vspace(Size.span.vertical_default))
        end
    end

    table.insert(content, Widgets.button(string.format("开始练习（%d 题）", #questions), {
        width = cw,
        height = Screen:scaleBySize(60),
        size = 22,
        enabled = #questions > 0,
        callback = function() self:start_kp_practice(subject, topic_id) end,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    table.insert(content, Widgets.button("诊断这个知识点", {
        width = cw,
        height = Screen:scaleBySize(56),
        size = 21,
        callback = function() self:start_diagnose(subject, topic_id) end,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    table.insert(content, Widgets.button("返回知识点列表", {
        width = cw,
        size = 20,
        callback = function() self:render_kp_select(subject) end,
    }))
    local scroll = ScrollableContainer:new{
        dimen = Geom:new{ w = cw, h = math.floor(Screen:getHeight() * 0.78) },
        show_parent = self,
        content,
    }
    self:set_body(scroll)
end

function MainView:start_kp_practice(subject, topic_id)
    local questions = Knowledge.questions_for(self.plugin_path, subject, topic_id)
    if #questions == 0 then
        UIManager:show(InfoMessage:new{ text = "这个知识点暂时没有可用题目", timeout = 3 })
        return
    end
    -- Easy questions first; keep source order within the same difficulty.
    local ordered = {}
    for i, q in ipairs(questions) do ordered[i] = { q = q, i = i } end
    table.sort(ordered, function(a, b)
        if a.q.difficulty ~= b.q.difficulty then return a.q.difficulty < b.q.difficulty end
        return a.i < b.i
    end)
    local list = {}
    for _, item in ipairs(ordered) do table.insert(list, item.q) end
    self:start_session({
        mode = "kp",
        subject = subject,
        kp_topic = topic_id,
        kp_questions = list,
    })
end

function MainView:start_kp_mixed(subject)
    local settings = self.progress.data.settings
    local grade = tonumber(settings.grade) or 2
    local volume, err = Knowledge.load(self.plugin_path, subject, grade, settings.semester)
    if not volume or #volume.units == 0 then
        UIManager:show(InfoMessage:new{ text = "知识点题库加载失败：" .. tostring(err), timeout = 4 })
        return
    end
    local rng = math.random
    local level = self.progress:adaptive_level(subject, grade)
    local recent = {}
    for _, id in ipairs(self.progress.data.recent_ids) do recent[id] = true end
    local questions = {}
    for i = 1, 10 do
        local unit = volume.units[((i - 1) % #volume.units) + 1]
        local unit_topics = {}
        for _, topic in ipairs(volume.topics) do
            if topic.unit == unit.id then table.insert(unit_topics, topic) end
        end
        if #unit_topics > 0 then
            local topic = unit_topics[rng(#unit_topics)]
            local pool = volume.by_topic[topic.id] or {}
            local difficulty = kp_choose_difficulty(rng, level)
            local candidates = {}
            for _, q in ipairs(pool) do
                if q.difficulty == difficulty and not recent[q.id] then table.insert(candidates, q) end
            end
            if #candidates == 0 then
                for _, q in ipairs(pool) do
                    if not recent[q.id] then table.insert(candidates, q) end
                end
            end
            if #candidates == 0 then candidates = pool end
            if #candidates > 0 then
                local q = candidates[rng(#candidates)]
                table.insert(questions, q)
                recent[q.id] = true
            end
        end
    end
    if #questions == 0 then
        UIManager:show(InfoMessage:new{ text = "没有可用题目", timeout = 3 })
        return
    end
    self:start_session({ mode = "kp", subject = subject, kp_questions = questions })
end

function MainView:start_diagnose(subject, topic_id)
    local graph, err = Knowledge.graph(self.plugin_path, subject)
    if not graph then
        UIManager:show(InfoMessage:new{ text = "知识图谱加载失败：" .. tostring(err), timeout = 4 })
        return
    end
    if #Knowledge.questions_for(self.plugin_path, subject, topic_id) == 0 then
        UIManager:show(InfoMessage:new{ text = "这个知识点暂时没有可用题目", timeout = 3 })
        return
    end
    local engine, derr = Diagnose.new{
        subject = subject,
        target = topic_id,
        graph = graph,
        questions_fn = function(id)
            return Knowledge.questions_for(self.plugin_path, subject, id)
        end,
        judge_fn = Knowledge.judge,
        rng = math.random,
    }
    if not engine then
        UIManager:show(InfoMessage:new{ text = "无法开始诊断：" .. tostring(derr), timeout = 4 })
        return
    end
    self.diagnose = engine
    self.diagnose_subject = subject
    self.diagnose_feedback = nil
    self.diagnose_summary = nil
    self:diagnose_next()
end

function MainView:diagnose_next()
    local item = self.diagnose:next()
    if not item then
        self:finish_diagnose()
        return
    end
    self.diagnose_item = item
    self.selected = nil
    self.number_input = ""
    self:render_diagnose_quiz()
end

function MainView:diagnose_submit(value)
    if not self.diagnose or not self.diagnose_item then return end
    local result = self.diagnose:submit(value)
    if not result then return end
    self.diagnose_feedback = {
        question = self.diagnose_item.question,
        correct = result.correct,
        hint = result.hint,
        status = result.status,
    }
    self:render_diagnose_feedback()
end

function MainView:finish_diagnose()
    local summary = self.diagnose:summary()
    -- Diagnosis is assessment: persist mastery only, no stars / wrong book.
    for _, entry in ipairs(summary.mastered) do
        self.progress:mark_kp_status(self.diagnose_subject, entry.id, "mastered")
    end
    for _, entry in ipairs(summary.shaky) do
        self.progress:mark_kp_status(self.diagnose_subject, entry.id, "learning")
    end
    for _, entry in ipairs(summary.weak) do
        self.progress:mark_kp_status(self.diagnose_subject, entry.id, "weak")
    end
    self.progress:flush()
    self.diagnose_summary = summary
    self:render_diagnose_result()
end

function MainView:render_diagnose_quiz()
    self.state = "diagnose_quiz"
    self:set_title("知识点诊断")
    local engine = self.diagnose
    local question = self.diagnose_item.question
    local cw = Widgets.width()
    local content = VerticalGroup:new{
        align = "center",
        Widgets.label(string.format("已答 %d/%d 题 · 答错会自动检查先修知识", #engine.answers, engine.limit), {
            size = 16, color = Blitbuffer.COLOR_DARK_GRAY,
        }),
        Widgets.vspace(Size.span.vertical_default),
        Widgets.progress(#engine.answers / engine.limit, cw),
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

function MainView:render_diagnose_feedback()
    self.state = "diagnose_feedback"
    self:set_title("知识点诊断")
    local fb = self.diagnose_feedback
    local q = fb.question
    local cw = Widgets.width()
    local parts = VerticalGroup:new{ align = "left" }
    if fb.correct then
        table.insert(parts, Widgets.label("✓ 答对了！", { size = 24, bold = true }))
    else
        table.insert(parts, Widgets.label("✗ 答错了", { size = 24, bold = true }))
        table.insert(parts, Widgets.label("正确答案：" .. answer_text(q), { size = 20, bold = true }))
    end
    table.insert(parts, Widgets.vspace(Size.span.vertical_default))
    table.insert(parts, Widgets.label(fb.hint or "", { size = 18, bold = true }))
    table.insert(parts, Widgets.vspace(Size.span.vertical_default))
    table.insert(parts, Widgets.textbox(q.explain or "", cw - 4 * Size.padding.default, { size = 18 }))
    local content = VerticalGroup:new{
        align = "center",
        Widgets.label(string.format("已答 %d/%d 题", #self.diagnose.answers, self.diagnose.limit), {
            size = 16, color = Blitbuffer.COLOR_DARK_GRAY,
        }),
        Widgets.vspace(Size.span.vertical_default),
        self:render_question_card(q),
        Widgets.vspace(Size.span.vertical_default),
        Widgets.card(parts, { width = cw, padding = Size.padding.large }),
        Widgets.vspace(Size.span.vertical_large),
        Widgets.button("继续", {
            width = cw,
            height = Screen:scaleBySize(58),
            size = 22,
            callback = function() self:diagnose_next() end,
        }),
    }
    self:set_body(content)
end

function MainView:render_diagnose_result()
    self.state = "diagnose_result"
    self:set_title("诊断结果")
    local cw = Widgets.width()
    local summary = self.diagnose_summary
    local graph = self.diagnose.graph
    local target_node = graph.nodes[summary.target] or {}
    local content = VerticalGroup:new{
        align = "center",
        Widgets.card(VerticalGroup:new{
            align = "center",
            Widgets.label("诊断完成", { size = 28, bold = true }),
            Widgets.vspace(Size.span.vertical_default),
            Widgets.label(string.format("目标：%s", target_node.name or summary.target), { size = 19 }),
            Widgets.vspace(Size.span.vertical_default),
            Widgets.label(string.format("共答 %d 题 · 掌握 %d · 不稳 %d · 薄弱 %d",
                summary.asked, #summary.mastered, #summary.shaky, #summary.weak), { size = 18 }),
            summary.limit_reached and Widgets.label("题量用完，还有知识点没测到。", {
                size = 16, color = Blitbuffer.COLOR_DARK_GRAY,
            }) or Widgets.vspace(0),
        }, { width = cw, padding = Size.padding.large }),
        Widgets.vspace(Size.span.vertical_default),
    }

    if #summary.path > 0 then
        table.insert(content, Widgets.label("学习路径（从基础补起）", { size = 19, bold = true }))
        table.insert(content, Widgets.vspace(Size.span.vertical_default))
        for i, entry in ipairs(summary.path) do
            local status_text = entry.status == "weak" and "薄弱" or "不稳"
            local tag = entry.is_root and "根因 · " or ""
            table.insert(content, Widgets.label(string.format("%d. %s%s（%s · %s）",
                i, tag, entry.name, kp_volume_label(entry.grade, entry.semester), status_text), {
                size = 18, max_width = cw,
            }))
            table.insert(content, Widgets.vspace(Size.span.vertical_default))
        end
        table.insert(content, Widgets.button("去学第一个薄弱点", {
            width = cw,
            height = Screen:scaleBySize(58),
            size = 21,
            callback = function()
                self:render_kp_learn(self.diagnose_subject, summary.path[1].id)
            end,
        }))
        table.insert(content, Widgets.vspace(Size.span.vertical_default))
    else
        table.insert(content, Widgets.textbox("没有发现薄弱点，继续保持！", cw, {
            size = 20, alignment = "center",
        }))
        table.insert(content, Widgets.vspace(Size.span.vertical_default))
    end

    if #summary.mastered > 0 then
        local names = {}
        for i, entry in ipairs(summary.mastered) do
            if i <= 8 then table.insert(names, entry.name) end
        end
        local text = "已掌握：" .. table.concat(names, "、")
        if #summary.mastered > 8 then
            text = text .. string.format(" 等 %d 个", #summary.mastered)
        end
        table.insert(content, Widgets.textbox(text, cw, { size = 16, color = Blitbuffer.COLOR_DARK_GRAY }))
        table.insert(content, Widgets.vspace(Size.span.vertical_default))
    end

    table.insert(content, Widgets.button("再诊断一次", {
        width = cw,
        size = 20,
        callback = function() self:start_diagnose(self.diagnose_subject, summary.target) end,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
    table.insert(content, Widgets.button("返回知识点列表", {
        width = cw,
        size = 20,
        callback = function() self:render_kp_select(self.diagnose_subject) end,
    }))
    table.insert(content, Widgets.vspace(Size.span.vertical_default))
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
