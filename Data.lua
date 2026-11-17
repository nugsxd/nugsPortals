--------------------------------------------------------------------------------
-- nugsPortals
-- Copyright (c) 2026 nugs. All Rights Reserved.
-- Unauthorized copying, distribution, or modification is prohibited. See LICENSE.
--------------------------------------------------------------------------------
-- nugsPortals  -  Data.lua
-- Where the portals come from, and how each one is named after its dungeon.
--
-- READ FROM THE GAME, NOT FROM A LIST
--
-- Every expansion's dungeon teleports live in a spellbook flyout - "Hero's Path: The
-- War Within" and so on - and the client will describe any flyout by id, earned or
-- not: its name, how many slots it has, and for each slot the spell, its name, and
-- whether this character knows it. So the whole catalogue is read at runtime. A new
-- season or a new expansion adds a flyout or a slot, and this picks it up with no
-- release, which a hand-kept table of spell ids never would.
--
-- WHICH DUNGEON
--
-- No API links a teleport to its dungeon. The link exists in exactly one place: the
-- spell's own description, "Teleport to the entrance to Ara-Kara, City of Echoes." So
-- the dungeon name is read out of that sentence. It is the client's own text, so it is
-- always current - but it is an English sentence, and a client in another language
-- will not match the patterns below. Those portals fall back to their own spell name,
-- which is still correct, just less helpful. `/np dump` records every
-- description verbatim, which is how the patterns get checked against a real client
-- rather than against what I expect it to say.
--
-- This file has no UI in it on purpose: it is what the test harness loads.
--------------------------------------------------------------------------------

local ADDON_NAME, NPT = ...

local Data = {}
NPT.Data = Data

local PlainNumber, PlainString, PlainBool, Try =
      NPT.PlainNumber, NPT.PlainString, NPT.PlainBool, NPT.Try

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

-- For comparing names that are written slightly differently in different places:
-- case, punctuation, and a leading "The" are not differences anybody means.
function Data.Norm(s)
    if type(s) ~= "string" then return "" end
    s = s:lower()
    s = s:gsub("%p", " ")
    s = s:gsub("%s+", " ")
    s = s:gsub("^ ", ""):gsub(" $", "")
    s = s:gsub("^the ", "")
    return s
end

-- The leads the game uses in front of a destination. Longest first, so "to the
-- entrance to X" is never caught by the bare "to X" and returned as "the entrance
-- to X".
local LEADS = {
    "[Tt]eleports? you to the entrance to (.+)",
    "[Tt]eleports? you to the entrance of (.+)",
    "[Tt]eleports? to the entrance to (.+)",
    "[Tt]eleports? to the entrance of (.+)",
    "[Tt]eleports? you to (.+)",
    "[Tt]eleports? to (.+)",
}

-- "Teleport to the entrance to Ara-Kara, City of Echoes." -> "Ara-Kara, City of Echoes"
function Data.DungeonFromDescription(desc)
    if type(desc) ~= "string" or desc == "" then return nil end
    -- The destination is in the first sentence of the first line. Anything after it
    -- - a cooldown note, a requirement - is not part of the name.
    local line = desc:match("^[^\r\n]*") or desc
    for _, lead in ipairs(LEADS) do
        local name = line:match(lead)
        if name then
            name = name:gsub("%.%s.*$", "")      -- a second sentence
            name = name:gsub("[%.%s]+$", "")     -- the full stop that ends this one
            -- "the Necrotic Wake" reads oddly at the start of a row.
            name = name:gsub("^the ", "The ")
            if name ~= "" then return name end
        end
    end
    return nil
end

-- Whether two names are the same dungeon.
--
-- They come from two places that do not agree on spelling. The portal's description
-- names the whole dungeon; the season's list names the Mythic+ map, and for a
-- dungeon split into halves that is one half - "Tazavesh: So'leah's Gambit" is a
-- season map whose portal goes to Tazavesh. So: equal, or one is the other with more
-- on the end, or they agree up to the first colon or comma. Short fragments are never
-- trusted on their own, or "Halls" would match half the game.
local MIN_FRAGMENT = 6

