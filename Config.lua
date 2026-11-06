-- Config.lua -- Configuration defaults and SavedVariables management for MyQuestPlates.
local ADDON, NS = ...

NS.defaultConfig = {
    enabled             = true,
    iconSize            = 24,
    anchorPoint         = "LEFT",     -- "LEFT", "RIGHT", "TOP", "TOPLEFT", "TOPRIGHT"
    xOffset             = 8,
    yOffset             = 0,
    showProgressText    = true,
    fontSize            = 10,
    showOnlyIncomplete  = true,
    showSlay            = true,
    showLoot            = true,
    showTalk            = true,
    preferQuestie       = true,
    testMode            = false,
}

function NS.InitDB()
    if type(_G.MyQuestPlatesDB) ~= "table" then
        _G.MyQuestPlatesDB = {}
    end

    -- Fill in any missing default settings
    for key, val in pairs(NS.defaultConfig) do
        if _G.MyQuestPlatesDB[key] == nil then
            _G.MyQuestPlatesDB[key] = val
        end
    end

    NS.db = _G.MyQuestPlatesDB
end
