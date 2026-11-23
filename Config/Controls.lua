local addonName, ns = ...

-- Control factories for the config page, one per option type.
--
-- A tracker or a display zone (the "owner" of the options) declares a list of
-- option descriptors:
--   { type = "header",   label }
--   { type = "toggle",   key, label }
--   { type = "slider",   key, label, min, max, step, percent }
--   { type = "select",   key, label, values = { { value, text }, ... } }
--   { type = "color",    key, label }             value is a { r, g, b } table
--   { type = "position", label }                  uses owner:GetPosition/SetPosition
--   { type = "button",   label, func(owner) }
-- Common optional fields:
--   half      take half a row instead of a full one
--   disabled  function(settings) returning true to grey the control out
--
-- Each factory is called as factory(parent, option, ctx, width) and returns a
-- frame with a :Refresh() method. `ctx` gives access to the values:
--   ctx.owner, ctx.settings, ctx.get(key), ctx.set(key, value)
--
-- Everything is built from raw widgets and a few long-standing templates
-- (UIPanelButtonTemplate, InputBoxTemplate): no UIDropDownMenu, which is a
-- classic source of taint.

local ROW_HEIGHT = 28
local HEADER_HEIGHT = 30

local Controls = {}
ns.Controls = Controls
Controls.ROW_HEIGHT = ROW_HEIGHT

local function Round(value)
    return math.floor(value + 0.5)
end

local function SetWidgetEnabled(widget, enabled)
    if widget.SetEnabled then
        widget:SetEnabled(enabled)
    elseif enabled then
        widget:Enable()
    else
        widget:Disable()
    end
end

local function IsDisabled(opt, ctx)
    return opt.disabled ~= nil and opt.disabled(ctx.settings) == true
end

local function CreateRow(parent, width, height)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, height or ROW_HEIGHT)
    return row
end

local function CreateLabel(row, text)
    local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", 2, 0)
    label:SetJustifyH("LEFT")
    label:SetText(text or "")
    return label
end

local function CreateNumberBox(row, width)
    local edit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    edit:SetSize(width, 20)
    edit:SetAutoFocus(false)
    edit:SetJustifyH("CENTER")
    edit:SetMaxLetters(6)
    return edit
end

-- Reads a number typed by the user ("12", "-3", "1,5"), or nil.
local function ParseNumber(text)
    return tonumber((strtrim(text or ""):gsub(",", ".")))
end

----------------------------------------------------------------------
-- header
----------------------------------------------------------------------

function Controls.header(parent, opt, ctx, width)
    local row = CreateRow(parent, width, HEADER_HEIGHT)

    local text = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("BOTTOMLEFT", 0, 7)
    text:SetText(opt.label or "")

    local line = row:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 0, 3)
    line:SetPoint("BOTTOMRIGHT", 0, 3)
    line:SetColorTexture(1, 0.82, 0, 0.35)

    function row:Refresh() end
    return row
end

----------------------------------------------------------------------
-- toggle
----------------------------------------------------------------------

function Controls.toggle(parent, opt, ctx, width)
    local row = CreateRow(parent, width)

    local check = CreateFrame("CheckButton", nil, row)
    check:SetSize(24, 24)
    check:SetPoint("LEFT", -2, 0)
    check:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    check:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    check:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    check:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")

    local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    label:SetText(opt.label or "")
    -- Clicking the label toggles the box too
    check:SetHitRectInsets(0, -(label:GetStringWidth() + 4), 0, 0)

    check:SetScript("OnClick", function(self)
        ctx.set(opt.key, self:GetChecked() and true or false)
    end)

    function row:Refresh()
        check:SetChecked(ctx.get(opt.key) and true or false)
        local disabled = IsDisabled(opt, ctx)
        SetWidgetEnabled(check, not disabled)
        row:SetAlpha(disabled and 0.4 or 1)
    end
    return row
end

----------------------------------------------------------------------
-- slider (with a number box for exact values)
----------------------------------------------------------------------

