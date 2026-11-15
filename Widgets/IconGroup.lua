local addonName, ns = ...

-- Icon group: a row of alert icons (Widgets/AlertIcon.lua) sharing one saved
-- position. Only the icons currently shown take room: they sit side by side,
-- in the order they joined the group, and the row is centred on the position
-- of the group. Each icon keeps its own size and opacity.
--
-- The group is what is moved (drag and drop while unlocked, X/Y offsets), see
-- Widgets/Movable.lua.

local SPACING = 6 -- gap between two icons

local IconGroup = {}
IconGroup.__index = IconGroup

for name, method in pairs(ns.Movable) do
    IconGroup[name] = method
end

-- `position` is the saved table { point, relativePoint, x, y } of the group.
function ns.CreateIconGroup(position)
    local self = setmetatable({ icons = {}, movable = false }, IconGroup)

    local anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetClampedToScreen(true)
    anchor:SetSize(1, 1)
    anchor:SetPoint("CENTER")
    self.anchor = anchor

    self.moveHighlight = ns.CreateMoveHighlight(anchor)
    self:AttachPosition(position)
    return self
end

-- Called by ns.CreateAlertIcon for an icon created with this group.
function IconGroup:Add(icon)
    table.insert(self.icons, icon)
    self:Layout()
end

-- Places the shown icons in a row and sizes the group around them. The group
-- is anchored by its centre, so the row stays centred as icons come and go.
function IconGroup:Layout()
    local width, height, count = 0, 0, 0
    for _, icon in ipairs(self.icons) do
        if icon:IsShown() then
            local size = icon:GetSize()
            width = width + size
            height = math.max(height, size)
            count = count + 1
        end
    end
    width = width + SPACING * math.max(0, count - 1)
    self.anchor:SetSize(math.max(1, width), math.max(1, height))

    local x = 0
    for _, icon in ipairs(self.icons) do
        if icon:IsShown() then
            icon.anchor:ClearAllPoints()
            icon.anchor:SetPoint("LEFT", self.anchor, "LEFT", x, 0)
            x = x + icon:GetSize() + SPACING
            icon:UpdateShake() -- restarted together, so the icons sway in sync
        end
    end

    self.moveHighlight:SetShown(self.movable and count > 0)
end

function IconGroup:SetMovable(movable)
    self.movable = movable and true or false
    ns.Movable.SetMovable(self, self.movable)
    self:Layout()
end

function IconGroup:ResetPosition()
    local default = self.defaultPosition
    self:SetOffset(default[3], default[4])
end

-- The reminder group: the icons telling that a buff is missing (paladin aura,
-- blessing...). Created on first use, once SavedVariables are loaded.
--
-- `legacyPosition` is optional: a position saved by a tracker from before the
-- group existed, used if the group has none yet.

local REMINDER_DEFAULT_POSITION = { "CENTER", "CENTER", 0, 120 }
local reminderGroup

function ns.GetReminderGroup(legacyPosition)
    if not reminderGroup then
        local db = MarcelTrackerDB.reminderGroup or {}
        MarcelTrackerDB.reminderGroup = db
        db.position = db.position or legacyPosition or { unpack(REMINDER_DEFAULT_POSITION) }

        reminderGroup = ns.CreateIconGroup(db.position)
        reminderGroup.defaultPosition = REMINDER_DEFAULT_POSITION
        reminderGroup.onMoved = function() ns.RefreshConfig() end
    end
    return reminderGroup
end

-- Option descriptors for the config window (see Config/Controls.lua), for a
-- tracker whose GetPosition / SetPosition / ResetPosition go to the group.
ns.ReminderGroupOptions = {
    { type = "header", label = "Position du groupe de rappels (commune)" },
    { type = "position" },
    {
        type = "button",
        label = "Réinitialiser la position",
        func = function(tracker) tracker:ResetPosition() end,
    },
}
