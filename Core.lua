-- Core.lua -- Core engine for MyQuestPlates: taint-free nameplate attachment, quest detection, and indicator display.
local ADDON, NS = ...
local C = NS.C

_G.MyQuestPlates = NS

local PlateFrames         = {}   -- [plateFrame] = indicatorFrame (anchored to plate/mpFrame)
NS.questLogCache          = {}   -- cached active quest objectives
NS.ActiveQuests           = {}   -- [questID] = { id = questID, title = questTitle, objectives = {}, isComplete = bool }
NS.NpcToQuests            = {}   -- [numNpcId] = { reqRecord1, reqRecord2, ... }
NS.NameToQuests           = {}   -- [lowerName] = { reqRecord1, reqRecord2, ... }
NS.activeQuestIDs         = {}   -- [questID] = true for quests currently in log
NS.activeQuestTitles      = {}   -- [lowerTitle] = true for quests currently in log
NS.activeQuestSpawns      = {}   -- [numNpcId] = { kind = "slay"|"loot"|"talk", progress = "0/10", finished = bool }
NS.activeQuestSpawnNames  = {}   -- [lowerName] = { kind = "slay"|"loot"|"talk", progress = "0/10", finished = bool }

-- ---------------------------------------------------------------------------
-- Simple Icon Textures (Transparent Backgrounds)
-- ---------------------------------------------------------------------------
local BUNDLED_ICONS = {
    slay     = "Interface\\AddOns\\MyQuestPlates\\Icons\\slay.blp",
    loot     = "Interface\\AddOns\\MyQuestPlates\\Icons\\loot.blp",
    talk     = "Interface\\AddOns\\MyQuestPlates\\Icons\\chatbubblegossipicon.blp",
    interact = "Interface\\AddOns\\MyQuestPlates\\Icons\\interact.blp",
    event    = "Interface\\AddOns\\MyQuestPlates\\Icons\\event.blp",
    complete = "Interface\\AddOns\\MyQuestPlates\\Icons\\complete.blp",
    default  = "Interface\\AddOns\\MyQuestPlates\\Icons\\available.blp",
}

local function GetTextureForKind(kind)
    if BUNDLED_ICONS[kind] then
        return BUNDLED_ICONS[kind]
    end
    local useQuestie = (_G.Questie and _G.Questie.icons)
    if useQuestie and _G.Questie.icons[kind] then
        return _G.Questie.icons[kind]
    end
    return BUNDLED_ICONS.default
end

-- ---------------------------------------------------------------------------
-- Secret Value Protection (Midnight 12.0+ / Modern Engine Safety)
-- ---------------------------------------------------------------------------
local function IsSecretValue(v)
    if v == nil then return false end
    local issec = issecretvalue or (_G and _G.issecretvalue)
    if issec then
        local ok, s = pcall(issec, v)
        if ok and s then return true end
    end
    local ok1 = pcall(function() if v then end end)
    if not ok1 then return true end
    local ok2 = pcall(function() return v == v end)
    if not ok2 then return true end
    local ok3 = pcall(function() local _ = "" .. v end)
    if not ok3 then return true end
    return false
end

local function GetQuestieModule(name)
    if _G.QuestieLoader and _G.QuestieLoader.ImportModule then
        local ok, mod = pcall(_G.QuestieLoader.ImportModule, _G.QuestieLoader, name)
        if ok and mod then return mod end
    end
    return _G[name]
end

-- ---------------------------------------------------------------------------
-- Objective Target Name Extraction (Strips counts, bullets, colons, verbs)
-- ---------------------------------------------------------------------------
local function ExtractTargetName(text)
    if not text or IsSecretValue(text) or text == "" then return "" end

    local t = strtrim(text)

    -- Strip leading bullet symbols, dashes, colons
    t = string.gsub(t, "^%s*[%-%*•:]%s*", "")

    -- Strip trailing completion tags: e.g. "(Complete)", "(Completed)"
    t = string.gsub(t, "%s*%(?[cC]omplete[d]?%)?$", "")

    -- Strip leading counts: e.g. "0/8 Valanaar Trout" -> "Valanaar Trout"
    t = string.gsub(t, "^%s*%d+%s*/%s*%d+%s*[%-:]?%s*", "")

    -- Strip trailing counts: e.g. "Defias Bandit slain: 0/8" or "Goretusk Snout - 0/8"
    t = string.gsub(t, "%s*[%-:]?%s*%d+%s*/%s*%d+.*$", "")

    -- Strip again any leading bullet symbols / colons left after count stripping
    t = string.gsub(t, "^%s*[%-%*•:]%s*", "")

    -- Strip common trailing objective suffixes
    t = string.gsub(t, "%s+[sS]lain$", "")
    t = string.gsub(t, "%s+[dD]efeated$", "")
    t = string.gsub(t, "%s+[kK]illed$", "")
    t = string.gsub(t, "%s+[cC]ollected$", "")
    t = string.gsub(t, "%s+[gG]athered$", "")
    t = string.gsub(t, "%s+[dD]estroyed$", "")

    -- Strip common leading action verbs
    t = string.gsub(t, "^[sS]lay%s+", "")
    t = string.gsub(t, "^[kK]ill%s+", "")
    t = string.gsub(t, "^[dD]efeat%s+", "")
    t = string.gsub(t, "^[cC]ollect%s+", "")
    t = string.gsub(t, "^[gG]ather%s+", "")
    t = string.gsub(t, "^[dD]estroy%s+", "")
    t = string.gsub(t, "^[sS]peak%s+[wW]ith%s+", "")
    t = string.gsub(t, "^[sS]peak%s+[tT]o%s+", "")
    t = string.gsub(t, "^[tT]alk%s+[tT]o%s+", "")
    t = string.gsub(t, "^[rR]eport%s+[tT]o%s+", "")
    t = string.gsub(t, "^[dD]eliver%s+.-%s+[tT]o%s+", "")

    -- Strip leading numbers (e.g. "10 Defias Bandits" -> "Defias Bandits")
    t = string.gsub(t, "^%d+%s+", "")

    -- Final strip of leading/trailing bullet or dash
    t = string.gsub(t, "^%s*[%-%*•:]%s*", "")
    t = string.gsub(t, "%s*[%-%*•:]%s*$", "")

    return strtrim(t)
end

