--------------------------------------------------------------------------------
-- nugsPortals
-- Copyright (c) 2026 nugs. All Rights Reserved.
-- Unauthorized copying, distribution, or modification is prohibited. See LICENSE.
--------------------------------------------------------------------------------
-- nugsPortals  -  Core.lua
-- The namespace, saved variables, the slash command and the events.
--
-- One idea: every Mythic+ dungeon teleport in the game, listed under the name of the
-- DUNGEON it takes you to.
--
-- The game files them the other way round. Each expansion gets a spellbook flyout
-- called "Hero's Path: <expansion>", and inside it the portals are named for lore
-- rather than for places - "Path of the Ruined City" is the one to Ara-Kara. Finding
-- the portal for the dungeon your group just formed for means knowing which expansion
-- it came from and then which poetic name is which. This puts the dungeon first.
--
-- Shared namespace: the second vararg is the same table across every Lua file in
-- this addon, so all state and functions hang off of it.
--------------------------------------------------------------------------------

local ADDON_NAME, NPT = ...

NPT.name    = ADDON_NAME
NPT.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version"))
              or "0.1.0"

local PREFIX = "|cff6fc2ffnugsPortals|r: "
function NPT.Print(msg)
    print(PREFIX .. tostring(msg))
end

--------------------------------------------------------------------------------
-- Secret values (Midnight / 12.0)
--
-- Nothing this addon reads is combat data - spellbook flyouts, spell descriptions
-- and the season's dungeon list are all plain - but the guard costs nothing and every
-- sibling has it, so anything out of a game API goes through these before it is
-- compared or concatenated.
--------------------------------------------------------------------------------

local issecretvalue = _G.issecretvalue

local function Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
NPT.Plain = Plain

function NPT.PlainNumber(v)
    v = Plain(v)
    if type(v) ~= "number" then return nil end
    return v
end

function NPT.PlainString(v)
    v = Plain(v)
    if type(v) ~= "string" then return nil end
    return v
end

