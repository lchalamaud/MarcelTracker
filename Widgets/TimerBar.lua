local addonName, ns = ...

-- Reusable timer bar: [icon][ label ... time (right) ], draining left.
--
-- Appearance is driven by a settings table (see ns.TimerBarDefaults), usually a
-- sub-table of SavedVariables. The bar keeps a reference to it: change a value,
-- then call bar:ApplySettings() to see it live.
--
-- Readable values (duration/expirationTime): the bar is animated in OnUpdate
-- and hides itself (or calls onExpire) when the timer reaches zero.
-- Secret aura values (Midnight restrictions): they cannot be compared or used in
-- arithmetic from addon code, so if the client offers a native duration object
-- (C_UnitAuras.GetAuraDuration + StatusBar:SetTimerDuration) the engine drives
-- the bar and the remaining time is only formatted, never compared.

local SPARK_TEXTURE = "Interface\\CastingBar\\UI-CastingBar-Spark"
local TEXT_UPDATE_INTERVAL = 0.1
local OUTLINE = 1 -- black line around the bar, when it has no border

-- Heartbeat of the time text when the timer is about to run out: it grows
-- then shrinks back, continuously, and turns orange to stand out.
local PULSE_THRESHOLD = 5 -- seconds left
local PULSE_SCALE = 1.1
local PULSE_HALF = 0.27   -- duration of the growth (and of the shrinking)
local PULSE_COLOR = { 1, 0.7, 0.1 }

-- Built-in textures only (no LibSharedMedia). Keys are what gets saved.
local TEXTURES = {
    blizzard = "Interface\\TargetingFrame\\UI-StatusBar",
    raid = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
    skills = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
    flat = "Interface\\Buttons\\WHITE8X8",
    target = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill",
    resource = "Interface\\RaidFrame\\Raid-Bar-Resource-Fill",
    loading = "Interface\\Glues\\LoadingBar\\Loading-BarFill",
    score = "Interface\\WorldStateFrame\\WORLDSTATEFINALSCORE-HIGHLIGHT",
    quest = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
}

-- Textures shipped with the addon: the designs of design/, converted by
-- tools/generate_textures.py. They carry their own colours (paladin pink), so they are drawn untinted and the colour settings
-- do not apply to them.
local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
local COLORED_TEXTURES = {
    incantation = MEDIA .. "Incantation.tga",
    lumiere = MEDIA .. "Lumiere.tga",
    ferveur = MEDIA .. "Ferveur.tga",
    astral = MEDIA .. "Astral.tga",
    courant = MEDIA .. "Courant.tga",
}

local function UsesOwnColors(settings)
    return COLORED_TEXTURES[settings.texture] ~= nil
end

-- Cast bar fills of the modern UI. They are atlases, not files, and may not
-- exist on every client: they are only offered when the client knows them.
-- Being already coloured, they are desaturated so the bar colour still applies.
local ATLAS_TEXTURES = {
    { "cast", "Sort (Blizzard)", "ui-castingbar-filling-standard" },
    { "channel", "Canal (Blizzard)", "ui-castingbar-filling-channel" },
    { "castgrey", "Sort gris", "ui-castingbar-uninterruptable" },
}
local ATLASES = {}
local GetAtlasInfo = C_Texture and C_Texture.GetAtlasInfo
for _, entry in ipairs(ATLAS_TEXTURES) do
    if GetAtlasInfo and GetAtlasInfo(entry[3]) then
        ATLASES[entry[1]] = entry[3]
    end
end

ns.TimerBarDefaults = {
    width = 220,
    height = 22,
    scale = 1,
    alpha = 1,
    colorMode = "class", -- "class" or "custom"
    color = { r = 1, g = 0.82, b = 0 },
    texture = "blizzard",
    showSpark = true,
    border = true,
    showIcon = true,
    showLabel = true,
    showTime = true,
    fontSize = 10,
    labelAlign = "CENTER",
    textOutline = true,
    fadeIn = 200, -- milliseconds, 0 = no fade
    fadeOut = 300,
    timePulse = true,
}