local DROP_NOUNS = {
    ["snout"] = true, ["snouts"] = true,
    ["liver"] = true, ["livers"] = true,
    ["meat"] = true, ["meats"] = true,
    ["rib"] = true, ["ribs"] = true,
    ["flank"] = true, ["flanks"] = true,
    ["haunch"] = true, ["haunches"] = true,
    ["entrail"] = true, ["entrails"] = true,
    ["intestine"] = true, ["intestines"] = true,
    ["heart"] = true, ["hearts"] = true,
    ["brain"] = true, ["brains"] = true,
    ["kidney"] = true, ["kidneys"] = true,
    ["belly"] = true, ["bellies"] = true,
    ["lung"] = true, ["lungs"] = true,
    ["spleen"] = true, ["spleens"] = true,
    ["eye"] = true, ["eyes"] = true,
    ["ear"] = true, ["ears"] = true,
    ["tooth"] = true, ["teeth"] = true,
    ["tusk"] = true, ["tusks"] = true,
    ["horn"] = true, ["horns"] = true,
    ["beak"] = true, ["beaks"] = true,
    ["claw"] = true, ["claws"] = true,
    ["talon"] = true, ["talons"] = true,
    ["paw"] = true, ["paws"] = true,
    ["hoof"] = true, ["hooves"] = true,
    ["foot"] = true, ["feet"] = true,
    ["feather"] = true, ["feathers"] = true,
    ["quill"] = true, ["quills"] = true,
    ["pelt"] = true, ["pelts"] = true,
    ["skin"] = true, ["skins"] = true,
    ["hide"] = true, ["hides"] = true,
    ["fur"] = true, ["furs"] = true,
    ["scale"] = true, ["scales"] = true,
    ["tail"] = true, ["tails"] = true,
    ["tendon"] = true, ["tendons"] = true,
    ["bone"] = true, ["bones"] = true,
    ["skull"] = true, ["skulls"] = true,
    ["wing"] = true, ["wings"] = true,
    ["venom"] = true, ["venoms"] = true,
    ["sac"] = true, ["sacs"] = true,
    ["gland"] = true, ["glands"] = true,
    ["blood"] = true,
    ["fluid"] = true, ["fluids"] = true,
    ["ichor"] = true,
    ["carcass"] = true, ["carcasses"] = true,
    ["head"] = true, ["heads"] = true,
    ["scalp"] = true, ["scalps"] = true,
    ["mane"] = true, ["manes"] = true,
    ["bristle"] = true, ["bristles"] = true,
    ["tongue"] = true, ["tongues"] = true,
    ["egg"] = true, ["eggs"] = true,
    ["carapace"] = true,
    ["chitin"] = true,
    ["shell"] = true, ["shells"] = true,
    ["stinger"] = true, ["stingers"] = true,
    ["antenna"] = true, ["antennae"] = true,
    ["mandible"] = true, ["mandibles"] = true,
    ["pincer"] = true, ["pincers"] = true,
    ["fin"] = true, ["fins"] = true,
    ["dust"] = true,
    ["candle"] = true, ["candles"] = true,
    ["bandana"] = true, ["bandanas"] = true,
    ["armband"] = true, ["armbands"] = true,
    ["necklace"] = true, ["necklaces"] = true,
    ["medal"] = true, ["medals"] = true,
    ["insignia"] = true, ["insignias"] = true,
    ["token"] = true, ["tokens"] = true,
    ["badge"] = true, ["badges"] = true,
    ["ring"] = true, ["rings"] = true,
    ["gizzard"] = true, ["gizzards"] = true,
    ["leg"] = true, ["legs"] = true,
    ["antler"] = true, ["antlers"] = true,
    ["muzzle"] = true, ["muzzles"] = true,
    ["amulet"] = true, ["amulets"] = true,
    ["fang"] = true, ["fangs"] = true,
    ["flesh"] = true,
    ["crystal"] = true, ["crystals"] = true,
    ["emblem"] = true, ["emblems"] = true,
    ["bead"] = true, ["beads"] = true,
    ["core"] = true, ["cores"] = true,
    ["sample"] = true, ["samples"] = true,
    ["relic"] = true, ["relics"] = true,
    ["artifact"] = true, ["artifacts"] = true,
    ["totem"] = true, ["totems"] = true,
    ["tome"] = true, ["tomes"] = true,
    ["letter"] = true, ["letters"] = true,
    ["note"] = true, ["notes"] = true,
    ["journal"] = true, ["journals"] = true,
    ["report"] = true, ["reports"] = true,
    ["order"] = true, ["orders"] = true,
    ["document"] = true, ["documents"] = true,
    ["key"] = true, ["keys"] = true,
    ["chunk"] = true, ["chunks"] = true,
    ["slab"] = true, ["slabs"] = true,
    ["piece"] = true, ["pieces"] = true,
    ["part"] = true, ["parts"] = true,
    ["remains"] = true,
    ["headdress"] = true,
    ["pouch"] = true, ["pouches"] = true,
    ["scrap"] = true, ["scraps"] = true,
    ["text"] = true, ["texts"] = true,
    ["hat"] = true, ["hats"] = true,
    ["tailspike"] = true, ["tailspikes"] = true,
    ["membrane"] = true, ["membranes"] = true,
    ["shard"] = true, ["shards"] = true,
    ["essence"] = true, ["essences"] = true,
    ["rifle"] = true, ["rifles"] = true,
    ["weapon"] = true, ["weapons"] = true,
    ["spine"] = true, ["spines"] = true,
    ["spore"] = true, ["spores"] = true,
    ["mixture"] = true, ["mixtures"] = true,
}

local CREATURE_PREFIXES = {
    ["young"] = true, ["elder"] = true, ["old"] = true, ["aged"] = true,
    ["greater"] = true, ["lesser"] = true, ["minor"] = true, ["major"] = true,
    ["giant"] = true, ["huge"] = true, ["small"] = true, ["tiny"] = true,
    ["starving"] = true, ["mangled"] = true, ["rabid"] = true, ["diseased"] = true,
    ["feral"] = true, ["wild"] = true, ["savage"] = true, ["vicious"] = true,
    ["scouting"] = true, ["patrolling"] = true, ["wandering"] = true,
    ["defias"] = true, ["riverpaw"] = true, ["rockjaw"] = true, ["frostmane"] = true,
    ["timber"] = true, ["mangy"] = true, ["plainstrider"] = true,
    ["forest"] = true, ["mountain"] = true, ["swamp"] = true, ["jungle"] = true,
    ["black"] = true, ["red"] = true, ["blue"] = true, ["green"] = true, ["white"] = true,
    ["crag"] = true, ["valley"] = true, ["ridge"] = true, ["loch"] = true,
    ["duskwood"] = true, ["westfall"] = true, ["redridge"] = true,
}

local function CleanUnitName(unitName)
    if not unitName or IsSecretValue(unitName) then return "" end
    local words = {}
    for w in string.gmatch(unitName, "%S+") do
        table.insert(words, w)
    end
    while #words > 0 and CREATURE_PREFIXES[string.lower(words[1])] do
        table.remove(words, 1)
    end
    if #words > 0 then
        local res = table.concat(words, " ")
        if string.len(res) >= 3 then
            return res
        end
    end
    return unitName
end

local function CleanTargetName(targetName)
    if not targetName or IsSecretValue(targetName) then return "" end
    local words = {}
    for w in string.gmatch(targetName, "%S+") do
        local lw = string.lower(w)
        if not DROP_NOUNS[lw] and not CREATURE_PREFIXES[lw] then
            table.insert(words, w)
        end
    end
    if #words > 0 then
        local res = table.concat(words, " ")
        if string.len(res) >= 3 then
            return res
        end
    end
    return targetName
end

local function WordBoundaryMatch(haystack, needle)
    if not haystack or not needle or haystack == "" or needle == "" then return false end
    local pattern = "(^|%s|%p)" .. needle .. "($|%s|%p)"
    return string.find(haystack, pattern) ~= nil
end

local function CompoundWordMatch(uClean, tClean)
    if not uClean or not tClean then return false end
    local uLen = string.len(uClean)
    local tLen = string.len(tClean)
    if uLen < 3 or tLen < 3 then return false end

    if uLen >= tLen then
        if string.sub(uClean, 1, tLen) == tClean or string.sub(uClean, -tLen) == tClean then
            return true
        end
    else
        if string.sub(tClean, 1, uLen) == uClean or string.sub(tClean, -uLen) == uClean then
            return true
        end
    end
    return false
end

local function GetNameVariants(str)
    local variants = {}
    if not str or IsSecretValue(str) or str == "" then return variants end
    local ok, s = pcall(function() return string.lower(strtrim(str)) end)
    if not ok or not s or s == "" then return variants end
    variants[s] = true

    -- Apostrophe normalization
    local sApos = string.gsub(s, "s'", "'s")
    if sApos ~= s then variants[sApos] = true end
    local sApos2 = string.gsub(s, "'s", "s'")
    if sApos2 ~= s then variants[sApos2] = true end
    local sNoApos = string.gsub(s, "'", "")
    if sNoApos ~= s then variants[sNoApos] = true end

    -- Plural / singular variants
    local len = string.len(s)
    if string.find(s, "ies$") and len > 4 then
        variants[string.sub(s, 1, -4) .. "y"] = true
    end
    if string.find(s, "ves$") and len > 4 then
        variants[string.sub(s, 1, -4) .. "f"] = true
        variants[string.sub(s, 1, -4) .. "fe"] = true
    end
    if string.find(s, "es$") and len > 3 then
        variants[string.sub(s, 1, -3)] = true
    end
    if string.find(s, "s$") and len > 2 then
        variants[string.sub(s, 1, -2)] = true
    end
    variants[s .. "s"] = true
    variants[s .. "es"] = true

    return variants
end

