local addonName, ns = ...

-- Draws a square texture cut in nine slices over a whole frame: the corners
-- keep their shape, the edges and the centre stretch. Used by the move
-- highlight (Widgets/Movable.lua) and the border (Widgets/Border.lua).
--
--   texture     file of a square texture
--   slice       size of a corner slice, as a fraction of the texture
--   cornerSize  size of a corner slice on screen (can be changed later)
--   hasCentre   false to leave the centre empty (a border)
--
-- Returns a function(size) that resizes the corners, hence the edges.
function ns.CreateNineSlice(frame, texture, slice, cornerSize, hasCentre)
    local a, b = slice, 1 - slice
    local function Piece(left, right, top, bottom)
        local piece = frame:CreateTexture(nil, "OVERLAY")
        piece:SetTexture(texture)
        piece:SetTexCoord(left, right, top, bottom)
        return piece
    end

    local topLeft, topRight = Piece(0, a, 0, a), Piece(b, 1, 0, a)
    local bottomLeft, bottomRight = Piece(0, a, b, 1), Piece(b, 1, b, 1)
    topLeft:SetPoint("TOPLEFT")
    topRight:SetPoint("TOPRIGHT")
    bottomLeft:SetPoint("BOTTOMLEFT")
    bottomRight:SetPoint("BOTTOMRIGHT")
    local corners = { topLeft, topRight, bottomLeft, bottomRight }

    local function Between(piece, from, fromPoint, to, toPoint)
        piece:SetPoint("TOPLEFT", from, fromPoint)
        piece:SetPoint("BOTTOMRIGHT", to, toPoint)
    end
    Between(Piece(a, b, 0, a), topLeft, "TOPRIGHT", topRight, "BOTTOMLEFT")          -- top
    Between(Piece(a, b, b, 1), bottomLeft, "TOPRIGHT", bottomRight, "BOTTOMLEFT")    -- bottom
    Between(Piece(0, a, a, b), topLeft, "BOTTOMLEFT", bottomLeft, "TOPRIGHT")        -- left
    Between(Piece(b, 1, a, b), topRight, "BOTTOMLEFT", bottomRight, "TOPRIGHT")      -- right
    if hasCentre ~= false then
        Between(Piece(a, b, a, b), topLeft, "BOTTOMRIGHT", bottomRight, "TOPLEFT")
    end

    local function SetCornerSize(size)
        for _, corner in ipairs(corners) do
            corner:SetSize(size, size)
        end
    end
    SetCornerSize(cornerSize)
    return SetCornerSize
end
