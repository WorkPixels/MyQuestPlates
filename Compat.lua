-- Compat.lua -- API compatibility layer for WoW: Forever (1.60), Classic Era, and modern clients.
local ADDON, NS = ...
local C = {}
NS.C = C

-- ---------------------------------------------------------------------------
-- Nameplate API wrappers
-- ---------------------------------------------------------------------------
function C.GetNamePlateForUnit(unit)
    if _G.C_NamePlate and _G.C_NamePlate.GetNamePlateForUnit then
        return _G.C_NamePlate.GetNamePlateForUnit(unit)
    end
    return nil
end

function C.GetNamePlates()
    if _G.C_NamePlate and _G.C_NamePlate.GetNamePlates then
        return _G.C_NamePlate.GetNamePlates()
    end
    return {}
end

-- ---------------------------------------------------------------------------
-- Quest Log API wrappers
-- ---------------------------------------------------------------------------
local CQL = _G.C_QuestLog

function C.GetNumQuestLogEntries()
    if CQL and CQL.GetNumQuestLogEntries then
        local ok, n = pcall(CQL.GetNumQuestLogEntries)
        if ok and type(n) == "number" and n > 0 then
            return n
        end
    end
    if _G.GetNumQuestLogEntries then
        local ok, n = pcall(_G.GetNumQuestLogEntries)
        if ok and type(n) == "number" then
            return n
        end
    end
    return 0
end

function C.IsOnQuest(questID)
    if not questID then return false end
    if CQL and CQL.IsOnQuest then
        local ok, res = pcall(CQL.IsOnQuest, questID)
        if ok and res then return true end
    end
    return false
end

-- Returns: title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID
function C.GetQuestInfo(index)
    if CQL and CQL.GetInfo then
        local ok, info = pcall(CQL.GetInfo, index)
        if ok and info and info.title then
            local isComplete = 0
            if CQL.IsFailed and info.questID then
                local okF, f = pcall(CQL.IsFailed, info.questID)
                if okF and f then isComplete = -1 end
            end
            if isComplete == 0 and CQL.IsComplete and info.questID then
                local okC, comp = pcall(CQL.IsComplete, info.questID)
                if okC and comp then isComplete = 1 end
            end
            if isComplete == 0 and info.isComplete ~= nil then
                isComplete = (info.isComplete == 1 or info.isComplete == true) and 1 or 0
            end
            return info.title, info.level, info.suggestedGroup, info.isHeader, info.isCollapsed, isComplete, info.frequency, info.questID
        end
    end
    if _G.GetQuestLogTitle then
        local ok, title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID = pcall(_G.GetQuestLogTitle, index)
        if ok and title then
            return title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID
        end
    end
    return nil
end

