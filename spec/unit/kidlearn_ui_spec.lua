describe("KidLearn UI smoke", function()
    local DataStorage
    local Device
    local MainView
    local AIBank
    local view
    local ai_bank_path

    setup(function()
        require("commonrequire")
        package.path = "plugins/kidlearn.koplugin/?.lua;" .. package.path
        DataStorage = require("datastorage")
        Device = require("device")
        MainView = require("ui/mainview")
        AIBank = require("core.ai_bank")
    end)

    before_each(function()
        ai_bank_path = DataStorage:getDataDir() .. "/kidlearn_ui_ai_bank_spec.json"
        os.remove(ai_bank_path)
        os.remove(ai_bank_path .. ".bad")
        os.remove(ai_bank_path .. ".tmp")
        view = MainView:new{
            plugin_path = "./plugins/kidlearn.koplugin",
            plugin = {},
        }
        view.ai_bank = AIBank.open(ai_bank_path)
    end)

    after_each(function()
        os.remove(ai_bank_path)
        os.remove(ai_bank_path .. ".bad")
        os.remove(ai_bank_path .. ".tmp")
    end)

    it("builds every top-level page", function()
        assert.are.equal("home", view.state)
        view:render_unit_select("chinese")
        assert.are.equal("unit_select", view.state)
        view:render_settings()
        assert.are.equal("settings", view.state)
        view:render_badges()
        assert.are.equal("badges", view.state)
        view:render_wrongbook()
        assert.are.equal("wrongbook", view.state)
        view:render_home()
        assert.are.equal("home", view.state)
    end)

    it("runs a math question through quiz and feedback pages", function()
        view:start_session({ mode = "subject", subject = "math", unit = "m2" })
        assert.are.equal("quiz", view.state)
        local q = view.session:current()
        assert.is_not_nil(q)
        view:submit_answer(q.answer)
        assert.are.equal("feedback", view.state)
        assert.is_true(view.feedback.correct)
        view:next_question()
        assert.are.equal("quiz", view.state)
    end)

    it("builds a math challenge page", function()
        view:start_session({ mode = "challenge", subject = "math", unit = "all" })
        assert.are.equal("quiz", view.state)
        local q = view.session:current()
        assert.is_true(q.challenge)
        assert.is_string(q.competency)
    end)

    it("builds a Chinese quiz page with the real bank", function()
        view:start_session({ mode = "subject", subject = "chinese", unit = "u1" })
        assert.are.equal("quiz", view.state)
        local q = view.session:current()
        assert.are.equal("chinese", q.subject)
        assert.are.equal(4, #q.options)
    end)

    it("opens province, grade and textbook selectors", function()
        view:render_settings()
        assert.are.equal("settings", view.state)
        view:render_province_select()
        assert.are.equal("choice_list", view.state)
        view:render_grade_select()
        assert.are.equal("choice_list", view.state)
        view:render_edition_select("chinese")
        assert.are.equal("choice_list", view.state)
        view:render_edition_select("math")
        assert.are.equal("choice_list", view.state)
    end)

    it("runs grade-one Chinese and grade-six math questions", function()
        view.progress.data.settings.grade = 1
        view.progress.data.settings.semester = "upper"
        view:start_session({ mode = "subject", subject = "chinese", unit = "all" })
        assert.are.equal("quiz", view.state)
        assert.are.equal(1, view.session:current().grade)

        view.progress.data.settings.grade = 6
        view.progress.data.settings.math_edition = "renjiao"
        view:start_session({ mode = "subject", subject = "math", unit = "all" })
        assert.are.equal("quiz", view.state)
        assert.are.equal(6, view.session:current().grade)
    end)

    it("builds AI settings, bank and wrong-detail AI entries", function()
        view:render_ai_settings()
        assert.are.equal("ai_settings", view.state)
        view:render_ai_preset_select()
        assert.are.equal("choice_list", view.state)
        view:render_ai_bank()
        assert.are.equal("ai_bank", view.state)
        local item = {
            id = "wrong-ai-ui", subject = "math", grade = 4, semester = "upper",
            edition = "renjiao", unit = "m2", unit_name = "测试单元",
            type = "math_choice", skill = "add_sub", difficulty = 2,
            answer_mode = "choice", stem = "1 + 1 = ?", options = { "1", "2", "3", "4" },
            answer = 2, explain = "1 + 1 = 2。",
        }
        view:render_wrong_detail(item)
        assert.are.equal("wrong_detail", view.state)
    end)

    local function find_button(widget, needle)
        if type(widget) ~= "table" then return nil end
        if type(widget.text) == "string" and widget.text:find(needle, 1, true) and widget.callback then
            return widget
        end
        for i = 1, #widget do
            local found = find_button(widget[i], needle)
            if found then return found end
        end
        return nil
    end

    it("enters AI settings from the settings page", function()
        view:render_settings()
        local button = assert(find_button(view.body, "AI 出题"))
        button.callback()
        assert.are.equal("ai_settings", view.state)
    end)

    it("paints settings and AI settings as full-screen pages", function()
        view:render_settings()
        view:paintTo(Device.screen.bb, 0, 0)
        view:render_ai_settings()
        local settings_scroll = view.body[1]
        assert.is_not_nil(settings_scroll[1])
        view:paintTo(Device.screen.bb, 0, 0)
        assert.are.equal("ai_settings", view.state)

        view:render_ai_bank()
        local bank_scroll = view.body[1]
        assert.is_not_nil(bank_scroll[1])
        view:paintTo(Device.screen.bb, 0, 0)
        assert.are.equal("ai_bank", view.state)
    end)

    it("previews a stored AI variant group", function()
        view.ai_bank:add_group({
            id = "aig-ui-1", created_at = 1760000000,
            provider = { name = "DeepSeek", model = "deepseek-chat" },
            origins = { { id = "wrong-ai-ui", subject = "math", stem = "1 + 1 = ?" } },
            questions = {
                {
                    id = "aig-ui-1-q1", origin_id = "wrong-ai-ui", ai_generated = true,
                    subject = "math", grade = 4, unit = "m2", unit_name = "测试单元",
                    type = "math_choice", skill = "add_sub", difficulty = 2,
                    answer_mode = "choice", stem = "2 + 2 = ?", options = { "3", "4", "5", "6" },
                    answer = 2, explain = "2 + 2 = 4。",
                },
            },
        })
        view:render_ai_preview("aig-ui-1")
        assert.are.equal("ai_preview", view.state)
    end)

    it("reflects the selected grade and textbook labels", function()
        view.progress.data.settings.grade = 4
        view.progress.data.settings.math_edition = "sujiao"
        assert.are.equal("四年级", view:grade_label())
        assert.are.equal("苏教版", view:edition_name("math"))
        assert.is_truthy(view:course_label():find("四年级", 1, true))
        assert.is_truthy(view:course_label():find("苏教版", 1, true))
    end)
end)

describe("KidLearn knowledge UI smoke", function()
    local DataStorage
    local MainView
    local AIBank
    local view
    local ai_bank_path

    setup(function()
        require("commonrequire")
        package.path = "plugins/kidlearn.koplugin/?.lua;" .. package.path
        DataStorage = require("datastorage")
        MainView = require("ui/mainview")
        AIBank = require("core.ai_bank")
    end)

    before_each(function()
        ai_bank_path = DataStorage:getDataDir() .. "/kidlearn_ui_kp_spec_ai_bank.json"
        os.remove(ai_bank_path)
        view = MainView:new{
            plugin_path = "./plugins/kidlearn.koplugin",
            plugin = {},
        }
        view.ai_bank = AIBank.open(ai_bank_path)
    end)

    after_each(function()
        os.remove(ai_bank_path)
        os.remove(ai_bank_path .. ".bad")
        os.remove(ai_bank_path .. ".tmp")
    end)

    it("builds the knowledge pages", function()
        view:render_kp_subject()
        assert.are.equal("kp_subject", view.state)
        view:render_kp_select("math")
        assert.are.equal("kp_select", view.state)
        view:render_kp_select("chinese")
        assert.are.equal("kp_select", view.state)
        view:render_kp_learn("math", "cnm_p001")
        assert.are.equal("kp_learn", view.state)
    end)

    it("runs a knowledge practice session to the summary", function()
        view:start_kp_practice("math", "cnm_p001")
        assert.are.equal("quiz", view.state)
        assert.are.equal("kp", view.session.mode)
        assert.are.equal(4, view.session:total())
        for i = 1, 4 do
            local q = view.session:current()
            view:submit_answer(q.answer)
            assert.are.equal("feedback", view.state)
            view:next_question()
        end
        assert.are.equal("summary", view.state)
        assert.is_not_nil(view.summary.kp_statuses)
    end)

    it("builds a mixed knowledge session for Chinese", function()
        view:start_kp_mixed("chinese")
        assert.are.equal("quiz", view.state)
        assert.are.equal(10, view.session:total())
        for _, q in ipairs(view.session.questions) do
            assert.are.equal("chinese", q.subject)
            assert.is_string(q.topic)
        end
    end)

    it("runs a diagnosis to the result page and persists mastery", function()
        view:start_diagnose("math", "cnm_p001")
        assert.are.equal("diagnose_quiz", view.state)
        local guard = 0
        while view.state ~= "diagnose_result" and guard < 20 do
            guard = guard + 1
            if view.state == "diagnose_quiz" then
                local q = view.diagnose_item.question
                view:submit_answer(q.answer)
                assert.are.equal("diagnose_feedback", view.state)
            elseif view.state == "diagnose_feedback" then
                view:diagnose_next()
            else
                break
            end
        end
        assert.are.equal("diagnose_result", view.state)
        assert.are.equal("mastered", view.progress:kp_status("math", "cnm_p001"))
    end)

    it("builds the extended keypad for a fraction question", function()
        view:start_session({
            mode = "kp",
            subject = "math",
            kp_topic = "cnm_p079",
            kp_questions = {
                {
                    id = "cnm_p079_q2", topic = "cnm_p079", subject = "math",
                    grade = 3, semester = "upper", unit = "u1",
                    unit_name = "分数的初步认识", type = "knowledge", skill = "数与代数",
                    difficulty = 1, answer_mode = "number", answer_format = "fraction",
                    stem = "每份是多少？", answer = "1/4", explain = "平均分成 4 份。",
                },
            },
        })
        assert.are.equal("quiz", view.state)
        assert.are.equal("fraction", view.session:current().answer_format)
        view:submit_answer("0.25")
        assert.are.equal("feedback", view.state)
        assert.is_true(view.feedback.correct)
    end)
    it("paints the knowledge pages full-screen", function()
        local Device = require("device")
        view:render_kp_select("math")
        view:paintTo(Device.screen.bb, 0, 0)
        view:render_kp_learn("math", "cnm_p001")
        view:paintTo(Device.screen.bb, 0, 0)
        view:start_diagnose("math", "cnm_p001")
        view:paintTo(Device.screen.bb, 0, 0)
        assert.are.equal("diagnose_quiz", view.state)
        local q = view.diagnose_item.question
        view:submit_answer(q.answer)
        view:paintTo(Device.screen.bb, 0, 0)
        assert.are.equal("diagnose_feedback", view.state)
        view:diagnose_next()
        view:paintTo(Device.screen.bb, 0, 0)
    end)
    it("backtracks across volumes on real data when answers are wrong", function()
        local settings = view.progress.data.settings
        local old_grade = settings.grade
        settings.grade = 3
        settings.semester = "upper"
        view:start_diagnose("math", "cnm_p079") -- 认识几分之一, hard prereq cnm_p278, soft cnm_p043 (grade 2)
        assert.are.equal("diagnose_quiz", view.state)
        local guard = 0
        while view.state ~= "diagnose_result" and guard < 30 do
            guard = guard + 1
            if view.state == "diagnose_quiz" then
                local q = view.diagnose_item.question
                local wrong = q.answer_mode == "number" and "999999"
                    or ((q.answer % #q.options) + 1)
                view:submit_answer(wrong)
            elseif view.state == "diagnose_feedback" then
                view:diagnose_next()
            else
                break
            end
        end
        assert.are.equal("diagnose_result", view.state)
        assert.are.equal("weak", view.progress:kp_status("math", "cnm_p079"))
        -- Hard prerequisite must be tested before the soft one.
        assert.are.equal("cnm_p079", view.diagnose.answers[1].topic)
        assert.are.equal("cnm_p079", view.diagnose.answers[2].topic)
        assert.are.equal("cnm_p278", view.diagnose.answers[3].topic)
        assert.is_true(#view.diagnose_summary.path > 0)
        settings.grade = old_grade
    end)
end)

describe("KidLearn title-bar back navigation", function()
    local DataStorage
    local Device
    local MainView
    local AIBank
    local view
    local ai_bank_path

    setup(function()
        require("commonrequire")
        package.path = "plugins/kidlearn.koplugin/?.lua;" .. package.path
        DataStorage = require("datastorage")
        Device = require("device")
        MainView = require("ui/mainview")
        AIBank = require("core.ai_bank")
    end)

    before_each(function()
        ai_bank_path = DataStorage:getDataDir() .. "/kidlearn_ui_back_spec_ai_bank.json"
        os.remove(ai_bank_path)
        view = MainView:new{
            plugin_path = "./plugins/kidlearn.koplugin",
            plugin = {},
        }
        view.ai_bank = AIBank.open(ai_bank_path)
    end)

    after_each(function()
        os.remove(ai_bank_path)
        os.remove(ai_bank_path .. ".bad")
        os.remove(ai_bank_path .. ".tmp")
    end)

    it("shows the back button only outside the home page", function()
        assert.are.equal("home", view.state)
        assert.is_nil(view.title_bar.left_icon)
        view:render_kp_select("math")
        assert.are.equal("chevron.left", view.title_bar.left_icon)
        view:render_home()
        assert.is_nil(view.title_bar.left_icon)
    end)

    it("returns second-level pages straight to home", function()
        view:render_unit_select("math")
        view:onBack()
        assert.are.equal("home", view.state)
        view:render_kp_select("chinese")
        view:onBack()
        assert.are.equal("home", view.state)
        view:render_settings()
        view:onBack()
        assert.are.equal("home", view.state)
        view:render_wrongbook()
        view:onBack()
        assert.are.equal("home", view.state)
        view:render_badges()
        view:onBack()
        assert.are.equal("home", view.state)
    end)

    it("steps up from the knowledge card to the list, then home", function()
        view:render_kp_learn("chinese", "cnc_p001")
        assert.are.equal("kp_learn", view.state)
        view:onBack()
        assert.are.equal("kp_select", view.state)
        assert.are.equal("chinese", view.kp_subject)
        view:onBack()
        assert.are.equal("home", view.state)
    end)

    it("keeps the session and asks for confirmation when backing out of a quiz", function()
        view:start_session({ mode = "subject", subject = "math", unit = "m1" })
        assert.are.equal("quiz", view.state)
        assert.are.equal("chevron.left", view.title_bar.left_icon)
        view:onBack()
        assert.are.equal("quiz", view.state) -- ConfirmBox pending, not exited
        assert.is_not_nil(view.session)
    end)

    it("honours custom back callbacks for choice lists and the AI bank", function()
        view:render_province_select()
        assert.are.equal("choice_list", view.state)
        view:onBack()
        assert.are.equal("settings", view.state)
        view:render_ai_bank(nil, function() view:render_wrongbook() end)
        assert.are.equal("ai_bank", view.state)
        view:onBack()
        assert.are.equal("wrongbook", view.state)
    end)

    it("paints correctly after the title bar is rebuilt", function()
        view:render_kp_select("math")
        view:paintTo(Device.screen.bb, 0, 0)
        view:onBack()
        assert.are.equal("home", view.state)
        view:paintTo(Device.screen.bb, 0, 0)
        view:render_kp_learn("math", "cnm_p001")
        view:paintTo(Device.screen.bb, 0, 0)
    end)
end)
