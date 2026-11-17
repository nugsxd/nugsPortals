--------------------------------------------------------------------------------
-- nugsPortals
-- Copyright (c) 2026 nugs. All Rights Reserved.
-- Unauthorized copying, distribution, or modification is prohibited. See LICENSE.
--------------------------------------------------------------------------------
-- nugsPortals  -  Attach.lua
-- This season's portals, docked beside the Mythic+ Dungeons page.
--
-- The page lists this season's dungeons and your scores in them; the next thing you
-- usually want is to GO to one. So when that page opens, a narrow panel opens beside
-- it with one row per season dungeon, and clicking a row teleports you there.
--
-- NOT TOUCHING BLIZZARD'S FRAME
--
-- The Group Finder window (PVEFrame) is protected, and an addon writing to it -
-- moving it, rescaling it, even changing its strata - taints it. EllesmereUI, which
-- skins this exact window on the dev client, carries a comment saying so. So this
-- panel never writes to PVEFrame or ChallengesFrame:
--   * it is parented to UIParent, not to them;
--   * it only READS their position, strata and level, to line up beside them;
--   * it listens with HookScript, which adds to their handlers without replacing
--     them, and does its work a frame LATER (C_Timer.After 0), so none of it runs
--     inside Blizzard's own show handler. BigWigs hooks this page the same way.
--
-- WHICH SIDE
--
-- The right. EllesmereUI docks the character panel beside the Group Finder and
-- prefers the left whenever there is room; the right is the side least likely to
-- already be occupied.
--
-- COMBAT
--
-- Same rule as the main window: the rows are secure buttons, so the panel hides on
-- PLAYER_REGEN_DISABLED (the last moment that is allowed) and never shows in combat.
-- If the page is still open when the fight ends, the panel comes back on its own -
-- unlike the main window, this one never "pops up" uninvited: it only ever appears
-- next to a page you opened.
--------------------------------------------------------------------------------

local ADDON_NAME, NPT = ...

local Attach = {}
NPT.Attach = Attach

local Data = NPT.Data

local PANEL_W  = 236
local ROW_H    = 30
local HEADER_H = 30
local FOOTER_H = 30
local GAP      = 6     -- between the Group Finder's edge and this panel

local panel
local rowPool = {}
local hooked = false

-- Closed with its own x, for the rest of this visit to the page. Reset when the page
-- closes, so it is back next time: dismissing a panel once should not be mistaken for
-- turning the feature off.
local dismissed = false

local function Enabled()
    return NPT.db and NPT.db.attachToMythicPage ~= false
end

-- The Mythic+ page is visible: ChallengesFrame exists (its addon has loaded) and is
-- actually on screen, which also requires the Group Finder window around it.
local function PageOpen()
    local cf = ChallengesFrame
    return cf and cf:IsVisible() and true or false
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function StateText(p)
    if not p then return "|cff808080no portal|r" end
    if not p.known then return "|cff808080not earned|r" end
    local left = Data.CooldownLeft(p.spellID)
    local text = left and Data.FormatTime(left)
    if text then return "|cfff2b34d" .. text .. "|r" end
    return "|cff73d973Ready|r"
end

local function RowEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local p = self.portal
    if p then
        GameTooltip:SetSpellByID(p.spellID)
        GameTooltip:AddLine(" ")
        if p.known then
            GameTooltip:AddLine("Click to teleport.", 0.45, 0.85, 0.45)
        else
            GameTooltip:AddLine("Not earned yet.", 0.6, 0.6, 0.6)
        end
    else
        GameTooltip:AddLine(self.dungeonName or "?")
        GameTooltip:AddLine("No teleport to this dungeon was found.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local function NewRow()
    local UI = NPT.UI
    -- A secure action button, as in the main window. Its OnClick belongs to the
    -- template and is never replaced; Enter and Leave are ours.
    local b = CreateFrame("Button", nil, panel, "SecureActionButtonTemplate")
    b:SetHeight(ROW_H)
    b:RegisterForClicks("AnyUp", "AnyDown")

    b.bgTex = b:CreateTexture(nil, "BACKGROUND")
    b.bgTex:SetAllPoints()

    local hi = b:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetColorTexture(1, 1, 1, 0.07)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(22, 22)
    b.icon:SetPoint("LEFT", 6, 0)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    b.state = UI.Label(b, "", "GameFontHighlightSmall")
    b.state:SetPoint("RIGHT", -8, 0)
    b.state:SetJustifyH("RIGHT")

    b.name = UI.Label(b, "", "GameFontHighlightSmall")
    b.name:SetPoint("LEFT", b.icon, "RIGHT", 7, 0)
    b.name:SetPoint("RIGHT", b, "RIGHT", -74, 0)
    b.name:SetWordWrap(false)

    b:SetScript("OnEnter", RowEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

local function BuildPanel()
    local UI = NPT.UI
    local C = UI.C

    local f = CreateFrame("Frame", "nugsPortalsMythicPanel", UIParent)
    f:SetWidth(PANEL_W)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    UI.Backdrop(f, C.bg, 1)

    local header = CreateFrame("Frame", nil, f)
    UI.Backdrop(header, C.header, 1)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H - 2)

    local accent = header:CreateTexture(nil, "OVERLAY")
    accent:SetPoint("BOTTOMLEFT", 0, 0)
    accent:SetPoint("BOTTOMRIGHT", 0, 0)
    accent:SetHeight(2)
    accent:SetColorTexture(unpack(C.gold))

    local icon = header:CreateTexture(nil, "OVERLAY")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetTexture("Interface\\AddOns\\nugsPortals\\icon")

    f.title = UI.Label(header, "This season's portals", "GameFontNormal", C.gold)
    f.title:SetPoint("LEFT", icon, "RIGHT", 6, 0)

    local close = UI.Button(header, "x", 20, 16, function()
        dismissed = true
        Attach:Sync()
    end)
    close:SetPoint("RIGHT", -5, 0)

    f.count = UI.Label(f, "", "GameFontDisableSmall", C.faint)
    f.count:SetPoint("BOTTOMLEFT", 9, 10)

    local all = UI.Button(f, "All portals", 84, 20, function()
        NPT.Window:Toggle()
    end)
    all:SetPoint("BOTTOMRIGHT", -6, 6)

    -- Cooldowns tick while it is open. Text only - nothing secure - so this is safe
    -- whenever it runs.
    -- Spelled the house way (`acc = acc + elapsed`), which is what apicheck recognises
    -- as a throttle; written any other way it reports "runs every frame".
    local acc = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 1 then return end
        acc = 0
        for _, row in ipairs(rowPool) do
            if row:IsShown() and row.portal and row.portal.known then
                row.state:SetText(StateText(row.portal))
            end
        end
    end)

    -- Shown from birth otherwise, and it must only ever appear beside the page.
    f:Hide()
    panel = f