-- Option descriptors for the config page (see Config/Controls.lua), to be
-- appended to the option list of any tracker displaying a timer bar.
ns.TimerBarOptions = {
    { type = "header", label = "Taille" },
    { type = "slider", key = "width", label = "Largeur", min = 80, max = 600, step = 1 },
    { type = "slider", key = "height", label = "Hauteur", min = 8, max = 60, step = 1 },
    { type = "slider", key = "scale", label = "Échelle (%)", min = 0.5, max = 2, step = 0.05, percent = true },

    { type = "header", label = "Apparence" },
    { type = "select", key = "colorMode", label = "Couleur", half = true, disabled = UsesOwnColors, values = {
        { "class", "De classe" },
        { "custom", "Personnalisée" },
    } },
    { type = "color", key = "color", label = "Couleur personnalisée", half = true,
        disabled = function(settings)
            return settings.colorMode ~= "custom" or UsesOwnColors(settings)
        end },
    { type = "select", key = "texture", label = "Texture", half = true, values = {
        { "incantation", "Incantation" },
        { "lumiere", "Lumière sacrée" },
        { "ferveur", "Ferveur" },
        { "astral", "Astral" },
        { "courant", "Courant sacré" },
        { "blizzard", "Blizzard" },
        { "raid", "Raid" },
        { "skills", "Compétences" },
        { "target", "Cible" },
        { "resource", "Raid (mana)" },
        { "loading", "Chargement" },
        { "score", "Reflet" },
        { "quest", "Surbrillance" },
        { "flat", "Unie" },
    } },
    { type = "toggle", key = "showSpark", label = "Étincelle", half = true },
    { type = "toggle", key = "border", label = "Bordure" },
    { type = "slider", key = "alpha", label = "Opacité (%)", min = 0.1, max = 1, step = 0.05, percent = true },
    { type = "slider", key = "fadeIn", label = "Fondu entrant (ms)", min = 0, max = 2000, step = 50 },
    { type = "slider", key = "fadeOut", label = "Fondu sortant (ms)", min = 0, max = 2000, step = 50 },

    { type = "header", label = "Textes" },
    { type = "toggle", key = "showIcon", label = "Icône", half = true },
    { type = "toggle", key = "showLabel", label = "Nom", half = true },
    { type = "toggle", key = "showTime", label = "Temps restant", half = true },
    { type = "select", key = "labelAlign", label = "Nom aligné", half = true, values = {
        { "CENTER", "Au centre" },
        { "LEFT", "À gauche" },
    } },
    { type = "toggle", key = "textOutline", label = "Contour noir fin", half = true },
    { type = "toggle", key = "timePulse", label = "Battement sous 5 s", half = true,
        disabled = function(settings) return not settings.showTime end },
    { type = "slider", key = "fontSize", label = "Taille de police", min = 6, max = 24, step = 1 },
}

-- Add the available cast bar atlases to the texture list, after our own
for _, option in ipairs(ns.TimerBarOptions) do
    if option.key == "texture" then
        local position = 1
        while option.values[position] and COLORED_TEXTURES[option.values[position][1]] do
            position = position + 1
        end
        for _, entry in ipairs(ATLAS_TEXTURES) do
            if ATLASES[entry[1]] then
                table.insert(option.values, position, { entry[1], entry[2] })
                position = position + 1
            end
        end
    end
end

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

-- Position, dragging and move highlight: see Widgets/Movable.lua
for name, method in pairs(ns.Movable) do
    TimerBar[name] = method
end

