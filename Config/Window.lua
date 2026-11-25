local addonName, ns = ...

-- Config window: a standalone, draggable frame (usable in combat, and without
-- running any of our code inside Blizzard's Settings panel), built from the
-- option lists declared by the display zones and the active trackers.
--
-- The window has one page per display zone (Zones/Zone.lua): the options of
-- the trackers showing icons in it ("Contenu"), then those of the zone itself
-- (appearance, position). A tracker outside of any zone gets a page of its
-- own if it has `name` and `options`, or shares the page named by its `page`
-- field with the other trackers naming it (e.g. "Divers").
--
-- Options are described in Config/Controls.lua. Each one belongs to an owner
-- (zone or tracker): its value is read from and written to owner.db.settings,
-- and after each change owner:ApplySettings(key) is called so the change is
-- visible immediately.

local Controls = ns.Controls

local FRAME_NAME = "MarcelTrackerConfigFrame" -- global name needed by UISpecialFrames
local PADDING = 14
local CONTENT_WIDTH = 420
local LIST_WIDTH = 140
local TOP_HEIGHT = 96 -- title, lock button, page name
local MAX_SCROLL_HEIGHT = 480
local SCROLLBAR_WIDTH = 6 -- fits in the right PADDING
local MIN_THUMB_HEIGHT = 20
local DEFAULT_POSITION = { "CENTER", "CENTER", 0, 0 }

local CONTENT_HEADER = { type = "header", label = "Contenu" }

local window
local panels = {} -- page -> panel
local currentPage

-- A page lists sections: { owner = zone or tracker, options = { ... } }.
local function GetPages()
    local pages, zonePages, namedPages = {}, {}, {}
    for _, tracker in ipairs(ns.activeTrackers) do
        local zone = tracker.zone
        if zone then
            local page = zonePages[zone]
            if not page then
                page = { name = zone.name, sections = {
                    { owner = zone, options = { CONTENT_HEADER } },
                } }
                zonePages[zone] = page
                table.insert(pages, page)
            end
            if tracker.options then
                table.insert(page.sections, { owner = tracker, options = tracker.options })
            end
        elseif tracker.options and tracker.name then
            local pageName = tracker.page or tracker.name
            local page = namedPages[pageName]
            if not page then
                page = { name = pageName, sections = {} }
                namedPages[pageName] = page
                table.insert(pages, page)
            end
            table.insert(page.sections, { owner = tracker, options = tracker.options })
        end
    end

    -- The zone's own options come after the content
    for zone, page in pairs(zonePages) do
        table.insert(page.sections, { owner = zone, options = zone.options })
    end
    return pages
end

-- Gives the controls of a section access to the settings of its owner.
local function CreateContext(panel, owner)
    local settings = owner.db.settings
    local ctx = { owner = owner, settings = settings }
    function ctx.refresh()
        panel:Refresh()
    end
    function ctx.get(key)
        return settings[key]
    end
    function ctx.set(key, value)
        settings[key] = value
        owner:ApplySettings(key)
        panel:Refresh()
    end
    return ctx
end

-- Builds the option controls of a page, laid out top to bottom. Options
-- flagged `half` are packed two per row, across sections too.
local function BuildPanel(parent, page)
    local panel = CreateFrame("Frame", nil, parent)
    panel.controls = {}

    function panel:Refresh()
        for _, control in ipairs(self.controls) do
            control:Refresh()
        end
    end

    local entries = {}
    for _, section in ipairs(page.sections) do
        local ctx = CreateContext(panel, section.owner)
        for _, opt in ipairs(section.options) do
            table.insert(entries, { opt = opt, ctx = ctx })
        end
    end

    local halfWidth = CONTENT_WIDTH / 2
    local y, column = 0, 0
    for _, entry in ipairs(entries) do
        local opt, ctx = entry.opt, entry.ctx
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
        window.hint:SetText("|cff7fd4ffBarres déverrouillées|r : glissez-les\nà la souris (cadre bleu).")
    else
        window.lockButton:SetText("Déverrouiller les barres")
        window.hint:SetText("Déverrouillez pour déplacer les barres\nà la souris.")
    end
end

-- Sizes the scroll bar to the page: thumb proportional to the visible part,
-- hidden when the whole page fits.
local function UpdateScrollBar(panel)
    local bar = window.scrollBar
    local visible = window.scroll:GetHeight()
    local total = panel:GetHeight()
    local maxScroll = math.max(0, total - visible)
    bar:SetMinMaxValues(0, maxScroll)
    bar:SetValue(0)
    if maxScroll > 0 then
        bar:GetThumbTexture():SetHeight(math.max(MIN_THUMB_HEIGHT, visible * visible / total))
        bar:Show()
    else
        bar:Hide()
    end
end

local function SelectPage(page)
    Controls.ClosePopup()
    if currentPage and panels[currentPage] then
        panels[currentPage]:Hide()
    end
    currentPage = page

    local panel = panels[page]
    window.scroll:SetScrollChild(panel)
    window.scroll:SetVerticalScroll(0)
    UpdateScrollBar(panel)
    panel:Show()
    panel:Refresh()

    window.pageName:SetText(page.name)
    for _, button in ipairs(window.listButtons) do
        if button.page == page then
            button:LockHighlight()
        else
            button:UnlockHighlight()
        end
    end
end

local function CreateWindow()
    local pages = GetPages()
    local hasList = #pages > 1
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

    -- Page list, only when there is more than one
    window.listButtons = {}
    if hasList then
        for index, page in ipairs(pages) do
            local button = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
            button:SetSize(LIST_WIDTH, 22)
            button:SetPoint("TOPLEFT", PADDING, -(TOP_HEIGHT - 24) - (index - 1) * 24)
            button:SetText(page.name)
            button.page = page
            button:SetScript("OnClick", function(self) SelectPage(self.page) end)
            window.listButtons[index] = button
        end
    end

    local pageName = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    pageName:SetPoint("TOPLEFT", PADDING + listOffset, -(TOP_HEIGHT - 24))
    window.pageName = pageName

    -- Options area. Scrolls with the mouse wheel when taller than the limit.
    local scroll = CreateFrame("ScrollFrame", nil, window)
    scroll:SetPoint("TOPLEFT", PADDING + listOffset, -TOP_HEIGHT)
    scroll:SetSize(CONTENT_WIDTH, 1)
    scroll:EnableMouseWheel(true)
    window.scroll = scroll

    -- Scroll bar in the right margin, shown only on pages taller than the
    -- options area. It drives the scrolling: the wheel moves it too, and it
    -- clamps the value to the page.
    local scrollBar = CreateFrame("Slider", nil, window)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetWidth(SCROLLBAR_WIDTH)
    scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
    scrollBar:EnableMouse(true)
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:Hide()

    local track = scrollBar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(1, 1, 1, 0.08)
    local thumb = scrollBar:CreateTexture(nil, "ARTWORK")
    thumb:SetWidth(SCROLLBAR_WIDTH)
    thumb:SetColorTexture(1, 1, 1, 0.35)
    scrollBar:SetThumbTexture(thumb)

    scrollBar:SetScript("OnValueChanged", function(_, value)
        Controls.ClosePopup()
        scroll:SetVerticalScroll(value)
    end)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        scrollBar:SetValue(scrollBar:GetValue() - delta * 40)
    end)
    window.scrollBar = scrollBar

    -- Every page is built up front so the window gets a fixed size, that of
    -- the tallest page (or of the page list, if taller): switching pages
    -- must not resize it.
    local tallest = 0
    for _, page in ipairs(pages) do
        local panel = BuildPanel(scroll, page)
        panel:Hide()
        panels[page] = panel
        tallest = math.max(tallest, panel:GetHeight())
    end
    if hasList then
        -- the list starts 24px above the options area, one button every 24px
        tallest = math.max(tallest, #pages * 24 - 24)
    end
    local scrollHeight = math.min(tallest, MAX_SCROLL_HEIGHT)
    scroll:SetHeight(math.max(scrollHeight, 1))
    window:SetHeight(TOP_HEIGHT + scrollHeight + PADDING)

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

    if #pages > 0 then
        SelectPage(pages[1])
    else
        pageName:SetText("Aucun tracker disponible pour ce personnage.")
        lockButton:Disable()
    end
end

-- Refreshes what the window displays, when a value changed from outside it
-- (bar dragged, /marcel lock, /marcel reset...). No-op while it is closed.
function ns.RefreshConfig()
    if not window or not window:IsShown() then return end
    UpdateLockButton()
    if currentPage and panels[currentPage] then
        panels[currentPage]:Refresh()
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
