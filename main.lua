--[[--
KidLearn: a small grades 1-6 Chinese and math practice app for KOReader.

@module koplugin.kidlearn
--]]--

local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local MainView = require("ui/mainview")
local _ = require("gettext")

local KidLearn = WidgetContainer:extend{
    name = "kidlearn",
    is_doc_only = false,
}

local autostarted = false

function KidLearn:init()
    math.randomseed(os.time() + math.floor((os.clock() or 0) * 1000))
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    if not autostarted and os.getenv("KIDLEARN_AUTOSTART") == "1" then
        autostarted = true
        UIManager:scheduleIn(1, function() self:showMainView() end)
    end
end

function KidLearn:onDispatcherRegisterActions()
    Dispatcher:registerAction("kidlearn_open", {
        category = "none",
        event = "KidLearnOpen",
        title = _("打开小小学习家"),
        general = true,
    })
end

function KidLearn:addToMainMenu(menu_items)
    menu_items.kidlearn = {
        text = _("小小学习家"),
        sorting_hint = "more_tools",
        callback = function()
            self:showMainView()
        end,
    }
end

function KidLearn:showMainView()
    UIManager:show(MainView:new{
        plugin = self,
        plugin_path = self.path,
    })
end

function KidLearn:onKidLearnOpen()
    self:showMainView()
    return true
end

return KidLearn
