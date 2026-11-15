local addonName, ns = ...

-- Reusable alert icon: a square icon with a short text in its centre, shown
-- while something needs the player's attention (a missing buff...). While
-- shown it sways gently from side to side, in short bursts.
--
-- Appearance is driven by a settings table (see ns.AlertIconDefaults), usually
-- a sub-table of SavedVariables. The icon keeps a reference to it: change a
-- value, then call icon:ApplySettings() to see it live.
--
-- An icon is either standalone (it carries its own saved position, see
-- Widgets/Movable.lua) or a member of an icon group (Widgets/IconGroup.lua),
-- which then places it and is what gets moved.

local BORDER = 1          -- black frame around the icon
local ICON_CROP = 0.07    -- hides the built-in border of Blizzard icons
local TEXT_RATIO = 0.3    -- font size, as a fraction of the icon size
local MIN_FONT_SIZE = 8

-- One burst of the shake: horizontal moves as multiples of the amplitude,
-- played one after the other (they add up, and sum to zero so that the icon
-- ends where it started), then a pause before the next burst.
local SHAKE_STEPS = { -1, 2, -2, 2, -1 }
local SHAKE_STEP_DURATION = 0.08
local SHAKE_PAUSE = 1.6
local SHAKE_RATIO = 0.07  -- amplitude, as a fraction of the icon size

ns.AlertIconDefaults = {
    size = 48,
    alpha = 1,
    shake = true,
}

-- Option descriptors for the config window (see Config/Controls.lua)
ns.AlertIconOptions = {
    { type = "header", label = "Apparence" },
    { type = "slider", key = "size", label = "Taille", min = 16, max = 128, step = 2 },
    { type = "slider", key = "alpha", label = "Opacité (%)", min = 0.1, max = 1, step = 0.05, percent = true },
    { type = "toggle", key = "shake", label = "Secouer l'icône" },
}

local AlertIcon = {}
AlertIcon.__index = AlertIcon

-- Position, dragging and move highlight: see Widgets/Movable.lua
for name, method in pairs(ns.Movable) do
    AlertIcon[name] = method
end

-- `group` is optional: an icon group (see Widgets/IconGroup.lua) that places
-- the icon next to its other members.
function ns.CreateAlertIcon(settings, group)
    local self = setmetatable({ settings = settings, group = group }, AlertIcon)

    -- The anchor carries position, size, opacity and dragging, and is always
    -- shown (it draws nothing by itself).
    local anchor = CreateFrame("Frame", nil, group and group.anchor or UIParent)
    if not group then
        anchor:SetClampedToScreen(true)
        anchor:SetPoint("CENTER")
    end
    self.anchor = anchor

    -- The content frame is what is shown, hidden and shaken, so that the
    -- anchor stays still while it is dragged.
    local frame = CreateFrame("Frame", nil, anchor)
    frame:SetAllPoints()
    frame:Hide()
    self.frame = frame

    local border = frame:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0, 0, 0, 1)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", BORDER, -BORDER)
    icon:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    self.icon = icon

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    text:SetPoint("CENTER")
    self.text = text
    self.fontFile = text:GetFont()

    if frame.CreateAnimationGroup then
        local shake = frame:CreateAnimationGroup()
        shake:SetLooping("REPEAT")
        self.shakeSteps = {}
        for order, factor in ipairs(SHAKE_STEPS) do
            local step = shake:CreateAnimation("Translation")
            step:SetOrder(order)
            step:SetDuration(SHAKE_STEP_DURATION)
            if step.SetSmoothing then step:SetSmoothing("IN_OUT") end -- eases each swing
            step.factor = factor
            self.shakeSteps[order] = step
        end
        local last = self.shakeSteps[#SHAKE_STEPS]
        if last.SetEndDelay then last:SetEndDelay(SHAKE_PAUSE) end
        self.shakeGroup = shake
    end

    -- Created last, so that it is drawn in front of everything else
    self.moveHighlight = ns.CreateMoveHighlight(anchor)

    self:ApplySettings()
    if group then group:Add(self) end
    return self
end

-- Re-reads every value of the settings table. Safe to call at any time.
function AlertIcon:ApplySettings()
    local s = self.settings

    self.anchor:SetSize(s.size, s.size)
    self.anchor:SetAlpha(s.alpha)

    if self.fontFile then
        self.text:SetFont(self.fontFile, math.max(MIN_FONT_SIZE, s.size * TEXT_RATIO), "OUTLINE")
    end

    if self.shakeSteps then
        local amplitude = s.size * SHAKE_RATIO
        for _, step in ipairs(self.shakeSteps) do
            step:SetOffset(step.factor * amplitude, 0)
        end
    end
    self:UpdateShake()
    self:NotifyGroup()
end

-- A change of size or visibility moves the other members of the group.
function AlertIcon:NotifyGroup()
    if self.group then self.group:Layout() end
end

function AlertIcon:GetSize()
    return self.settings.size
end

-- The shake runs only while the icon is shown. It is restarted after a change
-- of settings, so that the new amplitude applies at once.
function AlertIcon:UpdateShake()
    local shake = self.shakeGroup
    if not shake then return end
    shake:Stop()
    if self.frame:IsShown() and self.settings.shake then
        shake:Play()
    end
end

function AlertIcon:SetIcon(texture)
    self.icon:SetTexture(texture)
end

function AlertIcon:SetText(text)
    self.text:SetText(text)
end

function AlertIcon:IsShown()
    return self.frame:IsShown()
end

function AlertIcon:SetShown(shown)
    shown = shown and true or false
    if shown == self.frame:IsShown() then return end -- keep the shake running
    self.frame:SetShown(shown)
    self:UpdateShake()
    self:NotifyGroup()
end