local function LookupQuestItemDrop(targetName, unitName, numNpcId)
    if not targetName or targetName == "" then return false end

    local targetVars = GetNameVariants(targetName)
    local unitVars = unitName and GetNameVariants(unitName) or {}

    -- Check NPC ID table first (most precise)
    if NS.QuestItemNPCs and numNpcId then
        for tVar in pairs(targetVars) do
            local npcTable = NS.QuestItemNPCs[tVar]
            if npcTable and npcTable[numNpcId] then
                return true
            end
        end
    end

    -- Check Mob Name table
    if NS.QuestItemDrops then
        for tVar in pairs(targetVars) do
            local dropTable = NS.QuestItemDrops[tVar]
            if dropTable then
                for uVar in pairs(unitVars) do
                    if dropTable[uVar] then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local STOP_WORDS = {
    ["in"] = true, ["at"] = true, ["near"] = true, ["the"] = true,
    ["of"] = true, ["and"] = true, ["or"] = true, ["for"] = true,
    ["slain"] = true, ["killed"] = true, ["defeated"] = true,
    ["any"] = true, ["from"] = true, ["to"] = true, ["with"] = true,
}

local SHORT_CREATURE_WORDS = {
    ["orc"] = true, ["owl"] = true, ["cat"] = true, ["pig"] = true,
    ["ape"] = true, ["rat"] = true, ["bat"] = true, ["cow"] = true,
    ["dog"] = true,
}

local function GetSingularWord(w)
    if not w or IsSecretValue(w) or w == "" then return "" end
    local s = string.lower(w)
    local len = string.len(s)
    if len > 4 and string.find(s, "ies$") then
        return string.sub(s, 1, -4) .. "y"
    elseif len > 4 and string.find(s, "ves$") then
        return string.sub(s, 1, -4) .. "f"
    elseif len > 4 and string.find(s, "ches$") then
        return string.sub(s, 1, -3)
    elseif len > 4 and string.find(s, "shes$") then
        return string.sub(s, 1, -3)
    elseif len > 3 and string.find(s, "es$") then
        return string.sub(s, 1, -3)
    elseif len > 3 and string.find(s, "s$") and not string.find(s, "ss$") and not string.find(s, "us$") and not string.find(s, "is$") then
        return string.sub(s, 1, -2)
    end
    return s
end

local GROUP_PREFIXES = {
    defias = true, scarlet = true, syndicate = true, venture = true,
    riverpaw = true, blackrock = true, bloodscalp = true, skullsplitter = true,
    kurzen = true, wastewander = true, southsea = true, bloodsail = true,
    kolkar = true, galak = true, grimtotem = true, boulderfist = true,
    crushridge = true, dragonmaw = true, darkshore = true, ashenvale = true,
    darkspear = true, stormwind = true, ironforge = true, orgrimmar = true,
    murloc = true, gnoll = true, kobold = true, trogg = true,
    harpy = true, centaur = true, quillboar = true, furbolg = true,
}

local function IsNameMatch(unitName, targetName, isItem)
    if not unitName or not targetName or IsSecretValue(unitName) or IsSecretValue(targetName) then return false end
    local u = string.lower(strtrim(unitName))
    local t = string.lower(strtrim(targetName))
    if u == "" or t == "" then
        return false
    end

    -- 1. Exact match or simple plural match
    if u == t or (u .. "s") == t or (t .. "s") == u then
        return true
    end

    -- 2. Whole phrase singular match
    local uSing = GetSingularWord(u)
    local tSing = GetSingularWord(t)
    if uSing ~= "" and uSing == tSing then
        return true
    end

    -- 3. Extract core words excluding stop words and item drop nouns
    local uWords = {}
    for w in string.gmatch(u, "%a+") do
        if not STOP_WORDS[w] then
            table.insert(uWords, GetSingularWord(w))
        end
    end

    local tWords = {}
    for w in string.gmatch(t, "%a+") do
        if not STOP_WORDS[w] then
            if not (isItem and DROP_NOUNS[w]) then
                table.insert(tWords, GetSingularWord(w))
            end
        end
    end

    if #uWords == 0 or #tWords == 0 then return false end

    local uClean = table.concat(uWords, " ")
    local tClean = table.concat(tWords, " ")
    if uClean == tClean then return true end

    -- 4. Filter out creature age/size prefixes (young, starving, giant, etc.)
    local uCore = {}
    for _, w in ipairs(uWords) do
        if not CREATURE_PREFIXES[w] then
            table.insert(uCore, w)
        end
    end
    local tCore = {}
    for _, w in ipairs(tWords) do
        if not CREATURE_PREFIXES[w] then
            table.insert(tCore, w)
        end
    end

    if #uCore > 0 and #tCore > 0 then
        if table.concat(uCore, " ") == table.concat(tCore, " ") then
            return true
        end
    end

    -- 5. Disambiguate different ranks/roles within the same group (e.g. Defias Smuggler vs Defias Traitor)
    local sharedWords = {}
    local diffT = {}
    local diffU = {}

    local uCoreSet = {}
    for _, w in ipairs(uCore) do uCoreSet[w] = true end
    local tCoreSet = {}
    for _, w in ipairs(tCore) do tCoreSet[w] = true end

    for _, w in ipairs(tCore) do
        if uCoreSet[w] then
            table.insert(sharedWords, w)
        else
            table.insert(diffT, w)
        end
    end
    for _, w in ipairs(uCore) do
        if not tCoreSet[w] then
            table.insert(diffU, w)
        end
    end

    -- If both have differing specific nouns (e.g. smuggler vs traitor, worker vs vermin)
    if #diffT > 0 and #diffU > 0 then
        local allSharedAreGroups = true
        for _, sw in ipairs(sharedWords) do
            if not GROUP_PREFIXES[sw] then
                allSharedAreGroups = false
                break
            end
        end
        if allSharedAreGroups then
            return false
        end
    end

    if #sharedWords > 0 then
        for _, sw in ipairs(sharedWords) do
            if not GROUP_PREFIXES[sw] and string.len(sw) >= 4 then
                return true
            end
        end
    end

    return false
end

function NS.IsPlayerOnQuest(questID, questTitle)
    if questID and questID > 0 then
        if NS.activeQuestIDs[questID] then return true end
        if C.IsOnQuest(questID) then return true end
    end
    if questTitle and questTitle ~= "" then
        local lt = string.lower(strtrim(questTitle))
        if NS.activeQuestTitles[lt] then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Quest ID & Requirements Linking Engine
-- ---------------------------------------------------------------------------
local function LinkNpcToQuestRequirement(npcId, reqRecord)
    if not npcId or not reqRecord then return end
    local numId = tonumber(npcId)
    if not numId or numId <= 0 then return end
    if not NS.NpcToQuests[numId] then
        NS.NpcToQuests[numId] = {}
    end
    for _, existing in ipairs(NS.NpcToQuests[numId]) do
        if existing.questID == reqRecord.questID and existing.objIndex == reqRecord.objIndex and existing.kind == reqRecord.kind then
            return
        end
    end
    table.insert(NS.NpcToQuests[numId], reqRecord)
end

local function LinkNameToQuestRequirement(name, reqRecord)
    if not name or not reqRecord or IsSecretValue(name) or name == "" then return end
    local lower = string.lower(strtrim(name))
    if lower == "" or string.len(lower) < 2 then return end
    if not NS.NameToQuests[lower] then
        NS.NameToQuests[lower] = {}
    end
    for _, existing in ipairs(NS.NameToQuests[lower]) do
        if existing.questID == reqRecord.questID and existing.objIndex == reqRecord.objIndex and existing.kind == reqRecord.kind then
            return
        end
    end
    table.insert(NS.NameToQuests[lower], reqRecord)
end

