-- Options.lua -- Configuration panel, sliders, checkboxes, and slash commands for MyQuestPlates.
local ADDON, NS = ...
local C = NS.C

local configWin = nil
local checks = {}
local sliders = {}
local isRefreshingUI = false

-- ---------------------------------------------------------------------------
-- UI Helpers
-- ---------------------------------------------------------------------------
local function CreateHeader(parent, text, x, y, width)
    local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", x, y)
    h:SetText(text)
    h:SetTextColor(1, 0.82, 0)

    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.3)
    line:SetPoint("TOPLEFT", x, y - 16)
    line:SetSize(width or 440, 1)
    return h
end

local function MakeCheck(parent, key, label, x, y, getter, setter)
    local cb = CreateFrame("CheckButton", "MyQuestPlatesCfg_" .. key, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb:SetSize(26, 26)

    local text = _G[cb:GetName() .. "Text"] or cb.text or cb.Text
    if not text then
        text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    end
    text:SetText(label)
    if text.SetFontObject then text:SetFontObject("GameFontHighlight") end

    cb.key = key
    cb.getter = getter
    cb.setter = setter

    cb:SetScript("OnClick", function(self)
        local val = self:GetChecked() and true or false
        setter(val)
        if NS.UpdateAllNameplates then NS.UpdateAllNameplates() end
    end)

    table.insert(checks, cb)
    return cb
end

local function MakeSlider(parent, key, label, minVal, maxVal, step, x, y, getter, setter, fmt)
    local s = CreateFrame("Slider", "MyQuestPlatesCfg_" .. key, parent, "OptionsSliderTemplate")
    s:SetWidth(190)
    s:SetHeight(16)
    s:SetPoint("TOPLEFT", x, y)
    s:SetMinMaxValues(minVal, maxVal)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end

    local low = _G[s:GetName() .. "Low"] or s.Low
    if low then low:SetText(tostring(minVal)) end

    local high = _G[s:GetName() .. "High"] or s.High
    if high then high:SetText(tostring(maxVal)) end

    local titleFS = _G[s:GetName() .. "Text"] or s.Text
    if not titleFS then
        titleFS = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        titleFS:SetPoint("BOTTOM", s, "TOP", 0, 3)
    end
    s.titleFS = titleFS

    s.key = key
    s.label = label
    s.step = step
    s.fmt = fmt
    s.getter = getter
    s.setter = setter

    s:SetScript("OnValueChanged", function(self, val)
        if isRefreshingUI then return end
        val = math.floor(val / self.step + 0.5) * self.step
        self.setter(val)
        local display = self.fmt and self.fmt(val) or tostring(val)
        if self.titleFS then
            self.titleFS:SetText(self.label .. ": " .. display)
        end
        if NS.RefreshAllPlatePositions then NS.RefreshAllPlatePositions() end
        if NS.UpdateAllNameplates then NS.UpdateAllNameplates() end
    end)

    table.insert(sliders, s)
    return s
end

-- ---------------------------------------------------------------------------
-- Anchor Position Selector
-- ---------------------------------------------------------------------------
local anchorButtons = {}
local ANCHOR_OPTIONS = {
    { key = "LEFT",     label = "Left" },
    { key = "RIGHT",    label = "Right" },
    { key = "TOP",      label = "Above" },
    { key = "TOPLEFT",  label = "Top Left" },
    { key = "TOPRIGHT", label = "Top Right" },
}

local function UpdateAnchorButtons()
    local current = (NS.db and NS.db.anchorPoint) or "LEFT"
    for _, btn in ipairs(anchorButtons) do
        local fs = btn:GetFontString()
        if btn.anchorKey == current then
            btn:LockHighlight()
            if fs then fs:SetTextColor(1, 0.82, 0) end
        else
            btn:UnlockHighlight()
            if fs then fs:SetTextColor(1, 1, 1) end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Refresh UI Values
-- ---------------------------------------------------------------------------
local function RefreshConfigUI()
    if not NS.db then
        if NS.InitDB then NS.InitDB() end
    end
    if not NS.db then return end

    isRefreshingUI = true

    for _, cb in ipairs(checks) do
        if cb.getter then
            cb:SetChecked(cb.getter() and true or false)
        end
    end

    for _, s in ipairs(sliders) do
        if s.getter then
            local val = s.getter() or 0
            s:SetValue(val)
            local display = s.fmt and s.fmt(val) or tostring(val)
            if s.titleFS then
                s.titleFS:SetText(s.label .. ": " .. display)
            end
        end
    end

    UpdateAnchorButtons()
    isRefreshingUI = false
end

-- ---------------------------------------------------------------------------
-- Build Standalone Configuration Window
-- ---------------------------------------------------------------------------
function NS.CreateConfigWindow()
    if configWin then return configWin end

    if not NS.db then
        if NS.InitDB then NS.InitDB() end
    end

    local win = CreateFrame("Frame", "MyQuestPlatesConfigWindow", UIParent, "BackdropTemplate")
    win:SetSize(490, 560)
    win:SetPoint("CENTER", 0, 30)
    win:SetFrameStrata("DIALOG")
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetClampedToScreen(true)

    if win.SetBackdrop then
        win:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile     = true, tileSize = 32, edgeSize = 32,
            insets   = { left = 8, right = 8, top = 8, bottom = 8 }
        })
    else
        local bg = win:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.08, 0.08, 0.08, 0.95)
    end

    -- Title
    local title = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", 24, -20)
    title:SetText("|cffffd100MyQuestPlates|r")

    local subtitle = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("TOPLEFT", 24, -40)
    subtitle:SetText("v1.0.0 -- Quest icons & progress on default nameplates")

    -- Close Button
    local closeBtn = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -8, -8)
    closeBtn:SetScript("OnClick", function() win:Hide() end)

    -- Section 1: General Options
    CreateHeader(win, "General Settings", 24, -68, 440)

    MakeCheck(win, "enabled", "Enable MyQuestPlates", 24, -94,
        function() return NS.db and NS.db.enabled end,
        function(v) if NS.db then NS.db.enabled = v end end)

    MakeCheck(win, "incompleteOnly", "Show only incomplete objectives", 240, -94,
        function() return NS.db and NS.db.showOnlyIncomplete end,
        function(v) if NS.db then NS.db.showOnlyIncomplete = v end end)

    MakeCheck(win, "showProgress", "Show progress count (e.g. 3/8)", 24, -122,
        function() return NS.db and NS.db.showProgressText end,
        function(v) if NS.db then NS.db.showProgressText = v end end)

    -- Section 2: Objective Types
    CreateHeader(win, "Objective Types & Synergy", 24, -158, 440)

    MakeCheck(win, "showSlay", "Show Kill / Slay icons (Sword)", 24, -184,
        function() return NS.db and NS.db.showSlay end,
        function(v) if NS.db then NS.db.showSlay = v end end)

    MakeCheck(win, "showLoot", "Show Loot / Pickup icons (Bag)", 240, -184,
        function() return NS.db and NS.db.showLoot end,
        function(v) if NS.db then NS.db.showLoot = v end end)

    MakeCheck(win, "showTalk", "Show Talk / Interact icons", 24, -212,
        function() return NS.db and NS.db.showTalk end,
        function(v) if NS.db then NS.db.showTalk = v end end)

    MakeCheck(win, "preferQuestie", "Use Questie data & icons if loaded", 240, -212,
        function() return NS.db and NS.db.preferQuestie end,
        function(v) if NS.db then NS.db.preferQuestie = v end end)

    -- Section 3: Positioning & Layout
    CreateHeader(win, "Nameplate Icon Positioning", 24, -248, 440)

    local anchorLabel = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    anchorLabel:SetPoint("TOPLEFT", 24, -274)
    anchorLabel:SetText("Anchor Position:")

    local startX = 24
    for i, opt in ipairs(ANCHOR_OPTIONS) do
        local btn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        btn:SetSize(78, 22)
        btn:SetPoint("TOPLEFT", startX + ((i - 1) * 84), -296)
        btn:SetText(opt.label)
        btn.anchorKey = opt.key

        btn:SetScript("OnClick", function(self)
            if NS.db then NS.db.anchorPoint = self.anchorKey end
            UpdateAnchorButtons()
            if NS.RefreshAllPlatePositions then NS.RefreshAllPlatePositions() end
            if NS.UpdateAllNameplates then NS.UpdateAllNameplates() end
        end)

        table.insert(anchorButtons, btn)
    end

    -- Sliders
    MakeSlider(win, "iconSize", "Icon Size", 16, 48, 1, 24, -340,
        function() return NS.db and NS.db.iconSize end,
        function(v) if NS.db then NS.db.iconSize = v end end,
        function(v) return string.format("%d px", v) end)

    MakeSlider(win, "fontSize", "Text Size", 8, 20, 1, 240, -340,
        function() return NS.db and NS.db.fontSize end,
        function(v) if NS.db then NS.db.fontSize = v end end,
        function(v) return string.format("%d pt", v) end)

    MakeSlider(win, "xOffset", "Horizontal Offset (X)", -50, 50, 1, 24, -395,
        function() return NS.db and NS.db.xOffset end,
        function(v) if NS.db then NS.db.xOffset = v end end,
        function(v) return string.format("%d px", v) end)

    MakeSlider(win, "yOffset", "Vertical Offset (Y)", -50, 50, 1, 240, -395,
        function() return NS.db and NS.db.yOffset end,
        function(v) if NS.db then NS.db.yOffset = v end end,
        function(v) return string.format("%d px", v) end)

    -- Section 4: Testing & Presets
    CreateHeader(win, "Preview & Maintenance", 24, -440, 440)

    local testBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    testBtn:SetSize(130, 24)
    testBtn:SetPoint("TOPLEFT", 24, -468)
    testBtn:SetText((NS.db and NS.db.testMode) and "Disable Test Mode" or "Enable Test Mode")
    testBtn:SetScript("OnClick", function(self)
        if not NS.db then return end
        NS.db.testMode = not NS.db.testMode
        self:SetText(NS.db.testMode and "Disable Test Mode" or "Enable Test Mode")
        if NS.UpdateAllNameplates then NS.UpdateAllNameplates() end
        print("|cffffd100MyQuestPlates:|r Test mode " .. (NS.db.testMode and "|cff00ff00enabled|r" or "|cffff0000disabled|r") .. ".")
    end)

    local resetBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    resetBtn:SetSize(110, 24)
    resetBtn:SetPoint("TOPLEFT", 164, -468)
    resetBtn:SetText("Reset Defaults")
    resetBtn:SetScript("OnClick", function()
        if not NS.db or not NS.defaultConfig then return end
        for k, v in pairs(NS.defaultConfig) do
            NS.db[k] = v
        end
        testBtn:SetText(NS.db.testMode and "Disable Test Mode" or "Enable Test Mode")
        RefreshConfigUI()
        if NS.RefreshAllPlatePositions then NS.RefreshAllPlatePositions() end
        if NS.UpdateAllNameplates then NS.UpdateAllNameplates() end
        print("|cffffd100MyQuestPlates:|r Settings reset to default.")
    end)

    local doneBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    doneBtn:SetSize(90, 24)
    doneBtn:SetPoint("BOTTOMRIGHT", -24, 20)
    doneBtn:SetText("Close")
    doneBtn:SetScript("OnClick", function() win:Hide() end)

    win:SetScript("OnShow", function()
        RefreshConfigUI()
        if NS.db then
            testBtn:SetText(NS.db.testMode and "Disable Test Mode" or "Enable Test Mode")
        end
    end)

    configWin = win
    return win
