local addonName, ns = ...

-- Config window: a standalone, draggable frame (usable in combat, and without
-- running any of our code inside Blizzard's Settings panel), built from the
-- option lists declared by the active trackers.
--
-- A tracker shows up here if it has `name` and `options` (see
-- Config/Controls.lua for the option descriptors). Values are read from and
-- written to tracker.db.settings; after each change tracker:ApplySettings(key)
-- is called so the change is visible immediately.

local Controls = ns.Controls

local FRAME_NAME = "MarcelTrackerConfigFrame" -- global name needed by UISpecialFrames
local PADDING = 14
local CONTENT_WIDTH = 420
local LIST_WIDTH = 140
local TOP_HEIGHT = 96 -- title, lock button, tracker name
local MAX_SCROLL_HEIGHT = 480
local DEFAULT_POSITION = { "CENTER", "CENTER", 0, 0 }

local window
local panels = {} -- tracker -> panel
local currentTracker

local function GetConfigurableTrackers()
    local list = {}
    for _, tracker in ipairs(ns.activeTrackers) do
        if tracker.options and tracker.name then
            table.insert(list, tracker)
        end
    end
    return list
end

-- Builds the option controls of a tracker, laid out top to bottom. Options
-- flagged `half` are packed two per row.
local function BuildPanel(parent, tracker)
    local panel = CreateFrame("Frame", nil, parent)
    panel.controls = {}

    local settings = tracker.db.settings
    local ctx = { tracker = tracker, settings = settings }

    function panel:Refresh()
        for _, control in ipairs(self.controls) do
            control:Refresh()
        end
    end
    function ctx.refresh()
        panel:Refresh()
    end
    function ctx.get(key)
        return settings[key]
    end
    function ctx.set(key, value)
        settings[key] = value
        tracker:ApplySettings(key)
        panel:Refresh()
    end

    local halfWidth = CONTENT_WIDTH / 2
    local y, column = 0, 0
    for _, opt in ipairs(tracker.options) do
        local factory = Controls[opt.type]
        if factory then
            if not opt.half and column == 1 then
                -- close a row left half-filled
                y, column = y + Controls.ROW_HEIGHT, 0
            end
            local control = factory(panel, opt, ctx, opt.half and halfWidth or CONTENT_WIDTH)
            control:SetPoint("TOPLEFT", column * halfWidth, -y)
            table.insert(panel.controls, control)

            if not opt.half then
                y = y + control:GetHeight()
            elseif column == 0 then
                column = 1
            else
                y, column = y + Controls.ROW_HEIGHT, 0
            end
        end
    end
    if column == 1 then y = y + Controls.ROW_HEIGHT end

    panel:SetSize(CONTENT_WIDTH, y)
    return panel
end

local function UpdateLockButton()
    if ns.unlocked then
        window.lockButton:SetText("Verrouiller les barres")
        window.hint:SetText("|cff33ff33Barres déverrouillées|r : glissez-les\nà la souris (cadre vert).")
    else
        window.lockButton:SetText("Déverrouiller les barres")
        window.hint:SetText("Déverrouillez pour déplacer les barres\nà la souris.")
    end
end

local function SelectTracker(tracker)
    Controls.ClosePopup()
    if currentTracker and panels[currentTracker] then
        panels[currentTracker]:Hide()
    end
    currentTracker = tracker

    local panel = panels[tracker]
    if not panel then
        panel = BuildPanel(window.scroll, tracker)
        panels[tracker] = panel
    end
    window.scroll:SetScrollChild(panel)
    window.scroll:SetVerticalScroll(0)
    panel:Show()
    panel:Refresh()

    window.trackerName:SetText(tracker.name)
    for _, button in ipairs(window.listButtons) do
        if button.tracker == tracker then
            button:LockHighlight()
        else
            button:UnlockHighlight()
        end
    end

    local scrollHeight = math.min(panel:GetHeight(), MAX_SCROLL_HEIGHT)
    window.scroll:SetHeight(scrollHeight)
    window:SetHeight(TOP_HEIGHT + scrollHeight + PADDING)
end

local function CreateWindow()
    local trackers = GetConfigurableTrackers()
    local hasList = #trackers > 1
    local listOffset = hasList and (LIST_WIDTH + PADDING) or 0

    window = CreateFrame("Frame", FRAME_NAME, UIParent)
    window:SetFrameStrata("DIALOG")
    window:SetSize(CONTENT_WIDTH + PADDING * 2 + listOffset, TOP_HEIGHT + PADDING)
    window:SetClampedToScreen(true)
    window:EnableMouse(true) -- do not click through to the world
    window:Hide()

    local border = window:CreateTexture(nil, "BACKGROUND", nil, -1)
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.45, 0.45, 0.45, 1)
    local bg = window:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.06, 0.95)

    -- Window position, saved across sessions
    MarcelTrackerDB.configWindow = MarcelTrackerDB.configWindow or { unpack(DEFAULT_POSITION) }
    local pos = MarcelTrackerDB.configWindow
    window:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])

    -- Title bar, also the drag handle
    local titleBar = CreateFrame("Frame", nil, window)
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetPoint("TOPRIGHT")
    titleBar:SetHeight(28)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    window:SetMovable(true)
    titleBar:SetScript("OnDragStart", function() window:StartMoving() end)
    titleBar:SetScript("OnDragStop", function()
        window:StopMovingOrSizing()
        local point, _, relativePoint, x, y = window:GetPoint()
        pos[1], pos[2], pos[3], pos[4] = point, relativePoint, x, y
    end)

    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND", nil, 1)
    titleBg:SetAllPoints()
    titleBg:SetColorTexture(1, 1, 1, 0.06)

    local title = titleBar:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", PADDING, 0)
    title:SetText("MarcelTracker")

    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() window:Hide() end)

    -- Lock / unlock, shared by every tracker
    local lockButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    lockButton:SetSize(180, 24)
    lockButton:SetPoint("TOPLEFT", PADDING, -36)
    lockButton:SetScript("OnClick", function()
        ns.SetUnlocked(not ns.unlocked)
    end)
    window.lockButton = lockButton

    local hint = window:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", lockButton, "RIGHT", 10, 0)
    hint:SetPoint("RIGHT", window, "RIGHT", -PADDING, 0)
    hint:SetJustifyH("LEFT")
    window.hint = hint

    -- Tracker list, only when there is more than one
    window.listButtons = {}
    if hasList then
        for index, tracker in ipairs(trackers) do
            local button = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
            button:SetSize(LIST_WIDTH, 22)
            button:SetPoint("TOPLEFT", PADDING, -(TOP_HEIGHT - 24) - (index - 1) * 24)
            button:SetText(tracker.name)
            button.tracker = tracker
            button:SetScript("OnClick", function(self) SelectTracker(self.tracker) end)
            window.listButtons[index] = button
        end
    end

    local trackerName = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    trackerName:SetPoint("TOPLEFT", PADDING + listOffset, -(TOP_HEIGHT - 24))
    window.trackerName = trackerName

    -- Options area. Scrolls with the mouse wheel when taller than the limit.
    local scroll = CreateFrame("ScrollFrame", nil, window)
    scroll:SetPoint("TOPLEFT", PADDING + listOffset, -TOP_HEIGHT)
    scroll:SetSize(CONTENT_WIDTH, 1)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local child = self:GetScrollChild()
        if not child then return end
        local maxScroll = math.max(0, child:GetHeight() - self:GetHeight())
        local value = math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 40))
        Controls.ClosePopup()
        self:SetVerticalScroll(value)
    end)
    window.scroll = scroll

    -- While the window is open the trackers show an example of themselves.
    -- Closing it ends the preview and locks the bars where they are.
    window:SetScript("OnShow", function()
        ns.SetPreview(true)
    end)
    window:SetScript("OnHide", function()
        Controls.ClosePopup()
        ns.SetPreview(false)
        if ns.unlocked then
            ns.SetUnlocked(false)
            ns.Print("barres verrouillées.")
        end
    end)

    -- Close with Escape
    table.insert(UISpecialFrames, FRAME_NAME)

    if #trackers > 0 then
        SelectTracker(trackers[1])
    else
        trackerName:SetText("Aucun tracker disponible pour ce personnage.")
        lockButton:Disable()
    end
