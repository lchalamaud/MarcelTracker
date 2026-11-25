local addonName, ns = ...

-- Short buff tracker: while the player has one of the short protections
-- below, its icon is shown in the short buff zone (Zones/ShortBuffs.lua)
-- with the time left on it.
--
-- Out of combat the player's buffs are the source of truth, matched by spell
-- ID or by name; the duration of each spell is remembered in SavedVariables.
-- In combat auras are secret (see Trackers/PaladinSeal.lua): on Forever even
-- UNIT_AURA's update info is unreadable, so no buff can be seen. The state
-- is then updated by
--   * the player's own casts that reach them (UNIT_SPELLCAST_SUCCEEDED, whose
--     spell ID is readable), timed with the remembered duration;
--   * the expiry times, checked by the icons themselves;
--   * death.
-- So in combat a buff received from someone else is not shown, and one that
-- ends early (BoP cancelled, dispel) stays until its expected end. Leaving
-- combat resyncs from the auras.

-- Buffs, in display order. `spells`: known spell IDs, with the duration to
-- use until the real one has been seen. `selfOnly`: can only be cast on
-- oneself. `class` / `race`: only offered to such characters.
local BUFFS = {
    {
        key = "freedom",
        label = "Bénédiction de liberté",
        spells = { [1044] = 10 },
        names = { "Bénédiction de liberté", "Blessing of Freedom" },
    },
    {
        key = "divineProtection",
        label = "Protection divine",
        spells = { [498] = 6, [5573] = 8 },
        names = { "Protection divine", "Divine Protection" },
        selfOnly = true,
        class = "PALADIN",
    },
    {
        key = "protection",
        label = "Bénédiction de protection",
        spells = { [1022] = 6, [5599] = 8, [10278] = 10 },
        names = { "Bénédiction de protection", "Blessing of Protection" },
    },
    {
        key = "stoneform",
        label = "Forme de pierre",
        spells = { [20594] = 8 },
        names = { "Forme de pierre", "Stoneform" },
        selfOnly = true,
        race = "Dwarf",
    },
}

local DEFAULT_DURATION = 10
local DEMO_DURATION = 8      -- length of one loop of the example icons
local NO_EXPIRY = math.huge

local issecret = issecretvalue or function() return false end
local AurasAreSecret = C_Secrets and C_Secrets.ShouldAurasBeSecret or function() return false end
local GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local GetSpellTexture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
local GetSpellName = C_Spell and C_Spell.GetSpellName or GetSpellInfo

local function Readable(value)
    return value ~= nil and not issecret(value)
end

local function ReadableNumber(value)
    return Readable(value) and type(value) == "number"
end

-- The i-th player buff as an AuraData-like table, or nil.
-- Only call when auras are readable.
local function GetPlayerBuff(index)
    if GetAuraDataByIndex then
        return GetAuraDataByIndex("player", index, "HELPFUL")
    end
    local name, icon, _, _, duration, expirationTime, _, _, _, spellId = UnitBuff("player", index)
    if not name then return nil end
    return { name = name, icon = icon, duration = duration, expirationTime = expirationTime, spellId = spellId }
end

local function IsAvailable(buff)
    if buff.class then
        local _, class = UnitClass("player")
        if class ~= buff.class then return false end
    end
    if buff.race then
        local _, race = UnitRace("player")
        if race ~= buff.race then return false end
    end
    return true
end

local function DefaultTexture(buff)
    local spellID = next(buff.spells)
    return GetSpellTexture and GetSpellTexture(spellID)
end

local Tracker = { key = "shortBuffs", name = "Buffs courts" }

-- Settings (db.settings): one toggle per buff. The appearance of the icons is
-- that of the zone.
Tracker.defaults = {}
for _, buff in ipairs(BUFFS) do
    Tracker.defaults[buff.key] = true
end

-- The buff a spell ID or an aura name stands for, if any.
function Tracker:FindBuff(spellID, name)
    if ReadableNumber(spellID) and self.bySpell[spellID] then
        return self.bySpell[spellID]
    end
    if Readable(name) and type(name) == "string" then
        return self.byName[name]
    end
end

function Tracker:GetDuration(buff, spellID)
    return self.db.durations[spellID] or buff.spells[spellID] or DEFAULT_DURATION
end

-- State of each buff: self.state[key] = { duration, expiresAt, texture }.
-- expiresAt is NO_EXPIRY when unknown.
function Tracker:SetBuff(buff, duration, expiresAt, texture)
    self.state[buff.key] = {
        duration = duration,
        expiresAt = expiresAt,
        texture = texture or DefaultTexture(buff),
    }
end

-- Rebuilds the state from the player's buffs. Only call when auras are readable.
function Tracker:Scan()
    self.state = {}
    for index = 1, 40 do
        local aura = GetPlayerBuff(index)
        if not aura then break end
        local buff = self:FindBuff(aura.spellId, aura.name)
        if buff then
            local duration, expiresAt = aura.duration, aura.expirationTime
            if not (ReadableNumber(duration) and duration > 0 and ReadableNumber(expiresAt) and expiresAt > 0) then
                duration, expiresAt = nil, NO_EXPIRY
            elseif ReadableNumber(aura.spellId) then
                self.db.durations[aura.spellId] = duration
            end
            self:SetBuff(buff, duration, expiresAt, Readable(aura.icon) and aura.icon or nil)
        end
    end
