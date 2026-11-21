local addonName, ns = ...

-- Paladin seal tracker: a draining bar showing the active seal, its name and
-- the time left on it.
--
-- Two modes, depending on whether the client lets us read auras:
--   * Auras readable (out of combat): the player's buffs are the source of
--     truth. The active seal is found by spell ID or by name, and its spell ID
--     and duration are remembered in SavedVariables.
--   * Auras secret (in combat, Midnight restrictions): any aura read from addon
--     code raises an error, so auras are not touched at all. The bar is driven
--     by the player's own casts instead (UNIT_SPELLCAST_SUCCEEDED, readable):
--     casting a seal starts a timer with the remembered duration (on Forever,
--     Judgement does not consume the seal). Leaving combat resyncs from the auras.

local DEFAULT_POSITION = { "CENTER", "CENTER", 0, 0 }
local DEFAULT_SEAL_DURATION = 30
local DEMO_DURATION = 10 -- length of one loop of the example bar
local DEMO_SPELL_ID = 21084 -- Seal of Righteousness, for the example's icon

local SEAL_NAME_PATTERNS = { "^Sceau ", "^Seal of " }

local KNOWN_SEAL_IDS = {
    -- Seal of Righteousness
    20154, 21084, 20287, 20288, 20289, 20290, 20291, 20292, 20293,
    -- Seal of the Crusader
    21082, 20162, 20305, 20306, 20307, 20308,
    -- Seal of Command
    20375, 20915, 20918, 20919, 20920,
    -- Seal of Justice
    20164,
    -- Seal of Light
    20165, 20347, 20348, 20349,
    -- Seal of Wisdom
    20166, 20356, 20357,
}

local issecret = issecretvalue or function() return false end
local AurasAreSecret = C_Secrets and C_Secrets.ShouldAurasBeSecret or function() return false end
local GetPlayerAuraBySpellID = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
local GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex

