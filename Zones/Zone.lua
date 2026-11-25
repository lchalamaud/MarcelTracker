local addonName, ns = ...

-- Display zones: a place on screen where trackers show their icons, side by
-- side (an icon group, see Widgets/IconGroup.lua). The zone owns everything
-- about the display: its position and the appearance shared by all its icons
-- (size, opacity...). A tracker only tells what to show, in the zone it joins.
--
-- In the config window a zone has its own page: its appearance and position,
-- and the options of the trackers showing icons in it.
--
-- A zone is described by a definition (see Zones/Reminders.lua):
--   key              name of its SavedVariables sub-table, MarcelTrackerDB[key]
--   name             display name, in the config window
--   defaults         default settings, merged into db.settings
--   options          option descriptors (see Config/Controls.lua)
--   defaultPosition  { "CENTER", "CENTER", x, y }
--   Migrate(db)      optional, run on the saved table before the defaults
--                    are merged (settings moved from older versions...)
--
-- ns.GetZone(definition) creates the zone the first time a tracker asks for
-- it, from its Init (SavedVariables are loaded by then), then returns the
-- same zone. A zone that no tracker of the character uses is never created,
-- nor shown in the config window.

local Zone = {}
Zone.__index = Zone

local created = {} -- key -> zone

function ns.GetZone(definition)
    local zone = created[definition.key]
    if zone then return zone end

    local db = MarcelTrackerDB[definition.key] or {}
    MarcelTrackerDB[definition.key] = db
    if definition.Migrate then definition.Migrate(db) end
    db.position = db.position or { unpack(definition.defaultPosition) }
    db.settings = db.settings or {}
    ns.ApplyDefaults(db.settings, definition.defaults)

    zone = setmetatable({
        key = definition.key,
        name = definition.name,
        options = definition.options,
        defaultPosition = definition.defaultPosition,
        db = db,
        settings = db.settings, -- shared by every icon of the zone
        members = {},           -- trackers showing icons in the zone
    }, Zone)

    zone.group = ns.CreateIconGroup(db.position)
    zone.group.onMoved = function() ns.RefreshConfig() end
    zone.group:SetMovable(ns.unlocked)

    created[definition.key] = zone
    table.insert(ns.zones, zone)
    return zone
end

-- Called by a tracker from its Init. Its options then show on the page of
-- the zone, in the order the trackers joined.
function Zone:AddMember(tracker)
    tracker.zone = self
    table.insert(self.members, tracker)
end

-- Called by the config window after it changed settings[key]: every icon of
-- the zone reads the shared settings again, and so does every member tracker
-- that has ApplyZoneSettings(key) (zone settings about what is tracked, such
-- as the reminders' "ownOnly").
function Zone:ApplySettings(key)
    for _, icon in ipairs(self.group.icons) do
        icon:ApplySettings()
    end
    self.group:Layout()
    for _, tracker in ipairs(self.members) do
        if tracker.ApplyZoneSettings then tracker:ApplyZoneSettings(key) end
    end
end

function Zone:SetMovable(movable)
    self.group:SetMovable(movable)
end

function Zone:GetPosition()
    return self.group:GetOffset()
end

function Zone:SetPosition(x, y)
    self.group:SetOffset(x, y)
end

function Zone:ResetPosition()
    self.group:SetOffset(self.defaultPosition[3], self.defaultPosition[4])
end

-- Options shared by every zone, appended to its own: exact position and reset.
ns.ZonePositionOptions = {
    { type = "header", label = "Position (depuis le centre de l'écran)" },
    { type = "position" },
    {
        type = "button",
        label = "Réinitialiser la position",
        func = function(zone) zone:ResetPosition() end,
    },
}