function NS.GetLiveRequirement(reqRecord)
    if not reqRecord then return nil end
    local qId = reqRecord.questID
    local idx = reqRecord.objIndex or 1

    local liveCur = reqRecord.numFulfilled or 0
    local liveReq = reqRecord.numRequired or 1
    local liveDone = (reqRecord.finished == true)
    local liveDesc = reqRecord.description or reqRecord.targetName or ""
    local qTitle = reqRecord.questTitle or "Quest"

    -- 1. Query Questie live quest log if available
    if _G.QuestieLoader and _G.QuestieLoader.ImportModule then
        local okQP, QP = pcall(_G.QuestieLoader.ImportModule, _G.QuestieLoader, "QuestiePlayer")
        if okQP and QP and QP.currentQuestlog and qId and QP.currentQuestlog[qId] then
            local qData = QP.currentQuestlog[qId]
            if qData.name and qData.name ~= "" then
                qTitle = qData.name
            end
            if qData.Objectives then
                local obj = qData.Objectives[idx]
                if not obj and type(qData.Objectives) == "table" then
                    for _, o in pairs(qData.Objectives) do
                        if (reqRecord.targetName and o.Description and string.find(string.lower(o.Description), string.lower(reqRecord.targetName), 1, true)) or
                           (reqRecord.itemId and o.Id == reqRecord.itemId) then
                            obj = o
                            break
                        end
                    end
                end
                if obj then
                    if obj.Update then pcall(obj.Update, obj) end
                    if obj.Completed ~= nil then
                        liveDone = (obj.Completed == true)
                    end
                    if obj.Needed and obj.Needed > 0 then
                        liveReq = obj.Needed
                    end
                    if obj.Collected and obj.Collected >= 0 then
                        liveCur = obj.Collected
                    end
                    if obj.Description and obj.Description ~= "" then
                        liveDesc = obj.Description
                    end
                    local pStr = (liveReq > 0) and (liveCur .. "/" .. liveReq) or ""
                    return {
                        questID      = qId,
                        questTitle   = qTitle,
                        objIndex     = idx,
                        kind         = reqRecord.kind or "slay",
                        targetName   = reqRecord.targetName,
                        description  = liveDesc,
                        numFulfilled = liveCur,
                        numRequired  = liveReq,
                        progress     = pStr,
                        finished     = liveDone,
                    }
                end
            end
        end
    end

    -- 2. Query Blizzard C_QuestLog / Compat objectives
    if qId and qId > 0 then
        local objs = C.GetQuestObjectives(qId)
        if objs and #objs > 0 then
            local obj = objs[idx]
            if not obj and reqRecord.targetName then
                local lTarget = string.lower(reqRecord.targetName)
                for _, o in ipairs(objs) do
                    if o.text and string.find(string.lower(o.text), lTarget, 1, true) then
                        obj = o
                        break
                    end
                end
            end
            if obj then
                if obj.numRequired and obj.numRequired > 0 then
                    liveReq = obj.numRequired
                end
                if obj.numFulfilled and obj.numFulfilled >= 0 then
                    liveCur = obj.numFulfilled
                end
                liveDone = (obj.finished == true) or (liveCur >= liveReq)
                if obj.text and obj.text ~= "" then
                    liveDesc = obj.text
                end
                local pStr = (liveReq > 0) and (liveCur .. "/" .. liveReq) or ""
                return {
                    questID      = qId,
                    questTitle   = qTitle,
                    objIndex     = idx,
                    kind         = reqRecord.kind or "slay",
                    targetName   = reqRecord.targetName,
                    description  = liveDesc,
                    numFulfilled = liveCur,
                    numRequired  = liveReq,
                    progress     = pStr,
                    finished     = liveDone,
                }
            end
        end
    end

    -- 3. Return snapshot from reqRecord
    local pStr = (liveReq > 0) and (liveCur .. "/" .. liveReq) or ""
    return {
        questID      = qId,
        questTitle   = qTitle,
        objIndex     = idx,
        kind         = reqRecord.kind or "slay",
        targetName   = reqRecord.targetName,
        description  = liveDesc,
        numFulfilled = liveCur,
        numRequired  = liveReq,
        progress     = pStr,
        finished     = liveDone,
    }
end

