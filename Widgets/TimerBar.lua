local addonName, ns = ...

-- Reusable timer bar: [icon][ label (center) ... time (right) ], draining left.
--
-- Readable values (duration/expirationTime): the bar is animated in OnUpdate
-- and hides itself (or calls onExpire) when the timer reaches zero.
-- Secret aura values (Midnight restrictions): they cannot be compared or used in
-- arithmetic from addon code, so if the client offers a native duration object
-- (C_UnitAuras.GetAuraDuration + StatusBar:SetTimerDuration) the engine drives
-- the bar and the remaining time is only formatted, never compared.

local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local SPARK_TEXTURE = "Interface\\CastingBar\\UI-CastingBar-Spark"
local TEXT_UPDATE_INTERVAL = 0.1

local issecret = issecretvalue or function() return false end
local GetAuraDuration = C_UnitAuras and C_UnitAuras.GetAuraDuration
local TimerDirection = Enum and Enum.StatusBarTimerDirection
local Interpolation = Enum and Enum.StatusBarInterpolation

local function FormatRemaining(remaining)
    if issecret(remaining) then
        return string.format("%.1f", remaining)
    end
    if remaining <= 0 then
        return "0"
    elseif remaining >= 60 then
        return string.format("%d:%02d", math.floor(remaining / 60), math.floor(remaining % 60))
    elseif remaining >= 10 then
        return string.format("%d", math.floor(remaining))
    end
    return string.format("%.1f", remaining)
end

local TimerBar = {}
TimerBar.__index = TimerBar

local function OnUpdate(frame, elapsed)
    local self = frame.owner
    local remaining
    if self.durationObj then
        remaining = self.durationObj:GetRemainingDuration()
    else
        remaining = self.expirationTime - GetTime()
        if remaining <= 0 then
            self:StopAnimation()
            if self.onExpire then self.onExpire() else self:Hide() end
            return
        end
        self.bar:SetValue(remaining)
    end

    self.textElapsed = self.textElapsed + elapsed
    if self.textElapsed >= TEXT_UPDATE_INTERVAL then
        self.textElapsed = 0
        self.timeText:SetText(FormatRemaining(remaining))
    end
end

function ns.CreateTimerBar(width, height)
    local self = setmetatable({}, TimerBar)

    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(width, height)
    frame:SetClampedToScreen(true)
    frame:Hide()
    frame.owner = self
    self.frame = frame

    -- 1px black outline around the whole bar
    local outline = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    outline:SetPoint("TOPLEFT", -1, 1)
    outline:SetPoint("BOTTOMRIGHT", 1, -1)
    outline:SetColorTexture(0, 0, 0, 1)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT")
    icon:SetSize(height, height)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    self.icon = icon

    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetPoint("TOPLEFT", icon, "TOPRIGHT", 1, 0)
    bar:SetPoint("BOTTOMRIGHT")
    bar:SetStatusBarTexture(BAR_TEXTURE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    self.bar = bar

    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetTexture(BAR_TEXTURE)
    self.barBg = barBg

    -- Cast-bar style spark, glued to the edge of the fill (no value math needed)
    local spark = bar:CreateTexture(nil, "OVERLAY")
    spark:SetTexture(SPARK_TEXTURE)
    spark:SetBlendMode("ADD")
    spark:SetSize(16, height * 2.2)
    spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT")
    self.spark = spark

    local timeText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timeText:SetPoint("RIGHT", -4, 0)
    timeText:SetJustifyH("RIGHT")
    self.timeText = timeText

    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 4, 0)
    label:SetPoint("RIGHT", timeText, "LEFT", -4, 0)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    self.label = label

    self:SetColor(1, 0.82, 0)
    return self
end

function TimerBar:SetColor(r, g, b)
    self.bar:SetStatusBarColor(r, g, b)
    self.barBg:SetVertexColor(r * 0.25, g * 0.25, b * 0.25, 0.8)
end

function TimerBar:SetIcon(texture)
    self.icon:SetTexture(texture or 134400) -- question mark
end

function TimerBar:SetLabel(text)
    self.label:SetText(text or "")
end

function TimerBar:StopAnimation()
    self.frame:SetScript("OnUpdate", nil)
    if self.durationObj and self.bar.ClearTimerDuration then
        self.bar:ClearTimerDuration()
    end
    self.durationObj = nil
    self.expirationTime = nil
end

-- Show a static full bar (preview, permanent aura, or unreadable timer).
function TimerBar:ShowStatic(timeText)
    self:StopAnimation()
    self.bar:SetMinMaxValues(0, 1)
    self.bar:SetValue(1)
    self.spark:Hide()
    self.timeText:SetText(timeText or "")
    self.frame:Show()
end

-- Start draining the bar for an aura. `aura` is an AuraData-like table.
function TimerBar:ShowAura(unit, aura)
    local duration, expirationTime = aura.duration, aura.expirationTime
    if not issecret(duration) and not issecret(expirationTime) then
        if duration and duration > 0 then
            self:ShowTimer(duration, expirationTime)
        else
            self:ShowStatic("") -- permanent aura
        end
        return
    end

    -- Secret values: let the engine drive the bar from a duration object.
    self:StopAnimation()
    if GetAuraDuration and self.bar.SetTimerDuration and TimerDirection and aura.auraInstanceID then
        local durationObj = GetAuraDuration(unit, aura.auraInstanceID)
        if durationObj then
            self.durationObj = durationObj
            self.bar:SetTimerDuration(durationObj, Interpolation and Interpolation.Immediate, TimerDirection.RemainingTime)
            self:StartAnimation()
            return
        end
    end
    self:ShowStatic("")
end

function TimerBar:IsRunning()
    return self.expirationTime ~= nil or self.durationObj ~= nil
end

-- Start draining the bar from known, readable values (no aura needed).
-- When it reaches zero, `onExpire` is called (or the bar is hidden).
function TimerBar:ShowTimer(duration, expirationTime)
    self:StopAnimation()
    self.expirationTime = expirationTime
    self.bar:SetMinMaxValues(0, duration)
    self.bar:SetValue(expirationTime - GetTime())
    self:StartAnimation()
end

function TimerBar:StartAnimation()
    self.spark:Show()
    self.textElapsed = TEXT_UPDATE_INTERVAL -- refresh text on first frame
    self.frame:SetScript("OnUpdate", OnUpdate)
    self.frame:Show()
end

function TimerBar:Hide()
    self:StopAnimation()
    self.frame:Hide()
end

-- Position handling. `pos` is a saved table { point, relativePoint, x, y }.
function TimerBar:ApplyPosition(pos)
    self.frame:ClearAllPoints()
    self.frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
end

function TimerBar:SetMovable(movable, pos)
    local frame = self.frame
    frame:SetMovable(movable)
    frame:EnableMouse(movable)
    if movable then
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", function(f)
            f:StopMovingOrSizing()
            local point, _, relativePoint, x, y = f:GetPoint()
            pos[1], pos[2], pos[3], pos[4] = point, relativePoint, x, y
        end)
    else
        frame:RegisterForDrag()
        frame:SetScript("OnDragStart", nil)
        frame:SetScript("OnDragStop", nil)
    end
end
