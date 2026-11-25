local addonName, ns = ...

-- Short buff zone: the protections lasting a few seconds that the player
-- has (Blessing of Freedom, Divine Protection...), each with the time left on
-- it (Widgets/BuffIcon.lua). Meant to sit on or just above the character.

local ShortBuffs = {
    key = "shortBuffZone",
    name = "Buffs courts",
    defaultPosition = { "CENTER", "CENTER", 0, 60 },
    defaults = {},
    options = {},
}

for key, value in pairs(ns.BuffIconDefaults) do
    ShortBuffs.defaults[key] = value
end
for _, list in ipairs({ ns.BuffIconOptions, ns.ZonePositionOptions }) do
    for _, option in ipairs(list) do
        table.insert(ShortBuffs.options, option)
    end
end

function ns.GetShortBuffZone()
    return ns.GetZone(ShortBuffs)
end
