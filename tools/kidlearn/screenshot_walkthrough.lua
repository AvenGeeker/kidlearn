--[[--
UI walkthrough + screenshot generator (run via tools/kidlearn/take_screenshots.sh).

Renders every knowledge-learning page in the real KOReader rendering pipeline
(600x800 dummy framebuffer, same as the emulator) and writes PNGs into
docs/screenshots/.  Uses a fresh demo save: one perfect daily round, a few
seeded mastery marks, then learns/practices/diagnoses 认识几分之一 (cnm_p079).
--]]--

describe("KidLearn screenshot walkthrough", function()
    local DataStorage
    local Device
    local MainView
    local Knowledge
    local view
    local out_dir = "./plugins/kidlearn.koplugin/docs/screenshots/"

    setup(function()
        require("commonrequire")
        package.path = "plugins/kidlearn.koplugin/?.lua;" .. package.path
        DataStorage = require("datastorage")
        Device = require("device")
        MainView = require("ui/mainview")
        Knowledge = require("core.knowledge")
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

    it("walks through all knowledge pages and captures screenshots", function()
        -- Fresh demo save.
        local save = DataStorage:getSettingsDir() .. "/kidlearn.lua"
        os.remove(save)
        os.remove(save .. ".old")
        view = MainView:new{
            plugin_path = "./plugins/kidlearn.koplugin",
            plugin = {},
        }
        local settings = view.progress.data.settings
        settings.grade = 3
        settings.semester = "upper"
        view.progress:flush()

        -- One perfect daily round so the home page shows real progress.
        view:start_session({ mode = "daily" })
        for i = 1, view.session:total() do
            answer_current(true)
            view:next_question()
        end
        assert.are.equal("summary", view.state)
        view:render_home()
        shot("home")

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
