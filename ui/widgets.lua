--[[--
Small widget helpers shared by KidLearn screens.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LineWidget = require("ui/widget/linewidget")
local ProgressWidget = require("ui/widget/progresswidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = require("device").screen

local Widgets = {}

function Widgets.padding()
    return Size.padding.fullscreen
end

function Widgets.width()
    return Screen:getWidth() - 2 * Size.padding.fullscreen
end

function Widgets.label(text, opts)
    opts = opts or {}
    local face = Font:getFace(opts.face or "cfont", opts.size or 22)
    return TextWidget:new{
        text = text,
        face = face,
        bold = opts.bold,
        fgcolor = opts.color or Blitbuffer.COLOR_BLACK,
        max_width = opts.max_width,
    }
end

function Widgets.textbox(text, width, opts)
    opts = opts or {}
    return TextBoxWidget:new{
        text = text,
        width = width,
        face = Font:getFace(opts.face or "cfont", opts.size or 22),
        alignment = opts.alignment or "left",
        line_height = opts.line_height or 0.3,
        height = opts.height,
    }
end

function Widgets.button(text, opts)
    opts = opts or {}
    local height = opts.height or Size.item.height_large
    if height < Size.item.height_large then height = Size.item.height_large end
    return Button:new{
        text = text,
        width = opts.width,
        height = height,
        align = opts.align or "center",
        callback = opts.callback,
        enabled = opts.enabled ~= false,
        background = opts.background,
        bordersize = opts.bordersize or Size.border.button,
        radius = Size.radius.button,
        padding = opts.padding or Size.padding.default,
        text_font_face = "cfont",
        text_font_size = opts.size or 22,
        text_font_bold = opts.bold ~= false,
        avoid_text_truncation = true,
    }
end

function Widgets.choice_button(text, width, selected, callback)
    return Widgets.button((selected and "▶ " or "") .. text, {
        width = width,
        height = Screen:scaleBySize(64),
        align = "left",
        size = 22,
        background = selected and Blitbuffer.COLOR_LIGHT_GRAY or nil,
        callback = callback,
    })
end

function Widgets.card(child, opts)
    opts = opts or {}
    local padding = opts.padding or Size.padding.default
    local bordersize = opts.bordersize or Size.border.thin
    local content = child
    if opts.width then
        local inner_width = opts.width - 2 * padding - 2 * bordersize
        if inner_width > 0 then
            content = CenterContainer:new{
                dimen = Geom:new{ w = inner_width, h = child:getSize().h },
                child,
            }
        end
    end
    return FrameContainer:new{
        width = opts.width,
        padding = padding,
        bordersize = bordersize,
        radius = Size.radius.window,
        background = opts.background,
        content,
    }
end

function Widgets.stat(value, caption, width)
    local group = VerticalGroup:new{
        align = "center",
        Widgets.label(value, { size = 24, bold = true }),
        Widgets.label(caption, { size = 16, color = Blitbuffer.COLOR_DARK_GRAY }),
    }
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = group:getSize().h },
        group,
    }
end

function Widgets.progress(percentage, width, height)
    return ProgressWidget:new{
        width = width,
        height = height or Screen:scaleBySize(12),
        percentage = math.max(0, math.min(1, percentage or 0)),
        margin_v = Screen:scaleBySize(1),
        margin_h = Screen:scaleBySize(2),
    }
end

function Widgets.hline(width)
    return LineWidget:new{
        dimen = Geom:new{ w = width, h = Screen:scaleBySize(1) },
        background = Blitbuffer.COLOR_GRAY,
    }
end

function Widgets.vspace(height)
    return VerticalSpan:new{ width = height }
end

function Widgets.hspace(width)
    return HorizontalSpan:new{ width = width }
end

function Widgets.center(widget, width, height)
    return CenterContainer:new{
        dimen = Geom:new{ w = width or Screen:getWidth(), h = height or widget:getSize().h },
        widget,
    }
end

return Widgets