end

function NS.ToggleConfig()
    local ok, err = pcall(function()
        local win = NS.CreateConfigWindow()
        if not win then
            print("|cffff4444MyQuestPlates:|r Failed to create config window.")
            return
        end
        if win:IsShown() then
            win:Hide()
        else
            win:Show()
        end
    end)
    if not ok then
        print("|cffff4444MyQuestPlates Error:|r " .. tostring(err))
    end
end

-- ---------------------------------------------------------------------------
-- Blizzard Interface Options Category Registration
-- ---------------------------------------------------------------------------
local function RegisterBlizzardOptions()
    local ok, err = pcall(function()
        local panel = CreateFrame("Frame", "MyQuestPlatesBlizzPanel")
        panel.name = "MyQuestPlates"

        local pTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        pTitle:SetPoint("TOPLEFT", 16, -16)
        pTitle:SetText("|cffffd100MyQuestPlates|r")

        local pSub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pSub:SetPoint("TOPLEFT", 16, -42)
        pSub:SetText("Displays quest objective icons (slay, loot, talk) and progress directly on default Blizzard nameplates.")

        local openBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        openBtn:SetSize(180, 28)
        openBtn:SetPoint("TOPLEFT", 16, -80)
        openBtn:SetText("Open MyQuestPlates Config")
        openBtn:SetScript("OnClick", function()
            if _G.SettingsPanel and _G.SettingsPanel.IsShown and _G.SettingsPanel:IsShown() then
                pcall(function() _G.SettingsPanel:Hide() end)
            end
            if _G.InterfaceOptionsFrame and _G.InterfaceOptionsFrame.IsShown and _G.InterfaceOptionsFrame:IsShown() then
                pcall(function() _G.InterfaceOptionsFrame:Hide() end)
            end
            NS.ToggleConfig()
        end)

        C.RegisterOptionsCategory(panel, "MyQuestPlates")
    end)
    if not ok then
        -- Silent fallback, slash command is always available
    end
