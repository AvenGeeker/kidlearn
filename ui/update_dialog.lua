--[[--
Download progress dialog for the online updater.

Shows a real byte-progress bar, a size/percentage line and a big cancel
button. The download itself runs in short non-blocking ticks
(core/update_http.lua) with NO timeout, so this dialog stays responsive:
the user decides when to cancel, however slow the network is.

This is a transient modal dialog (like ConfirmBox), not a MainView page:
the full-screen InputContainer swallows outside taps so they cannot hit
the page below; only the cancel button or the Back key cancels.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Widgets = require("ui/widgets")
local time = require("ui/time")

local Screen = Device.screen

local UpdateDialog = InputContainer:extend{
    align = "center",
    vertical_align = "center",
}

-- E-ink friendly repaint throttle: at most ~1.4 partial refreshes/second,
-- plus forced repaints on phase changes (100% / installing).
local REPAINT_INTERVAL_US = 700000

local function format_bytes(n)
    if n >= 1024 * 1024 then
        return string.format("%.1f MB", n / (1024 * 1024))
    elseif n >= 1024 then
        return string.format("%.0f KB", n / 1024)
    end
    return string.format("%d B", n)
end

function UpdateDialog:init()
    self.dimen = Screen:getSize()
    self._received = 0
    self._total = self.total or 0
    self._installing = false
    self._closed = false
    self._last_paint_us = 0

    local width = math.min(Screen:getWidth() - 2 * Size.padding.fullscreen, Screen:scaleBySize(460))
    local inner = width - 2 * Size.padding.large

    self.title_label = Widgets.label("正在下载更新", { size = 24, bold = true })
    self.bar = Widgets.progress(0, inner, Screen:scaleBySize(16))
    -- Reserve a fixed slot for the dynamic status line so changing text never
    -- shifts the layout (CenterContainer re-centers its child on every paint).
    self.status_label = Widgets.label(self:_status_text(), {
        size = 18,
        color = Blitbuffer.COLOR_DARK_GRAY,
    })
    local status_slot = CenterContainer:new{
        dimen = Geom:new{ w = inner, h = self.status_label:getSize().h },
        self.status_label,
    }
    self.cancel_button = Widgets.button("取消下载", {
        width = inner,
        callback = function() self:_cancel() end,
    })

    local group = VerticalGroup:new{
        align = "center",
        self.title_label,
        Widgets.vspace(Screen:scaleBySize(12)),
        self.bar,
        Widgets.vspace(Screen:scaleBySize(8)),
        status_slot,
        Widgets.vspace(Screen:scaleBySize(14)),
        self.cancel_button,
    }
    local frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = Size.padding.large,
        group,
    }
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        frame,
    }

    -- Refresh only the dialog region, not the whole screen.
    local fs = frame:getSize()
    self._region = Geom:new{
        x = math.floor((Screen:getWidth() - fs.w) / 2),
        y = math.floor((Screen:getHeight() - fs.h) / 2),
        w = fs.w,
        h = fs.h,
    }

    if Device:isTouchDevice() then
        self.ges_events.TapOutside = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                },
            },
        }
    end
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
end

function UpdateDialog:_status_text()
    if self._total > 0 then
        local pct = math.floor(math.min(1, self._received / self._total) * 100)
        return string.format("%s / %s（%d%%）",
            format_bytes(self._received), format_bytes(self._total), pct)
    end
    return string.format("已下载 %s", format_bytes(self._received))
end

function UpdateDialog:_paint(force)
    local now = time.now()
    if not force and now - self._last_paint_us < REPAINT_INTERVAL_US then return end
    self._last_paint_us = now
    UIManager:setDirty(self, function() return "ui", self._region end)
end

--- Called by the download engine with byte counts; total may be 0 (unknown).
function UpdateDialog:update_progress(received, total)
    if self._closed or self._installing then return end
    self._received = received or 0
    if total and total > 0 then self._total = total end
    local pct = self._total > 0 and math.min(1, self._received / self._total) or 0
    self.bar:setPercentage(pct)
    self.status_label:setText(self:_status_text())
    self:_paint(pct >= 1)
end

--- Download finished; the (fast, local) install phase is running now.
function UpdateDialog:set_installing()
    if self._closed or self._installing then return end
    self._installing = true
    self.cancel_callback = nil
    self.cancel_button:disable()
    self.bar:setPercentage(1)
    self.title_label:setText("正在安装更新")
    self.status_label:setText("下载完成，正在替换插件程序…")
    self:_paint(true)
end

function UpdateDialog:_cancel()
    local cb = self.cancel_callback
    self.cancel_callback = nil
    if cb then cb() end
end

--- Close without cancelling (used by the completion callback).
function UpdateDialog:dismiss()
    self.cancel_callback = nil
    self:close()
end

function UpdateDialog:show()
    UIManager:show(self)
end

function UpdateDialog:close()
    if self._closed then return end
    self._closed = true
    UIManager:close(self)
end

function UpdateDialog:onTapOutside()
    -- Swallow outside taps; only the cancel button cancels.
    return true
end

function UpdateDialog:onClose()
    self:_cancel()
    return true
end

function UpdateDialog:onCloseWidget()
    -- Closed by any other means (e.g. the system): stop the download too.
    self._closed = true
    self:_cancel()
end

return UpdateDialog