-- ---------------------------------------------------------------------------
-- Quest Log Cache Engine (Multi-Source: Questie + C_QuestLog + Classic Logs)
-- ---------------------------------------------------------------------------
local isUpdatingCache = false
function NS.UpdateQuestLogCache()
    if isUpdatingCache then return end
    isUpdatingCache = true

    pcall(function()
        table.wipe(NS.ActiveQuests)
        table.wipe(NS.NpcToQuests)
        table.wipe(NS.NameToQuests)
        table.wipe(NS.questLogCache)
        table.wipe(NS.activeQuestIDs)
        table.wipe(NS.activeQuestTitles)
        table.wipe(NS.activeQuestSpawns)
        table.wipe(NS.activeQuestSpawnNames)

        -- 1. HYDRATE FROM QUESTIE IF PRESENT (authoritative active quest list)
        if _G.QuestieLoader and _G.QuestieLoader.ImportModule then
            local okQP, QP = pcall(_G.QuestieLoader.ImportModule, _G.QuestieLoader, "QuestiePlayer")
            if okQP and QP and QP.currentQuestlog then
                for qId, qData in pairs(QP.currentQuestlog) do
                    if type(qData) == "table" and qData.Objectives then
                        local qTitle = qData.name or ""
                        if qTitle ~= "" then
                            local lowerTitle = string.lower(strtrim(qTitle))
                            NS.activeQuestTitles[lowerTitle] = true
                            NS.activeQuestIDs[qId] = true

                            NS.ActiveQuests[qId] = {
                                id = qId,
                                title = qTitle,
                                objectives = {},
                                isComplete = (qData.IsComplete == 1 or qData.isComplete == true),
                            }

                            local objIdx = 0
                            for _, obj in pairs(qData.Objectives) do
                                objIdx = objIdx + 1
                                local oText = obj.Description or ""
                                local target = ExtractTargetName(oText)
                                if target == "" or string.len(target) < 3 then
                                    target = oText
                                end

                                local isDone = (obj.Completed == true)
                                local needed = (obj.Needed and obj.Needed > 0) and obj.Needed or 1
                                local cur = (obj.Collected and obj.Collected >= 0) and obj.Collected or 0
                                local pStr = cur .. "/" .. needed
                                local kind = (obj.Type == "item") and "loot" or ((obj.Type == "talk") and "talk" or "slay")

                                local reqRecord = {
                                    questID      = qId,
                                    questTitle   = qTitle,
                                    objIndex     = objIdx,
                                    kind         = kind,
                                    targetName   = target,
                                    description  = oText,
                                    numFulfilled = cur,
                                    numRequired  = needed,
                                    finished     = isDone,
                                    itemId       = (obj.Type == "item" and obj.Id),
                                }

                                table.insert(NS.ActiveQuests[qId].objectives, reqRecord)

                                table.insert(NS.questLogCache, {
                                    questTitle   = qTitle,
                                    questID      = qId,
                                    fullText     = oText,
                                    targetName   = target,
                                    type         = obj.Type or "monster",
                                    finished     = isDone,
                                    numFulfilled = cur,
                                    numRequired  = needed,
                                })

                                -- Index spawns directly for O(1) matching
                                local hasQuestieSpawns = false
                                if obj.spawnList and type(obj.spawnList) == "table" then
                                    for spawnId, spawnData in pairs(obj.spawnList) do
                                        local nId = tonumber(spawnId) or (type(spawnData) == "table" and tonumber(spawnData.Id))
                                        if nId then
                                            hasQuestieSpawns = true
                                            LinkNpcToQuestRequirement(nId, reqRecord)
                                            NS.activeQuestSpawns[nId] = {
                                                kind     = kind,
                                                progress = pStr,
                                                finished = isDone,
                                                title    = qTitle,
                                                questID  = qId,
                                            }
                                        end
                                        if type(spawnData) == "table" and spawnData.Name and spawnData.Name ~= "" then
                                            hasQuestieSpawns = true
                                            local sName = spawnData.Name
                                            LinkNameToQuestRequirement(sName, reqRecord)
                                            NS.activeQuestSpawnNames[string.lower(strtrim(sName))] = {
                                                kind     = kind,
                                                progress = pStr,
                                                finished = isDone,
                                                title    = qTitle,
                                                questID  = qId,
                                            }
                                        end
                                    end
                                end

                                -- If Questie already provided verified spawns, DO NOT pollute them with static drop tables!
                                if not hasQuestieSpawns then
                                    local foundItemSources = false
                                    if obj.Type == "item" and obj.Id and _G.QuestieLoader and _G.QuestieLoader.ImportModule then
                                        local okDB, QDB = pcall(_G.QuestieLoader.ImportModule, _G.QuestieLoader, "QuestieDB")
                                        if okDB and QDB and QDB.GetItem then
                                            local itemData = QDB:GetItem(obj.Id)
                                            if itemData and itemData.Sources then
                                                for _, src in pairs(itemData.Sources) do
                                                    if src.Type == "monster" and src.Id then
                                                        foundItemSources = true
                                                        LinkNpcToQuestRequirement(src.Id, reqRecord)
                                                    end
                                                end
                                            end
                                        end
                                    end

                                    -- Check static kill tables only if monster objective without Questie spawns
                                    if obj.Type == "monster" then
                                        if NS.QuestKillNPCs and NS.QuestKillNPCs[qId] then
                                            for npcKId in pairs(NS.QuestKillNPCs[qId]) do
                                                LinkNpcToQuestRequirement(npcKId, reqRecord)
                                            end
                                        end
                                        if NS.QuestKillMobs and NS.QuestKillMobs[qId] then
                                            for mobKName in pairs(NS.QuestKillMobs[qId]) do
                                                LinkNameToQuestRequirement(mobKName, reqRecord)
                                            end
                                        end
                                    end

                                    -- Check static item drops only if item objective without Questie spawns
                                    if obj.Type == "item" and not foundItemSources then
                                        local lowerT = string.lower(strtrim(target))
                                        local tVars = GetNameVariants(lowerT)
                                        if NS.QuestItemNPCs then
                                            for tVar in pairs(tVars) do
                                                local nTable = NS.QuestItemNPCs[tVar]
                                                if nTable then
                                                    for nDropId in pairs(nTable) do
                                                        local lootReq = {
                                                            questID      = qId,
                                                            questTitle   = qTitle,
                                                            objIndex     = objIdx,
                                                            kind         = "loot",
                                                            targetName   = target,
                                                            description  = oText,
                                                            numFulfilled = cur,
                                                            numRequired  = needed,
                                                            finished     = isDone,
                                                        }
                                                        LinkNpcToQuestRequirement(nDropId, lootReq)
                                                    end
                                                end
                                            end
                                        end
                                        if NS.QuestItemDrops then
                                            for tVar in pairs(tVars) do
                                                local dTable = NS.QuestItemDrops[tVar]
                                                if dTable then
                                                    for mDropName in pairs(dTable) do
                                                        local lootReq = {
                                                            questID      = qId,
                                                            questTitle   = qTitle,
                                                            objIndex     = objIdx,
                                                            kind         = "loot",
                                                            targetName   = target,
                                                            description  = oText,
                                                            numFulfilled = cur,
                                                            numRequired  = needed,
                                                            finished     = isDone,
                                                        }
                                                        LinkNameToQuestRequirement(mDropName, lootReq)
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end

                                -- Only link monster target names directly (items are not creature names!)
                                if obj.Type == "monster" or obj.Type == "talk" then
                                    LinkNameToQuestRequirement(target, reqRecord)
                                    LinkNameToQuestRequirement(CleanTargetName(target), reqRecord)
                                end
                            end
                        end
                    end
                end
            end
        end

        -- 2. HYDRATE FROM BLIZZARD CLIENT QUEST LOG
        local numEntries = C.GetNumQuestLogEntries() or 0
        local maxScan = (numEntries > 0) and math.max(numEntries, 75) or 75
        local consecutiveEmpty = 0

        for i = 1, maxScan do
            local title, _, _, isHeader, _, isComplete, _, questID = C.GetQuestInfo(i)
            if not title or title == "" then
                consecutiveEmpty = consecutiveEmpty + 1
                if consecutiveEmpty >= 5 and i > numEntries then
                    break
                end
            else
                consecutiveEmpty = 0
                local isHeaderBool = (isHeader == true or isHeader == 1)
                if not isHeaderBool and title and title ~= "" then
                    local lowerTitle = string.lower(strtrim(title))
                    NS.activeQuestTitles[lowerTitle] = true
                    if questID and questID > 0 then
                        NS.activeQuestIDs[questID] = true
                    end

                    if not questID or not NS.ActiveQuests[questID] then
                        local qRecord = {
                            id = questID or 0,
                            title = title,
                            objectives = {},
                            isComplete = (isComplete == 1),
                        }
                        if questID and questID > 0 then
                            NS.ActiveQuests[questID] = qRecord
                        end

                        local objs = C.GetQuestObjectives(questID, i)
                        for objIdx, obj in ipairs(objs) do
                            local targetName = ExtractTargetName(obj.text)
                            if targetName == "" or string.len(targetName) < 3 then
                                targetName = obj.text or title
                            end
                            local isFin = obj.finished or (isComplete == 1)
                            local req = (obj.numRequired and obj.numRequired > 0) and obj.numRequired or 1
                            local cur = obj.numFulfilled or 0
                            local pStr = cur .. "/" .. req
                            local oKind = (obj.type == "item" or obj.type == "object") and "loot" or "slay"

                            local reqRecord = {
                                questID      = questID,
                                questTitle   = title,
                                objIndex     = objIdx,
                                kind         = oKind,
                                targetName   = targetName,
                                description  = obj.text,
                                numFulfilled = cur,
                                numRequired  = req,
                                finished     = isFin,
                            }
                            table.insert(qRecord.objectives, reqRecord)

                            table.insert(NS.questLogCache, {
                                questTitle   = title,
                                questID      = questID,
                                fullText     = obj.text,
                                targetName   = targetName,
                                type         = obj.type or "monster",
                                finished     = isFin,
                                numFulfilled = cur,
                                numRequired  = req,
                            })

                            -- Map from QuestKillNPCs and QuestKillMobs
                            if questID then
                                if NS.QuestKillNPCs and NS.QuestKillNPCs[questID] then
                                    for npcKId in pairs(NS.QuestKillNPCs[questID]) do
                                        LinkNpcToQuestRequirement(npcKId, reqRecord)
                                        NS.activeQuestSpawns[npcKId] = {
                                            kind     = oKind,
                                            progress = pStr,
                                            finished = isFin,
                                            title    = title,
                                            questID  = questID,
                                        }
                                    end
                                end
                                if NS.QuestKillMobs and NS.QuestKillMobs[questID] then
                                    for mobKName in pairs(NS.QuestKillMobs[questID]) do
                                        LinkNameToQuestRequirement(mobKName, reqRecord)
                                        NS.activeQuestSpawnNames[string.lower(mobKName)] = {
                                            kind     = oKind,
                                            progress = pStr,
                                            finished = isFin,
                                            title    = title,
                                            questID  = questID,
                                        }
                                    end
                                end
                            end

                            -- Map from QuestItemDrops and QuestItemNPCs
                            local lowerT = string.lower(strtrim(targetName))
                            local tVars = GetNameVariants(lowerT)
                            if NS.QuestItemNPCs then
                                for tVar in pairs(tVars) do
                                    local nTable = NS.QuestItemNPCs[tVar]
                                    if nTable then
                                        for nDropId in pairs(nTable) do
                                            local lootReq = {
                                                questID      = questID,
                                                questTitle   = title,
                                                objIndex     = objIdx,
                                                kind         = "loot",
                                                targetName   = targetName,
                                                description  = obj.text,
                                                numFulfilled = cur,
                                                numRequired  = req,
                                                finished     = isFin,
                                            }
                                            LinkNpcToQuestRequirement(nDropId, lootReq)
                                        end
                                    end
                                end
                            end
                            if NS.QuestItemDrops then
                                for tVar in pairs(tVars) do
                                    local dTable = NS.QuestItemDrops[tVar]
                                    if dTable then
                                        for mDropName in pairs(dTable) do
                                            local lootReq = {
                                                questID      = questID,
                                                questTitle   = title,
                                                objIndex     = objIdx,
                                                kind         = "loot",
                                                targetName   = targetName,
                                                description  = obj.text,
                                                numFulfilled = cur,
                                                numRequired  = req,
                                                finished     = isFin,
                                            }
                                            LinkNameToQuestRequirement(mDropName, lootReq)
                                        end
                                    end
                                end
                            end

                            LinkNameToQuestRequirement(targetName, reqRecord)
                            LinkNameToQuestRequirement(CleanTargetName(targetName), reqRecord)
                        end

                        -- If quest has no objectives listed in log (delivery / report-to / finisher quests)
                        if #objs == 0 and title and title ~= "" then
                            local reqRecord = {
                                questID      = questID,
                                questTitle   = title,
                                objIndex     = 1,
                                kind         = "talk",
                                targetName   = title,
                                description  = title,
                                numFulfilled = (isComplete == 1) and 1 or 0,
                                numRequired  = 1,
                                finished     = (isComplete == 1),
                            }
                            table.insert(qRecord.objectives, reqRecord)
                            table.insert(NS.questLogCache, {
                                questTitle   = title,
                                questID      = questID,
                                fullText     = title,
                                targetName   = title,
                                type         = "talk",
                                finished     = (isComplete == 1),
                                numFulfilled = (isComplete == 1) and 1 or 0,
                                numRequired  = 1,
                            })
                        end
                    end
                end
            end
        end
    end)

    isUpdatingCache = false
