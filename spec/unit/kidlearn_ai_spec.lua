describe("KidLearn AI", function()
    local DataStorage
    local JSON
    local AIConfig
    local AIClient
    local AIBank
    local AIVariant
    local Bank
    local Progress
    local Session

    setup(function()
        require("commonrequire")
        package.path = "plugins/kidlearn.koplugin/?.lua;" .. package.path
        DataStorage = require("datastorage")
        JSON = require("json")
        AIConfig = require("core.ai_config")
        AIClient = require("core.ai_client")
        AIBank = require("core.ai_bank")
        AIVariant = require("core.ai_variant")
        Bank = require("core.bank")
        Progress = require("core.progress")
        Session = require("core.session")
    end)

    local function profile(preset_id, model)
        local ai = { profiles = {}, active_id = nil }
        local item = assert(AIConfig.new_profile(preset_id, ai))
        item.api_key = "test-key-1234"
        item.model = model or item.model
        table.insert(ai.profiles, item)
        ai.active_id = item.id
        AIConfig.normalize(ai)
        return ai, ai.profiles[1]
    end

    local function wrong_item(id, subject)
        return {
            id = id or "wrong-1",
            subject = subject or "math",
            grade = 4,
            semester = "upper",
            edition = "renjiao",
            unit = subject == "chinese" and "u1" or "m2",
            unit_name = subject == "chinese" and "第一单元" or "100以内的加法和减法",
            type = subject == "chinese" and "word_choice" or "math_choice",
            skill = subject == "chinese" and "word" or "add_sub",
            difficulty = 2,
            answer_mode = "choice",
            stem = "原题：8 + 7 = ？",
            options = { "13", "14", "15", "16" },
            answer = 3,
            explain = "8 + 7 = 15。",
        }
    end

    local function variant(origin_index, stem, answer)
        return {
            origin = origin_index,
            stem = stem,
            options = { "11", "12", "13", "14" },
            answer = answer or 1,
            explain = "这是变种的解析。",
        }
    end

    it("normalizes AI profiles and chooses an active one", function()
        local ai = AIConfig.normalize({ profiles = {} })
        assert.are.equal("table", type(ai.profiles))
        assert.is_nil(ai.active_id)
        local configured, item = profile("deepseek")
        assert.are.equal(item.id, configured.active_id)
        assert.are.equal("openai", item.protocol)
        assert.is_true(AIConfig.validate(item))
        assert.are.equal("••••1234", AIConfig.mask_key(item.api_key))
    end)

    it("validates custom endpoints and required model fields", function()
        local ai, item = profile("custom")
        item.model = ""
        item.base_url = ""
        local ok, err = AIConfig.validate(item)
        assert.is_nil(ok)
        assert.is_truthy(err:find("模型"))
        item.model = "local-model"
        ok, err = AIConfig.validate(item)
        assert.is_nil(ok)
        assert.is_truthy(err:find("接口"))
        item.base_url = "http://127.0.0.1:11434/v1"
        assert.is_true(AIConfig.validate(item))
    end)

    it("keeps editable base URLs for local and custom services", function()
        local ai, item = profile("ollama")
        item.base_url = "http://192.168.0.5:11434/v1"
        AIConfig.normalize(ai)
        local normalized = ai.profiles[1]
        assert.are.equal("http://192.168.0.5:11434/v1", normalized.base_url)
        assert.is_true(AIConfig.validate(normalized))
    end)

    it("imports a single AI service from kidlearn_ai_config.json", function()
        local path = DataStorage:getDataDir() .. "/kidlearn_ai_config_spec.json"
        os.remove(path)
        local file = assert(io.open(path, "w"))
        file:write(JSON.encode({
            preset = "deepseek",
            base_url = "https://proxy.example.com/v1",
            api_key = "sk-config-9876",
            model = "deepseek-chat",
        }))
        file:close()

        local ai = {}
        local status, count = AIConfig.import_file(ai, path)
        assert.are.equal("imported", status)
        assert.are.equal(1, count)
        assert.are.equal(1, #ai.profiles)
        local item = ai.profiles[1]
        assert.are.equal("deepseek", item.preset)
        assert.are.equal("https://proxy.example.com/v1", item.base_url)
        assert.are.equal("deepseek-chat", item.model)
        assert.are.equal("••••9876", AIConfig.mask_key(item.api_key))
        assert.are.equal(item.id, ai.active_id)
        assert.are.equal("kidlearn_ai_config.json", ai.config_source)
        assert.is_nil(ai.config_error)

        status = AIConfig.import_file(ai, path)
        assert.are.equal("unchanged", status)
        os.remove(path)
    end)

    it("imports multiple services and keeps the selected active one", function()
        local path = DataStorage:getDataDir() .. "/kidlearn_ai_config_multi_spec.json"
        os.remove(path)
        local file = assert(io.open(path, "w"))
        file:write(JSON.encode({
            active_id = "second",
            profiles = {
                { id = "first", preset = "openai", api_key = "sk-first", model = "gpt-4o-mini" },
                { id = "second", preset = "qwen", api_key = "sk-second", model = "qwen-plus" },
            },
        }))
        file:close()

        local ai = {}
        local status, count = AIConfig.import_file(ai, path)
        assert.are.equal("imported", status)
        assert.are.equal(2, count)
        assert.are.equal("second", ai.active_id)
        assert.are.equal("qwen-plus", AIConfig.active_profile(ai).model)
        os.remove(path)
    end)

    it("keeps existing AI settings when the config file is invalid", function()
        local path = DataStorage:getDataDir() .. "/kidlearn_ai_config_bad_spec.json"
        os.remove(path)
        local file = assert(io.open(path, "w"))
        file:write("{ not json")
        file:close()

        local ai, item = profile("deepseek")
        local status, err, changed = AIConfig.import_file(ai, path)
        assert.is_nil(status)
        assert.is_truthy(err)
        assert.is_true(changed)
        assert.are.equal("test-key-1234", ai.profiles[1].api_key)
        assert.are.equal("test-key-1234", item.api_key)
        assert.is_truthy(ai.config_error)
        os.remove(path)
    end)

    it("loads the AI config file when progress opens", function()
        local progress_path = DataStorage:getDataDir() .. "/kidlearn_ai_config_progress_spec.lua"
        local config_path = DataStorage:getDataDir() .. "/kidlearn_ai_config_progress_spec.json"
        os.remove(progress_path)
        os.remove(progress_path .. ".old")
        os.remove(config_path)
        local file = assert(io.open(config_path, "w"))
        file:write(JSON.encode({
            preset = "kimi",
            api_key = "sk-progress-4321",
            model = "moonshot-v1-8k",
        }))
        file:close()

        local progress = Progress.open(progress_path, config_path)
        local active = AIConfig.active_profile(progress.data.settings.ai)
        assert.is_not_nil(active)
        assert.are.equal("kimi", active.preset)
        assert.are.equal("moonshot-v1-8k", active.model)
        assert.are.equal("••••4321", AIConfig.mask_key(active.api_key))
        os.remove(progress_path)
        os.remove(progress_path .. ".old")
        os.remove(config_path)
    end)

    it("builds OpenAI, Anthropic and Gemini requests", function()
        local _, openai = profile("deepseek")
        local req = assert(AIClient.build_request(openai, "system", "user"))
        assert.is_truthy(req.url:find("/chat/completions", 1, true))
        assert.are.equal("Bearer test-key-1234", req.headers.Authorization)
        local body = JSON.decode(req.body)
        assert.are.equal("deepseek-chat", body.model)
        assert.are.equal("system", body.messages[1].content)

        local _, claude = profile("claude")
        req = assert(AIClient.build_request(claude, "system", "user"))
        assert.is_truthy(req.url:find("/messages", 1, true))
        assert.are.equal("test-key-1234", req.headers["x-api-key"])
        body = JSON.decode(req.body)
        assert.is_true(body.max_tokens > 0)

        local _, gemini = profile("gemini")
        req = assert(AIClient.build_request(gemini, "system", "user"))
        assert.is_truthy(req.url:find(":generateContent", 1, true))
        assert.are.equal("test-key-1234", req.headers["x-goog-api-key"])
    end)

    it("parses provider responses and friendly HTTP errors", function()
        local _, openai = profile("deepseek")
        local text = assert(AIClient.parse_response(openai, 200, JSON.encode({
            choices = { { message = { content = "hello" } } },
        })))
        assert.are.equal("hello", text)

        local _, claude = profile("claude")
        text = assert(AIClient.parse_response(claude, 200, JSON.encode({
            content = { { type = "text", text = "claude" } },
        })))
        assert.are.equal("claude", text)

        local _, gemini = profile("gemini")
        text = assert(AIClient.parse_response(gemini, 200, JSON.encode({
            candidates = { { content = { parts = { { text = "gemini" } } } } },
        })))
        assert.are.equal("gemini", text)

        local result, err = AIClient.parse_response(openai, 401, JSON.encode({
            error = { message = "invalid key" },
        }))
        assert.is_nil(result)
        assert.is_truthy(err:find("API Key", 1, true))

        result, err = AIClient.parse_response(openai, nil, nil, "request timeout")
        assert.is_nil(result)
        assert.is_truthy(err:find("超时", 1, true))
    end)

    it("maps LuaSec socket wait timeouts to a friendly retry message", function()
        local _, item = profile("deepseek")
        -- LuaSec reports an expired socket wait as "wantread"/"wantwrite";
        -- slow batch generation used to surface that raw code to the user.
        for _, code in ipairs({ "wantread", "wantwrite" }) do
            local result, err = AIClient.parse_response(item, nil, nil, code)
            assert.is_nil(result)
            assert.is_truthy(err:find("超时", 1, true))
        end
    end)

    it("gives the blocking transport enough time for batch generation", function()
        local AIHTTP = require("core.ai_http")
        local socketutil = require("socketutil")
        local original = socketutil.set_timeout
        local captured
        socketutil.set_timeout = function(self, block, total)
            captured = { block, total }
            return original(self, block, total)
        end
        -- Loopback only: port 1 refuses immediately, no external network.
        local ok, status, body, err = pcall(AIHTTP.request, {
            url = "http://127.0.0.1:1/",
            headers = {},
            body = "{}",
        })
        socketutil.set_timeout = original
        assert.is_true(ok)
        assert.is_nil(status)
        assert.is_nil(body)
        assert.is_truthy(err)
        assert.is_not_nil(captured)
        -- The old 20s block timeout aborted slow batch answers with "wantread".
        assert.is_true(captured[1] >= 60)
        assert.is_true(captured[2] >= captured[1])
    end)

    it("falls back cleanly when no turbo looper is available", function()
        local AIHTTP = require("core.ai_http")
        local UIManager = require("ui/uimanager")
        -- Kindle defaults keep DUSE_TURBO_LIB off, so no looper exists.
        assert.is_nil(UIManager.looper)
        local scheduled = #UIManager._task_queue
        local calls, got_err = 0, nil
        AIHTTP.request({
            url = "http://127.0.0.1:1/",
            headers = {},
            body = "{}",
        }, function(_status, _body, err)
            calls = calls + 1
            got_err = err
        end)
        assert.are.equal(1, calls)
        assert.is_truthy(got_err)
        -- A failed async setup must not leave a stray watchdog behind.
        assert.are.equal(scheduled, #UIManager._task_queue)
    end)

    it("supports callback transports without blocking tests", function()
        local _, item = profile("deepseek")
        local captured
        AIClient.generate(item, "system", "user", {
            transport = function(_request, callback)
                callback(200, JSON.encode({ choices = { { message = { content = "ok" } } } }), nil)
            end,
            callback = function(text, err)
                captured = { text = text, err = err }
            end,
        })
        assert.are.equal("ok", captured.text)
        assert.is_nil(captured.err)
    end)

    it("generates with a synchronous transport", function()
        local _, item = profile("deepseek")
        local text, err = AIClient.generate(item, "system", "user", {
            transport = function(_request)
                return 200, JSON.encode({ choices = { { message = { content = "sync-ok" } } } }), nil
            end,
        })
        assert.are.equal("sync-ok", text)
        assert.is_nil(err)
    end)

    it("builds prompts and validates generated variants", function()
        local item = wrong_item("wrong-1")
        local system, user = AIVariant.build_prompt({ item }, 3)
        assert.is_truthy(system:find("只输出严格 JSON", 1, true))
        assert.is_truthy(user:find("共 3 道", 1, true))

        local payload = { questions = {
            variant(1, "变种一：9 + 8 = ？"),
            variant(1, "变种二：7 + 6 = ？"),
            variant(1, "变种三：6 + 5 = ？"),
        } }
        local questions = assert(AIVariant.parse("```json\n" .. JSON.encode(payload) .. "\n```", { item }, 3, {
            group_id = "aig-test-1", now = 1760000000,
        }))
        assert.are.equal(3, #questions)
        assert.is_true(questions[1].ai_generated)
        assert.are.equal("wrong-1", questions[1].origin_id)
        assert.are.equal("aig-test-1-q1", questions[1].id)
        assert.are.equal("choice", questions[1].answer_mode)
    end)

    it("rejects malformed, duplicated and incomplete variant sets", function()
        local item = wrong_item("wrong-1")
        local payload = { questions = {
            variant(1, "变种一：9 + 8 = ？"),
            variant(1, "变种二：7 + 6 = ？"),
            variant(1, "变种三：6 + 5 = ？"),
        } }
        payload.questions[2].options = { "1", "1", "3", "4" }
        local result, err = AIVariant.parse(JSON.encode(payload), { item }, 3, { group_id = "aig-test-2" })
        assert.is_nil(result)
        assert.is_truthy(err:find("选项", 1, true))

        payload.questions[2].options = { "1", "2", "3", "4" }
        table.remove(payload.questions)
        result, err = AIVariant.parse(JSON.encode(payload), { item }, 3, { group_id = "aig-test-3" })
        assert.is_nil(result)
        assert.is_truthy(err:find("数量", 1, true))
    end)

    it("maps batch variants to their origin questions and inherits passages", function()
        local first = wrong_item("wrong-1")
        local second = wrong_item("wrong-2", "chinese")
        second.passage = "小明在公园里看书。"
        second.stem = "短文写了什么？"
        local payload = { questions = {
            variant(1, "数学变种一"), variant(1, "数学变种二"),
            variant(2, "阅读变种一"), variant(2, "阅读变种二"),
        } }
        local questions = assert(AIVariant.parse(JSON.encode(payload), { first, second }, 2, {
            group_id = "aig-test-4", now = 1760000000,
        }))
        assert.are.equal(4, #questions)
        assert.are.equal("wrong-1", questions[1].origin_id)
        assert.are.equal("wrong-2", questions[3].origin_id)
        assert.are.equal("小明在公园里看书。", questions[3].passage)
    end)

    it("persists AI bank groups and removes them", function()
        local path = DataStorage:getDataDir() .. "/kidlearn_ai_bank_spec.json"
        os.remove(path)
        os.remove(path .. ".bad")
        os.remove(path .. ".tmp")
        local bank = AIBank.open(path)
        local group = { id = bank:next_group_id(1760000000), created_at = 1760000000,
            provider = { name = "DeepSeek" }, origins = { { id = "wrong-1", stem = "原题" } },
            questions = { { id = "q1" }, { id = "q2" } } }
        assert(bank:add_group(group))
        assert.are.equal(2, bank:count_questions())
        assert.are.equal(1, #bank:groups("wrong-1"))
        local reopened = AIBank.open(path)
        assert.are.equal(1, #reopened:groups())
        assert(reopened:remove_group(group.id))
        assert.are.equal(0, #reopened:groups())
        os.remove(path)
    end)

    it("recovers from a corrupt AI bank file", function()
        local path = DataStorage:getDataDir() .. "/kidlearn_ai_bank_bad_spec.json"
        os.remove(path)
        os.remove(path .. ".bad")
        local file = assert(io.open(path, "w"))
        file:write("not json")
        file:close()
        local bank = AIBank.open(path)
        assert.are.equal(0, #bank:groups())
        local backup = io.open(path .. ".bad", "r")
        assert.is_not_nil(backup)
        if backup then backup:close() end
        os.remove(path)
        os.remove(path .. ".bad")
    end)

    it("does not clear the original wrong question when a variant is correct", function()
        local path = DataStorage:getDataDir() .. "/kidlearn_ai_independent_spec.lua"
        os.remove(path)
        os.remove(path .. ".old")
        local progress = Progress.open(path)
        local origin = wrong_item("origin-1")
        progress:record_wrong(origin, 1760000000)
        local unit = "m2"
        local q = assert(Bank.normalize_question({
            id = "ai-correct", unit = unit, type = "math_choice", skill = "add_sub",
            difficulty = 2, answer_mode = "choice", stem = "9 + 8 = ?",
            options = { "15", "16", "17", "18" }, answer = 3, explain = "9 + 8 = 17。",
        }, "math", 4, "upper", "renjiao", { [unit] = true }, { [unit] = "AI 变种" }))
        q.ai_generated = true
        q.origin_id = "origin-1"
        local session = assert(Session.new({
            mode = "ai", ai_questions = { q }, progress = progress,
            plugin_path = "./plugins/kidlearn.koplugin",
        }))
        assert.is_true(session:submit(3).correct)
        assert.is_not_nil(progress.data.wrong["origin-1"])
        assert.is_nil(progress.data.wrong["ai-correct"])
        os.remove(path)
    end)

    it("runs an AI session and records wrong variants", function()
        local path = DataStorage:getDataDir() .. "/kidlearn_ai_session_spec.lua"
        os.remove(path)
        os.remove(path .. ".old")
        local progress = Progress.open(path)
        local unit = "m2"
        local q1 = assert(Bank.normalize_question({
            id = "ai-q1", unit = unit, type = "math_choice", skill = "add_sub",
            difficulty = 2, answer_mode = "choice", stem = "9 + 8 = ?",
            options = { "15", "16", "17", "18" }, answer = 3, explain = "9 + 8 = 17。",
        }, "math", 4, "upper", "renjiao", { [unit] = true }, { [unit] = "AI 变种" }))
        q1.ai_generated = true
        q1.origin_id = "wrong-1"
        q1.ai_group_id = "aig-test"
        local session = assert(Session.new({
            mode = "ai", ai_questions = { q1 }, progress = progress,
            plugin_path = "./plugins/kidlearn.koplugin",
        }))
        assert.are.equal(1, session:total())
        assert.is_false(session:submit(1).correct)
        assert.is_true(progress.data.wrong["ai-q1"].ai_generated)
        os.remove(path)
    end)
end)
