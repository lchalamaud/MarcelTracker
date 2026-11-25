local addonName, ns = ...

-- Reminder zone: the alert icons telling that a buff is missing (paladin
-- aura, blessing...). They share the appearance of the alert icon
-- (Widgets/AlertIcon.lua): size, opacity, shake, border.
--
-- The zone also holds a setting read by its trackers: "ownOnly", only the
-- buffs cast by the player count (another paladin's aura or blessing does not
-- hide the reminder).

-- Trackers whose icons had their own appearance before zones existed, in
-- order of preference when taking it over.
local LEGACY_TRACKERS = { "paladinAura", "paladinBlessing" }

local Reminders = {
    key = "reminderGroup", -- SavedVariables of the reminder group it replaces
    name = "Rappels",
    defaultPosition = { "CENTER", "CENTER", 0, 120 },
    defaults = { ownOnly = true },
    options = {
        -- Shown right after the trackers' own options, under "Contenu"
        { type = "toggle", key = "ownOnly", label = "Seulement mes buffs" },
    },
}

for key, value in pairs(ns.AlertIconDefaults) do
    Reminders.defaults[key] = value
end
for _, list in ipairs({ ns.AlertIconOptions, ns.ZonePositionOptions }) do
    for _, option in ipairs(list) do
        table.insert(Reminders.options, option)
    end
end

-- Older versions saved the appearance in each tracker's settings, and the
-- aura tracker its own position (from before the reminder group). The zone
-- takes over the first ones it finds, so that nothing moves on screen, and
-- the trackers forget them.
function Reminders.Migrate(db)
    for _, trackerKey in ipairs(LEGACY_TRACKERS) do
        local trackerDB = MarcelTrackerDB[trackerKey]
        if trackerDB then
            local old = trackerDB.settings
            if old and old.size ~= nil and not db.settings then
                db.settings = {}
                for key in pairs(ns.AlertIconDefaults) do
                    db.settings[key] = old[key]
                end
            end
            if old then
                for key in pairs(ns.AlertIconDefaults) do
                    old[key] = nil
                end
            end

            if trackerDB.position and not db.position then
                db.position = trackerDB.position
            end
            trackerDB.position = nil
        end
    end
end

function ns.GetReminderZone()
    return ns.GetZone(Reminders)
end