-- true / false / nil, where nil means "not allowed to know". A secret boolean cannot
-- even be truth-tested, so this is the only safe way to branch on one.
function NPT.PlainBool(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v and true or false
end

-- Calls that may not exist on every build, without the caller writing the same three
-- lines each time. Returns up to three results.
function NPT.Try(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c
end

--------------------------------------------------------------------------------
-- Saved variables
--
-- Account-wide and small. Which portals you have earned is the game's to say, not
-- ours to store - it is read fresh every time - so the only things worth keeping are
-- where the window and the minimap button sit.
--------------------------------------------------------------------------------

NPT.defaults = {
    minimapHidden = false,
    minimapAngle  = 215,

    -- The window, where you last left it. Nil until it has been moved once, which
    -- means "centre of the screen".
    point = nil,
    x     = nil,
    y     = nil,

    -- Whether portals you have not earned are listed. On by default: seeing what
    -- exists is half of what the list is for.
    showUnearned = true,

    -- Which sections and expansions are folded shut, by key: "season", "dungeons",
    -- "raids", and "g<flyoutID>" for one expansion. Absent means open, so a group the
    -- game adds next patch arrives open rather than hidden.
    collapsed = {},

    -- This season's portals in a narrow panel docked beside the Mythic+ Dungeons page,
    -- whenever that page is open. On by default: it only ever appears next to a page
    -- you opened yourself.
    attachToMythicPage = true,

    -- The last /np dump. Diagnostic only; never exported.
    dump = nil,
}

local function CopyTable(v)
    local t = {}
    for i, n in pairs(v) do
        t[i] = (type(n) == "table") and CopyTable(n) or n
    end
    return t
end
NPT.CopyTable = CopyTable

local function InitDB()
    -- Reached through NPT.db from here on, never through a file-scope local:
    -- SavedVariables are populated AFTER an addon's files run, and a local taken at
    -- file scope would point at a table the client is about to replace.
    nugsPortalsDB = nugsPortalsDB or {}
    NPT.db = nugsPortalsDB
    for k, v in pairs(NPT.defaults) do
        if NPT.db[k] == nil and v ~= nil then
            NPT.db[k] = (type(v) == "table") and CopyTable(v) or v
        end
    end
    if type(NPT.db.minimapAngle) ~= "number" then NPT.db.minimapAngle = NPT.defaults.minimapAngle end
    if type(NPT.db.collapsed) ~= "table" then NPT.db.collapsed = {} end
end

--------------------------------------------------------------------------------
-- Slash command
--------------------------------------------------------------------------------

local function HandleSlash(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")

    if cmd == "" or cmd == "show" or cmd == "toggle" then
        NPT.Window:Toggle()

    elseif cmd == "dump" then
        NPT.Data.Dump()

    elseif cmd == "minimap" then
        NPT.db.minimapHidden = not NPT.db.minimapHidden
        NPT.SetMinimapShown(not NPT.db.minimapHidden)
        NPT.Print("minimap button " .. (NPT.db.minimapHidden and "hidden." or "shown."))

    elseif cmd == "attach" then
        NPT.SetAttach(not NPT.db.attachToMythicPage)
        NPT.Print("portals beside the Mythic+ page " ..
                  (NPT.db.attachToMythicPage and "on." or "off."))

    elseif cmd == "help" then
        NPT.Print("commands:")
        print("  |cff6fc2ff/np|r - open or close the portal list")
        print("  |cff6fc2ff/np attach|r - this season's portals beside the Mythic+ page, on or off")
        print("  |cff6fc2ff/np minimap|r - show or hide the minimap button")
        print("  |cff6fc2ff/np dump|r - record what the game says about every portal,")
        print("      for when a dungeon name comes out wrong")

    else
        NPT.Print("unknown command. Try |cff6fc2ff/np help|r.")
    end
end

-- /np is the one to type. Checked against every addon installed on the dev client on
-- 2026-11-16 - nothing else claims /np or /nport. The long forms stay so a macro
-- written against the first build keeps working.
SLASH_NUGSPORTALS1 = "/np"
SLASH_NUGSPORTALS2 = "/nport"
SLASH_NUGSPORTALS3 = "/nportals"
SLASH_NUGSPORTALS4 = "/nugsportals"
SlashCmdList["NUGSPORTALS"] = HandleSlash

--------------------------------------------------------------------------------
-- Keybinding
--
-- Named here, run from Bindings.xml. The binding body is a bare global that forwards
-- to the slash handler, so a key, a macro and the minimap button are one code path.
-- The XML carries `name` and nothing else - see the note in nugsNotToday's Core.lua
-- for the two attributes 12.1 rejects and the quote-in-body bug the bare global
-- avoids.
--------------------------------------------------------------------------------

BINDING_NAME_NUGSPORTALS_TOGGLE = "Open or close the portal list"

function nugsPortalsToggle()
    HandleSlash("toggle")
end

--------------------------------------------------------------------------------
-- nugsSuite
--
-- One entry written into a plain global table. Not a call into the suite: a global
-- is free of load order, so whichever side loads first the table is already there
-- and neither addon has to exist for the other to work.
--------------------------------------------------------------------------------

local function RegisterWithSuite()
    _G.nugsSuiteRegistry = _G.nugsSuiteRegistry or {}
    _G.nugsSuiteRegistry[ADDON_NAME] = {
        title      = "nugsPortals",
        version    = NPT.version,
        icon       = "Interface\\AddOns\\nugsPortals\\icon",
        slash      = "/np",
        Open       = function() NPT.Window:Toggle() end,
        SetMinimap = function(shown)
            NPT.db.minimapHidden = not shown
            NPT.SetMinimapShown(shown)
        end,
        GetDB      = function() return NPT.db, NPT.defaults end,
        -- Where things sit on this screen is nobody else's business, and the dump is
        -- a diagnostic, not a setting.
        exclude    = { minimapAngle = true, point = true, x = true, y = true, dump = true },
    }
end

--------------------------------------------------------------------------------
-- Events
--
-- Everything that can change what the list says - a portal learned, a cooldown
-- started, the season's dungeons arriving from the server, a spell description
-- finishing loading - funnels into one request for a refresh. The window decides
-- whether there is anything to do: it does nothing while hidden, and nothing in
-- combat, where the buttons that cast the portals cannot be touched.
--------------------------------------------------------------------------------

-- One switch, used by the slash command and the button in the main window, so the two
-- cannot leave the setting and the screen disagreeing.
function NPT.SetAttach(on)
    NPT.db.attachToMythicPage = on and true or false
    NPT.Attach:Sync()
    if NPT.Window.RefreshFooter then NPT.Window:RefreshFooter() end
end

local function RefreshEverything()
    NPT.Window:RequestRefresh()
    NPT.Attach:RequestRefresh()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
events:RegisterEvent("SPELL_DATA_LOAD_RESULT")
events:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            InitDB()
            RegisterWithSuite()
        elseif arg1 == "Blizzard_ChallengesUI" then
            -- The Mythic+ page is load-on-demand: its frame does not exist until the
            -- page is first opened, so the panel beside it is hooked up here.
            NPT.Attach:Hook()
        end

    elseif event == "PLAYER_LOGIN" then
        NPT.InitMinimap()
        NPT.InitOptions()
        -- In case something else loaded the Mythic+ page before this addon did.
        if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_ChallengesUI") then
            NPT.Attach:Hook()
        end
        -- The season's dungeon list comes from the server and is empty until asked
        -- for. Asking at login means it is there by the time anybody opens the list.
        if C_MythicPlus and C_MythicPlus.RequestMapInfo then
            pcall(C_MythicPlus.RequestMapInfo)
        end

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Fires just BEFORE the combat lockdown begins, which is the last moment the
        -- window can be hidden: it holds the buttons that cast the portals, and those
        -- are protected for the whole fight.
        NPT.Window:OnCombatStart()
        NPT.Attach:OnCombatStart()

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- The panel beside the Mythic+ page comes back if the page is still open. The
        -- main window does not: reopening that uninvited after a pull would be a
        -- window popping up at the end of every fight.
        NPT.Attach:Sync()
        RefreshEverything()

    else
        RefreshEverything()
    end
end)