local function GetSpellNameAndIcon(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then return info.name, info.iconID end
    elseif GetSpellInfo then
        local name, _, icon = GetSpellInfo(spellID)
        return name, icon
    end
end

local function MatchesAny(name, patterns)
    if issecret(name) or type(name) ~= "string" then return false end
    for _, pattern in ipairs(patterns) do
        if name:find(pattern) then return true end
    end
    return false
end

-- Returns the i-th player buff as an AuraData-like table, or nil.
-- Only call when auras are readable.
local function GetPlayerBuff(index)
    if GetAuraDataByIndex then
        return GetAuraDataByIndex("player", index, "HELPFUL")
    end
    local name, icon, _, _, duration, expirationTime, _, _, _, spellId = UnitBuff("player", index)
    if not name then return nil end
    return { name = name, icon = icon, duration = duration, expirationTime = expirationTime, spellId = spellId }
end

local Tracker = { key = "paladinSeal", name = "Sceau de paladin" }

-- Settings (db.settings): the tracker's own keys plus those of the timer bar.
Tracker.defaults = { enabled = true, visibility = "always" }
for key, value in pairs(ns.TimerBarDefaults) do
    Tracker.defaults[key] = value
end

Tracker.options = {
    { type = "header", label = "Général" },
    { type = "toggle", key = "enabled", label = "Activé", half = true },
    { type = "select", key = "visibility", label = "Affichage", half = true, values = {
        { "always", "Toujours" },
        { "combat", "En combat" },
    } },
}
for _, option in ipairs(ns.TimerBarOptions) do
    table.insert(Tracker.options, option)
end
table.insert(Tracker.options, { type = "header", label = "Position (depuis le centre de l'écran)" })
table.insert(Tracker.options, { type = "position" })
table.insert(Tracker.options, {
    type = "button",
    label = "Réinitialiser la position",
    func = function(tracker) tracker:ResetPosition() end,
})

function Tracker:ShouldLoad()
    local _, class = UnitClass("player")
    return class == "PALADIN"
end

function Tracker:LearnSeal(spellID)
    if self.sealIds[spellID] then return end
    self.sealIds[spellID] = true
    self.db.learnedSealIds[spellID] = true
end

-- Returns spellID, aura of the active seal, or nil. Only call when auras are readable.
function Tracker:FindActiveSeal()
    if GetPlayerAuraBySpellID then
        for spellID in pairs(self.sealIds) do
            local aura = GetPlayerAuraBySpellID(spellID)
            if aura then return spellID, aura end
        end
    end

    -- Scan buffs: catches seals whose spell ID is not known yet.
    for i = 1, 40 do
        local aura = GetPlayerBuff(i)
        if not aura then break end
        local spellID = aura.spellId
        if spellID and not issecret(spellID) then
            if self.sealIds[spellID] then
                return spellID, aura
            elseif MatchesAny(aura.name, SEAL_NAME_PATTERNS) then
                self:LearnSeal(spellID)
                return spellID, aura
            end
        end
    end
end

function Tracker:ShowSealInfo(spellID)
    self.demo = false
    local name, icon = GetSpellNameAndIcon(spellID)
    self.bar:SetIcon(icon)
    self.bar:SetLabel(name)
end

-- No seal to show. While the config window is open or the bars are unlocked,
-- an example bar drains and restarts in a loop (onExpire calls this again);
-- otherwise the bar is hidden.
function Tracker:ShowIdle()
    if not (self.preview or self.unlocked) then
        self.demo = false
        self.bar:Hide()
        return
    end

    self.bar:SetLabel(self.unlocked and "Sceau (déplacez-moi)" or "Sceau (aperçu)")
    if self.demo and self.bar:IsRunning() then return end -- let the loop run

    local _, icon = GetSpellNameAndIcon(DEMO_SPELL_ID)
    self.bar:SetIcon(icon)
    self.demo = true
    self.bar:ShowTimer(DEMO_DURATION, GetTime() + DEMO_DURATION)
end

-- Full resync from the player's auras. No-op while auras are secret: the bar
-- then keeps the state set by the cast events.
function Tracker:SyncFromAuras()
    if AurasAreSecret() then return end

    local spellID, aura = self:FindActiveSeal()
    if not spellID then
        self:ShowIdle()
        return
    end

    local duration = aura.duration
    if duration and not issecret(duration) and duration > 0 then
        self.db.sealDurations[spellID] = duration
    end
    self:ShowSealInfo(spellID)
    self.bar:ShowAura("player", aura)
end

-- Whether a cast of `spellID` puts a seal on the player. Seal procs (Seal of
-- Command's extra attack, Seal of Light's heal...) also fire
-- UNIT_SPELLCAST_SUCCEEDED and share the seal's name, but are not spells of
-- the player: only known seal auras, or player spells named like a seal, count.
function Tracker:IsSealCast(spellID)
    if self.sealIds[spellID] then return true end
    if not IsPlayerSpell or not IsPlayerSpell(spellID) then return false end
    return MatchesAny(GetSpellNameAndIcon(spellID), SEAL_NAME_PATTERNS)
end

function Tracker:OnSpellCast(spellID)
    if not spellID or issecret(spellID) then return end

    if self:IsSealCast(spellID) then
        self:LearnSeal(spellID)
        if AurasAreSecret() then
            local duration = self.db.sealDurations[spellID] or DEFAULT_SEAL_DURATION
            self:ShowSealInfo(spellID)
            self.bar:ShowTimer(duration, GetTime() + duration)
        else
            self:SyncFromAuras()
        end
    end
end

function Tracker:OnEvent(event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        self:OnSpellCast(spellID)
    elseif event == "PLAYER_REGEN_DISABLED" then
        self.inCombat = true
        self:UpdateVisibility()
    else
        -- UNIT_AURA, PLAYER_REGEN_ENABLED, PLAYER_ENTERING_WORLD
        if event == "PLAYER_REGEN_ENABLED" then
            self.inCombat = false
            self:UpdateVisibility()
        end
        self:SyncFromAuras()
    end
end

-- "Only in combat": the bar is hidden out of combat, except while unlocked or
-- previewed from the config window.
function Tracker:UpdateVisibility()
    local combatOnly = self.settings.visibility == "combat"
    local forced = self.unlocked or self.preview
    self.bar:SetSuppressed(combatOnly and not self.inCombat and not forced)
end

-- Registers or unregisters the events according to the "enabled" setting, so
-- that a disabled tracker costs nothing.
function Tracker:UpdateEvents()
    local events = self.events
    if self.settings.enabled then
        events:RegisterUnitEvent("UNIT_AURA", "player")
        events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        self.inCombat = UnitAffectingCombat("player") and true or false
    else
        events:UnregisterAllEvents()
    end
end

-- Recomputes what the bar should show right now.
function Tracker:Refresh()
    if not self.settings.enabled then
        self.demo = false
        self.bar:Hide()
    elseif not AurasAreSecret() then
        self:SyncFromAuras()
    elseif self.demo or not self.bar:IsRunning() then
        -- Auras unreadable: keep a real timer started by a cast, if any
        self:ShowIdle()
    end
end

-- Called by the config window after it changed settings[key].
function Tracker:ApplySettings(key)
    self.bar:ApplySettings()
    if key == nil or key == "enabled" then
        self:UpdateEvents()
        self:Refresh()
    end
    self:UpdateVisibility()
end

function Tracker:Init(db)
    self.db = db
    self.settings = db.settings
    db.position = db.position or { unpack(DEFAULT_POSITION) }
    db.learnedSealIds = db.learnedSealIds or {}
    db.sealDurations = db.sealDurations or {}

    self.sealIds = {}
    for _, spellID in ipairs(KNOWN_SEAL_IDS) do
        self.sealIds[spellID] = true
    end
    for spellID in pairs(db.learnedSealIds) do
        -- A real seal is seen as an aura and gets a duration; an ID without one
        -- was learned from a seal proc's cast event by an older version.
        if db.sealDurations[spellID] then
            self.sealIds[spellID] = true
        else
            db.learnedSealIds[spellID] = nil
        end
    end

    self.bar = ns.CreateTimerBar(self.settings)
    self.bar.onExpire = function() self:ShowIdle() end
    self.bar.onMoved = function() ns.RefreshConfig() end
    self.bar:AttachPosition(db.position)

    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, ...) self:OnEvent(...) end)

    self:ApplySettings()
end

function Tracker:SetUnlocked(unlocked)
    self.unlocked = unlocked
    self.bar:SetMovable(unlocked)
    self:UpdateVisibility()
    self:Refresh()
end

function Tracker:SetPreview(preview)
    self.preview = preview
    self:UpdateVisibility()
    self:Refresh()
end

function Tracker:GetPosition()
    return self.bar:GetOffset()
end

function Tracker:SetPosition(x, y)
    self.bar:SetOffset(x, y)
end

function Tracker:ResetPosition()
    self.bar:SetOffset(DEFAULT_POSITION[3], DEFAULT_POSITION[4])
end

ns.RegisterTracker(Tracker)
