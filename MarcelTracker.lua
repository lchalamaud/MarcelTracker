local addonName, ns = ...

local MT = CreateFrame("Frame")
ns.MT = MT

local defaults = {}

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MarcelTracker|r: " .. tostring(msg))
end
ns.Print = Print

MT:RegisterEvent("ADDON_LOADED")
MT:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= addonName then return end
        MarcelTrackerDB = MarcelTrackerDB or {}
        for k, v in pairs(defaults) do
            if MarcelTrackerDB[k] == nil then MarcelTrackerDB[k] = v end
        end
        self:UnregisterEvent("ADDON_LOADED")
        Print("chargé. Tapez /mt pour l'aide.")
    end
end)

SLASH_MARCELTRACKER1 = "/mt"
SLASH_MARCELTRACKER2 = "/marceltracker"
SlashCmdList.MARCELTRACKER = function(msg)
    Print("version " .. (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(addonName, "Version"))
end
