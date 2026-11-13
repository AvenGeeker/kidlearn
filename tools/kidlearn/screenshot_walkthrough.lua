--[[--
UI walkthrough + screenshot generator (run via tools/kidlearn/take_screenshots.sh).

Renders every KidLearn page in the real KOReader rendering pipeline
(600x800 dummy framebuffer, same as the emulator) and writes PNGs into
docs/screenshots/.  Uses a fresh demo save: one perfect daily round, one
perfect challenge round, a seeded card collection, the daily report draw,
the card book and card detail page, then learns/practices/diagnoses
认识几分之一 (cnm_p079).
--]]--

describe("KidLearn screenshot walkthrough", function()
    local DataStorage
    local Device
    local MainView
    local Knowledge
    local Cards
    local view
    local out_dir = "./plugins/kidlearn.koplugin/docs/screenshots/"

    setup(function()
        require("commonrequire")
        package.path = "plugins/kidlearn.koplugin/?.lua;" .. package.path
        DataStorage = require("datastorage")
        Device = require("device")
        MainView = require("ui/mainview")
        Knowledge = require("core.knowledge")
        Cards = require("core.cards")
    end)

    local function shot(name)
        view:paintTo(Device.screen.bb, 0, 0)
        local ok, err = Device.screen:shot(out_dir .. name .. ".png")
        assert.is_true(ok, tostring(err))
        print("screenshot: " .. name .. ".png")
    end

    local function answer_current(correct)
        local q = view.session:current()
        local value
        if correct then
            value = q.answer
        elseif q.answer_mode == "number" then
            value = "999999"
        else
            value = (q.answer % #q.options) + 1
        end
        view:submit_answer(value)
    end

    local function finish_round()
        for _ = 1, view.session:total() do
            answer_current(true)
            view:next_question()
        end
        assert.are.equal("summary", view.state)
    end

    it("walks through all pages and captures screenshots", function()
        -- Fresh demo save.
        local save = DataStorage:getSettingsDir() .. "/kidlearn.lua"
        os.remove(save)
        os.remove(save .. ".old")
        os.remove(save .. ".pre-v5.bak")
        view = MainView:new{
            plugin_path = "./plugins/kidlearn.koplugin",
            plugin = {},
        }
        local settings = view.progress.data.settings
        settings.grade = 3
        settings.semester = "upper"
        view.progress:flush()

        -- One perfect daily round; capture the quiz and feedback pages.
        view:start_session({ mode = "daily" })
        shot("daily-quiz")
        answer_current(true)
        shot("answer-feedback")
        view:next_question()
        for _ = 2, view.session:total() do
            answer_current(true)
            view:next_question()
        end
        assert.are.equal("summary", view.state)

        -- One perfect challenge round: unlocks the challenge badge line.
        view:start_session({ mode = "challenge", subject = "math", unit = "all" })
        finish_round()

        -- Seed a demo collection so the card book shows lit and unlit cards.
        local seed = {
            Cards.get("r01"), Cards.get("r01"), Cards.get("r01"),
            Cards.get("r02"), Cards.get("r04"), Cards.get("r09"),
            Cards.get("rr01"), Cards.get("rr01"), Cards.get("rr03"), Cards.get("rr07"),
            Cards.get("s02"), Cards.get("s05"),
            Cards.get("ss01"),
            Cards.get("sss01"),
        }
        view.progress:add_cards(seed)

        -- Daily report: local score + offline summary, then reveal the cards.
        -- Inject an evening timestamp so the pre-19:00 confirmation never
        -- blocks the walkthrough regardless of the real clock.
        local t = os.date("*t")
        t.hour, t.min, t.sec = 20, 0, 0
        view:open_daily_report(os.time(t))
        assert.are.equal("daily_report", view.state)
        shot("daily-report")
        local report = view.progress:daily_report()
        report.revealed = true
        view.progress:save_daily_report(report)
        view:render_daily_report()
        shot("daily-report-cards")

        view:render_cards(true)
        assert.are.equal("cards", view.state)
        shot("card-book")
        view:render_card_detail("sss01", "cards")
        assert.are.equal("card_detail", view.state)
        shot("card-detail")
        view:onBack()
        assert.are.equal("cards", view.state)
        view:leave_cards()

        -- Home page with the new entry row and the "today drawn" marker.
        view:render_home()
        shot("home")

        -- Badge wall: page 1 (original line) and page 4 (challenge line).
        view:render_badges(1)
        shot("badges")
        view:render_badges(4)
        shot("badges-challenge")
        view:render_home()

        -- Seed a few mastery marks for the list view.
        view.progress:mark_kp_status("math", "cnm_p221", "mastered")
        view.progress:mark_kp_status("math", "cnm_p223", "learning")
        view.progress:mark_kp_status("math", "cnm_p067", "weak")
        view.progress:flush()

        view:render_kp_subject()
        shot("kp-subject")

        view:render_kp_select("math")
        shot("kp-select-math")

        view:render_kp_learn("math", "cnm_p079")
        shot("kp-learn")

        -- Single-topic practice: answer q1, then show the fraction keypad on q2.
        view:start_kp_practice("math", "cnm_p079")
        assert.are.equal("quiz", view.state)
        answer_current(true) -- q1 choice
        view:next_question()
        local q2 = view.session:current()
        assert.are.equal("fraction", q2.answer_format)
        view.number_input = "1/"
        view:render_quiz()
        shot("kp-quiz-fraction")
        view:submit_answer("1/4")
        view:next_question()
        answer_current(true) -- q3
        view:next_question()
        answer_current(true) -- q4
        view:next_question()
        assert.are.equal("summary", view.state)
        shot("kp-summary")

        -- Diagnosis: first question, wrong-answer feedback, then the result page.
        view:start_diagnose("math", "cnm_p079")
        assert.are.equal("diagnose_quiz", view.state)
        shot("diagnose-quiz")
        local dq = view.diagnose_item.question
        local wrong = dq.answer_mode == "number" and "999999"
            or ((dq.answer % #dq.options) + 1)
        view:submit_answer(wrong)
        assert.are.equal("diagnose_feedback", view.state)
        shot("diagnose-feedback")
        local guard = 0
        while view.state ~= "diagnose_result" and guard < 30 do
            guard = guard + 1
            if view.state == "diagnose_quiz" then
                local q = view.diagnose_item.question
                local w = q.answer_mode == "number" and "999999"
                    or ((q.answer % #q.options) + 1)
                view:submit_answer(w)
            elseif view.state == "diagnose_feedback" then
                view:diagnose_next()
            else
                break
            end
        end
        assert.are.equal("diagnose_result", view.state)
        shot("diagnose-result")

        view:render_kp_select("chinese")
        shot("kp-select-chinese")

        view:close_view()
    end)
end)
