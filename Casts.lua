local addonName, ns = ...

-- Helpers about the player's own casts, shared by the trackers that follow
-- buffs through them while auras are secret (in combat).

local issecret = issecretvalue or function() return false end

-- Friendly units a buff may have been cast on.
local CAST_UNITS = { "target", "focus", "mouseover" }
for i = 1, 4 do table.insert(CAST_UNITS, "party" .. i) end
for i = 1, 40 do table.insert(CAST_UNITS, "raid" .. i) end

local function Readable(value)
    return value ~= nil and not issecret(value)
end

-- Whether a buff cast on `targetName` (the target given by
-- UNIT_SPELLCAST_SENT) reaches the player. With `reachesClass`, the spell
-- also reaches every group member of the target's class (greater blessings).
function ns.CastReachesPlayer(targetName, reachesClass)
    if not Readable(targetName) or type(targetName) ~= "string" or targetName == "" then
        return true
    end
    -- A player may be named with their realm; a creature's name may hold a dash
    local shortName = targetName:match("^[^-]+") or targetName
    if shortName == UnitName("player") then return true end

    for _, unit in ipairs(CAST_UNITS) do
        local name = UnitExists(unit) and UnitName(unit)
        if Readable(name) and (name == targetName or name == shortName) then
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
    -- Nobody around has that name: assume someone out of sight
    return false
end
