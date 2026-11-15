local addonName, ns = ...

local MT = CreateFrame("Frame")
ns.MT = MT

local defaults = {}

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MarcelTracker|r: " .. tostring(msg))
end
ns.Print = Print

-- Tracker registry. Each tracker is a table with:
--   key            unique string, also the name of its SavedVariables sub-table
--   ShouldLoad()   optional, return false to skip this tracker (wrong class...)
--   Init(db)       called once at PLAYER_LOGIN with its own sub-table of MarcelTrackerDB
--   SetUnlocked(b) optional, show/hide a draggable preview
--   ResetPosition() optional
ns.trackers = {}
ns.activeTrackers = {}

function ns.RegisterTracker(tracker)
    table.insert(ns.trackers, tracker)
end

local function InitTrackers()
    for _, tracker in ipairs(ns.trackers) do
        if not tracker.ShouldLoad or tracker:ShouldLoad() then
            MarcelTrackerDB[tracker.key] = MarcelTrackerDB[tracker.key] or {}
            tracker:Init(MarcelTrackerDB[tracker.key])
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
    Print("/marcel unlock - déverrouiller les barres pour les déplacer")
    Print("/marcel lock - verrouiller les barres")
    Print("/marcel reset - remettre les barres à leur position par défaut")
end

SLASH_MARCELTRACKER1 = "/marcel"
SLASH_MARCELTRACKER2 = "/marceltracker"
SlashCmdList.MARCELTRACKER = function(msg)
    local cmd = strtrim(msg or ""):lower()
    if cmd == "unlock" or cmd == "lock" or cmd == "reset" then
        if #ns.activeTrackers == 0 then
            Print("aucun tracker actif pour ce personnage.")
            return
        end
        if cmd == "unlock" then
            ForEachActive("SetUnlocked", true)
            Print("barres déverrouillées : glissez-les pour les déplacer, puis /marcel lock.")
        elseif cmd == "lock" then
            ForEachActive("SetUnlocked", false)
            Print("barres verrouillées.")
        else
            ForEachActive("ResetPosition")
            Print("positions réinitialisées.")
        end
    else
        PrintHelp()
    end
end
