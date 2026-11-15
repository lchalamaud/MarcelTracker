local addonName, ns = ...

-- Paladin seal tracker: a draining bar showing the active seal, its name and
-- the time left on it.
--
-- Seals are identified by spell ID so lookups keep working when aura fields are
-- secret (in combat). Known vanilla ranks are listed below; any other seal
-- (unknown rank, client-specific seal) is recognised by its name when auras are
-- readable, then its spell ID is remembered in SavedVariables.

local BAR_WIDTH, BAR_HEIGHT = 220, 22
local DEFAULT_POSITION = { "CENTER", "CENTER", 0, -160 }

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

local function IsSealName(name)
    if issecret(name) or type(name) ~= "string" then return false end
    for _, pattern in ipairs(SEAL_NAME_PATTERNS) do
        if name:find(pattern) then return true end
    end
    return false
end

-- Returns the i-th player buff as an AuraData-like table, or nil.
local function GetPlayerBuff(index)
    if GetAuraDataByIndex then
        return GetAuraDataByIndex("player", index, "HELPFUL")
    end
    local name, icon, _, _, duration, expirationTime, _, _, _, spellId = UnitBuff("player", index)
    if not name then return nil end
    return { name = name, icon = icon, duration = duration, expirationTime = expirationTime, spellId = spellId }
end

local Tracker = { key = "paladinSeal" }

function Tracker:ShouldLoad()
    local _, class = UnitClass("player")
    return class == "PALADIN"
end

function Tracker:LearnSeal(spellID)
    if self.sealIds[spellID] then return end
    self.sealIds[spellID] = true
    self.db.learnedSealIds[spellID] = true
end

-- Returns spellID, aura of the active seal, or nil.
function Tracker:FindActiveSeal()
    -- Direct lookup by spell ID: works even when aura fields are secret.
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
            elseif IsSealName(aura.name) then
                self:LearnSeal(spellID)
                return spellID, aura
            end
        end
    end
end

function Tracker:Update()
    local spellID, aura = self:FindActiveSeal()
    if spellID then
        local name, icon = GetSpellNameAndIcon(spellID)
        self.bar:SetIcon(icon)
        self.bar:SetLabel(name)
        self.bar:ShowAura("player", aura)
    elseif self.unlocked then
        self.bar:SetIcon(nil)
        self.bar:SetLabel("Sceau (déplacez-moi)")
        self.bar:ShowStatic("30")
    else
        self.bar:Hide()
    end
end

function Tracker:OnEvent(event, unit, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Learn seals we did not know as soon as they are cast.
        if issecret(spellID) or self.sealIds[spellID] then return end
        if IsSealName((GetSpellNameAndIcon(spellID))) then
            self:LearnSeal(spellID)
            self:Update()
        end
    else
        self:Update()
    end
end

function Tracker:Init(db)
    self.db = db
    db.position = db.position or { unpack(DEFAULT_POSITION) }
    db.learnedSealIds = db.learnedSealIds or {}

    self.sealIds = {}
    for _, spellID in ipairs(KNOWN_SEAL_IDS) do
        self.sealIds[spellID] = true
    end
    for spellID in pairs(db.learnedSealIds) do
        self.sealIds[spellID] = true
    end

    self.bar = ns.CreateTimerBar(BAR_WIDTH, BAR_HEIGHT)
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS.PALADIN
    if color then self.bar:SetColor(color.r, color.g, color.b) end
    self.bar:ApplyPosition(db.position)

    local events = CreateFrame("Frame")
    events:SetScript("OnEvent", function(_, ...) self:OnEvent(...) end)
    events:RegisterUnitEvent("UNIT_AURA", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")

    self:Update()
end

function Tracker:SetUnlocked(unlocked)
    self.unlocked = unlocked
    self.bar:SetMovable(unlocked, self.db.position)
    self:Update()
end

function Tracker:ResetPosition()
    local pos = self.db.position
    pos[1], pos[2], pos[3], pos[4] = unpack(DEFAULT_POSITION)
    self.bar:ApplyPosition(pos)
end

ns.RegisterTracker(Tracker)
