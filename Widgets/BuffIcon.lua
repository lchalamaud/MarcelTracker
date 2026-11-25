local addonName, ns = ...

-- Buff icon: the icon of a buff the player has, with the time left on it in
-- its centre. As time passes the icon is erased by a circular sweep, like
-- the hand of a clock: only the share matching the time left remains. What
-- is erased can stay visible as a faint "ghost".
--
-- The sweep is a Cooldown frame whose swipe texture is the buff icon itself:
-- the swipe covers the share of the time left, drawn by the engine. Below it,
-- the icon is only drawn at the ghost opacity.
--
-- Appearance is driven by a settings table (see ns.BuffIconDefaults), shared
-- by all the icons of a display zone (Zones/Zone.lua). The icon is always a
-- member of an icon group (Widgets/IconGroup.lua), which places it.

local OUTLINE = 1          -- black frame around the icon, when it has no border
local ICON_CROP = 0.07     -- hides the built-in border of Blizzard icons
local TEXT_RATIO = 0.4     -- font size, as a fraction of the icon size
local MIN_FONT_SIZE = 8
local TEXT_UPDATE_INTERVAL = 0.1
local DECIMALS_BELOW = 3   -- seconds left under which a decimal is shown
local LOW_TIME_COLOR = { 1, 0.7, 0.1 }
local QUESTION_MARK = 134400

ns.BuffIconDefaults = {
    size = 40,
    alpha = 1,
    border = true,
    sweep = true,
    ghostAlpha = 0.15,
    showTime = true,
}

-- Option descriptors for the config window (see Config/Controls.lua)
ns.BuffIconOptions = {
    { type = "header", label = "Apparence" },
    { type = "slider", key = "size", label = "Taille", min = 16, max = 160, step = 2 },
    { type = "slider", key = "alpha", label = "Opacité (%)", min = 0.1, max = 1, step = 0.05, percent = true },
    { type = "toggle", key = "sweep", label = "Balayage circulaire", half = true },
    { type = "toggle", key = "border", label = "Bordure", half = true },
    { type = "slider", key = "ghostAlpha", label = "Partie écoulée (%)", min = 0, max = 1, step = 0.05, percent = true,
        disabled = function(settings) return not settings.sweep end },
    { type = "toggle", key = "showTime", label = "Temps restant" },
}

local function FormatRemaining(remaining)
    if remaining < DECIMALS_BELOW then
        return string.format("%.1f", math.max(0, remaining))
    end
    return tostring(math.ceil(remaining))
end

local BuffIcon = {}
BuffIcon.__index = BuffIcon

-- Runs while the icon is shown with a timer.
local function OnUpdate(frame, elapsed)
    local self = frame.owner
    local remaining = self.expiresAt - GetTime()
    if remaining <= 0 then
        self:Stop()
        if self.onExpire then self.onExpire() end
        return
    end

    self.textElapsed = self.textElapsed + elapsed
    if self.textElapsed >= TEXT_UPDATE_INTERVAL then
        self.textElapsed = 0
        self:UpdateText(remaining)
    end
end

function ns.CreateBuffIcon(settings, group)
    local self = setmetatable({ settings = settings, group = group }, BuffIcon)

    -- The anchor is placed by the group and is always shown (it draws
    -- nothing by itself); the content frame is what is shown and hidden.
    local anchor = CreateFrame("Frame", nil, group.anchor)
    self.anchor = anchor

    local frame = CreateFrame("Frame", nil, anchor)
    frame:SetAllPoints()
    frame:Hide()
    frame.owner = self
    self.frame = frame

    local outline = frame:CreateTexture(nil, "BACKGROUND")
    outline:SetAllPoints()
    outline:SetColorTexture(0, 0, 0, 1)
    self.outline = outline

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    self.icon = icon

    -- The sweep, if the client's cooldown frames can draw a texture
    local cooldown = CreateFrame("Cooldown", nil, frame)
    if cooldown.SetSwipeTexture then
        cooldown:SetAllPoints(icon)
        cooldown:SetSwipeColor(1, 1, 1, 1)
        if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
        if cooldown.SetDrawBling then cooldown:SetDrawBling(false) end
        if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(true) end
        if cooldown.SetReverse then cooldown:SetReverse(false) end
        if cooldown.SetTexCoordRange and CreateVector2D then
            cooldown:SetTexCoordRange(CreateVector2D(ICON_CROP, ICON_CROP), CreateVector2D(1 - ICON_CROP, 1 - ICON_CROP))
        end
        self.cooldown = cooldown
    else
        cooldown:Hide()
    end

    -- In front of the sweep
    self.border = ns.CreateBorder(frame, 2)

    local textHolder = CreateFrame("Frame", nil, frame)
    textHolder:SetAllPoints()
    textHolder:SetFrameLevel(frame:GetFrameLevel() + 3)
    local text = textHolder:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    text:SetPoint("CENTER")
    self.text = text
    self.fontFile = text:GetFont()

    -- Created last, so that it is drawn in front of everything else
    self.moveHighlight = ns.CreateMoveHighlight(anchor)

    self:ApplySettings()
    group:Add(self)
    return self