function Data.SameDungeon(a, b)
    local x, y = Data.Norm(a), Data.Norm(b)
    if x == "" or y == "" then return false end
    if x == y then return true end

    if #x >= MIN_FRAGMENT and #y >= MIN_FRAGMENT then
        -- Whole words only: "operation mechagon" is inside "operation mechagon
        -- workshop", but "mecha" is not a match for anything.
        local px, py = " " .. x .. " ", " " .. y .. " "
        if py:find(px, 1, true) or px:find(py, 1, true) then return true end
    end

    local hx = Data.Norm((a:match("^(.-)[:,]")) or a)
    local hy = Data.Norm((b:match("^(.-)[:,]")) or b)
    if #hx >= MIN_FRAGMENT and hx == hy then return true end

    return false
end

-- "Hero's Path: The War Within" -> "The War Within". Everything after the colon; the
-- whole name when there is none, which is at least never wrong.
function Data.ExpansionLabel(flyoutName)
    if type(flyoutName) ~= "string" then return "?" end
    return flyoutName:match(":%s*(.+)$") or flyoutName
end

--------------------------------------------------------------------------------
-- What kind of group a flyout is
--
-- Measured on live 12.1.5 (a /np dump, 2026-11-16), the Hero's Path flyouts are
-- three different things wearing one name:
--
--   dungeons  "Hero's Path: The War Within"        one per expansion
--   raids     "Hero's Path: War Within Raids"       raid portals, a separate flyout -
--                                                   note "War Within", not "The War
--                                                   Within": Norm() drops the article,
--                                                   so it still finds its expansion
--   season    "Hero's Path: Midnight Season 2"      Blizzard's own list of THIS
--                                                   season's portals. Every one of them
--                                                   also lives in its home expansion,
--                                                   so listing it as a group repeats
--                                                   eight portals under a name that is
--                                                   not an expansion and sorts last.
--
-- The season flyout is not shown as a group. Its portals are still read, because a
-- season dungeon whose portal exists ONLY there would otherwise go unmatched.
--------------------------------------------------------------------------------

-- The flyout ids from that dump, by kind. They make discovery and grouping work on a
-- client in any language; the English patterns below cover flyouts added since,
-- which every new season and expansion will be.
Data.KNOWN_FLYOUTS = {
    [84]  = "dungeons",   -- Mists of Pandaria
    [96]  = "dungeons",   -- Warlords of Draenor
    [220] = "dungeons",   -- Shadowlands
    [222] = "raids",      -- Shadowlands Raids
    [223] = "dungeons",   -- Battle for Azeroth
    [224] = "dungeons",   -- Legion
    [227] = "dungeons",   -- Dragonflight
    [230] = "dungeons",   -- Cataclysm
    [231] = "raids",      -- Dragonflight Raids
    [232] = "dungeons",   -- The War Within
    [242] = "raids",      -- War Within Raids
    [244] = "season",     -- Midnight Season 2
    [246] = "dungeons",   -- Midnight
    [274] = "dungeons",   -- Wrath of the Lich King
}

function Data.GroupKind(flyoutID, label)
    local known = Data.KNOWN_FLYOUTS[flyoutID]
    if known then return known end
    if type(label) ~= "string" then return "dungeons" end
    if label:find("[Ss]eason%s*%d+%s*$") then return "season" end
    if label:find("%s[Rr]aids?%s*$") then return "raids" end
    return "dungeons"
end

-- The expansion a group belongs to, with the kind's suffix taken off:
-- "War Within Raids" -> "War Within", "Midnight Season 2" -> "Midnight".
function Data.ExpansionOf(label)
    if type(label) ~= "string" then return "?" end
    local base = label:gsub("%s+[Rr]aids?%s*$", ""):gsub("%s+[Ss]eason%s*%d+%s*$", "")
    return base
end

