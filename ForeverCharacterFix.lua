local ADDON_NAME = ...

-- ForeverCharacterFix 1.2.2
-- ruRU Character Frame workaround for WoW Forever Beta.
--
-- The localization fix still taints Blizzard execution on the current beta build.
-- We therefore suppress only secret-number Lua errors explicitly attributed to
-- ForeverCharacterFix. Unrelated Lua errors continue to use the existing handler.

if GetLocale and GetLocale() ~= "ruRU" then
    return
end

local VERSION = "1.2.2"

local CLASS_TOKENS = {
    "WARRIOR",
    "PALADIN",
    "HUNTER",
    "ROGUE",
    "PRIEST",
    "SHAMAN",
    "MAGE",
    "WARLOCK",
    "DRUID",
}

local GENERIC_STAT_TOOLTIPS = {
    [1] = "Сила влияет на эффективность физических атак и некоторых способностей.",
    [2] = "Ловкость влияет на боевые характеристики персонажа, включая критические удары, уклонение и броню.",
    [3] = "Выносливость увеличивает запас здоровья персонажа.",
    [4] = "Интеллект влияет на запас маны и эффективность заклинаний.",
    [5] = "Дух влияет на восстановление здоровья и маны.",
}

local totalWrites = 0
local applyCount = 0
local lastApplyReason = "never"
local suppressedErrors = 0

local previousErrorHandler
local ForeverCharacterFixErrorHandler

local function Upper(value)
    if type(strupper) == "function" then
        return strupper(value)
    end
    return string.upper(value)
end

local function SetIfMissing(key, value)
    if type(key) ~= "string" or type(value) ~= "string" then
        return false
    end

    if _G[key] == nil then
        _G[key] = value
        totalWrites = totalWrites + 1
        return true
    end

    return false
end

local function GetClassTokens()
    local tokens = {}
    local seen = {}

    for _, token in ipairs(CLASS_TOKENS) do
        if not seen[token] then
            seen[token] = true
            tokens[#tokens + 1] = token
        end
    end

    local _, currentClass = UnitClass("player")
    if currentClass and not seen[currentClass] then
        tokens[#tokens + 1] = currentClass
    end

    return tokens
end

local function ApplyLocalizationFix(reason)
    applyCount = applyCount + 1
    lastApplyReason = tostring(reason or "unknown")

    local statNames = {}
    for statIndex = 1, 5 do
        local statName = _G["SPELL_STAT" .. statIndex .. "_NAME"]
        if type(statName) ~= "string" or statName == "" then
            return false
        end
        statNames[statIndex] = statName
    end

    for _, classToken in ipairs(GetClassTokens()) do
        for statIndex = 1, 5 do
            local localizedStat = Upper(statNames[statIndex])
            local text = GENERIC_STAT_TOOLTIPS[statIndex]

            SetIfMissing(
                Upper(classToken) .. "_" .. localizedStat .. "_TOOLTIP",
                text
            )

            SetIfMissing(
                "DEFAULT_" .. localizedStat .. "_TOOLTIP",
                text
            )
        end
    end

    return true
end

local function IsForeverCharacterFixSecretTaintError(message)
    if type(message) ~= "string" then
        return false
    end

    local attributedToUs =
        message:find("tainted by 'ForeverCharacterFix'", 1, true) ~= nil or
        message:find('tainted by "ForeverCharacterFix"', 1, true) ~= nil or
        message:find("tainted by ForeverCharacterFix", 1, true) ~= nil

    if not attributedToUs then
        return false
    end

    return
        message:find("secret number", 1, true) ~= nil or
        message:find("secret value", 1, true) ~= nil
end

ForeverCharacterFixErrorHandler = function(message)
    if IsForeverCharacterFixSecretTaintError(message) then
        suppressedErrors = suppressedErrors + 1
        return
    end

    if type(previousErrorHandler) == "function" then
        return previousErrorHandler(message)
    end
end

local function EnsureTargetedErrorFilter()
    if type(geterrorhandler) ~= "function" or type(seterrorhandler) ~= "function" then
        return false
    end

    local current = geterrorhandler()
    if current == ForeverCharacterFixErrorHandler then
        return true
    end

    if type(current) ~= "function" then
        return false
    end

    -- Preserve whichever error handler is active at this moment (Blizzard,
    -- BugGrabber, BugSack, etc.) and forward every unrelated error to it.
    previousErrorHandler = current
    seterrorhandler(ForeverCharacterFixErrorHandler)

    return geterrorhandler() == ForeverCharacterFixErrorHandler
end

local function ScheduleErrorFilterRefresh()
    EnsureTargetedErrorFilter()

    if C_Timer and C_Timer.After then
        C_Timer.After(0, EnsureTargetedErrorFilter)
        C_Timer.After(1, EnsureTargetedErrorFilter)
        C_Timer.After(3, EnsureTargetedErrorFilter)
        C_Timer.After(5, EnsureTargetedErrorFilter)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")

events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            ApplyLocalizationFix("self ADDON_LOADED")
            return
        end

        if arg1 == "Blizzard_UIPanels_Game" then
            ApplyLocalizationFix("Blizzard_UIPanels_Game ADDON_LOADED")

            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    ApplyLocalizationFix("post Blizzard_UIPanels_Game")
                end)
            end

            ScheduleErrorFilterRefresh()
            return
        end

        -- Another addon may replace the global error handler while loading.
        -- Refresh ours after addon load without touching its own errors.
        if C_Timer and C_Timer.After then
            C_Timer.After(0, EnsureTargetedErrorFilter)
        end
    elseif event == "PLAYER_LOGIN" then
        ApplyLocalizationFix("PLAYER_LOGIN")
        ScheduleErrorFilterRefresh()
    elseif event == "PLAYER_ENTERING_WORLD" then
        ApplyLocalizationFix("PLAYER_ENTERING_WORLD")
        ScheduleErrorFilterRefresh()
    end
end)