-- Runs while the bar is fading and/or its timer is running (see UpdateScript).
local function OnUpdate(frame, elapsed)
    local self = frame.owner

    if self.fadeTo then
        local alpha = self.fadeAlpha
        if self.fadeTo > alpha then
            alpha = math.min(alpha + elapsed * self.fadeSpeed, 1)
        else
            alpha = math.max(alpha - elapsed * self.fadeSpeed, 0)
        end
        self:SetFadeAlpha(alpha)
        if alpha == self.fadeTo then
            self.fadeTo = nil
            if alpha == 0 then frame:Hide() end
            self:UpdateScript()
        end
    end
    if not self:IsRunning() or not frame:IsShown() then return end

    local remaining
    if self.durationObj then
        remaining = self.durationObj:GetRemainingDuration()
        -- A secret value cannot be compared: no heartbeat in that case
        self:SetPulsing(not issecret(remaining) and self:ShouldPulse(remaining))
    else
        remaining = self.expirationTime - GetTime()
        if remaining <= 0 then
            self.bar:SetValue(0)
            self:StopAnimation()
            if self.onExpire then self.onExpire() else self:Hide() end
            return
        end
        self.bar:SetValue(remaining)
        self:SetPulsing(self:ShouldPulse(remaining))
    end

    self.textElapsed = self.textElapsed + elapsed
    if self.textElapsed >= TEXT_UPDATE_INTERVAL then
        self.textElapsed = 0
        self.timeText:SetText(FormatRemaining(remaining))
    end
end

-- `settings` is a table shaped like ns.TimerBarDefaults (all keys present).
function ns.CreateTimerBar(settings)
    local self = setmetatable({ settings = settings }, TimerBar)

    -- The anchor carries position, size, scale, opacity and dragging, and is
    -- always shown.
    local anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetClampedToScreen(true)
    anchor:SetPoint("CENTER")
    self.anchor = anchor

    -- The content frame (inset in the anchor, see ApplySettings) is shown only
    -- while there is something to display and
    -- the bar is not suppressed (plus the time of its fade out). Its own alpha
    -- is the fade, multiplied by the engine with the opacity of the anchor.
    -- Hiding it also pauses its OnUpdate.
    local frame = CreateFrame("Frame", nil, anchor)
    frame:SetAllPoints()
    frame:SetAlpha(0)
    frame:Hide()
    self.fadeAlpha = 0
    self.active, self.suppressed, self.visible = false, false, false
    frame.owner = self
    self.frame = frame

    -- 1px black outline around the whole bar. With the border, only what
    -- shows between the icon and the bar remains visible.
    local outline = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    outline:SetPoint("TOPLEFT", -OUTLINE, OUTLINE)
    outline:SetPoint("BOTTOMRIGHT", OUTLINE, -OUTLINE)
    outline:SetColorTexture(0, 0, 0, 1)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    self.icon = icon

    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    self.bar = bar

    self.barBg = bar:CreateTexture(nil, "BACKGROUND")
    self.barBg:SetAllPoints()

    -- Cast-bar style spark, glued to the edge of the fill (no value math needed)
    local spark = bar:CreateTexture(nil, "OVERLAY")
    spark:SetTexture(SPARK_TEXTURE)
    spark:SetBlendMode("ADD")
    spark:Hide()
    self.spark = spark

    local timeText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timeText:SetPoint("RIGHT", -4, 0)
    timeText:SetJustifyH("RIGHT")
    self.timeText = timeText

    -- Heartbeat: a single scale animation played back and forth ("BOUNCE"),
    -- eased at both ends. No delay: while an animation waits it is not applied,
    -- so on the way back the text would snap to its normal size and jump. An
    -- animation does not change the layout, so the label anchored to the time
    -- text does not move.
    if timeText.CreateAnimationGroup then
        local pulse = timeText:CreateAnimationGroup()
        pulse:SetLooping("BOUNCE")
        local scale = pulse:CreateAnimation("Scale")
        local setFrom = scale.SetScaleFrom or scale.SetFromScale
        local setTo = scale.SetScaleTo or scale.SetToScale
        if setFrom and setTo then
            setFrom(scale, 1, 1)
            setTo(scale, PULSE_SCALE, PULSE_SCALE)
        else
            scale:SetScale(PULSE_SCALE, PULSE_SCALE)
        end
        scale:SetOrigin("CENTER", 0, 0)
        scale:SetDuration(PULSE_HALF)
        scale:SetSmoothing("IN_OUT")
        self.pulse = pulse
    end

    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetWordWrap(false)
    self.label = label

    local fontFile, _, fontFlags = label:GetFont()
    self.fontFile, self.fontFlags = fontFile, fontFlags

    -- Around the whole bar, in front of the status bar and its spark
    self.border = ns.CreateBorder(frame, 3)

    -- Created last, so that it is drawn in front of everything else
    self.moveHighlight = ns.CreateMoveHighlight(anchor)

    self:ApplySettings()
    return self
