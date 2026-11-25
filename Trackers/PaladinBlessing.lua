local addonName, ns = ...

-- Paladin blessing tracker: nothing is shown while the player has a paladin
-- blessing; as soon as there is none, a blessing icon labelled "Béné" pops
-- up and shakes until a blessing is back. With the reminder zone's "ownOnly"
-- setting, only the blessings cast by the player count; otherwise anyone's do.
--
-- Out of combat the player's buffs are the source of truth, matched by name:
-- each blessing is remembered by its aura instance ID with its expiry time,
-- and its duration is remembered per spell in SavedVariables.
-- In combat auras are secret (see Trackers/PaladinSeal.lua) and no buff is
-- read. The last known state is kept, and updated by
--   * UNIT_AURA's update info, as far as it is readable: a remembered
--     instance ID that is removed is a blessing gone (expired, dispelled,
--     cancelled), an added aura whose name is readable may be a new one
--     (with "ownOnly", only if its caster is readable and is the player);
--   * the expiry times, checked by a timer;
--   * the player's own casts of a blessing that reach them (cast on
--     themselves, auto self-cast while targeting an enemy, greater blessing on
--     someone of their class); such a blessing has no known instance ID and
--     lasts the remembered duration of the spell;
--   * death.
-- A blessing received from someone else in combat may only be seen once out
-- of it.
--
-- The icon is shown in the reminder zone (Zones/Reminders.lua), which owns
-- its position and appearance.

local ICON_SPELL_ID = 20217 -- Blessing of Kings
local ICON_FALLBACK = "Interface\\Icons\\Spell_Magic_MageArmor"
local LABEL = "Béné"
local EXPIRY_MARGIN = 0.2 -- UNIT_AURA may fire a hair before the expiry time
local NO_EXPIRY = math.huge

-- frFR "Bénédiction des rois", "Bénédiction des rois supérieure"
-- enUS "Blessing of Kings", "Greater Blessing of Kings"
local BLESSING_NAME_PATTERNS = { "^Bénédiction ", "Blessing of " }
-- Greater blessings reach every group member of the target's class.
local GREATER_NAME_PATTERNS = { " supérieure$", "^Greater " }
-- Short blessings: protections lasting a few seconds, not what this reminder
-- is about (some are shown by Trackers/ShortBuffs.lua).
local SHORT_BLESSING_NAMES = {
    ["Bénédiction de liberté"] = true, ["Blessing of Freedom"] = true,
    ["Bénédiction de protection"] = true, ["Blessing of Protection"] = true,
    ["Bénédiction de sacrifice"] = true, ["Blessing of Sacrifice"] = true,
}

local issecret = issecretvalue or function() return false end
local issecrettable = issecrettable or function() return false end
local AurasAreSecret = C_Secrets and C_Secrets.ShouldAurasBeSecret or function() return false end
local GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local GetSpellTexture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
local GetSpellName = C_Spell and C_Spell.GetSpellName or GetSpellInfo

local function Readable(value)
    return value ~= nil and not issecret(value)
end

local function MatchesAny(name, patterns)
    if not Readable(name) or type(name) ~= "string" then return false end
    for _, pattern in ipairs(patterns) do
        if name:find(pattern) then return true end
    end
    return false
end

local function IsBlessingName(name)
    return MatchesAny(name, BLESSING_NAME_PATTERNS) and not SHORT_BLESSING_NAMES[name]
end

-- Expiry time of an aura, NO_EXPIRY if it has none or it is not readable.
local function ReadExpiration(expiration)
    if not Readable(expiration) or type(expiration) ~= "number" or expiration <= 0 then
        return NO_EXPIRY
    end
    return expiration
end

-- Whether an aura is known to come from the player. False when it cannot be
-- told (secret values).
local function IsOwnAura(aura)
    local fromPlayer = aura.isFromPlayerOrPlayerPet
    if Readable(fromPlayer) and type(fromPlayer) == "boolean" then
        return fromPlayer
    end
    local source = aura.sourceUnit
    return Readable(source) and source == "player"
end

-- The i-th player buff as an AuraData-like table, or nil. With `ownOnly`,
-- only the buffs cast by the player are listed.
-- Only call when auras are readable.
local function GetPlayerBuff(index, ownOnly)
    if GetAuraDataByIndex then
        return GetAuraDataByIndex("player", index, ownOnly and "HELPFUL|PLAYER" or "HELPFUL")
    end
    local name, _, _, _, duration, expirationTime, _, _, _, spellId =
        UnitBuff("player", index, ownOnly and "PLAYER" or nil)
    if not name then return nil end
    return { name = name, duration = duration, expirationTime = expirationTime, spellId = spellId }
end

local Tracker = { key = "paladinBlessing", name = "Bénédiction" }

-- Settings (db.settings). The appearance of the icon is that of the zone.
Tracker.defaults = { enabled = true }

Tracker.options = {
    { type = "toggle", key = "enabled", label = "Rappel de bénédiction", half = true },
}

function Tracker:ShouldLoad()
    local _, class = UnitClass("player")
    return class == "PALADIN"
end

-- State, while auras are secret:
--   self.known     false until the buffs could be read once
--   self.auras     instance ID (or a placeholder key) -> expiry time of each
--                  blessing seen on the player
--   self.castUntil expiry time of a blessing cast by the player in combat,
--                  whose instance ID is unknown; nil if none
function Tracker:ResetState(known)
    self.known = known
    self.auras = {}
    self.castUntil = nil
end