-- Which expansion number a label names, by asking the game for every expansion's
-- name. Used to sort newest first, and to find the current expansion's group.
function Data.ExpansionIndex(label)
    local want = Data.Norm(label)
    if want == "" then return nil end
    for level = 0, 30 do
        local name = PlainString(_G["EXPANSION_NAME" .. level])
        if name and Data.Norm(name) == want then return level end
    end
    return nil
end

function Data.FormatTime(seconds)
    if type(seconds) ~= "number" or seconds <= 0 then return nil end
    if seconds >= 3600 then
        return ("%dh %dm"):format(math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
    elseif seconds >= 60 then
        return ("%dm"):format(math.floor(seconds / 60))
    end
    return ("%ds"):format(math.floor(seconds))
end

--------------------------------------------------------------------------------
-- The flyouts
--------------------------------------------------------------------------------

-- Flyout ids are small and sparse, and there is no call that lists every flyout in
-- the game - GetNumFlyouts answers for the ones in YOUR spellbook, which leaves out
-- every expansion you have not earned a portal from. So they are asked for one by
-- one. A thousand cheap calls, once per session, out of combat.
local SCAN_LIMIT = 1000

-- What a Hero's Path flyout is called. The apostrophe is matched loosely because the
-- client is free to use a typographic one, which is three bytes, not one.
local HERO_PATTERN = "^Hero.-s Path"

-- Data.KNOWN_FLYOUTS (above, with the group kinds) is what makes this work without the
-- English name.

local flyoutCache

function Data.FlyoutIDs()
    if flyoutCache then return flyoutCache end
    local ids = {}
    if type(GetFlyoutInfo) ~= "function" then return ids end
    for id = 1, SCAN_LIMIT do
        local ok, name, _, numSlots = pcall(GetFlyoutInfo, id)
        name = ok and PlainString(name) or nil
        if name and (PlainNumber(numSlots) or 0) > 0
           and (Data.KNOWN_FLYOUTS[id] or name:find(HERO_PATTERN)) then
            ids[#ids + 1] = id
        end
    end
    -- An empty scan is not cached. It means the client has not loaded spellbook data
    -- yet, or the language did not match, and remembering it would make the window
    -- empty for the rest of the session.
    if #ids > 0 then flyoutCache = ids end
    return ids
end

--------------------------------------------------------------------------------
-- Spell text
--------------------------------------------------------------------------------

-- Descriptions are loaded on demand. One that is not in the client's cache yet comes
-- back empty, and asking for it to be loaded fires SPELL_DATA_LOAD_RESULT when it
-- arrives, which refreshes the window.
local requested = {}

function Data.Description(spellID)
    local S = C_Spell
    if not (S and S.GetSpellDescription) then return nil end
    local desc = PlainString(Try(S.GetSpellDescription, spellID))
    if desc and desc ~= "" then return desc end
    if S.RequestLoadSpellData and not requested[spellID] then
        requested[spellID] = true
        pcall(S.RequestLoadSpellData, spellID)
    end
    return nil
end

function Data.SpellName(spellID)
    local S = C_Spell
    return S and S.GetSpellName and PlainString(Try(S.GetSpellName, spellID)) or nil
end

function Data.SpellIcon(spellID)
    local S = C_Spell
    return S and S.GetSpellTexture and Try(S.GetSpellTexture, spellID) or nil
end

-- Seconds until this portal can be used again; 0 when it is ready, nil when the
-- client will not say. The global cooldown is not a cooldown worth showing.
function Data.CooldownLeft(spellID)
    local S = C_Spell
    if not (S and S.GetSpellCooldown) then return nil end
    local ok, start, duration = pcall(function()
        local info = S.GetSpellCooldown(spellID)
        if type(info) ~= "table" then return nil, nil end
        return info.startTime, info.duration
    end)
    if not ok then return nil end
    start, duration = PlainNumber(start), PlainNumber(duration)
    if not (start and duration) then return nil end
    if start <= 0 or duration <= 1.5 then return 0 end
    return math.max(0, start + duration - GetTime())
end

--------------------------------------------------------------------------------
-- The season and the expansion
--------------------------------------------------------------------------------

function Data.CurrentExpansion()
    local level = PlainNumber(Try(GetClientDisplayExpansionLevel))
               or PlainNumber(Try(GetExpansionLevel))
    local name = level and PlainString(_G["EXPANSION_NAME" .. level]) or nil
    return level, name
end

-- The season number as the game's own UI shows it. Nil before the server has said,
-- and for the stretch between seasons.
function Data.SeasonNumber()
    local MP = C_MythicPlus
    if not MP then return nil end
    local n = PlainNumber(Try(MP.GetCurrentUIDisplaySeason))
    if n and n > 0 then return n end
    return nil
end

-- The current season's dungeons, from the server. Empty until C_MythicPlus has been
-- asked for map info, which Core does at login.
function Data.SeasonDungeons()
    local CM = C_ChallengeMode
    if not (CM and CM.GetMapTable and CM.GetMapUIInfo) then return {} end
    local ok, ids = pcall(CM.GetMapTable)
    if not ok or type(ids) ~= "table" then return {} end

    local out = {}
    for _, mapID in ipairs(ids) do
        -- Called directly rather than through Try, which only hands back three
        -- results: the texture is the fourth.
        local okI, name, _, _, texture = pcall(CM.GetMapUIInfo, mapID)
        name = okI and PlainString(name) or nil
        if name then
            out[#out + 1] = { challengeMapID = mapID, name = name, texture = texture }
        end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end

--------------------------------------------------------------------------------
-- The catalogue
--
-- Returns
--   {
--     dungeons = { group ... },   newest expansion first
--     raids    = { group ... },   newest expansion first
--     season   = { { name, challengeMapID, texture, portal|nil } },
--     seasonLabel = "Midnight Season 2" | nil,   from Blizzard's own season flyout
--     total, earned,              distinct portals, counted once however many groups
--   }
-- where a group is
--   { flyoutID, flyoutName, label, kind, expansion, level, portals = { portal ... } }
-- and a portal is
--   { spellID, portalName, dungeon|nil, known, icon, group, inSeason }
--
-- `dungeon` is nil when the description has not loaded yet or did not match. Callers
-- show `portalName` in its place.
--------------------------------------------------------------------------------

local function SortKey(p)
    return (p.dungeon or p.portalName or ""):lower()
end

-- Newest expansion first. One the game could not put a number on goes last rather
-- than first: an unrecognised name is more likely an oddity than the current
-- expansion.
local function ByExpansion(a, b)
    if a.level and b.level then
        if a.level ~= b.level then return a.level > b.level end
    elseif a.level or b.level then
        return a.level ~= nil
    end
    return a.label:lower() < b.label:lower()
end

local function ReadGroup(flyoutID)
    local ok, flyoutName, _, numSlots = pcall(GetFlyoutInfo, flyoutID)
    flyoutName = ok and PlainString(flyoutName) or nil
    numSlots = ok and PlainNumber(numSlots) or 0
    if not flyoutName then return nil end

    local label = Data.ExpansionLabel(flyoutName)
    local expansion = Data.ExpansionOf(label)
    local group = {
        flyoutID   = flyoutID,
        flyoutName = flyoutName,
        label      = label,
        kind       = Data.GroupKind(flyoutID, label),
        expansion  = expansion,
        level      = Data.ExpansionIndex(expansion),
        portals    = {},
    }

    -- One row per DESTINATION. Battle for Azeroth lists Siege of Boralus and the
    -- Motherlode twice each - an Alliance and a Horde spell for the same door - and
    -- two identical rows, one of them greyed, reads as a bug. The one this character
    -- can cast wins; between two it can, the first.
    local indexOf = {}

    for slot = 1, numSlots do
        local okS, baseID, overrideID, isKnown, slotName = pcall(GetFlyoutSlotInfo, flyoutID, slot)
        baseID = okS and PlainNumber(baseID) or nil
        if baseID then
            -- The override is what the flyout itself casts when there is one, so it is
            -- what this casts too, and what is described.
            local spellID = PlainNumber(overrideID)
            if not spellID or spellID == 0 then spellID = baseID end

            local portal = {
                spellID    = spellID,
                portalName = PlainString(slotName) or Data.SpellName(spellID)
                             or ("spell " .. spellID),
                dungeon    = Data.DungeonFromDescription(Data.Description(spellID)),
                known      = (PlainBool(isKnown) == true),
                icon       = Data.SpellIcon(spellID),
                group      = group,
            }

            -- Keyed on the portal's name as well as the destination, so the two
            -- variants still collapse before their descriptions have loaded.
            local key = (portal.dungeon or portal.portalName):lower()
            local at = indexOf[key] or indexOf[portal.portalName:lower()]
            if not at then
                group.portals[#group.portals + 1] = portal
                indexOf[key] = #group.portals
                indexOf[portal.portalName:lower()] = #group.portals
            elseif portal.known and not group.portals[at].known then
                group.portals[at] = portal
            end
        end
    end

    table.sort(group.portals, function(a, b) return SortKey(a) < SortKey(b) end)
    if #group.portals == 0 then return nil end
    return group
end

function Data.Build()
    local dungeons, raids, seasonFlyouts = {}, {}, {}

    for _, flyoutID in ipairs(Data.FlyoutIDs()) do
        local group = ReadGroup(flyoutID)
        if group then
            if group.kind == "season" then
                seasonFlyouts[#seasonFlyouts + 1] = group
            elseif group.kind == "raids" then
                raids[#raids + 1] = group
            else
                dungeons[#dungeons + 1] = group
            end
        end
    end

    table.sort(dungeons, ByExpansion)
    table.sort(raids, ByExpansion)

    -- This season's dungeons, each matched to its portal. Searched in the expansion
    -- groups FIRST, so the row says "Ruby Life Pools - Dragonflight" rather than
    -- naming the season flyout it was also copied into. Blizzard's season flyout is
    -- the fallback, for a portal that lives nowhere else. Raid groups are not
    -- searched: a Mythic+ season is dungeons.
    local candidates = {}
    for _, g in ipairs(dungeons) do
        for _, p in ipairs(g.portals) do candidates[#candidates + 1] = p end
    end
    for _, g in ipairs(seasonFlyouts) do
        for _, p in ipairs(g.portals) do candidates[#candidates + 1] = p end
    end

    local season = {}
    for _, d in ipairs(Data.SeasonDungeons()) do
        local match
        for _, p in ipairs(candidates) do
            if p.dungeon and Data.SameDungeon(d.name, p.dungeon) then
                match = p
                break
            end
        end
        if match then match.inSeason = true end
        season[#season + 1] = {
            name = d.name, challengeMapID = d.challengeMapID, texture = d.texture, portal = match,
        }
    end

    -- Totals over DISTINCT portals. The season flyout repeats eight that are already
    -- counted in their expansions; counting them twice would put "98 portals" on a
    -- game that has ninety.
    local seen, total, earned = {}, 0, 0
    local function Count(groups)
        for _, g in ipairs(groups) do
            for _, p in ipairs(g.portals) do
                if not seen[p.spellID] then
                    seen[p.spellID] = true
                    total = total + 1
                    if p.known then earned = earned + 1 end
                end
            end
        end
    end
    Count(dungeons)
    Count(raids)
    Count(seasonFlyouts)

    return {
        dungeons    = dungeons,
        raids       = raids,
        season      = season,
        seasonLabel = seasonFlyouts[1] and seasonFlyouts[1].label or nil,
        total       = total,
        earned      = earned,
    }
end

--------------------------------------------------------------------------------
-- /np dump
--
-- Everything the game says about every portal, written into the saved variables
-- verbatim, so the matching above can be checked against a real client - and so a
-- wrong dungeon name gets fixed from evidence rather than from a guess. The file is
-- written when you /reload or log out.
--------------------------------------------------------------------------------

function Data.Dump()
    local out = {
        when    = date and date("%Y-%m-%d %H:%M:%S") or "?",
        addon   = NPT.version,
        locale  = GetLocale and GetLocale() or "?",
        build   = GetBuildInfo and select(4, GetBuildInfo()) or "?",
        levels  = {
            clientDisplay = PlainNumber(Try(GetClientDisplayExpansionLevel)),
            account       = PlainNumber(Try(GetExpansionLevel)),
            server        = PlainNumber(Try(GetServerExpansionLevel)),
        },
        expansionNames = {},
        season  = {},
        spellbookFlyouts = {},
        heroFlyouts = {},
        otherFlyoutNames = {},
    }

    for level = 0, 20 do
        local name = _G["EXPANSION_NAME" .. level]
        if name ~= nil then out.expansionNames[level] = tostring(PlainString(name) or "(secret)") end
    end

    local MP = C_MythicPlus
    if MP then
        out.season.current   = PlainNumber(Try(MP.GetCurrentSeason))
        out.season.uiDisplay = PlainNumber(Try(MP.GetCurrentUIDisplaySeason))
        local d, m, r = Try(MP.GetCurrentSeasonValues)
        out.season.values = { display = PlainNumber(d), milestone = PlainNumber(m), reward = PlainNumber(r) }
    end
    out.season.maps = {}
    for _, d in ipairs(Data.SeasonDungeons()) do
        out.season.maps[#out.season.maps + 1] = { id = d.challengeMapID, name = d.name }
    end

    -- What GetNumFlyouts covers, to confirm whether it lists unearned groups.
    local n = PlainNumber(Try(GetNumFlyouts)) or 0
    for i = 1, n do
        local id = PlainNumber(Try(GetFlyoutID, i))
        local name = id and PlainString(Try(GetFlyoutInfo, id))
        out.spellbookFlyouts[#out.spellbookFlyouts + 1] = { index = i, id = id, name = name }
    end

    -- Every flyout in the scan range, Hero's Path or not, by name - so a client whose
    -- Hero's Path name does not match the pattern still shows up here.
    for id = 1, SCAN_LIMIT do
        local ok, name, _, numSlots = pcall(GetFlyoutInfo, id)
        name = ok and PlainString(name) or nil
        if name then
            if name:find(HERO_PATTERN) or Data.KNOWN_FLYOUTS[id] then
                local entry = { id = id, name = name, numSlots = PlainNumber(numSlots), slots = {} }
                for slot = 1, (PlainNumber(numSlots) or 0) do
                    local okS, baseID, overrideID, isKnown, slotName = pcall(GetFlyoutSlotInfo, id, slot)
                    if okS then
                        local spellID = PlainNumber(overrideID)
                        if not spellID or spellID == 0 then spellID = PlainNumber(baseID) end
                        local desc = spellID and Data.Description(spellID) or nil
                        entry.slots[#entry.slots + 1] = {
                            baseID      = PlainNumber(baseID),
                            overrideID  = PlainNumber(overrideID),
                            known       = PlainBool(isKnown),
                            name        = PlainString(slotName),
                            description = desc,
                            parsed      = Data.DungeonFromDescription(desc),
                        }
                    end
                end
                out.heroFlyouts[#out.heroFlyouts + 1] = entry
            else
                out.otherFlyoutNames[id] = name
            end
        end
    end

    -- And the season matching, both ways, since that is the fragile part.
    local built = Data.Build()
    out.seasonMatches = {}
    for _, s in ipairs(built.season) do
        out.seasonMatches[#out.seasonMatches + 1] = {
            map = s.name,
            portal = s.portal and s.portal.portalName or false,
            dungeon = s.portal and s.portal.dungeon or false,
        }
    end

    NPT.db.dump = out

    local pending = 0
    for _, f in ipairs(out.heroFlyouts) do
        for _, s in ipairs(f.slots) do
            if not s.description then pending = pending + 1 end
        end
    end
    NPT.Print(("recorded %d Hero's Path group(s), %d season dungeon(s)."):format(
        #out.heroFlyouts, #out.season.maps))
    if pending > 0 then
        NPT.Print(("|cffffd479%d description(s) were still loading|r - run |cff6fc2ff/np dump|r "
            .. "once more in a few seconds to catch them."):format(pending))
    end
    NPT.Print("it is written to disk on |cffffd479/reload|r or logout.")
end