-- Returns an array of objective tables: { text = string, type = string, finished = bool, numFulfilled = num, numRequired = num }
function C.GetQuestObjectives(questID, questIndex)
    local objectives = {}

    -- 1. Try Questie's QuestLogCache if present (most accurate & pre-parsed in Forever/Classic)
    if _G.QuestieLoader and _G.QuestieLoader.ImportModule and questID then
        local ok, QLC = pcall(_G.QuestieLoader.ImportModule, _G.QuestieLoader, "QuestLogCache")
        if ok and QLC and QLC.TryGetQuest then
            local okQ, q = pcall(QLC.TryGetQuest, questID)
            if okQ and q and q.objectives then
                for _, obj in pairs(q.objectives) do
                    local txt = obj.text and strtrim(obj.text) or ""
                    if txt ~= "" then
                        table.insert(objectives, {
                            text = txt,
                            type = obj.type or "monster",
                            finished = obj.finished or false,
                            numFulfilled = obj.numFulfilled or 0,
                            numRequired = (obj.numRequired and obj.numRequired > 0) and obj.numRequired or 1,
                        })
                    end
                end
                if #objectives > 0 then
                    return objectives
                end
            end
        end
    end

    -- 2. Try modern C_QuestLog.GetQuestObjectives first if available
    if questID and CQL and CQL.GetQuestObjectives then
        local ok, objs = pcall(CQL.GetQuestObjectives, questID)
        if ok and objs and #objs > 0 then
            local validObjs = {}
            for i, obj in ipairs(objs) do
                local txt = obj.text and strtrim(obj.text) or ""
                if txt ~= "" then
                    table.insert(validObjs, {
                        text = txt,
                        type = obj.type or "monster",
                        finished = obj.finished or false,
                        numFulfilled = obj.numFulfilled or 0,
                        numRequired = (obj.numRequired and obj.numRequired > 0) and obj.numRequired or 1,
                    })
                end
            end
            if #validObjs > 0 then
                return validObjs
            end
        end
    end

    -- 3. Classic leaderboards API fallback
    if questIndex and (_G.GetQuestLogLeaderBoard or _G.GetNumQuestLeaderBoards) then
        local oldSelection = nil
        if _G.GetQuestLogSelection then
            local ok, sel = pcall(_G.GetQuestLogSelection)
            if ok and type(sel) == "number" then
                oldSelection = sel
            end
        end

        if _G.SelectQuestLogEntry then
            pcall(_G.SelectQuestLogEntry, questIndex)
        end
        if questID and CQL and CQL.SetSelectedQuest then
            pcall(CQL.SetSelectedQuest, questID)
        end

        local numLeaderBoards = 0
        if _G.GetNumQuestLeaderBoards then
            local ok, num = pcall(_G.GetNumQuestLeaderBoards, questIndex)
            if ok and type(num) == "number" and num > 0 then
                numLeaderBoards = num
            else
                local ok2, num2 = pcall(_G.GetNumQuestLeaderBoards)
                if ok2 and type(num2) == "number" and num2 > 0 then
                    numLeaderBoards = num2
                end
            end
        end

        local maxProbe = (numLeaderBoards > 0) and numLeaderBoards or 10
        local lbObjectives = {}
        for j = 1, maxProbe do
            local leaderBoardText, leaderBoardType, isFinished
            local ok, t, ty, fin = pcall(_G.GetQuestLogLeaderBoard, j, questIndex)
            if ok and t and t ~= "" then
                leaderBoardText, leaderBoardType, isFinished = t, ty, fin
            else
                local ok2, t2, ty2, fin2 = pcall(_G.GetQuestLogLeaderBoard, j)
                if ok2 and t2 and t2 ~= "" then
                    leaderBoardText, leaderBoardType, isFinished = t2, ty2, fin2
                end
            end

            if leaderBoardText and leaderBoardText ~= "" then
                local txt = strtrim(leaderBoardText)
                local cur, req = string.match(txt, "(%d+)%s*/%s*(%d+)")
                table.insert(lbObjectives, {
                    text = txt,
                    type = leaderBoardType or "monster",
                    finished = isFinished or false,
                    numFulfilled = tonumber(cur) or (isFinished and 1 or 0),
                    numRequired = tonumber(req) or 1,
                })
            elseif numLeaderBoards == 0 then
                break
            end
        end

        -- If no leaderboards found (e.g. delivery / talk-to quest), inspect quest objective summary
        if #lbObjectives == 0 and _G.GetQuestLogQuestText then
            local ok, qDesc, qObj = pcall(_G.GetQuestLogQuestText)
            if ok and qObj and qObj ~= "" then
                table.insert(lbObjectives, {
                    text = strtrim(qObj),
                    type = "talk",
                    finished = false,
                    numFulfilled = 0,
                    numRequired = 1,
                })
            end
        end

        if oldSelection and _G.SelectQuestLogEntry and oldSelection ~= questIndex then
            pcall(_G.SelectQuestLogEntry, oldSelection)
        end

        if #lbObjectives > 0 then
            return lbObjectives
        end
    end

    return objectives
end

-- ---------------------------------------------------------------------------
-- Settings / Interface Options Registration
-- ---------------------------------------------------------------------------
function C.RegisterOptionsCategory(frame, name, parentName)
    if _G.Settings and _G.Settings.RegisterCanvasLayoutCategory then
        local category
        if parentName then
            local parent = _G.Settings.GetCategory(parentName)
            if parent then
                category = _G.Settings.RegisterCanvasLayoutSubcategory(parent, frame, name)
            else
                category = _G.Settings.RegisterCanvasLayoutCategory(frame, name)
            end
        else
            category = _G.Settings.RegisterCanvasLayoutCategory(frame, name)
        end
        _G.Settings.RegisterAddOnCategory(category)
        return category
    elseif _G.InterfaceOptions_AddCategory then
        frame.name = name
        frame.parent = parentName
        _G.InterfaceOptions_AddCategory(frame)
        return frame
    end
end