end

-- Re-reads every value of the settings table. Safe to call at any time,
-- including in combat (nothing here is a protected frame).
function TimerBar:ApplySettings()
    local s = self.settings
    local anchor, bar, icon, label, timeText = self.anchor, self.bar, self.icon, self.label, self.timeText

    anchor:SetSize(s.width, s.height)
    anchor:SetScale(s.scale)
    anchor:SetAlpha(s.alpha)
    if self.position then self:ApplyPosition() end -- offsets depend on the scale

    -- The configured size is that of the whole box: the content is inset by
    -- what surrounds it, the border or else the 1px black outline.
    local inset = OUTLINE
    if s.border then inset = self.border:Apply(s.height, true) end
    self.border:SetShown(s.border)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOPLEFT", inset, -inset)
    self.frame:SetPoint("BOTTOMRIGHT", -inset, inset)

    local innerHeight = s.height - 2 * inset
    icon:SetSize(innerHeight, innerHeight)
    icon:SetShown(s.showIcon)
    bar:ClearAllPoints()
    if s.showIcon then
        bar:SetPoint("TOPLEFT", icon, "TOPRIGHT", 1, 0)
    else
        bar:SetPoint("TOPLEFT")
    end
    bar:SetPoint("BOTTOMRIGHT")

    local atlas = ATLASES[s.texture]
    local colored = COLORED_TEXTURES[s.texture]
    local texture = atlas or colored or TEXTURES[s.texture] or TEXTURES.blizzard
    if texture ~= self.texture then
        self.texture = texture
        bar:SetStatusBarTexture(texture) -- accepts a file or an atlas name
        if atlas then
            self.barBg:SetAtlas(atlas)
        else
            self.barBg:SetTexture(texture)
            self.barBg:SetTexCoord(0, 1, 0, 1) -- SetAtlas leaves its own coords
        end
        bar:GetStatusBarTexture():SetDesaturated(atlas ~= nil)
        self.barBg:SetDesaturated(atlas ~= nil)
        self.spark:ClearAllPoints()
        self.spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT")
    end

    local r, g, b = s.color.r, s.color.g, s.color.b
    if s.colorMode == "class" then
        local _, class = UnitClass("player")
        local classColor = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
        if classColor then r, g, b = classColor.r, classColor.g, classColor.b end
    end
    if colored then r, g, b = 1, 1, 1 end
    bar:SetStatusBarColor(r, g, b)
    self.barBg:SetVertexColor(r * 0.25, g * 0.25, b * 0.25, 0.8)

    self.spark:SetSize(16, innerHeight * 2.2)
    self.spark:SetShown(self.sparkActive and s.showSpark)

    if self.fontFile then
        -- "OUTLINE" is the thinnest outline the client offers (about 1px). The
        -- drop shadow is removed with it, or the two add up into a thick edge.
        local flags = s.textOutline and "OUTLINE" or self.fontFlags
        local shadowAlpha = s.textOutline and 0 or 1
        for _, text in ipairs({ label, timeText }) do
            text:SetFont(self.fontFile, s.fontSize, flags)
            text:SetShadowColor(0, 0, 0, shadowAlpha)
        end
    end
    timeText:SetShown(s.showTime)
    label:SetShown(s.showLabel)
    label:SetJustifyH(s.labelAlign)
    label:ClearAllPoints()
    label:SetPoint("LEFT", 4, 0)
    if s.showTime then
        label:SetPoint("RIGHT", timeText, "LEFT", -4, 0)
    else
        label:SetPoint("RIGHT", -4, 0)
    end