end

-- Line up beside the Group Finder. Reads its position and layer; writes nothing to it.
local function Place()
    local pve = PVEFrame
    panel:ClearAllPoints()
    if pve then
        panel:SetPoint("TOPLEFT", pve, "TOPRIGHT", GAP, 0)
        panel:SetFrameStrata(pve:GetFrameStrata())
        panel:SetFrameLevel((pve:GetFrameLevel() or 1) + 10)
    else
        panel:SetPoint("CENTER")
    end
end

function Attach:Refresh()
    if not panel or not panel:IsShown() or InCombatLockdown() then return end
    local C = NPT.UI.C

    local cat = Data.Build()
    local y = HEADER_H
    local earned = 0

    for i, s in ipairs(cat.season) do
        local b = rowPool[i]
        if not b then b = NewRow(); rowPool[i] = b end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -y)
        b:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -y)
        b.bgTex:SetColorTexture(unpack(i % 2 == 0 and C.rowB or C.rowA))

        local p = s.portal
        b.portal, b.dungeonName = p, s.name
        local usable = p and p.known
        if usable then
            earned = earned + 1
            b:SetAttribute("type", "spell")
            b:SetAttribute("spell", p.spellID)
        else
            -- Cleared, so a pooled row never casts whatever it showed last time.
            b:SetAttribute("type", nil)
            b:SetAttribute("spell", nil)
        end

        b.icon:SetTexture((p and p.icon) or s.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        b.icon:SetDesaturated(not usable)
        b.icon:SetAlpha(usable and 1 or 0.55)
        b.name:SetText(s.name)
        b.name:SetTextColor(unpack(usable and C.text or C.faint))
        b.state:SetText(StateText(p))
        b:Show()
        y = y + ROW_H
    end
    for i = #cat.season + 1, #rowPool do
        rowPool[i]:Hide()
        rowPool[i].portal = nil
    end

    if #cat.season == 0 then
        -- The page itself asks the server for the season; a refresh follows when it
        -- answers (CHALLENGE_MODE_MAPS_UPDATE), so this lasts a moment at most.
        panel.count:SetText("Loading this season...")
        y = y + 24
    else
        panel.count:SetText(("|cff73d973%d|r of %d earned"):format(earned, #cat.season))
    end

    panel:SetHeight(y + FOOTER_H)
end

local refreshQueued = false

function Attach:RequestRefresh()
    if not panel or not panel:IsShown() or refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.15, function()
        refreshQueued = false
        Attach:Refresh()
    end)
end

-- Decide whether the panel should be up, and make it so. The single place that
-- shows or hides it, so the conditions cannot disagree with each other.
function Attach:Sync()
    -- Nothing secure may be shown, hidden or moved in combat. PLAYER_REGEN_ENABLED
    -- calls back in here, which is how the panel returns after a fight.
    if InCombatLockdown() then return end

    local want = Enabled() and PageOpen() and not dismissed
    if want then
        if not panel then BuildPanel() end
        Place()
        panel:Show()
        Attach:Refresh()
    elseif panel and panel:IsShown() then
        panel:Hide()
    end
end

function Attach:OnCombatStart()
    -- PLAYER_REGEN_DISABLED fires just before the lockdown; the last moment this is
    -- allowed. Points are cleared too, so a hidden secure frame is not left anchored
    -- to Blizzard's while it moves about during the fight.
    if panel and panel:IsShown() then
        panel:Hide()
        panel:ClearAllPoints()
    end
end

-- Blizzard_ChallengesUI is load-on-demand: ChallengesFrame does not exist until the
-- page is first opened. Called from ADDON_LOADED for that addon, and at login in case
-- it was already loaded by something else.
function Attach:Hook()
    local cf = ChallengesFrame
    if hooked or not cf then return end
    hooked = true

    -- HookScript adds after Blizzard's handler and replaces nothing. The work itself
    -- is deferred a frame so none of it runs inside Blizzard's own call.
    cf:HookScript("OnShow", function()
        C_Timer.After(0, function() Attach:Sync() end)
    end)
    cf:HookScript("OnHide", function()
        dismissed = false
        C_Timer.After(0, function() Attach:Sync() end)
    end)

    -- If the page is already open as this runs, catch up.
    C_Timer.After(0, function() Attach:Sync() end)
end