end

local tooltipScanner = CreateFrame("GameTooltip", "MyQuestPlatesScannerTooltip", nil, "GameTooltipTemplate")
tooltipScanner:SetOwner(WorldFrame, "ANCHOR_NONE")

local function GetTooltipLinesForUnit(unit)
    local lines = {}
    if not unit or IsSecretValue(unit) then return lines end

    -- 1. Modern C_TooltipInfo (if available)
    if _G.C_TooltipInfo and _G.C_TooltipInfo.GetUnit then
        local ok, data = pcall(_G.C_TooltipInfo.GetUnit, unit)
        if ok and data and data.lines and #data.lines > 1 then
            for i = 2, #data.lines do
                local line = data.lines[i]
                if _G.TooltipUtil and _G.TooltipUtil.SurfaceArgs then
                    pcall(_G.TooltipUtil.SurfaceArgs, line)
                end
                local text = line.leftText
                if text and not IsSecretValue(text) and text ~= "" then
                    table.insert(lines, text)
                end
            end
            if #lines > 0 then
                return lines
            end
        end
    end

    -- 2. Classic GameTooltip scanner fallback
    pcall(tooltipScanner.ClearLines, tooltipScanner)
    local okSet = pcall(tooltipScanner.SetUnit, tooltipScanner, unit)
    if okSet then
        local okNum, num = pcall(tooltipScanner.NumLines, tooltipScanner)
        local n = (okNum and type(num) == "number") and num or 0
        for i = 2, n do
            local fontString = _G["MyQuestPlatesScannerTooltipTextLeft" .. i]
            if fontString then
                local okText, text = pcall(fontString.GetText, fontString)
                if okText and text and not IsSecretValue(text) and text ~= "" then
                    table.insert(lines, text)
                end
            end
        end
    end

    return lines
end