end

-- Refreshes what the window displays, when a value changed from outside it
-- (bar dragged, /marcel lock, /marcel reset...). No-op while it is closed.
function ns.RefreshConfig()
    if not window or not window:IsShown() then return end
    UpdateLockButton()
    if currentTracker and panels[currentTracker] then
        panels[currentTracker]:Refresh()
    end
end

function ns.OpenConfig()
    if not window then CreateWindow() end
    window:Show()
    window:Raise()
    ns.RefreshConfig()
end

function ns.ToggleConfig()
    if window and window:IsShown() then
        window:Hide()
    else
        ns.OpenConfig()
    end
end

-- Entry in Blizzard's Options > AddOns: only a button opening our own window,
-- to keep the surface shared with Blizzard's panel (and the taint risk that
-- comes with it) as small as possible.
local function RegisterBlizzardLink()
    local hasSettings = Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory
    if not hasSettings and not InterfaceOptions_AddCategory then return end

    local panel = CreateFrame("Frame")
    panel.name = "MarcelTracker"
    -- Callbacks the Settings panel may call on canvas frames
    panel.OnCommit = function() end
    panel.OnDefault = function() end
    panel.OnRefresh = function() end

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("MarcelTracker")

    local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    text:SetJustifyH("LEFT")
    text:SetText("La configuration s'ouvre dans sa propre fenêtre,\nutilisable aussi en combat. Commande : /marcel config")

    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(200, 24)
    button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)
    button:SetText("Ouvrir la configuration")
    button:SetScript("OnClick", ns.OpenConfig)

    if hasSettings then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    else
        InterfaceOptions_AddCategory(panel)
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    RegisterBlizzardLink()
end)
