local addonName, ns = ...

local MT = CreateFrame("Frame")
ns.MT = MT

local defaults = {}

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MarcelTracker|r: " .. tostring(msg))
end
ns.Print = Print

-- Debug mode (/marcel debug, not saved): trackers report in the chat what
-- they receive, to find out what the client lets us read in combat.
ns.debug = false

local issecret = issecretvalue or function() return false end

-- A value as text for a debug message, without touching a secret one.
function ns.DebugValue(value)
    if issecret(value) then return "<secret>" end
    return tostring(value)
end

-- Prints its arguments, turned into text with ns.DebugValue, while in debug mode.
function ns.Debug(...)
    if not ns.debug then return end
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = ns.DebugValue((select(i, ...)))
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff999999MarcelTracker debug|r " .. table.concat(parts, " "))
end

-- Tracker registry. Each tracker is a table with:
--   key              unique string, also the name of its SavedVariables sub-table
--   ShouldLoad()     optional, return false to skip this tracker (wrong class...)
--   Init(db)         called once at PLAYER_LOGIN with its own sub-table of
--                    MarcelTrackerDB; must keep it as self.db
--   SetUnlocked(b)   optional, show/hide a draggable preview
--   SetPreview(b)    optional, show an example while the config window is open
--   ResetPosition()  optional
--   zone             optional, set in Init: the display zone (Zones/Zone.lua)
--                    the tracker shows its icons in. The zone owns their
--                    position and appearance, and the config window shows the
--                    tracker's options on the page of its zone.
-- To appear in the config window (Config/Window.lua), a tracker also has:
--   name             display name
--   page             optional, for a tracker outside of any zone: name of a
--                    page shared with other such trackers (e.g. "Divers"),
--                    instead of a page of its own
--   defaults         default values, merged into db.settings before Init
--   options          list of option descriptors (see Config/Controls.lua)
--   ApplySettings(key)  re-read db.settings after a change (key may be nil)
--   GetPosition() / SetPosition(x, y)  if it declares a "position" option
ns.trackers = {}
ns.activeTrackers = {}
ns.zones = {} -- display zones in use, see Zones/Zone.lua
ns.unlocked = false

function ns.RegisterTracker(tracker)
    table.insert(ns.trackers, tracker)
end

local function CopyValue(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = CopyValue(v) end
    return copy
end

-- Fills the missing (or wrongly typed) keys of `target` from `source`, without
-- touching the values already saved.
local function ApplyDefaults(target, source)
    for key, default in pairs(source) do
        if type(target[key]) ~= type(default) then
            target[key] = CopyValue(default)
        elseif type(default) == "table" then
            ApplyDefaults(target[key], default)
        end
    end
end
ns.ApplyDefaults = ApplyDefaults

local function InitTrackers()
    for _, tracker in ipairs(ns.trackers) do
        if not tracker.ShouldLoad or tracker:ShouldLoad() then
            local db = MarcelTrackerDB[tracker.key] or {}
            MarcelTrackerDB[tracker.key] = db
            db.settings = db.settings or {}
            if tracker.defaults then ApplyDefaults(db.settings, tracker.defaults) end
            tracker:Init(db)
            table.insert(ns.activeTrackers, tracker)
        end
    end
end

local function ForEachActive(method, ...)
    local count = 0
    for _, tracker in ipairs(ns.activeTrackers) do
        if tracker[method] then
            tracker[method](tracker, ...)
            count = count + 1
        end
    end
    return count
end

local function RefreshConfig()
    if ns.RefreshConfig then ns.RefreshConfig() end
end

-- Unlocked: every tracker shows a preview, and every bar or zone can be
-- dragged around.
function ns.SetUnlocked(unlocked)
    ns.unlocked = unlocked and true or false
    for _, zone in ipairs(ns.zones) do zone:SetMovable(ns.unlocked) end
    ForEachActive("SetUnlocked", ns.unlocked)
    RefreshConfig()
end

-- Preview: every tracker shows an example of itself, even with nothing to
-- track, so that settings can be judged live. On while the config is open.
function ns.SetPreview(preview)
    ns.preview = preview and true or false
    ForEachActive("SetPreview", ns.preview)
end

function ns.ResetPositions()
    for _, zone in ipairs(ns.zones) do zone:ResetPosition() end
    ForEachActive("ResetPosition")
    RefreshConfig()
end

MT:RegisterEvent("ADDON_LOADED")
MT:RegisterEvent("PLAYER_LOGIN")
MT:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= addonName then return end
        MarcelTrackerDB = MarcelTrackerDB or {}
        for k, v in pairs(defaults) do
            if MarcelTrackerDB[k] == nil then MarcelTrackerDB[k] = v end
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        InitTrackers()
        self:UnregisterEvent("PLAYER_LOGIN")
        Print("chargé. Tapez /marcel pour l'aide.")
    end
end)

local function PrintHelp()
    Print("version " .. (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(addonName, "Version"))
    Print("/marcel config - ouvrir la fenêtre de configuration")
    Print("/marcel unlock - déverrouiller les barres pour les déplacer")
    Print("/marcel lock - verrouiller les barres")
    Print("/marcel reset - remettre les barres à leur position par défaut")
    Print("/marcel debug - afficher dans le chat ce que l'addon détecte (diagnostic)")
end

SLASH_MARCELTRACKER1 = "/marcel"
SLASH_MARCELTRACKER2 = "/marceltracker"
SlashCmdList.MARCELTRACKER = function(msg)
    local cmd = strtrim(msg or ""):lower()
    if cmd == "config" then
        ns.ToggleConfig()
    elseif cmd == "debug" then
        ns.debug = not ns.debug
        Print(ns.debug and "diagnostic activé." or "diagnostic désactivé.")
    elseif cmd == "unlock" or cmd == "lock" or cmd == "reset" then
        if #ns.activeTrackers == 0 then
            Print("aucun tracker actif pour ce personnage.")
            return
        end
        if cmd == "unlock" then
            ns.SetUnlocked(true)
            Print("barres déverrouillées : glissez-les pour les déplacer, puis /marcel lock.")
        elseif cmd == "lock" then
            ns.SetUnlocked(false)
            Print("barres verrouillées.")
        else
            ns.ResetPositions()
            Print("positions réinitialisées.")
        end
    else
        PrintHelp()
    end
end