function Controls.slider(parent, opt, ctx, width)
    local row = CreateRow(parent, width)
    CreateLabel(row, opt.label)

    local factor = opt.percent and 100 or 1 -- stored value -> displayed value
    local updating = false

    local edit = CreateNumberBox(row, 44)
    edit:SetPoint("RIGHT", -2, 0)

    local slider = CreateFrame("Slider", nil, row)
    slider:SetOrientation("HORIZONTAL")
    slider:SetHeight(16)
    slider:SetPoint("LEFT", 140, 0)
    slider:SetPoint("RIGHT", edit, "LEFT", -14, 0)
    slider:EnableMouse(true)
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:SetMinMaxValues(opt.min, opt.max)
    slider:SetValueStep(opt.step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetHeight(6)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetColorTexture(0, 0, 0, 0.6)

    local function Snap(value)
        value = math.max(opt.min, math.min(opt.max, value))
        return opt.min + Round((value - opt.min) / opt.step) * opt.step
    end

    local function ShowValue(value)
        edit:SetText(tostring(Round(value * factor)))
        edit:SetCursorPosition(0)
    end

    slider:SetScript("OnValueChanged", function(self, value)
        if updating then return end
        value = Snap(value)
        if value ~= ctx.get(opt.key) then
            ctx.set(opt.key, value)
        end
    end)

    edit:SetScript("OnEnterPressed", function(self)
        local value = ParseNumber(self:GetText())
        self:ClearFocus()
        if value then
            ctx.set(opt.key, Snap(value / factor))
        else
            row:Refresh()
        end
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        row:Refresh()
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        row:Refresh()
    end)

    function row:Refresh()
        local value = ctx.get(opt.key)
        updating = true
        slider:SetValue(value)
        updating = false
        if not edit:HasFocus() then ShowValue(value) end

        local disabled = IsDisabled(opt, ctx)
        SetWidgetEnabled(slider, not disabled)
        SetWidgetEnabled(edit, not disabled)
        row:SetAlpha(disabled and 0.4 or 1)
    end
    return row
end

----------------------------------------------------------------------
-- select (home-made dropdown: one shared popup list)
----------------------------------------------------------------------

local popup

function Controls.ClosePopup()
    if popup then popup:Hide() end
end

local function GetPopup()
    if popup then return popup end

    popup = CreateFrame("Frame", nil, UIParent)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:Hide()
    popup.items = {}

    local border = popup:CreateTexture(nil, "BACKGROUND", nil, -1)
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.5, 0.5, 0.5, 1)
    local bg = popup:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.06, 0.06, 1)

    popup:SetScript("OnHide", function(self) self.owner = nil end)
    return popup
end

local function GetPopupItem(index)
    local item = popup.items[index]
    if item then return item end

    item = CreateFrame("Button", nil, popup)
    item:SetHeight(20)
    item:SetPoint("TOPLEFT", 2, -2 - (index - 1) * 20)
    item:SetPoint("RIGHT", -2, 0)

    local highlight = item:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.15)

    item.text = item:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    item.text:SetPoint("LEFT", 6, 0)

    item:SetScript("OnClick", function(self)
        local onSelect = self.onSelect
        popup:Hide()
        onSelect(self.value)
    end)

    popup.items[index] = item
    return item
end

local function TogglePopup(owner, values, current, onSelect)
    GetPopup()
    if popup:IsShown() and popup.owner == owner then
        popup:Hide()
        return
    end

    for index, entry in ipairs(values) do
        local item = GetPopupItem(index)
        item.value, item.onSelect = entry[1], onSelect
        item.text:SetText(entry[2])
        if entry[1] == current then
            item.text:SetTextColor(1, 0.82, 0)
        else
            item.text:SetTextColor(1, 1, 1)
        end
        item:Show()
    end
    for index = #values + 1, #popup.items do
        popup.items[index]:Hide()
    end

    popup:SetSize(owner:GetWidth(), #values * 20 + 4)
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -1)
    popup:Show()
    popup.owner = owner -- after Show: OnHide clears it
end

function Controls.select(parent, opt, ctx, width)
    local row = CreateRow(parent, width)
    CreateLabel(row, opt.label)

    local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    button:SetSize(112, 22)
    button:SetPoint("RIGHT", -8, 0)

    local function TextFor(value)
        for _, entry in ipairs(opt.values) do
            if entry[1] == value then return entry[2] end
        end
        return "?"
    end

    button:SetScript("OnClick", function(self)
        TogglePopup(self, opt.values, ctx.get(opt.key), function(value)
            ctx.set(opt.key, value)
        end)
    end)

    function row:Refresh()
        button:SetText(TextFor(ctx.get(opt.key)))
        local disabled = IsDisabled(opt, ctx)
        SetWidgetEnabled(button, not disabled)
        row:SetAlpha(disabled and 0.4 or 1)
    end
    return row
end