-- ---------------------------------------------------------------------------
-- Quest Objective Resolution for a Unit (Multi-Tier O(1) Match Engine)
-- ---------------------------------------------------------------------------
-- Returns: hasQuest (bool), texture (string), progressText (string), kind ("slay"|"loot"|"talk"|"interact")
function NS.ResolveQuestForUnit(unit)
    if not NS.db then
        if NS.InitDB then NS.InitDB() end
    end
    if not NS.db or not NS.db.enabled then
        return false
    end

    -- Test mode mockup
    if NS.db.testMode then
        local unitName = UnitName(unit)
        if not unitName or IsSecretValue(unitName) then unitName = "Unit" end
        local isEven = (string.len(unitName) % 2 == 0)
        local testKind = isEven and "slay" or "loot"
        return true, GetTextureForKind(testKind), isEven and "3/10" or "2/5", testKind, {
            questTitle = "Test Quest Preview",
            questID = 99999,
            description = "Kill or gather test objectives",
            progress = isEven and "3/10" or "2/5",
            finished = false,
        }, {}
    end

    local guid = nil
    local okGuid, g = pcall(UnitGUID, unit)
    if okGuid and g and not IsSecretValue(g) then
        guid = g
    end

    local numNpcId = nil
    if guid then
        local okSplit, uType = pcall(strsplit, "-", guid)
        if okSplit and uType and not IsSecretValue(uType) then
            if uType ~= "Creature" and uType ~= "Vehicle" then
                return false
            end
            local _, _, _, _, _, npcIdStr = strsplit("-", guid)
            if npcIdStr and not IsSecretValue(npcIdStr) then
                numNpcId = tonumber(npcIdStr)
            end
        end
    end

    local unitName = nil
    local okName, uName = pcall(UnitName, unit)
    if okName and uName and not IsSecretValue(uName) then
        unitName = uName
    end

    if not guid and not unitName then
        return false
    end

    local lowerUnit = unitName and string.lower(strtrim(unitName))

    -- Check attackable status safely
    local isAttackable = true
    local okFriend, isFriend = pcall(UnitIsFriend, "player", unit)
    local okAttack, canAttack = pcall(UnitCanAttack, "player", unit)
    if okFriend and okAttack and not IsSecretValue(isFriend) and not IsSecretValue(canAttack) then
        isAttackable = (canAttack == true) and (isFriend ~= true)
    end

    -- -----------------------------------------------------------------------
    -- CANDIDATE GATHERING: Collect all matching requirements for this unit
    -- -----------------------------------------------------------------------
    local rawCandidates = {}

    -- A. Check NpcToQuests
    if numNpcId and NS.NpcToQuests and NS.NpcToQuests[numNpcId] then
        for _, rec in ipairs(NS.NpcToQuests[numNpcId]) do
            table.insert(rawCandidates, rec)
        end
    end

    -- B. Check NameToQuests
    if lowerUnit and NS.NameToQuests and NS.NameToQuests[lowerUnit] then
        for _, rec in ipairs(NS.NameToQuests[lowerUnit]) do
            table.insert(rawCandidates, rec)
        end
    end

    -- C. Check Questie Tooltips if preferQuestie and module available
    local QuestieTooltips = (NS.db and NS.db.preferQuestie) and GetQuestieModule("QuestieTooltips")
    local hasQuestie = (QuestieTooltips and QuestieTooltips.lookupByKey ~= nil)
    if hasQuestie and numNpcId then
        local questieTooltips = QuestieTooltips.lookupByKey["m_" .. numNpcId]
        if questieTooltips then
            for _, entry in pairs(questieTooltips) do
                local obj = entry.objective
                if obj then
                    if obj.Update then pcall(obj.Update, obj) end
                    local iconType = obj.Icon
                    local kind = "slay"
                    if iconType == 2 or iconType == 4 or iconType == 23 or (_G.Questie and (iconType == _G.Questie.ICON_TYPE_LOOT or iconType == _G.Questie.ICON_TYPE_OBJECT)) then
                        kind = "loot"
                    elseif iconType == 1 or (_G.Questie and iconType == _G.Questie.ICON_TYPE_SLAY) then
                        kind = "slay"
                    elseif iconType == 5 or (_G.Questie and iconType == _G.Questie.ICON_TYPE_TALK) then
                        kind = "talk"
                    elseif iconType == 17 or (_G.Questie and iconType == _G.Questie.ICON_TYPE_INTERACT) then
                        kind = "interact"
                    else
                        local oType = obj.Type or obj.type
                        if oType == "item" or oType == "object" then
                            kind = "loot"
                        elseif oType == "monster" then
                            kind = "slay"
                        elseif oType == "event" then
                            kind = "event"
                        else
                            kind = isAttackable and "slay" or "talk"
                        end
                    end
                    local needed = obj.Needed or obj.needed or 1
                    local cur = obj.Collected or obj.collected or 0
                    local qTitle = (entry.quest and entry.quest.name) or (obj.quest and obj.quest.name) or "Quest"
                    local qId = (entry.quest and entry.quest.Id) or (obj.quest and obj.quest.Id) or 0
                    table.insert(rawCandidates, {
                        questID      = qId,
                        questTitle   = qTitle,
                        objIndex     = obj.Index or 1,
                        kind         = kind,
                        targetName   = obj.Description,
                        description  = obj.Description,
                        numFulfilled = cur,
                        numRequired  = needed,
                        finished     = (obj.Completed == true),
                    })
                elseif entry.type == "Finisher" or entry.type == "NPC" then
                    local qTitle = (entry.quest and entry.quest.name) or "Quest"
                    local qId = (entry.quest and entry.quest.Id) or 0
                    table.insert(rawCandidates, {
                        questID      = qId,
                        questTitle   = qTitle,
                        objIndex     = 1,
                        kind         = "talk",
                        targetName   = qTitle,
                        description  = "Turn in: " .. qTitle,
                        numFulfilled = 0,
                        numRequired  = 1,
                        finished     = false,
                    })
                end
            end
        end
    end

    -- -----------------------------------------------------------------------
    -- LIVE REQUIREMENT EVALUATION & DEDUPLICATION
    -- -----------------------------------------------------------------------
    local evaluated = {}
    local seenKey = {}
    local incompleteList = {}
    local completeList = {}

    for _, cand in ipairs(rawCandidates) do
        local live = NS.GetLiveRequirement(cand)
        if live then
            local key = tostring(live.questID) .. ":" .. tostring(live.objIndex) .. ":" .. tostring(live.kind)
            if not seenKey[key] then
                seenKey[key] = true
                table.insert(evaluated, live)
                if live.finished then
                    table.insert(completeList, live)
                else
                    table.insert(incompleteList, live)
                end
            end
        end
    end

    -- Fallback 1: If no direct hash match, check Tooltip Lines
    if #evaluated == 0 then
        local tooltipLines = GetTooltipLinesForUnit(unit)
        if #tooltipLines > 0 then
            local currentQuestMatch = nil
            for _, lineText in ipairs(tooltipLines) do
                local lowerLine = string.lower(strtrim(lineText))
                local cleanTitle = string.match(lowerLine, "^%[?(.-)%]?$") or lowerLine
                if NS.activeQuestTitles[cleanTitle] or NS.activeQuestTitles[lowerLine] then
                    currentQuestMatch = cleanTitle
                end

                local cur, req = string.match(lineText, "(%d+)%s*/%s*(%d+)")
                if cur and req then
                    local curNum = tonumber(cur) or 0
                    local reqNum = tonumber(req) or 1
                    local isFin = (curNum >= reqNum)
                    local kind = isAttackable and "slay" or "talk"

                    local live = {
                        questID      = 0,
                        questTitle   = currentQuestMatch or "Quest",
                        objIndex     = 1,
                        kind         = kind,
                        targetName   = lineText,
                        description  = lineText,
                        numFulfilled = curNum,
                        numRequired  = reqNum,
                        progress     = curNum .. "/" .. reqNum,
                        finished     = isFin,
                    }
                    table.insert(evaluated, live)
                    if isFin then
                        table.insert(completeList, live)
                    else
                        table.insert(incompleteList, live)
                    end
                end
            end
        end
    end

    -- Fallback 2: Algorithmic / Database Drop Lookup fallback
    if #evaluated == 0 and (unitName or numNpcId) and #NS.questLogCache > 0 then
        for _, cached in ipairs(NS.questLogCache) do
            if cached.targetName and cached.targetName ~= "" then
                local isItem = (cached.type == "item" or cached.type == "object")
                local isMatched = false

                if cached.questID then
                    if numNpcId and NS.QuestKillNPCs and NS.QuestKillNPCs[cached.questID] and NS.QuestKillNPCs[cached.questID][numNpcId] then
                        isMatched = true
                        isItem = false
                    elseif lowerUnit and NS.QuestKillMobs and NS.QuestKillMobs[cached.questID] and NS.QuestKillMobs[cached.questID][lowerUnit] then
                        isMatched = true
                        isItem = false
                    end
                end

                if not isMatched then
                    local isDrop = LookupQuestItemDrop(cached.targetName, unitName, numNpcId)
                    if isDrop then
                        isMatched = true
                        isItem = true
                    end
                end

                if not isMatched and unitName then
                    isMatched = IsNameMatch(unitName, cached.targetName, isItem)
                end

                if isMatched then
                    local kind = isItem and "loot" or "slay"
                    if cached.type == "talk" then kind = "talk" end
                    local live = NS.GetLiveRequirement({
                        questID      = cached.questID,
                        questTitle   = cached.questTitle,
                        objIndex     = 1,
                        kind         = kind,
                        targetName   = cached.targetName,
                        description  = cached.fullText,
                        numFulfilled = cached.numFulfilled,
                        numRequired  = cached.numRequired,
                        finished     = cached.finished,
                    })
                    table.insert(evaluated, live)
                    if live.finished then
                        table.insert(completeList, live)
                    else
                        table.insert(incompleteList, live)
                    end
                    break
                end
            end
        end
    end

    -- Fallback 3: Boss / Quest Related Engine Check
    if #evaluated == 0 and isAttackable then
        local isBoss = false
        if _G.UnitIsQuestBoss then
            local ok, b = pcall(_G.UnitIsQuestBoss, unit)
            if ok and not IsSecretValue(b) and b == true then isBoss = true end
        end
        local isRelated = false
        if _G.C_QuestLog and _G.C_QuestLog.UnitIsRelatedToActiveQuest then
            local ok, r = pcall(_G.C_QuestLog.UnitIsRelatedToActiveQuest, unit)
            if ok and not IsSecretValue(r) and r == true then isRelated = true end
        end

        if isBoss or isRelated then
            local live = {
                questID      = 0,
                questTitle   = isBoss and "Quest Target Boss" or "Active Quest Target",
                objIndex     = 1,
                kind         = isBoss and "slay" or "loot",
                targetName   = unitName or "Target",
                description  = isBoss and "Boss target for active quest" or "Related to active quest",
                numFulfilled = 0,
                numRequired  = 1,
                progress     = "",
                finished     = false,
            }
            table.insert(evaluated, live)
            table.insert(incompleteList, live)
        end
    end

    if #evaluated == 0 then
        return false
    end

    -- -----------------------------------------------------------------------
    -- SELECTION & KIND FILTERING
    -- -----------------------------------------------------------------------
    local chosen = nil
    if #incompleteList > 0 then
        chosen = incompleteList[1]
    elseif not NS.db.showOnlyIncomplete and #completeList > 0 then
        chosen = completeList[1]
    end

    if not chosen then
        return false
    end

    local kind = chosen.kind or (isAttackable and "slay" or "talk")
    if (kind == "slay" or kind == "loot") and not isAttackable then
        kind = "talk"
    end

    local showIt = false
    if kind == "slay" and NS.db.showSlay then showIt = true end
    if kind == "loot" and NS.db.showLoot then showIt = true end
    if kind == "talk" and NS.db.showTalk then showIt = true end
    if kind == "interact" or kind == "event" then showIt = true end

    if showIt then
        local tex = GetTextureForKind(kind)
        return true, tex, chosen.progress or "", kind, chosen, evaluated
    end

    return false
end

-- ---------------------------------------------------------------------------
-- Nameplate Layout & Anchor Management (Configured Once, Zero In-Combat Shifts)
-- ---------------------------------------------------------------------------
local function ApplyFramePosition(f, plate)
    local anchor = plate.mpFrame or plate.UnitFrame or plate
    local point = (NS.db and NS.db.anchorPoint) or "LEFT"
    local x = (NS.db and NS.db.xOffset) or 8
    local y = (NS.db and NS.db.yOffset) or 0
    local size = (NS.db and NS.db.iconSize) or 24

    f:SetSize(size, size)
    f:ClearAllPoints()

    -- If plate.mpFrame does not exist and anchor is plate, offset from plate center
    if anchor == plate then
        local halfW = 60
        if point == "LEFT" then
            f:SetPoint("CENTER", plate, "CENTER", -(halfW + x + size / 2), y)
        elseif point == "RIGHT" then
            f:SetPoint("CENTER", plate, "CENTER", halfW + x + size / 2, y)
        elseif point == "TOP" then
            f:SetPoint("CENTER", plate, "CENTER", x, 15 + y + size / 2)
        else
            f:SetPoint("CENTER", plate, "CENTER", -(halfW + x + size / 2), y)
        end
    else
        if point == "LEFT" then
            f:SetPoint("RIGHT", anchor, "LEFT", -x, y)
        elseif point == "RIGHT" then
            f:SetPoint("LEFT", anchor, "RIGHT", x, y)
        elseif point == "TOP" then
            f:SetPoint("BOTTOM", anchor, "TOP", x, y)
        elseif point == "TOPLEFT" then
            f:SetPoint("BOTTOMRIGHT", anchor, "TOPLEFT", -x, y)
        elseif point == "TOPRIGHT" then
            f:SetPoint("BOTTOMLEFT", anchor, "TOPRIGHT", x, y)
        else
            f:SetPoint("RIGHT", anchor, "LEFT", -x, y)
        end
    end

    local anchorLevel = anchor:GetFrameLevel() or plate:GetFrameLevel() or 10
    f:SetFrameLevel(anchorLevel + 35)

    local fontSize = (NS.db and NS.db.fontSize) or 10
    f.Text:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
