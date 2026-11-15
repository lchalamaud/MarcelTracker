local addonName, ns = ...

-- Paladin aura tracker: nothing is shown while one of the paladin's own auras
-- is active; as soon as there is none, an aura icon labelled "Aura" pops up
-- and shakes until an aura is cast again.
--
-- Two sources tell whether an aura is active:
--   * The shapeshift bar, where a paladin's auras live: one of its buttons is
--     flagged active. Not an aura read, so it also works in combat.
--   * The player's own buffs, matched by name. Only readable out of combat
--     (in combat auras are secret, see Trackers/PaladinSeal.lua).
-- Out of combat the buffs are the source of truth, and the shapeshift bar is
-- marked as reliable the first time both agree that an aura is active. In
-- combat the bar is trusted if it proved reliable; otherwise the last known
-- state is kept, updated by the player's own casts and by death.
--
-- The icon is a member of the reminder group (Widgets/IconGroup.lua), which
-- owns the position shared by all the reminder icons.

local ICON_SPELL_ID = 7294 -- Retribution Aura
local ICON_FALLBACK = "Interface\\Icons\\Spell_Holy_AuraOfLight"
local LABEL = "Aura"

-- frFR "Aura de dévotion", enUS "Devotion Aura"
local AURA_NAME_PATTERNS = { "^Aura ", " Aura$" }

local issecret = issecretvalue or function() return false end
local AurasAreSecret = C_Secrets and C_Secrets.ShouldAurasBeSecret or function() return false end
local GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local GetSpellTexture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
local GetSpellName = C_Spell and C_Spell.GetSpellName or GetSpellInfo

local function IsAuraName(name)
    if issecret(name) or type(name) ~= "string" then return false end
    for _, pattern in ipairs(AURA_NAME_PATTERNS) do
        if name:find(pattern) then return true end
    end
    return false
end

-- Returns true/false if the shapeshift bar tells whether an aura is active,
-- nil if it cannot tell (no such bar for this character, secret values).
local function IsAuraFormActive()
    if not (GetNumShapeshiftForms and GetShapeshiftFormInfo) then return nil end
    local count = GetNumShapeshiftForms()
    if issecret(count) or not count or count == 0 then return nil end
    for index = 1, count do
        local _, active = GetShapeshiftFormInfo(index)
        if issecret(active) then return nil end
        if active then return true end
    end
    return false
end

-- True if the player has an aura buff cast by themselves (another paladin's
-- aura gives a buff of the same name). Only call when auras are readable.
local function HasOwnAuraBuff()
    for index = 1, 40 do
        local name
        if GetAuraDataByIndex then
            local aura = GetAuraDataByIndex("player", index, "HELPFUL|PLAYER")
            name = aura and aura.name
        else
            name = UnitBuff("player", index, "PLAYER")
        end
        if not name then return false end
        if IsAuraName(name) then return true end
    end
    return false
end

local Tracker = { key = "paladinAura", name = "Aura de paladin" }

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

-- Returns true or false, or nil when the state is not known (e.g. interface
-- reloaded in combat on a client whose shapeshift bar is not reliable).
function Tracker:HasAura()
    local form = IsAuraFormActive()

    if AurasAreSecret() then
        if form ~= nil and self.db.formsReliable then
            self.hasAura = form
        end
        return self.hasAura
    end

    local buff = HasOwnAuraBuff()
    if buff and form then self.db.formsReliable = true end
    self.hasAura = buff or form == true
    return self.hasAura
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
        shown = self:HasAura() == false and not UnitIsDeadOrGhost("player")
    end
    self.icon:SetShown(shown)
end

function Tracker:OnEvent(event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        if not spellID or issecret(spellID) then return end
        if not IsAuraName(GetSpellName and GetSpellName(spellID)) then return end
        self.hasAura = true
    elseif event == "PLAYER_DEAD" then
        self.hasAura = false -- auras do not survive death
    end
    self:Refresh()
end

-- Registers or unregisters the events according to the "enabled" setting, so
-- that a disabled tracker costs nothing.
function Tracker:UpdateEvents()
    local events = self.events
    if self.settings.enabled then
        events:RegisterUnitEvent("UNIT_AURA", "player")
        events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        events:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
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

    -- db.position: where the icon was before it joined the reminder group
    self.group = ns.GetReminderGroup(db.position)
    db.position = nil

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