----------------------------------------------------------------------
-- color (Blizzard colour picker)
----------------------------------------------------------------------

-- Calls callback(r, g, b) on every change, and with the initial colour on cancel.
local function OpenColorPicker(r, g, b, callback)
    local function OnChange()
        callback(ColorPickerFrame:GetColorRGB())
    end
    local function OnCancel()
        callback(r, g, b)
    end

    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b,
            hasOpacity = false,
            swatchFunc = OnChange,
            cancelFunc = OnCancel,
        })
    else
        ColorPickerFrame:Hide() -- make sure OnShow runs again
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.previousValues = { r, g, b }
        ColorPickerFrame.func = OnChange
        ColorPickerFrame.cancelFunc = OnCancel
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Show()
    end
end

function Controls.color(parent, opt, ctx, width)
    local row = CreateRow(parent, width)

    local button = CreateFrame("Button", nil, row)
    button:SetSize(20, 20)
    button:SetPoint("LEFT", 0, 0)

    local border = button:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.7, 0.7, 0.7, 1)
    local swatch = button:CreateTexture(nil, "ARTWORK")
    swatch:SetPoint("TOPLEFT", 1, -1)
    swatch:SetPoint("BOTTOMRIGHT", -1, 1)

    local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", button, "RIGHT", 6, 0)
    label:SetText(opt.label or "")
    button:SetHitRectInsets(0, -(label:GetStringWidth() + 8), 0, 0)

    button:SetScript("OnClick", function()
        local color = ctx.get(opt.key)
        OpenColorPicker(color.r, color.g, color.b, function(r, g, b)
            -- Mutate in place: the owner keeps a reference to this table
            color.r, color.g, color.b = r, g, b
            ctx.set(opt.key, color)
        end)
    end)

    function row:Refresh()
        local color = ctx.get(opt.key)
        swatch:SetColorTexture(color.r, color.g, color.b, 1)
        local disabled = IsDisabled(opt, ctx)
        SetWidgetEnabled(button, not disabled)
        row:SetAlpha(disabled and 0.4 or 1)
    end
    return row
end

----------------------------------------------------------------------
-- position (exact X/Y, complements drag and drop)
----------------------------------------------------------------------

local POSITION_LIMIT = 5000

function Controls.position(parent, opt, ctx, width)
    local row = CreateRow(parent, width)
    local owner = ctx.owner
    local boxes = {}

    local function Commit()
        local x, y = owner:GetPosition()
        x = ParseNumber(boxes[1]:GetText()) or x
        y = ParseNumber(boxes[2]:GetText()) or y
        x = math.max(-POSITION_LIMIT, math.min(POSITION_LIMIT, Round(x)))
        y = math.max(-POSITION_LIMIT, math.min(POSITION_LIMIT, Round(y)))
        owner:SetPosition(x, y)
        row:Refresh()
    end

    local function CreateAxis(index, text, left)
        local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("LEFT", left, 0)
        label:SetText(text)

        local edit = CreateNumberBox(row, 56)
        edit:SetPoint("LEFT", label, "RIGHT", 12, 0)
        edit:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            Commit()
        end)
        edit:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            row:Refresh()
        end)
        edit:SetScript("OnEditFocusLost", function(self)
            self:HighlightText(0, 0)
        end)
        -- Tab jumps from X to Y and back
        edit:SetScript("OnTabPressed", function()
            boxes[index == 1 and 2 or 1]:SetFocus()
        end)
        boxes[index] = edit
    end

    CreateAxis(1, "X", 2)
    CreateAxis(2, "Y", width / 2 + 2)

    function row:Refresh()
        local x, y = owner:GetPosition()
        if not boxes[1]:HasFocus() then boxes[1]:SetText(tostring(Round(x))) end
        if not boxes[2]:HasFocus() then boxes[2]:SetText(tostring(Round(y))) end
    end
    return row
end

----------------------------------------------------------------------
-- button
----------------------------------------------------------------------

function Controls.button(parent, opt, ctx, width)
    local row = CreateRow(parent, width)

    local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    button:SetHeight(22)
    button:SetPoint("LEFT", 0, 0)
    button:SetText(opt.label or "")
    button:SetWidth(button:GetTextWidth() + 28)
    button:SetScript("OnClick", function()
        opt.func(ctx.owner)
        ctx.refresh()
    end)

    function row:Refresh()
        SetWidgetEnabled(button, not IsDisabled(opt, ctx))
    end
    return row
end