end

function NS.RefreshAllPlatePositions()
    for plate, f in pairs(PlateFrames) do
        if plate and f then
            ApplyFramePosition(f, plate)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Nameplate Indicator Frame Creation (Attached directly to plate root)
-- ---------------------------------------------------------------------------
local function CreatePlateIndicator(plate)
    if not plate or PlateFrames[plate] then return PlateFrames[plate] end

    -- f is created directly on plate root so other addons never orphan or unparent it
    local f = CreateFrame("Frame", nil, plate)
    f.isMyQuestPlates = true
    f.isQuestPlate = true
    f:EnableMouse(true)
    if f.SetMouseClickEnabled then
        pcall(f.SetMouseClickEnabled, f, false)
    end
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel((plate:GetFrameLevel() or 10) + 35)
    f:Hide()

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(f)
    icon:SetTexCoord(0, 1, 0, 1)
    f.Icon = icon

    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetFont(STANDARD_TEXT_FONT, (NS.db and NS.db.fontSize) or 10, "OUTLINE")
    text:SetTextColor(1, 0.9, 0.2, 1)
    text:SetPoint("BOTTOM", f, "BOTTOM", 0, -11)
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, 1)
    f.Text = text

    f:SetScript("OnEnter", function(self)
        if not self._activeRequirements or #self._activeRequirements == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Quest Objectives", 1, 0.82, 0)
        local seenTitle = {}
        for _, req in ipairs(self._activeRequirements) do
            local qTitle = req.questTitle or "Quest"
            local qIdStr = (req.questID and req.questID > 0) and (" |cff888888(ID: " .. req.questID .. ")|r") or ""
            if not seenTitle[qTitle] then
                seenTitle[qTitle] = true
                GameTooltip:AddLine(qTitle .. qIdStr, 1, 1, 1)
            end
            local statusColor = req.finished and "|cff00ff00[Complete]|r " or ""
            local progStr = (req.progress and req.progress ~= "") and (" (" .. req.progress .. ")") or ""
            local desc = req.description or req.targetName or ""
            local kindTag = req.kind and (" |cffaaaaaa[" .. string.upper(req.kind) .. "]|r") or ""
            GameTooltip:AddLine("  " .. statusColor .. desc .. progStr .. kindTag, 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)

    f:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    PlateFrames[plate] = f
    ApplyFramePosition(f, plate)

    return f
end

-- ---------------------------------------------------------------------------
-- Update Nameplate Unit
-- ---------------------------------------------------------------------------
local ActivePlates = {}

local function UpdatePlateIndicator(plate, unit)
    if not plate then return end
    local f = PlateFrames[plate] or CreatePlateIndicator(plate)
    if not f then return end

    if not unit then
        unit = f._unit or plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
    end
    if not unit then
        f:Hide()
        return
    end
    f._unit = unit

    local okExists, exists = pcall(UnitExists, unit)
    if okExists and not IsSecretValue(exists) and exists == false then
        f:Hide()
        return
    end

    local ok, hasQuest, texture, progress, kind, chosenReq, allReqs = pcall(NS.ResolveQuestForUnit, unit)
    if not ok or not hasQuest or not texture or IsSecretValue(texture) then
        f._activeRequirements = nil
        f:Hide()
        return
    end

    f._activeRequirements = allReqs
    f._chosenReq = chosenReq

    ApplyFramePosition(f, plate)
    f.Icon:SetTexture(texture)

    if NS.db and NS.db.showProgressText and progress and not IsSecretValue(progress) and progress ~= "" then
        f.Text:SetText(progress)
        f.Text:Show()
    else
        f.Text:SetText("")
        f.Text:Hide()
    end

    f:SetAlpha(1)
    f:Show()
end

function NS.UpdateNamePlate(unit)
    if not unit or IsSecretValue(unit) then return end
    local plate = C.GetNamePlateForUnit(unit)
    if plate then
        UpdatePlateIndicator(plate, unit)
    end
end

-- ---------------------------------------------------------------------------
-- Refresh All Active Nameplates
-- ---------------------------------------------------------------------------
function NS.UpdateAllNameplates()
    local plates = C.GetNamePlates()
    for _, plate in ipairs(plates) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        local f = PlateFrames[plate]
        if f and f._unit then unit = f._unit end
        if unit then
            UpdatePlateIndicator(plate, unit)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Event Frame & Dispatch
-- ---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame", "MyQuestPlatesCoreFrame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("NAME_PLATE_CREATED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
eventFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
eventFrame:RegisterEvent("QUEST_ACCEPTED")
eventFrame:RegisterEvent("QUEST_REMOVED")
eventFrame:RegisterEvent("QUEST_TURNED_IN")
eventFrame:RegisterEvent("QUEST_WATCH_UPDATE")
eventFrame:RegisterEvent("QUEST_DATA_LOAD_RESULT")
eventFrame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("CHAT_MSG_LOOT")
eventFrame:RegisterEvent("UNIT_NAME_UPDATE")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")

local timeSinceLastTick = 0
eventFrame:SetScript("OnUpdate", function(self, elapsed)
    timeSinceLastTick = timeSinceLastTick + elapsed
    if timeSinceLastTick >= 0.25 then
        timeSinceLastTick = 0
        NS.UpdateAllNameplates()
    end
end)

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        NS.InitDB()
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        NS.UpdateQuestLogCache()
        local plates = C.GetNamePlates()
        for _, plate in ipairs(plates) do
            CreatePlateIndicator(plate)
        end
        NS.UpdateAllNameplates()

        -- Delayed hydration to capture quest log entries after server sync
        if C_Timer and C_Timer.After then
            C_Timer.After(0.5, function()
                NS.UpdateQuestLogCache()
                NS.UpdateAllNameplates()
            end)
            C_Timer.After(1.5, function()
                NS.UpdateQuestLogCache()
                NS.UpdateAllNameplates()
            end)
            C_Timer.After(3.0, function()
                NS.UpdateQuestLogCache()
                NS.UpdateAllNameplates()
            end)
        end
    elseif event == "NAME_PLATE_CREATED" then
        CreatePlateIndicator(arg1)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if not arg1 or IsSecretValue(arg1) then return end
        local plate = C.GetNamePlateForUnit(arg1)
        if plate then
            ActivePlates[arg1] = plate
            local f = PlateFrames[plate] or CreatePlateIndicator(plate)
            if f then f._unit = arg1 end
            UpdatePlateIndicator(plate, arg1)
            -- Follow-up retry after nameplate layout settles
            if C_Timer and C_Timer.After then
                C_Timer.After(0.05, function()
                    if ActivePlates[arg1] then
                        UpdatePlateIndicator(plate, arg1)
                    end
                end)
            end
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if not arg1 or IsSecretValue(arg1) then return end
        local plate = ActivePlates[arg1] or C.GetNamePlateForUnit(arg1)
        if plate and PlateFrames[plate] then
            PlateFrames[plate]._unit = nil
            PlateFrames[plate]:Hide()
        end
        ActivePlates[arg1] = nil
    elseif event == "UNIT_NAME_UPDATE" then
        if arg1 and not IsSecretValue(arg1) and string.sub(arg1, 1, 9) == "nameplate" then
            NS.UpdateNamePlate(arg1)
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        if UnitExists("target") then
            local plate = C.GetNamePlateForUnit("target")
            if plate then
                UpdatePlateIndicator(plate, "target")
            end
        end
    elseif event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" or
           event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" or
           event == "QUEST_TURNED_IN" or event == "QUEST_WATCH_UPDATE" or
           event == "QUEST_DATA_LOAD_RESULT" or event == "QUEST_WATCH_LIST_CHANGED" or
           event == "ZONE_CHANGED_NEW_AREA" or event == "CHAT_MSG_LOOT" then
        NS.UpdateQuestLogCache()
        NS.UpdateAllNameplates()
    end
end)