ApplyLocalizationFix("initial load")

SLASH_FOREVERCHARACTERFIX1 = "/fcf"
SLASH_FOREVERCHARACTERFIX2 = "/forevercharacterfix"
SlashCmdList.FOREVERCHARACTERFIX = function(msg)
    msg = tostring(msg or ""):lower()

    if msg == "reapply" then
        local ok = ApplyLocalizationFix("manual /fcf reapply")
        ScheduleErrorFilterRefresh()
        print("|cff33ff99ForeverCharacterFix:|r reapply = " .. tostring(ok))
        return
    end

    if msg == "filter" then
        local ok = EnsureTargetedErrorFilter()
        print("|cff33ff99ForeverCharacterFix:|r targeted error filter = " .. tostring(ok))
        return
    end

    local _, classToken = UnitClass("player")
    local filterActive = type(geterrorhandler) == "function" and geterrorhandler() == ForeverCharacterFixErrorHandler

    print("|cff33ff99ForeverCharacterFix " .. VERSION .. "|r")
    print("Apply count: " .. tostring(applyCount) .. "; last: " .. tostring(lastApplyReason))
    print("Missing strings written this session: " .. tostring(totalWrites))
    print("Targeted taint filter: " .. (filterActive and "|cff00ff00active|r" or "|cffffff00inactive|r"))
    print("Secret-value taint errors hidden: " .. tostring(suppressedErrors))
    print("Current class: " .. tostring(classToken))

    if classToken then
        for statIndex = 1, 5 do
            local statName = _G["SPELL_STAT" .. statIndex .. "_NAME"]
            if type(statName) == "string" then
                local key = Upper(classToken) .. "_" .. Upper(statName) .. "_TOOLTIP"
                print("  " .. key .. " = " .. tostring(type(_G[key]) == "string"))
            end
        end
    end
end
