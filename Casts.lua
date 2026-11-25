local addonName, ns = ...

-- Helpers about the player's own casts, shared by the trackers that follow
-- buffs through them while auras are secret (in combat).
--
-- In combat most unit values (names, reactions...) may be secret too: they
-- cannot be compared without raising an error. Everything here is guarded so
-- that it never errors, and the player's own name is read out of combat.

local issecret = issecretvalue or function() return false end

-- Friendly units a buff may have been cast on.
local CAST_UNITS = { "target", "focus", "mouseover" }
for i = 1, 4 do table.insert(CAST_UNITS, "party" .. i) end
for i = 1, 40 do table.insert(CAST_UNITS, "raid" .. i) end

local function Readable(value)
    return value ~= nil and not issecret(value)
end

local function ReadableString(value)
    return Readable(value) and type(value) == "string" and value ~= ""
end

-- The player's name, as last read while readable.
local playerName

local function GetPlayerName()
    local name = UnitName("player")
    if ReadableString(name) then playerName = name end
    return playerName
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    GetPlayerName()
end)

-- Whether `full` is `name` followed by more: a realm ("Name-Realm") or, on
-- Forever, a family name ("Marcel Patulaccì" for "Marcel").
local function Extends(full, name)
    local prefix = full:sub(1, #name + 1)
    return prefix == name .. " " or prefix == name .. "-"
end

-- Whether two readable names stand for the same character.
local function SameName(a, b)
    return a == b or Extends(a, b) or Extends(b, a)
end

-- Looks for the unit `targetName` stands for among the friendly units around.
-- Returns true/false if found, nil otherwise. May raise an error on a secret
-- value: only call through pcall.
local function CheckUnits(targetName, reachesClass)
    for _, unit in ipairs(CAST_UNITS) do
        if UnitExists(unit) then
            local name = UnitName(unit)
            if ReadableString(name) and SameName(name, targetName) then
                -- An enemy cannot be buffed: the spell was self-cast instead
                if not UnitIsFriend("player", unit) then return true end
                if reachesClass and (UnitInParty(unit) or UnitInRaid(unit)) then
                    local _, playerClass = UnitClass("player")
                    local _, unitClass = UnitClass(unit)
                    return Readable(unitClass) and unitClass == playerClass
                end
                return false
            end
        end
    end
    return nil
end

-- Whether a buff cast on `targetName` (the target given by
-- UNIT_SPELLCAST_SENT) reaches the player. With `reachesClass`, the spell
-- also reaches every group member of the target's class (greater blessings).
function ns.CastReachesPlayer(targetName, reachesClass)
    if not ReadableString(targetName) then return true end

    local name = GetPlayerName()
    if name and SameName(targetName, name) then return true end

    local ok, result = pcall(CheckUnits, targetName, reachesClass)
    if ok and result ~= nil then return result end
    -- Nobody around has that name, or it could not be told: assume someone else
    return false
end