end

-- The player cast a spell while auras are secret.
function Tracker:OnOwnCast(spellID, target)
    if not ReadableNumber(spellID) then
        ns.Debug("buffs courts: sort lancé, identifiant illisible", spellID)
        return
    end
    local spellName = GetSpellName and GetSpellName(spellID)
    local buff = self:FindBuff(spellID, spellName)
    ns.Debug("buffs courts: sort lancé", spellID, spellName, "cible", target, "->", buff and buff.key)
    if not buff then return end
    if not self.settings[buff.key] then
        ns.Debug("  désactivé dans la configuration: ignoré")
        return
    end
    if not buff.selfOnly and not ns.CastReachesPlayer(target, false) then
        ns.Debug("  cible autre que soi: ignoré")
        return
    end

    local now = GetTime()
    local duration = self:GetDuration(buff, spellID)
    ns.Debug("  affiché pour", duration, "s")
    self:SetBuff(buff, duration, now + duration, GetSpellTexture and GetSpellTexture(spellID))
end

-- Recomputes what each icon shows right now.
function Tracker:Refresh()
    local now = GetTime()
    local example = self.preview or self.unlocked
    for _, buff in ipairs(self.buffs) do
        local icon = self.icons[buff.key]
        local state = self.state[buff.key]
        if state and state.expiresAt <= now then
            self.state[buff.key] = nil
            state = nil
        end

        if not self.settings[buff.key] then
            icon:Stop()
        elseif state then
            self.demo[buff.key] = nil
            if state.expiresAt == NO_EXPIRY then
                icon:Start(state.texture)
            else
                icon:Start(state.texture, state.duration, state.expiresAt)
            end
        elseif example then
            -- An example icon, draining and restarting in a loop
            if not (self.demo[buff.key] and icon:IsShown()) then
                self.demo[buff.key] = true
                icon:Start(DefaultTexture(buff), DEMO_DURATION, now + DEMO_DURATION)
            end
        else
            self.demo[buff.key] = nil
            icon:Stop()
        end
    end
end

-- An icon reached the end of its timer.
function Tracker:OnExpire(buff)
    self.state[buff.key] = nil
    self.demo[buff.key] = nil
    self:Refresh()
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
        -- Out of combat UNIT_AURA tells it all
        if not AurasAreSecret() then
            ns.Debug("buffs courts: sort lancé hors combat", spellID, "auras lisibles")
            return
        end
        self:OnOwnCast(spellID, target)
    elseif event == "UNIT_AURA" then
        -- Nothing can be read from it in combat
        if AurasAreSecret() then return end
        self:Scan()
    elseif event == "PLAYER_DEAD" then
        self.state = {} -- buffs do not survive death
    elseif not AurasAreSecret() then
        -- PLAYER_REGEN_ENABLED, PLAYER_ENTERING_WORLD
        self:Scan()
    end
    self:Refresh()
end

function Tracker:IsAnyEnabled()
    for _, buff in ipairs(self.buffs) do
        if self.settings[buff.key] then return true end
    end
    return false
end

-- Registers or unregisters the events according to the settings, so that a
-- tracker with every buff turned off costs nothing.
function Tracker:UpdateEvents()
    local events = self.events
    if self:IsAnyEnabled() then
        events:RegisterUnitEvent("UNIT_AURA", "player")
        events:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
        events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterEvent("PLAYER_DEAD")
        if not AurasAreSecret() then self:Scan() end
    else
        events:UnregisterAllEvents()
        self.state = {}
    end
end

-- Called by the config window after it changed settings[key].
function Tracker:ApplySettings(key)
    self:UpdateEvents()
    self:Refresh()
end

function Tracker:Init(db)
    self.db = db
    self.settings = db.settings
    db.durations = db.durations or {}

    self.state, self.demo = {}, {}
    self.buffs, self.icons = {}, {}
    self.bySpell, self.byName = {}, {}
    self.options = {}

    local zone = ns.GetShortBuffZone()
    zone:AddMember(self)

    -- Only the buffs this character can get
    for _, buff in ipairs(BUFFS) do
        if IsAvailable(buff) then
            table.insert(self.buffs, buff)
            for spellID in pairs(buff.spells) do self.bySpell[spellID] = buff end
            for _, name in ipairs(buff.names) do self.byName[name] = buff end
            table.insert(self.options, { type = "toggle", key = buff.key, label = buff.label, half = true })

            local icon = ns.CreateBuffIcon(zone.settings, zone.group)
            icon.onExpire = function() self:OnExpire(buff) end
            self.icons[buff.key] = icon
        end
    end

    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, ...) self:OnEvent(...) end)

    self:ApplySettings()
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
