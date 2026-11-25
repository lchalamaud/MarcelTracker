local addonName, ns = ...

-- Aura caster in tooltips: adds a line to the tooltip of a buff or debuff,
-- "Caster" on the left and the caster's full name on the right, in their
-- class colour.
-- Covers every aura tooltip shown through GameTooltip (buff frame, unit
-- frames...). Its option sits on the "Divers" page of the config window.
--
-- An aura tooltip is its own tooltip type, so no OnTooltipSet script covers
-- it: the GameTooltip setters are hooked instead (the player buff frame uses
-- the instance ID ones). Hooks cannot be removed, so the "enabled" setting is
-- checked inside them.
--
-- In combat the aura data may be secret (see Trackers/PaladinSeal.lua): the
-- line is then left out rather than risking an error.

local LABEL = "Caster"
local LABEL_COLOR = { 0.8, 0.8, 0.8 }
local DEFAULT_COLOR = { 1, 1, 1 } -- caster who is not a player

local issecret = issecretvalue or function() return false end
local issecrettable = issecrettable or function() return false end

local function Readable(value)
    return value ~= nil and not issecret(value)
end

-- Tooltip setter -> function(unit, key, filter) returning the caster unit of
-- the aura it shows.
local SOURCE_GETTERS = {}

local function FromAuraData(getAura)
    return function(unit, key, filter)
        local aura = getAura(unit, key, filter)
        if type(aura) ~= "table" or issecrettable(aura) then return nil end
        return aura.sourceUnit
    end
end

if C_UnitAuras then
    local byInstance = C_UnitAuras.GetAuraDataByAuraInstanceID
    local getters = {
        SetUnitAura = C_UnitAuras.GetAuraDataByIndex,
        SetUnitBuff = C_UnitAuras.GetBuffDataByIndex,
        SetUnitDebuff = C_UnitAuras.GetDebuffDataByIndex,
        SetUnitAuraByAuraInstanceID = byInstance,
        SetUnitBuffByAuraInstanceID = byInstance,
        SetUnitDebuffByAuraInstanceID = byInstance,
    }
    for method, getAura in pairs(getters) do
        SOURCE_GETTERS[method] = FromAuraData(getAura)
    end
end

-- Older API: the caster is the 7th value returned
local legacy = { SetUnitAura = UnitAura, SetUnitBuff = UnitBuff, SetUnitDebuff = UnitDebuff }
for method, getAura in pairs(legacy) do
    if not SOURCE_GETTERS[method] and getAura then
        SOURCE_GETTERS[method] = function(unit, index, filter)
            return (select(7, getAura(unit, index, filter)))
        end
    end
end

-- Whether a value is a readable, non-empty string.
local function ReadableString(value)
    return Readable(value) and type(value) == "string" and value ~= ""
end

-- The full name of a unit: on Forever a character is "Firstname Surname", and
-- the second value of UnitNameUnmodified is the surname (UnitName only gives
-- the first name). Nil if it cannot be read.
local function FullName(unit)
    local first, surname = (UnitNameUnmodified or UnitName)(unit)
    if not ReadableString(first) then return nil end
    if ReadableString(surname) then return first .. " " .. surname end
    return first
end

-- The caster's full name, in their class colour if they are a player; nil if
-- it cannot be read.
local function CasterText(source)
    if not Readable(source) or type(source) ~= "string" then return nil end
    local name = FullName(source)
    if not name then return nil end

    if UnitIsPlayer(source) then
        local _, class = UnitClass(source)
        local color = Readable(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if color then
            return string.format("|cff%02x%02x%02x%s|r",
                color.r * 255, color.g * 255, color.b * 255, name)
        end
    end
    return name
end

local Tracker = { key = "auraCaster", name = "Lanceur des auras", page = "Divers" }

Tracker.defaults = { enabled = true }

Tracker.options = {
    { type = "header", label = "Infobulles" },
    { type = "toggle", key = "enabled", label = "Afficher le lanceur des buffs et débuffs" },
}

function Tracker:AddCasterLine(tooltip, getSource, unit, key, filter)
    if not self.settings.enabled then return end
    local ok, text = pcall(function()
        return CasterText(getSource(unit, key, filter))
    end)
    if not ok then
        ns.Debug("AuraCaster", text)
        return
    end
    if not text then return end
    -- A double line: left column left-aligned, right column right-aligned
    tooltip:AddDoubleLine(LABEL, text,
        LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3],
        DEFAULT_COLOR[1], DEFAULT_COLOR[2], DEFAULT_COLOR[3])
    tooltip:Show() -- resize to the new line
end

-- Nothing to re-read: the setting is checked each time a tooltip is shown.
function Tracker:ApplySettings(key)
end

function Tracker:Init(db)
    self.db = db
    self.settings = db.settings

    for method, getSource in pairs(SOURCE_GETTERS) do
        if GameTooltip[method] then
            hooksecurefunc(GameTooltip, method, function(tooltip, unit, key, filter)
                self:AddCasterLine(tooltip, getSource, unit, key, filter)
            end)
        end
    end
end

ns.RegisterTracker(Tracker)