end

-- ---------------------------------------------------------------------------
-- Slash Commands
-- ---------------------------------------------------------------------------
SLASH_MYQUESTPLATES1 = "/myquestplates"
SLASH_MYQUESTPLATES2 = "/mqp"

SlashCmdList["MYQUESTPLATES"] = function(msg)
    local cmd = string.lower(strtrim(msg or ""))
    if cmd == "test" then
        if not NS.db then
            if NS.InitDB then NS.InitDB() end
        end
        if NS.db then
            NS.db.testMode = not NS.db.testMode
            if NS.UpdateAllNameplates then NS.UpdateAllNameplates() end
            print("|cffffd100MyQuestPlates:|r Test mode " .. (NS.db.testMode and "|cff00ff00enabled|r" or "|cffff0000disabled|r") .. ".")
        end
    elseif cmd == "reset" then
        if not NS.db then
            if NS.InitDB then NS.InitDB() end
        end
        if NS.db and NS.defaultConfig then
            for k, v in pairs(NS.defaultConfig) do
                NS.db[k] = v
            end
            if NS.RefreshAllPlatePositions then NS.RefreshAllPlatePositions() end
            if NS.UpdateAllNameplates then NS.UpdateAllNameplates() end
            print("|cffffd100MyQuestPlates:|r All settings reset to default.")
        end
    elseif cmd == "debug" then
        if not NS.db then
            if NS.InitDB then NS.InitDB() end
        end
        if NS.UpdateQuestLogCache then NS.UpdateQuestLogCache() end
        print("|cffffd100MyQuestPlates Diagnostics:|r")
        print("  Enabled: " .. tostring(NS.db and NS.db.enabled))
        print("  PreferQuestie: " .. tostring(NS.db and NS.db.preferQuestie))
        local hasQuestieLoader = (_G.QuestieLoader ~= nil)
        print("  QuestieLoader detected: " .. tostring(hasQuestieLoader))

        -- Active Quests by Quest ID
        local activeQCount = 0
        if NS.ActiveQuests then
            for qId, qData in pairs(NS.ActiveQuests) do
                activeQCount = activeQCount + 1
                local status = qData.isComplete and "|cff00ff00[Complete]|r" or "|cffffd100[Active]|r"
                print(string.format("  Quest ID %d: %s %s", qId, qData.title or "Unknown", status))
                if qData.objectives then
                    for idx, obj in ipairs(qData.objectives) do
                        local live = (NS.GetLiveRequirement and NS.GetLiveRequirement(obj)) or obj
                        local doneStr = live.finished and "|cff00ff00(Done)|r" or "|cffff8800(Incomplete)|r"
                        print(string.format("    Req #%d: [%s] %s -> %s %s", idx, live.kind or "slay", live.description or live.targetName or "", live.progress or "", doneStr))
                    end
                end
            end
        end
        print("  Total Active Quests indexed: " .. activeQCount)

        local npcMapCount = 0
        if NS.NpcToQuests then
            for _ in pairs(NS.NpcToQuests) do npcMapCount = npcMapCount + 1 end
        end
        print("  NPCs mapped to requirements: " .. npcMapCount)

        local nameMapCount = 0
        if NS.NameToQuests then
            for _ in pairs(NS.NameToQuests) do nameMapCount = nameMapCount + 1 end
        end
        print("  Mob names mapped to requirements: " .. nameMapCount)

        local plates = (NS.C and NS.C.GetNamePlates and NS.C.GetNamePlates()) or {}
        print("  Visible engine nameplates: " .. #plates)
        if UnitExists("target") then
            local tName = UnitName("target") or "Unknown"
            local tGuid = UnitGUID("target") or "None"
            local _, _, _, _, _, tNpcId = strsplit("-", tGuid)
            print("  Target: " .. tName .. " (NpcID: " .. tostring(tNpcId) .. ", GUID: " .. tGuid .. ")")
            local ok, hasQ, tex, prog, kind, chosenReq, allReqs = pcall(NS.ResolveQuestForUnit, "target")
            print("  Target resolved: ok=" .. tostring(ok) .. ", hasQuest=" .. tostring(hasQ) .. ", kind=" .. tostring(kind) .. ", progress=" .. tostring(prog))
            if allReqs and #allReqs > 0 then
                print("  Target matched requirements (" .. #allReqs .. "):")
                for _, r in ipairs(allReqs) do
                    print(string.format("    -> [Quest %s] %s | %s (%s) %s", tostring(r.questID), r.questTitle or "", r.description or "", r.progress or "", r.finished and "[Done]" or "[Needed]"))
                end
            end
        else
            print("  Target: None (target a mob to test resolution)")
        end
    elseif cmd == "help" then
        print("|cffffd100MyQuestPlates Commands:|r")
        print("  |cffffd100/mqp|r or |cffffd100/myquestplates|r - Open configuration panel")
        print("  |cffffd100/mqp test|r - Toggle test preview on visible nameplates")
        print("  |cffffd100/mqp debug|r - Print active quest objectives & detection status")
        print("  |cffffd100/mqp reset|r - Reset settings to defaults")
    else
        NS.ToggleConfig()
    end
end

-- ---------------------------------------------------------------------------
-- Init on Player Login
-- ---------------------------------------------------------------------------
local optFrame = CreateFrame("Frame")
optFrame:RegisterEvent("PLAYER_LOGIN")
optFrame:SetScript("OnEvent", function()
    RegisterBlizzardOptions()
end)