end

-- Re-reads every value of the settings table. Safe to call at any time.
function BuffIcon:ApplySettings()
    local s = self.settings

    self.anchor:SetSize(s.size, s.size)
    self.anchor:SetAlpha(s.alpha)

    -- The border replaces the black outline, which would show in its notched
    -- corners. The icon goes 1px under the band, to leave no gap.
    local inset = OUTLINE
    if s.border then inset = self.border:Apply(s.size) - 1 end
    self.border:SetShown(s.border)
    self.outline:SetShown(not s.border)
    self.icon:ClearAllPoints()
    self.icon:SetPoint("TOPLEFT", inset, -inset)
    self.icon:SetPoint("BOTTOMRIGHT", -inset, inset)

    if self.fontFile then
        self.text:SetFont(self.fontFile, math.max(MIN_FONT_SIZE, s.size * TEXT_RATIO), "OUTLINE")
    end
    self.text:SetShown(s.showTime)

    self:UpdateSweep()
    if self.group then self.group:Layout() end
end

-- Whether the sweep is drawn: wanted, possible, and with a timer to follow.
function BuffIcon:IsSweeping()
    return self.settings.sweep and self.cooldown ~= nil and self.expiresAt ~= nil
end

function BuffIcon:UpdateSweep()
    local sweeping = self:IsSweeping()
    self.icon:SetAlpha(sweeping and self.settings.ghostAlpha or 1)
    if not self.cooldown then return end
    if sweeping then
        self.cooldown:SetCooldown(self.expiresAt - self.duration, self.duration)
        self.cooldown:Show()
    else
        self.cooldown:SetCooldown(0, 0)
        self.cooldown:Hide()
    end
end

function BuffIcon:UpdateText(remaining)
    if remaining < DECIMALS_BELOW then
        self.text:SetTextColor(unpack(LOW_TIME_COLOR))
    else
        self.text:SetTextColor(1, 1, 1)
    end
    self.text:SetText(FormatRemaining(remaining))
end

function BuffIcon:GetSize()
    return self.settings.size
end

function BuffIcon:IsShown()
    return self.frame:IsShown()
end

-- Shows the icon. With a duration, the timer runs until `expiresAt` (a
-- GetTime() value), then the icon hides itself and calls `onExpire`.
-- Without one, the icon stays as it is, with no time and no sweep.
-- Calling it again with the same values changes nothing.
function BuffIcon:Start(texture, duration, expiresAt)
    texture = texture or QUESTION_MARK
    if not (duration and duration > 0 and expiresAt) then
        duration, expiresAt = nil, nil
    end
    if self.frame:IsShown() and texture == self.texture
        and duration == self.duration and expiresAt == self.expiresAt then
        return
    end

    self.texture, self.duration, self.expiresAt = texture, duration, expiresAt
    self.icon:SetTexture(texture)
    if self.cooldown then self.cooldown:SetSwipeTexture(texture) end

    local wasShown = self.frame:IsShown()
    self.frame:Show()
    self:UpdateSweep() -- once shown, so that the cooldown is drawn

    if expiresAt then
        self.textElapsed = 0
        self:UpdateText(expiresAt - GetTime())
        self.frame:SetScript("OnUpdate", OnUpdate)
    else
        self.text:SetText("")
        self.frame:SetScript("OnUpdate", nil)
    end
    if not wasShown and self.group then self.group:Layout() end
end

function BuffIcon:Stop()
    self.duration, self.expiresAt = nil, nil
    self.frame:SetScript("OnUpdate", nil)
    if self.cooldown then
        self.cooldown:SetCooldown(0, 0)
        self.cooldown:Hide()
    end
    if not self.frame:IsShown() then return end
    self.frame:Hide()
    if self.group then self.group:Layout() end
end