-- Rebuilds the state from the player's buffs. Only call when auras are readable.
function Tracker:ScanBlessings()
    self:ResetState(true)
    for index = 1, 40 do
        local aura = GetPlayerBuff(index, self.zone.settings.ownOnly)
        if not aura then break end
        if IsBlessingName(aura.name) then
            local id = aura.auraInstanceID
            if not Readable(id) then id = "index" .. index end
            self.auras[id] = ReadExpiration(aura.expirationTime)

            local spellID, duration = aura.spellId, aura.duration
            if Readable(spellID) and Readable(duration) and type(duration) == "number" and duration > 0 then
                self.db.blessingDurations[spellID] = duration
            end
        end
    end
end

-- Applies UNIT_AURA's update info while auras are secret, as far as it can be
-- read; anything unreadable leaves the state as it is.
function Tracker:ApplyAuraUpdate(info)
    if type(info) ~= "table" or issecrettable(info) then return end

    local removed = info.removedAuraInstanceIDs
    if type(removed) == "table" and not issecrettable(removed) then
        for _, id in ipairs(removed) do
            if Readable(id) then self.auras[id] = nil end
        end
    end

    local added = info.addedAuras
    if type(added) == "table" and not issecrettable(added) then
        for _, aura in ipairs(added) do
            if type(aura) == "table" and not issecrettable(aura) and IsBlessingName(aura.name)
                and (not self.zone.settings.ownOnly or IsOwnAura(aura)) then
                local id = aura.auraInstanceID
                if Readable(id) then
                    self.auras[id] = ReadExpiration(aura.expirationTime)
                    self.known = true
                end
            end
        end
    end
end

-- A blessing cast by the player has just reached them, auras being secret.
function Tracker:OnOwnBlessing(spellID)
    local duration = self.db.blessingDurations[spellID]
    local expiresAt = duration and GetTime() + duration or NO_EXPIRY
    if not self.castUntil or expiresAt > self.castUntil then
        self.castUntil = expiresAt
    end
    self.known = true
end

-- Forgets the blessings whose expiry time has passed.
function Tracker:DropExpired()
    local deadline = GetTime() + EXPIRY_MARGIN
    for id, expiresAt in pairs(self.auras) do
        if expiresAt <= deadline then self.auras[id] = nil end
    end
    if self.castUntil and self.castUntil <= deadline then
        self.castUntil = nil
    end
end

-- Returns true or false, or nil when the state is not known (interface
-- reloaded in combat).
function Tracker:HasBlessing()
    if not AurasAreSecret() then
        self:ScanBlessings()
    else
        self:DropExpired()
        if not self.known then return nil end
    end
    return next(self.auras) ~= nil or self.castUntil ~= nil
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
    if AurasAreSecret() then self:ScheduleExpiryCheck() end
end

-- In combat nothing may tell that a blessing ran out: check again by
-- ourselves when the next one is due to.
function Tracker:ScheduleExpiryCheck()
    if not (C_Timer and C_Timer.After) then return end
    local nextExpiry = self.castUntil or NO_EXPIRY
    for _, expiresAt in pairs(self.auras) do
        if expiresAt < nextExpiry then nextExpiry = expiresAt end
    end
    if nextExpiry == NO_EXPIRY or nextExpiry == self.checkAt then return end

    self.checkAt = nextExpiry
    C_Timer.After(math.max(0, nextExpiry - GetTime()) + 0.1, function()
        if self.checkAt == nextExpiry then self.checkAt = nil end
        if self.settings.enabled then self:Refresh() end
    end)
end

function Tracker:OnEvent(event, ...)
    if event == "UNIT_SPELLCAST_SENT" then
        -- Remember who the cast is aimed at, for UNIT_SPELLCAST_SUCCEEDED
        local _, target = ...
        self.castTarget = target
        return
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        local target = self.castTarget
        self.castTarget = nil
        if not Readable(spellID) then return end
        local spellName = GetSpellName and GetSpellName(spellID)
        if not IsBlessingName(spellName) then return end
        -- Out of combat UNIT_AURA tells it all
        if not AurasAreSecret() then return end
        if not ns.CastReachesPlayer(target, MatchesAny(spellName, GREATER_NAME_PATTERNS)) then return end
        self:OnOwnBlessing(spellID)
    elseif event == "UNIT_AURA" then
        if AurasAreSecret() then
            local _, info = ...
            self:ApplyAuraUpdate(info)
        end
    elseif event == "PLAYER_DEAD" then
        self:ResetState(true) -- blessings do not survive death
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
    if key == nil or key == "enabled" then
        self:UpdateEvents()
    end
    self:Refresh()
end

function Tracker:Init(db)
    self.db = db
    self.settings = db.settings
    db.blessingDurations = db.blessingDurations or {}
    self:ResetState(false)

    local zone = ns.GetReminderZone()
    zone:AddMember(self)

    self.icon = ns.CreateAlertIcon(zone.settings, zone.group)
    self.icon:SetIcon(GetSpellTexture and GetSpellTexture(ICON_SPELL_ID) or ICON_FALLBACK)
    self.icon:SetText(LABEL)

    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, ...) self:OnEvent(...) end)

    self:ApplySettings()
end

-- Called by the zone after it changed settings[key].
function Tracker:ApplyZoneSettings(key)
    if key == nil or key == "ownOnly" then self:Refresh() end
end

function Tracker:SetUnlocked(unlocked)
    self.unlocked = unlocked
    self:Refresh()
end

function Tracker:SetPreview(preview)
    self.preview = preview
    self:Refresh()
end

ns.RegisterTracker(Tracker)
