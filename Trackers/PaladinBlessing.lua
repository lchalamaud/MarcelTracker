local addonName, ns = ...

-- Paladin blessing tracker: nothing is shown while the player has a paladin
-- blessing, whoever cast it; as soon as there is none, a blessing icon
-- labelled "Béné" pops up and shakes until a blessing is back.
--
-- Out of combat the player's buffs are the source of truth, matched by name.
-- In combat auras are secret (see Trackers/PaladinSeal.lua) and nothing is
-- read: the last known state is kept, and updated by
--   * the expiry time of the blessing, remembered from the last read;
--   * the player's own casts of a blessing on themselves;
--   * death.
-- A blessing received from someone else in combat is only seen once out of it.
--
-- The icon is a member of the reminder group (Widgets/IconGroup.lua), which
-- owns the position shared by all the reminder icons.

local ICON_SPELL_ID = 20217 -- Blessing of Kings
local ICON_FALLBACK = "Interface\\Icons\\Spell_Magic_MageArmor"
local LABEL = "Béné"
local EXPIRY_MARGIN = 0.2 -- UNIT_AURA may fire a hair before the expiry time

-- frFR "Bénédiction des rois", "Bénédiction des rois supérieure"
-- enUS "Blessing of Kings", "Greater Blessing of Kings"
local BLESSING_NAME_PATTERNS = { "^Bénédiction ", "Blessing of " }

local issecret = issecretvalue or function() return false end
local AurasAreSecret = C_Secrets and C_Secrets.ShouldAurasBeSecret or function() return false end
local GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local GetSpellTexture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
local GetSpellName = C_Spell and C_Spell.GetSpellName or GetSpellInfo

local function IsBlessingName(name)
    if issecret(name) or type(name) ~= "string" then return false end
    for _, pattern in ipairs(BLESSING_NAME_PATTERNS) do
        if name:find(pattern) then return true end
    end
    return false
end

-- Returns whether the player has a blessing, and when the last of them
-- expires (nil if unknown or never). Only call when auras are readable.
local function ScanBlessings()
    local found, expiresAt = false, 0
    for index = 1, 40 do
        local name, expiration
        if GetAuraDataByIndex then
            local aura = GetAuraDataByIndex("player", index, "HELPFUL")
            if aura then name, expiration = aura.name, aura.expirationTime end
        else
            local _
            name, _, _, _, _, expiration = UnitBuff("player", index)
        end
        if not name then break end
        if IsBlessingName(name) then
            found = true
            if expiresAt then
                if issecret(expiration) or type(expiration) ~= "number" or expiration <= 0 then
                    expiresAt = nil
                elseif expiration > expiresAt then
                    expiresAt = expiration
                end
            end
        end
    end
    return found, found and expiresAt or nil
end

local Tracker = { key = "paladinBlessing", name = "Bénédiction" }

-- Settings (db.settings): the tracker's own keys plus those of the alert icon.
Tracker.defaults = { enabled = true }
for key, value in pairs(ns.AlertIconDefaults) do
    Tracker.defaults[key] = value
end

Tracker.options = {
    { type = "header", label = "Général" },
    { type = "toggle", key = "enabled", label = "Activé" },
}
for _, option in ipairs(ns.AlertIconOptions) do
    table.insert(Tracker.options, option)
end
for _, option in ipairs(ns.ReminderGroupOptions) do
    table.insert(Tracker.options, option)
end

function Tracker:ShouldLoad()
    local _, class = UnitClass("player")
    return class == "PALADIN"
end

-- Returns true or false, or nil when the state is not known (interface
-- reloaded in combat).
function Tracker:HasBlessing()
    if AurasAreSecret() then
        local expiresAt = self.expiresAt
        if self.hasBlessing and expiresAt and GetTime() >= expiresAt - EXPIRY_MARGIN then
            self.hasBlessing, self.expiresAt = false, nil
        end
        return self.hasBlessing
    end

    self.hasBlessing, self.expiresAt = ScanBlessings()
    return self.hasBlessing
end

-- Recomputes whether the icon should be shown right now. An unknown state
-- does not raise the alert.
function Tracker:Refresh()
    local shown
    if not self.settings.enabled then
        shown = false
    elseif self.preview or self.unlocked then
        shown = true
    else
        shown = self:HasBlessing() == false and not UnitIsDeadOrGhost("player")
    end
    self.icon:SetShown(shown)
end

-- In combat nothing tells that the blessing ran out: check again by ourselves
-- when it is due to.
function Tracker:ScheduleExpiryCheck()
    local expiresAt = self.expiresAt
    if not (expiresAt and C_Timer and C_Timer.After) then return end
    C_Timer.After(math.max(0, expiresAt - GetTime()) + 0.1, function()
        if self.settings.enabled then self:Refresh() end
    end)
end

function Tracker:OnEvent(event, ...)
    if event == "UNIT_SPELLCAST_SENT" then
        -- Remember who the cast is aimed at, for UNIT_SPELLCAST_SUCCEEDED
        local _, target = ...
        if not issecret(target) and type(target) == "string" and target ~= "" then
            self.castTarget = target
        else
            self.castTarget = nil
        end
        return
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        if not spellID or issecret(spellID) then return end
        if not IsBlessingName(GetSpellName and GetSpellName(spellID)) then return end
        -- A blessing cast on someone else changes nothing for the player
        local target = self.castTarget
        if target and target ~= UnitName("player") then return end
        self.hasBlessing, self.expiresAt = true, nil
    elseif event == "PLAYER_DEAD" then
        self.hasBlessing, self.expiresAt = false, nil -- blessings do not survive death
    elseif event == "PLAYER_REGEN_DISABLED" then
        self:ScheduleExpiryCheck()
    end
    self:Refresh()
end

-- Registers or unregisters the events according to the "enabled" setting, so
-- that a disabled tracker costs nothing.
function Tracker:UpdateEvents()
    local events = self.events
    if self.settings.enabled then
        events:RegisterUnitEvent("UNIT_AURA", "player")
        events:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
        events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterEvent("PLAYER_DEAD")
        events:RegisterEvent("PLAYER_ALIVE")
        events:RegisterEvent("PLAYER_UNGHOST")
    else
        events:UnregisterAllEvents()
    end
end

-- Called by the config window after it changed settings[key].
function Tracker:ApplySettings(key)
    self.icon:ApplySettings()
    if key == nil or key == "enabled" then
        self:UpdateEvents()
    end
    self:Refresh()
end

function Tracker:Init(db)
    self.db = db
    self.settings = db.settings
    self.group = ns.GetReminderGroup()

    self.icon = ns.CreateAlertIcon(self.settings, self.group)
    self.icon:SetIcon(GetSpellTexture and GetSpellTexture(ICON_SPELL_ID) or ICON_FALLBACK)
    self.icon:SetText(LABEL)

    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, ...) self:OnEvent(...) end)

    self:ApplySettings()
end

function Tracker:SetUnlocked(unlocked)
    self.unlocked = unlocked
    self:Refresh()
    self.group:SetMovable(unlocked)
end

function Tracker:SetPreview(preview)
    self.preview = preview
    self:Refresh()
end

function Tracker:GetPosition()
    return self.group:GetOffset()
end

function Tracker:SetPosition(x, y)
    self.group:SetOffset(x, y)
end

function Tracker:ResetPosition()
    self.group:ResetPosition()
end

ns.RegisterTracker(Tracker)
