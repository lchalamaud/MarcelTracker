local addonName, ns = ...

-- Border of the widgets, in the style of the native frames: a thin gold bevel
-- with notched corners, whose thickness follows the size of the widget.
--
-- Drawn from our own texture (Media/Border.tga, built by
-- tools/generate_textures.py) cut in nine slices. A corner slice is twice as
-- wide as the band: its outer half is the band itself, its inner half a soft
-- shadow cast on what the border surrounds.

local BORDER_TEXTURE = "Interface\\AddOns\\" .. addonName .. "\\Media\\Border.tga"
local BORDER_SLICE = 0.25   -- a corner slice, as a fraction of the texture (8 / 32)
local THICKNESS_RATIO = 1 / 16 -- thickness of the band, as a fraction of the widget
local MIN_THICKNESS = 2     -- below that, the bevel cannot be drawn
local MAX_THICKNESS = 6

local Border = {}

-- Sizes the border for a widget whose smallest side is `size`, and returns
-- the thickness of its band. With `outside`, the band sits around the parent
-- frame; otherwise it takes the outer edge of the parent, whose content must
-- then be inset by the thickness.
function Border:Apply(size, outside)
    local thickness = math.floor(size * THICKNESS_RATIO + 0.5)
    thickness = math.max(MIN_THICKNESS, math.min(MAX_THICKNESS, thickness))

    local outset = outside and thickness or 0
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", -outset, outset)
    self:SetPoint("BOTTOMRIGHT", outset, -outset)
    self.setCornerSize(thickness * 2)
    return thickness
end

-- `levelOffset` puts the border in front of the child frames of `parent`.
function ns.CreateBorder(parent, levelOffset)
    local border = CreateFrame("Frame", nil, parent)
    border:SetFrameLevel(parent:GetFrameLevel() + (levelOffset or 1))
    border.setCornerSize = ns.CreateNineSlice(border, BORDER_TEXTURE, BORDER_SLICE, MIN_THICKNESS * 2, false)
    border.Apply = Border.Apply
    border:Apply(0)
    return border
end