end

function TimerBar:SetIcon(texture)
    self.icon:SetTexture(texture or 134400) -- question mark
end

function TimerBar:SetLabel(text)
    self.label:SetText(text or "")
end

function TimerBar:SetSparkActive(active)
    self.sparkActive = active
    self.spark:SetShown(active and self.settings.showSpark)
end

function TimerBar:ShouldPulse(remaining)
    local s = self.settings
    return s.timePulse and s.showTime and remaining < PULSE_THRESHOLD
end

function TimerBar:SetPulsing(pulsing)
    pulsing = pulsing and true or false
    if pulsing == self.pulsing then return end
    self.pulsing = pulsing
    if pulsing then
        self.timeText:SetTextColor(unpack(PULSE_COLOR))
    else
        self.timeText:SetTextColor(1, 1, 1)
    end
    if not self.pulse then return end
    if pulsing then self.pulse:Play() else self.pulse:Stop() end
end

function TimerBar:StopAnimation()
    self:SetPulsing(false)
    if self.durationObj and self.bar.ClearTimerDuration then
        self.bar:ClearTimerDuration()
    end
    self.durationObj = nil
    self.expirationTime = nil
    self:UpdateScript()
end

-- OnUpdate is only needed while something moves: a timer or a fade.
function TimerBar:UpdateScript()
    local needed = self.fadeTo ~= nil or self:IsRunning()
    self.frame:SetScript("OnUpdate", needed and OnUpdate or nil)
end

function TimerBar:SetFadeAlpha(alpha)
    self.fadeAlpha = alpha
    self.frame:SetAlpha(alpha)
end

-- The bar is visible when it has something to display (`active`) and is not
-- suppressed. Any change of that state fades the content frame in or out,
-- starting from its current alpha so that a fade can be reversed midway.
function TimerBar:UpdateVisibility()
    local visible = self.active and not self.suppressed
    if visible == self.visible then return end
    self.visible = visible

    local duration = (visible and self.settings.fadeIn or self.settings.fadeOut) / 1000
    if duration > 0 then
        self.fadeTo = visible and 1 or 0
        self.fadeSpeed = 1 / duration
        if visible then self.frame:Show() end
    else
        self.fadeTo = nil
        self:SetFadeAlpha(visible and 1 or 0)
        self.frame:SetShown(visible)
    end
    self:UpdateScript()
end

function TimerBar:SetActive(active)
    self.active = active
    self:UpdateVisibility()
end

-- Show a static full bar (preview, permanent aura, or unreadable timer).
function TimerBar:ShowStatic(timeText)
    self:StopAnimation()
    self.bar:SetMinMaxValues(0, 1)
    self.bar:SetValue(1)
    self:SetSparkActive(false)
    self.timeText:SetText(timeText or "")
    self:SetActive(true)
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
    self:SetSparkActive(true)
    self.textElapsed = TEXT_UPDATE_INTERVAL -- refresh text on first frame
    self:SetActive(true)
    self:UpdateScript()
end

-- Nothing to display any more: the bar freezes where it is and fades out.
function TimerBar:Hide()
    self:StopAnimation()
    self:SetSparkActive(false)
    self:SetActive(false)
end

-- Hide the bar regardless of its timer state (e.g. "only in combat"). The
-- timer keeps its state and catches up when the bar is shown again.
function TimerBar:SetSuppressed(suppressed)
    self.suppressed = suppressed and true or false
    self:UpdateVisibility()
end
