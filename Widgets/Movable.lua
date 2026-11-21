local addonName, ns = ...

-- Shared by the widgets that can be placed on screen (timer bar, alert icon):
-- saved position, X/Y offsets, dragging and the highlight shown while unlocked.
--
-- ns.Movable is a set of methods to copy into a widget class. The widget must
-- have:
--   self.anchor         the frame that is positioned and dragged
--   self.moveHighlight  from ns.CreateMoveHighlight(anchor)
--   self.onMoved        optional, called after each drag

local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"

local function Round(value)
    return math.floor(value + 0.5)
end

-- Highlight shown over a widget while it can be dragged, in the style of
-- Blizzard's Edit Mode: a thin light-blue rounded border and a translucent
-- blue veil in front of the widget.
--
-- Drawn from our own texture (Media/MoveHighlight.tga, a 32x32 rounded
-- rectangle built by tools/generate_textures.py) cut in nine slices (see
-- Widgets/NineSlice.lua), with 8px corners.
local HIGHLIGHT_TEXTURE = MEDIA .. "MoveHighlight.tga"
local HIGHLIGHT_CORNER = 8  -- size of a corner slice, on screen
local HIGHLIGHT_SLICE = 0.25 -- same, as a fraction of the texture (8 / 32)
local HIGHLIGHT_OUTSET = 2  -- the border sits just outside of the widget

function ns.CreateMoveHighlight(anchor)
    local highlight = CreateFrame("Frame", nil, anchor)
    highlight:SetPoint("TOPLEFT", -HIGHLIGHT_OUTSET, HIGHLIGHT_OUTSET)
    highlight:SetPoint("BOTTOMRIGHT", HIGHLIGHT_OUTSET, -HIGHLIGHT_OUTSET)
    highlight:SetFrameLevel(anchor:GetFrameLevel() + 10) -- in front of the widget
    highlight:Hide()

    ns.CreateNineSlice(highlight, HIGHLIGHT_TEXTURE, HIGHLIGHT_SLICE, HIGHLIGHT_CORNER)
    return highlight
end

local Movable = {}
ns.Movable = Movable

-- Position handling. `pos` is a saved table { point, relativePoint, x, y }
-- that the widget keeps a reference to and updates in place. Offsets are stored in
-- UIParent units, so changing the scale does not move the widget.
--
-- The canonical form is { "CENTER", "CENTER", x, y } (offset of the bar's
-- centre from the centre of the screen), which is what makes X/Y editable.
-- Positions saved by older versions used whatever anchor the drag ended on:
-- they are converted here, without moving the bar.
function Movable:AttachPosition(pos)
    self.position = pos
    self:ApplyPosition()
    if pos[1] ~= "CENTER" or pos[2] ~= "CENTER" then
        self:CapturePosition()
    end
end

function Movable:ApplyPosition()
    local pos, scale = self.position, self.anchor:GetScale()
    self.anchor:ClearAllPoints()
    self.anchor:SetPoint(pos[1], UIParent, pos[2], pos[3] / scale, pos[4] / scale)
end

-- Rewrites the saved position in canonical form from where the bar currently
-- is on screen. Returns false if the layout is not resolved yet.
function Movable:CapturePosition()
    local anchor = self.anchor
    local x, y = anchor:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if not x or not parentX then return false end

    local scale = anchor:GetScale()
    local pos = self.position
    pos[1], pos[2] = "CENTER", "CENTER"
    pos[3], pos[4] = Round(x * scale - parentX), Round(y * scale - parentY)
    self:ApplyPosition()
    return true
end

-- Offset of the bar's centre from the centre of the screen.
function Movable:GetOffset()
    return self.position[3], self.position[4]
end

function Movable:SetOffset(x, y)
    local pos = self.position
    pos[1], pos[2], pos[3], pos[4] = "CENTER", "CENTER", x, y
    self:ApplyPosition()
end

-- While movable, the bar can be dragged (and shows an Edit Mode style highlight); `onMoved` is called after each drag.
function Movable:SetMovable(movable)
    local anchor = self.anchor
    anchor:SetMovable(movable)
    anchor:EnableMouse(movable)
    self.moveHighlight:SetShown(movable)
    if movable then
        anchor:RegisterForDrag("LeftButton")
        anchor:SetScript("OnDragStart", anchor.StartMoving)
        anchor:SetScript("OnDragStop", function(f)
            f:StopMovingOrSizing()
            if not self:CapturePosition() then
                local scale = f:GetScale()
                local point, _, relativePoint, x, y = f:GetPoint()
                local pos = self.position
                pos[1], pos[2], pos[3], pos[4] = point, relativePoint, x * scale, y * scale
            end
            if self.onMoved then self.onMoved() end
        end)
    else
        anchor:RegisterForDrag()
        anchor:SetScript("OnDragStart", nil)
        anchor:SetScript("OnDragStop", nil)
    end
end
