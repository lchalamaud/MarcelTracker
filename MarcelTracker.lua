local addonName, ns = ...

local MT = CreateFrame("Frame")
ns.MT = MT

local defaults = {}

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MarcelTracker|r: " .. tostring(msg))
end
ns.Print = Print

-- Tracker registry. Each tracker is a table with:
--   key              unique string, also the name of its SavedVariables sub-table
--   ShouldLoad()     optional, return false to skip this tracker (wrong class...)
--   Init(db)         called once at PLAYER_LOGIN with its own sub-table of
--                    MarcelTrackerDB; must keep it as self.db
--   SetUnlocked(b)   optional, show/hide a draggable preview
--   SetPreview(b)    optional, show an example while the config window is open
--   ResetPosition()  optional
-- To appear in the config window (Config/Window.lua), a tracker also has:
--   name             display name
--   defaults         default values, merged into db.settings before Init
--   options          list of option descriptors (see Config/Controls.lua)
--   ApplySettings(key)  re-read db.settings after a change (key may be nil)
--   GetPosition() / SetPosition(x, y)  if it declares a "position" option
ns.trackers = {}
ns.activeTrackers = {}
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

-- Unlocked: every tracker shows a preview that can be dragged around.
function ns.SetUnlocked(unlocked)
    ns.unlocked = unlocked and true or false
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
end

SLASH_MARCELTRACKER1 = "/marcel"
SLASH_MARCELTRACKER2 = "/marceltracker"
SlashCmdList.MARCELTRACKER = function(msg)
    local cmd = strtrim(msg or ""):lower()
    if cmd == "config" then
        ns.ToggleConfig()
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
