--------------------------------------------------------------------------------
-- nugsPortals
-- Copyright (c) 2026 nugs. All Rights Reserved.
-- Unauthorized copying, distribution, or modification is prohibited. See LICENSE.
--------------------------------------------------------------------------------
-- nugsPortals  -  Window.lua
-- The portal list.
--
-- This season's dungeons first, because that is the list people are actually looking
-- up during a season; then every expansion, newest first. Each row is named for the
-- DUNGEON, with the portal's own name underneath for anybody who knows it that way.
-- Clicking a row you have earned casts it.
--
-- COMBAT
--
-- Casting a spell from an addon button needs a secure action button, and secure
-- buttons cannot be changed, shown, hidden or moved during combat - nor can a frame
-- that contains them. So:
--   * the window closes on PLAYER_REGEN_DISABLED, which fires just before the
--     lockdown starts and is the last moment hiding it is allowed;
--   * it refuses to open during combat, and says why;
--   * nothing here rebuilds while InCombatLockdown() is true.
-- Since a portal cannot be cast in combat anyway, none of that costs anything real.
--
-- Shared namespace: the second vararg is the same table across every Lua file in
-- this addon, so all state and functions hang off of it.
--------------------------------------------------------------------------------

local ADDON_NAME, NPT = ...

local Window = {}
NPT.Window = Window

local Data = NPT.Data

local C = {
    bg     = { 0.07, 0.07, 0.07, 0.96 },
    header = { 0.10, 0.10, 0.10, 1.00 },
    panel  = { 0.10, 0.10, 0.10, 0.90 },
    input  = { 0.14, 0.14, 0.14, 1.00 },
    btn    = { 0.16, 0.16, 0.16, 1.00 },
    btnHi  = { 0.24, 0.24, 0.24, 1.00 },
    accent = { 0.35, 0.72, 1.00, 1.00 },
    rowA   = { 1, 1, 1, 0.025 },
    rowB   = { 1, 1, 1, 0.055 },
    text   = { 0.82, 0.82, 0.82 },
    faint  = { 0.50, 0.50, 0.50 },
    gold   = { 1.00, 0.84, 0.42 },
    good   = { 0.45, 0.85, 0.45 },
    warn   = { 0.95, 0.70, 0.30 },
    bad    = { 0.90, 0.40, 0.40 },
    raid   = { 1.00, 0.60, 0.25, 1.00 },
}

-- One colour per section, so where you are in a long scroll is readable from the
-- edge of your eye. Raids get the warm one because they are the odd ones out: a
-- different kind of content from everything else in the list.
local SECTIONS = {
    season   = { title = "This season", color = C.gold   },
    dungeons = { title = "Dungeons",    color = C.accent },
    raids    = { title = "Raids",       color = C.raid   },
}

local ADDON_ICON = "Interface\\AddOns\\nugsPortals\\icon"
local QUESTION   = "Interface\\Icons\\INV_Misc_QuestionMark"

-- The shared white triangle, rotated by texture coordinates: the eight-argument
-- SetTexCoord rotates the quad. Pointing right means folded, down means open - the
-- same arrow the rest of the suite uses for the same idea.
local ARROW_TEX   = "Interface\\AddOns\\nugsPortals\\arrow"
local ARROW_RIGHT = { 0, 1, 1, 1, 0, 0, 1, 0 }
local ARROW_DOWN  = { 1, 1, 1, 0, 0, 1, 0, 0 }

local WIDTH, HEIGHT = 480, 640
local LIST_W    = WIDTH - 24 - 12   -- the scroll content; set explicitly, see ScrollArea
local ROW_H     = 36
local SECTION_H = 30
local GROUP_H   = 26
local SECTION_GAP = 12              -- above every section bar but the first
local INDENT_GROUP = 8              -- an expansion header, under its section
local INDENT_ROW   = 16             -- a portal, under its expansion
-- Notes wrap to two lines, and a wrapped FontString cannot report its height until
-- the layout pass that would ask has already run - so they get a fixed height with
-- room for two lines, rather than one measured too early and overlapping the row
-- beneath.
local NOTE_H  = 40

local window, scroll
local filterText = ""

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local function Backdrop(frame, color, borderAlpha)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(unpack(color))
    frame.bgTex = bg
    if borderAlpha then
        for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" } }) do
            local t = frame:CreateTexture(nil, "BORDER")
            t:SetPoint(p[1]); t:SetPoint(p[2]); t:SetHeight(1)
            t:SetColorTexture(0, 0, 0, borderAlpha)
        end
        for _, p in ipairs({ { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
            local t = frame:CreateTexture(nil, "BORDER")
            t:SetPoint(p[1]); t:SetPoint(p[2]); t:SetWidth(1)
            t:SetColorTexture(0, 0, 0, borderAlpha)
        end
    end
    return bg
end

local function Label(parent, text, template, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(unpack(color or C.text))
    return fs
end

local function Button(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    Backdrop(b, C.btn, 1)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    b.text:SetTextColor(unpack(C.text))
    b:SetScript("OnEnter", function(self) self.bgTex:SetColorTexture(unpack(C.btnHi)) end)
    b:SetScript("OnLeave", function(self) self.bgTex:SetColorTexture(unpack(C.btn)) end)
    b:SetScript("OnClick", onClick)
    b.SetLabel = function(self, t) self.text:SetText(t) end
    return b
end

-- Shared with Attach.lua's panel beside the Mythic+ page, so the two windows are one
-- skin rather than a copy that drifts.
NPT.UI = { C = C, Backdrop = Backdrop, Label = Label, Button = Button }

-- The placeholder is a FontString of our own rather than anything the EditBox
-- provides, so it is shown whenever the box is empty however it got that way.
local function SearchBox(parent, placeholder, onChanged)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetHeight(22)
    eb:SetAutoFocus(false)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetTextInsets(8, 8, 0, 0)
    Backdrop(eb, C.input, 1)

    local ph = Label(eb, placeholder, "GameFontDisableSmall", C.faint)
    ph:SetPoint("LEFT", 9, 0)

    -- Escape and Enter both just let go of the box. Escape a second time closes the
    -- window, through UISpecialFrames, which is the order people expect.
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    eb:SetScript("OnTextChanged", function(self, user)
        ph:SetShown(self:GetText() == "")
        if user then onChanged(self:GetText()) end
    end)
    eb:SetScript("OnShow", function(self) ph:SetShown(self:GetText() == "") end)
    return eb
end

-- Wheel-scrolled area: a child frame we shift plus a draggable position indicator.
-- The same one as the sibling windows, so it carries their fixes.
local function ScrollArea(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(1, 1)
    sf:SetScrollChild(content)
    sf.content = content

    local BAR_W = 9
    local bar = CreateFrame("Frame", nil, sf)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", 0, 0)
    bar:SetWidth(BAR_W)
    bar:EnableMouse(true)

    local track = bar:CreateTexture(nil, "ARTWORK")
    track:SetPoint("TOPRIGHT", 0, 0)
    track:SetPoint("BOTTOMRIGHT", 0, 0)
    track:SetWidth(3)
    track:SetColorTexture(1, 1, 1, 0.05)

    local thumb = CreateFrame("Frame", nil, bar)
    thumb:SetWidth(BAR_W)
    thumb:EnableMouse(true)
    local thumbTex = thumb:CreateTexture(nil, "OVERLAY")
    thumbTex:SetPoint("TOPRIGHT", 0, 0)
    thumbTex:SetPoint("BOTTOMRIGHT", 0, 0)
    thumbTex:SetWidth(3)
    thumbTex:SetColorTexture(unpack(C.accent))

    local function MaxScroll()
        return math.max(0, (content:GetHeight() or 1) - (sf:GetHeight() or 1))
    end
    local function ScrollTo(value)
        sf:SetVerticalScroll(math.max(0, math.min(MaxScroll(), value)))
        sf:UpdateBar()
    end

    function sf:UpdateBar()
        local viewH    = self:GetHeight() or 1
        local totalH   = content:GetHeight() or 1
        local maxScrol = math.max(0, totalH - viewH)
        if self:GetVerticalScroll() > maxScrol then self:SetVerticalScroll(maxScrol) end
        if maxScrol <= 0 then
            bar:Hide()
            return
        end
        bar:Show()
        local frac   = math.min(1, viewH / totalH)
        local thumbH = math.max(20, viewH * frac)
        local travel = viewH - thumbH
        local pos    = (self:GetVerticalScroll() / maxScrol) * travel
        thumb:SetHeight(thumbH)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, -pos)
        self.thumbTravel = travel
    end

    local function CursorY()
        local _, y = GetCursorPosition()
        return y / (thumb:GetEffectiveScale() or 1)
    end
    local function OnDrag(self)
        local travel = sf.thumbTravel or 0
        if travel <= 0 then return end
        local delta = (self.grabY - CursorY()) * (MaxScroll() / travel)
        ScrollTo(self.grabScroll + delta)
    end
    thumb:SetScript("OnMouseDown", function(self)
        self.grabY      = CursorY()
        self.grabScroll = sf:GetVerticalScroll()
        thumbTex:SetColorTexture(1, 1, 1, 0.9)
        self:SetScript("OnUpdate", OnDrag)
    end)
    local function EndDrag(self)
        self:SetScript("OnUpdate", nil)
        thumbTex:SetColorTexture(unpack(C.accent))
    end
    thumb:SetScript("OnMouseUp", EndDrag)
    thumb:SetScript("OnHide", EndDrag)

    bar:SetScript("OnMouseDown", function()
        local viewH = sf:GetHeight() or 1
        local top   = thumb:GetTop()
        local bot   = thumb:GetBottom()
        local y     = CursorY()
        if top and bot and y <= top and y >= bot then return end
        ScrollTo(sf:GetVerticalScroll() + ((top and y > top) and -viewH or viewH))
    end)

    -- Only corrects a content width that is still unset, and only once the scroll
    -- frame itself has a width. The real width is set by the caller at creation:
    -- relying on this alone copies a 0 from the first layout pass, and rows anchored
    -- to a zero-wide content draw but cannot be clicked.
    sf:SetScript("OnSizeChanged", function(self)
        local w = self:GetWidth() or 0
        if w > 1 and (self.content:GetWidth() or 0) <= 1 then
            self.content:SetWidth(w)
        end
        if self.UpdateBar then self:UpdateBar() end
    end)

    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local viewH    = self:GetHeight() or 1
        local maxScrol = math.max(0, (content:GetHeight() or 1) - viewH)
        self:SetVerticalScroll(math.max(0, math.min(maxScrol, self:GetVerticalScroll() - delta * 40)))
        self:UpdateBar()
    end)

    return sf
end

--------------------------------------------------------------------------------
-- Rows
--
-- Pooled and reused, never destroyed: a secure button cannot be thrown away, and
-- building a new set on every refresh would leak them. A refresh takes as many as
-- it needs from the front of each pool and hides the rest.
--------------------------------------------------------------------------------

local rowPool, sectionPool, groupPool, notePool = {}, {}, {}, {}
local liveRows = {}

local function StateText(row)
    local p = row.portal
    if not p then
        return "|cff808080no portal|r"
    elseif not p.known then
        return "|cff808080not earned|r"
    end
    local left = Data.CooldownLeft(p.spellID)
    local text = left and Data.FormatTime(left)
    if text then return "|cfff2b34d" .. text .. "|r" end
    return "|cff73d973Ready|r"
end

-- The expansion's name as the game spells it. A raid flyout calls itself "War Within
-- Raids"; under a Raids heading the expansion is just "The War Within", the same name
-- its dungeons sit under.
local function ExpansionName(g)
    local name = g.level and NPT.PlainString(_G["EXPANSION_NAME" .. g.level])
    return name or g.expansion or g.label
end

local function RowEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local p = self.portal
    if p then
        GameTooltip:SetSpellByID(p.spellID)
    else
        GameTooltip:AddLine(self.titleText or "?")
    end
    GameTooltip:AddLine(" ")
    if not p then
        GameTooltip:AddLine("No teleport to this dungeon was found among your Hero's Path "
            .. "portals. It may not have one, or its name did not match.", 0.6, 0.6, 0.6, true)
    elseif p.known then
        GameTooltip:AddLine("Click to teleport.", 0.45, 0.85, 0.45)
        GameTooltip:AddLine(p.group.flyoutName, 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine("Not earned yet. Portals are unlocked through Mythic+ while "
            .. "their dungeon is in the season.", 0.6, 0.6, 0.6, true)
        GameTooltip:AddLine(p.group.flyoutName, 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function NewRow()
    -- A secure action button: the only kind of button an addon may cast a spell from.
    -- Its OnClick belongs to the template and is never replaced here - SetScript on it
    -- would take the casting away. Enter and Leave are ours to set.
    local b = CreateFrame("Button", nil, scroll.content, "SecureActionButtonTemplate")
    b:SetHeight(ROW_H)
    -- Both halves of the click, so it casts whichever way the game's "cast on key
    -- down" option is set. The template acts on one of them and ignores the other.
    b:RegisterForClicks("AnyUp", "AnyDown")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    b.bgTex = bg

    local hi = b:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetColorTexture(1, 1, 1, 0.07)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(28, 28)
    b.icon:SetPoint("LEFT", 5, 0)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    b.state = Label(b, "", "GameFontHighlightSmall")
    b.state:SetPoint("RIGHT", -10, 0)
    b.state:SetJustifyH("RIGHT")

    b.title = Label(b, "", "GameFontHighlight")
    b.title:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 9, -1)
    b.title:SetPoint("RIGHT", b, "RIGHT", -96, 0)
    b.title:SetWordWrap(false)

    b.sub = Label(b, "", "GameFontDisableSmall", C.faint)
    b.sub:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 9, 1)
    b.sub:SetPoint("RIGHT", b, "RIGHT", -96, 0)
    b.sub:SetWordWrap(false)

    b:SetScript("OnEnter", RowEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

--------------------------------------------------------------------------------
-- Folding
--
-- Every section and every expansion folds. The state is saved per key, and a key
-- that has never been folded is open - so a group the game adds next patch arrives
-- open, where somebody will notice it, rather than folded away.
--
-- A search ignores the folds. Typing "ara" and getting nothing back because The War
-- Within happens to be folded would read as "it is not in here", which is the one
-- thing a search must never say wrongly. The arrows hide while searching, so the
-- headers do not look clickable when clicking would change nothing you can see.
--------------------------------------------------------------------------------

local function Searching() return filterText ~= "" end

local function IsOpen(key)
    if Searching() then return true end
    return not (NPT.db.collapsed and NPT.db.collapsed[key])
end

local function HeaderClick(self)
    if not self.key or Searching() then return end
    NPT.db.collapsed = NPT.db.collapsed or {}
    -- Stored as true or removed, never false, so the table only ever holds the folds.
    NPT.db.collapsed[self.key] = (not NPT.db.collapsed[self.key]) or nil
    Window:Refresh()
end

local function SetArrow(h, open)
    h.arrow:SetShown(not Searching())
    h.arrow:SetTexCoord(unpack(open and ARROW_DOWN or ARROW_RIGHT))
end

-- A section bar: This season, Dungeons, Raids. Tinted in its section's colour with a
-- stripe down the left, so the three read as three different places.
local function NewSection()
    local h = CreateFrame("Button", nil, scroll.content)
    h:SetHeight(SECTION_H)
    h:RegisterForClicks("LeftButtonUp")

    h.bg = h:CreateTexture(nil, "BACKGROUND")
    h.bg:SetAllPoints()

    h.stripe = h:CreateTexture(nil, "ARTWORK")
    h.stripe:SetPoint("TOPLEFT", 0, 0)
    h.stripe:SetPoint("BOTTOMLEFT", 0, 0)
    h.stripe:SetWidth(3)

    local hi = h:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetColorTexture(1, 1, 1, 0.05)

    h.arrow = h:CreateTexture(nil, "OVERLAY")
    h.arrow:SetTexture(ARROW_TEX)
    h.arrow:SetSize(9, 9)
    h.arrow:SetPoint("LEFT", 12, 0)

    h.title = Label(h, "", "GameFontNormalLarge")
    h.title:SetPoint("LEFT", h.arrow, "RIGHT", 8, 0)

    h.sub = Label(h, "", "GameFontDisableSmall", C.faint)
    h.sub:SetPoint("LEFT", h.title, "RIGHT", 10, -1)

    h.count = Label(h, "", "GameFontHighlightSmall")
    h.count:SetPoint("RIGHT", -10, 0)
    h.count:SetJustifyH("RIGHT")

    h:SetScript("OnClick", HeaderClick)
    return h
end

-- An expansion header inside a section. Quieter than a section bar: no tint, just a
-- rule underneath in the section's colour.
local function NewGroup()
    local h = CreateFrame("Button", nil, scroll.content)
    h:SetHeight(GROUP_H)
    h:RegisterForClicks("LeftButtonUp")

    local hi = h:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetColorTexture(1, 1, 1, 0.04)

    h.rule = h:CreateTexture(nil, "ARTWORK")
    h.rule:SetPoint("BOTTOMLEFT", 0, 0)
    h.rule:SetPoint("BOTTOMRIGHT", 0, 0)
    h.rule:SetHeight(1)

    h.arrow = h:CreateTexture(nil, "OVERLAY")
    h.arrow:SetTexture(ARROW_TEX)
    h.arrow:SetSize(7, 7)
    h.arrow:SetPoint("LEFT", 4, 0)
    h.arrow:SetAlpha(0.8)

    h.title = Label(h, "", "GameFontNormal", C.text)
    h.title:SetPoint("LEFT", h.arrow, "RIGHT", 7, 0)

    h.sub = Label(h, "", "GameFontDisableSmall", C.faint)
    h.sub:SetPoint("LEFT", h.title, "RIGHT", 8, -1)
    h.sub:SetPoint("RIGHT", h, "RIGHT", -84, 0)
    h.sub:SetWordWrap(false)

    h.count = Label(h, "", "GameFontDisableSmall", C.faint)
    h.count:SetPoint("RIGHT", -10, 0)
    h.count:SetJustifyH("RIGHT")

    h:SetScript("OnClick", HeaderClick)
    return h
end

local function NewNote()
    local h = CreateFrame("Frame", nil, scroll.content)
    h.text = Label(h, "", "GameFontDisableSmall", C.faint)
    h.text:SetPoint("TOPLEFT", 6, -6)
    h.text:SetPoint("RIGHT", h, "RIGHT", -8, 0)
    h.text:SetWordWrap(true)
    return h
end

--------------------------------------------------------------------------------
-- Filtering
--------------------------------------------------------------------------------

local function Matches(p, extra)
    if filterText == "" then return true end
    local hay = ((p and p.dungeon or "") .. " " .. (p and p.portalName or "") .. " "
                 .. (p and p.group and (p.group.label .. " " .. ExpansionName(p.group)) or "")
                 .. " " .. (extra or "")):lower()
    return hay:find(filterText, 1, true) ~= nil
end

local function Wanted(p)
    if p and not p.known and not NPT.db.showUnearned then return false end
    return true
end

local function Earned(n, total)
    return ("|cff73d973%d|r / %d"):format(n, total)
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

function Window:Refresh()
    if not window or not window:IsShown() then return end
    -- Secure buttons cannot be touched in combat. The window is closed by then, but
    -- an event can still land in the gap, and this is the line that holds.
    if InCombatLockdown() then return end

    local cat = Data.Build()

    ------------------------------------------------------------------ summary
    local currentLevel, expName = Data.CurrentExpansion()
    local seasonNo = Data.SeasonNumber()
    local line = (expName and ("|cffffd76a" .. expName .. "|r") or "")
    if seasonNo then
        line = line .. (expName and "  |cff666666-|r  " or "") .. "Season " .. seasonNo
    else
        line = line .. (expName and "  |cff666666-|r  " or "")
               .. "|cff888888no Mythic+ season data yet|r"
    end
    window.seasonFS:SetText(line)
    window.countFS:SetText(("|cff73d973%d|r of %d portals earned"):format(cat.earned, cat.total))
    window.unearnedBtn:SetLabel(NPT.db.showUnearned and "Hide unearned" or "Show unearned")
    Window:RefreshFooter()

    ------------------------------------------------------------------ the list
    local y = 0
    local ri, si, gi, ni = 0, 0, 0, 0
    local sections = 0
    wipe(liveRows)

    local function Place(f, indent)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", indent or 0, -y)
        f:SetPoint("TOPRIGHT", scroll.content, "TOPRIGHT", 0, -y)
    end

    local function Section(key, sub, count)
        local def = SECTIONS[key]
        if sections > 0 then y = y + SECTION_GAP end
        sections = sections + 1

        si = si + 1
        local h = sectionPool[si]
        if not h then h = NewSection(); sectionPool[si] = h end
        Place(h, 0)
        local col = def.color
        h.bg:SetColorTexture(col[1], col[2], col[3], 0.10)
        h.stripe:SetColorTexture(col[1], col[2], col[3], 0.9)
        h.title:SetText(def.title)
        h.title:SetTextColor(col[1], col[2], col[3])
        h.sub:SetText(sub or "")
        h.count:SetText(count or "")
        h.key = key
        local open = IsOpen(key)
        SetArrow(h, open)
        h.arrow:SetVertexColor(col[1], col[2], col[3])
        h:Show()
        y = y + SECTION_H
        return open
    end

    local function Group(key, title, sub, count, color)
        gi = gi + 1
        local h = groupPool[gi]
        if not h then h = NewGroup(); groupPool[gi] = h end
        Place(h, INDENT_GROUP)
        h.title:SetText(title)
        h.sub:SetText(sub or "")
        h.count:SetText(count or "")
        h.rule:SetColorTexture(color[1], color[2], color[3], 0.30)
        h.key = key
        local open = IsOpen(key)
        SetArrow(h, open)
        h:Show()
        y = y + GROUP_H
        return open
    end

    local function Note(text, indent)
        ni = ni + 1
        local h = notePool[ni]
        if not h then h = NewNote(); notePool[ni] = h end
        Place(h, indent or INDENT_GROUP)
        h:SetHeight(NOTE_H)
        h.text:SetText(text)
        h:Show()
        y = y + NOTE_H
    end

    local function Row(title, sub, portal, icon, indent, warm)
        ri = ri + 1
        local b = rowPool[ri]
        if not b then b = NewRow(); rowPool[ri] = b end
        Place(b, indent)
        -- Raid rows carry a faint warm tint, so a row seen half-way down a long scroll
        -- still says which section it is in.
        if warm then
            b.bgTex:SetColorTexture(C.raid[1], C.raid[2], C.raid[3], ri % 2 == 0 and 0.07 or 0.035)
        else
            b.bgTex:SetColorTexture(unpack(ri % 2 == 0 and C.rowB or C.rowA))
        end

        b.portal, b.titleText = portal, title
        local usable = portal and portal.known
        if usable then
            b:SetAttribute("type", "spell")
            b:SetAttribute("spell", portal.spellID)
        else
            -- Cleared, not left over from whatever this pooled row showed last time:
            -- a greyed row that still cast the previous portal would be a nasty one.
            b:SetAttribute("type", nil)
            b:SetAttribute("spell", nil)
        end

        b.icon:SetTexture(icon or QUESTION)
        b.icon:SetDesaturated(not usable)
        b.icon:SetAlpha(usable and 1 or 0.55)
        b.title:SetText(title)
        b.title:SetTextColor(unpack(usable and C.text or C.faint))
        b.sub:SetText(sub or "")
        b.state:SetText(StateText(b))
        b:Show()

        liveRows[#liveRows + 1] = b
        y = y + ROW_H
    end

    ------------------------------------------------------------- This season
    local seasonRows, seasonEarned = {}, 0
    for _, s in ipairs(cat.season) do
        if s.portal and s.portal.known then seasonEarned = seasonEarned + 1 end
        if Wanted(s.portal) and Matches(s.portal, s.name) then seasonRows[#seasonRows + 1] = s end
    end

    if #cat.season == 0 and not Searching() then
        if Section("season", cat.seasonLabel, nil) then
            Note("The season's dungeons have not arrived from the server yet. They "
                 .. "usually do within a few seconds of logging in.")
        end
    elseif #seasonRows > 0 then
        if Section("season", cat.seasonLabel or "the current Mythic+ rotation",
                   Earned(seasonEarned, #cat.season)) then
            for _, s in ipairs(seasonRows) do
                local p = s.portal
                local sub = p and (p.portalName .. "  |cff666666-|r  " .. ExpansionName(p.group))
                              or "no teleport found for this dungeon"
                Row(s.name, sub, p, (p and p.icon) or s.texture, INDENT_GROUP, false)
            end
        end
    end

    ------------------------------------------------- Dungeons and Raids
    local anyGroupShown = false

    local function Kind(key, groups, warm)
        -- Which groups have anything to show, worked out first, so a section with
        -- nothing in it under the current search or toggle is left out entirely
        -- instead of drawing an empty bar.
        local visible, earned, total = {}, 0, 0
        for _, g in ipairs(groups) do
            local rows, gEarned = {}, 0
            for _, p in ipairs(g.portals) do
                if p.known then gEarned = gEarned + 1 end
                if Wanted(p) and Matches(p) then rows[#rows + 1] = p end
            end
            earned, total = earned + gEarned, total + #g.portals
            if #rows > 0 then
                visible[#visible + 1] = { g = g, rows = rows, earned = gEarned }
            end
        end
        if #visible == 0 then return end
        anyGroupShown = true

        local color = SECTIONS[key].color
        if not Section(key, nil, Earned(earned, total)) then return end

        for _, v in ipairs(visible) do
            local g = v.g
            local title = ExpansionName(g)
            if currentLevel and g.level == currentLevel then
                title = title .. "  |cff888888(current)|r"
            end
            if Group("g" .. g.flyoutID, title, g.flyoutName, Earned(v.earned, #g.portals), color) then
                for _, p in ipairs(v.rows) do
                    local sub = p.dungeon and p.portalName or "|cff888888name not loaded yet|r"
                    Row(p.dungeon or p.portalName, sub, p, p.icon, INDENT_ROW, warm)
                end
            end
        end
    end

    Kind("dungeons", cat.dungeons, false)
    Kind("raids", cat.raids, true)

    -------------------------------------------------------------- nothing
    if #cat.dungeons == 0 and #cat.raids == 0 then
        Note("The game listed no Hero's Path portals. |cff6fc2ff/np dump|r records what "
             .. "it does say, so this can be fixed.", 0)
    elseif not anyGroupShown and #seasonRows == 0 then
        Note(Searching() and ("Nothing matches \"" .. filterText .. "\".")
             or "Every portal is hidden - use Show unearned to list the ones you do not have.", 0)
    end

    for i = ri + 1, #rowPool do
        rowPool[i]:Hide()
        rowPool[i].portal = nil
    end
    for i = si + 1, #sectionPool do sectionPool[i]:Hide() end
    for i = gi + 1, #groupPool do groupPool[i]:Hide() end
    for i = ni + 1, #notePool do notePool[i]:Hide() end

    scroll.content:SetWidth(LIST_W)
    scroll.content:SetHeight(math.max(1, y + 6))
    scroll:UpdateBar()
end

-- Many events can arrive together - a login brings spell data, map info and a
-- cooldown update in the same second - so they are collected into one refresh.
local refreshQueued = false

function Window:RequestRefresh()
    if not window or not window:IsShown() or refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.15, function()
        refreshQueued = false
        Window:Refresh()
    end)
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

-- Just the footer switch, so flipping it does not rebuild the whole list.
function Window:RefreshFooter()
    if not window then return end
    window.attachBtn:SetLabel(NPT.db.attachToMythicPage
        and "Beside Mythic+ page: |cff73d973on|r"
        or  "Beside Mythic+ page: |cff808080off|r")
end

local function SavePosition(f)
    local point, _, _, x, y = f:GetPoint(1)
    if point then
        NPT.db.point, NPT.db.x, NPT.db.y = point, x, y
    end
end

local function BuildWindow()
    local f = CreateFrame("Frame", "nugsPortalsWindow", UIParent)
    f:SetSize(WIDTH, HEIGHT)
    if NPT.db.point and NPT.db.x and NPT.db.y then
        f:SetPoint(NPT.db.point, UIParent, NPT.db.point, NPT.db.x, NPT.db.y)
    else
        f:SetPoint("CENTER")
    end
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    Backdrop(f, C.bg, 1)
    -- Escape closes it. Safe here only because the window is never open in combat,
    -- where hiding a frame holding secure buttons would be refused.
    table.insert(UISpecialFrames, "nugsPortalsWindow")

    --------------------------------------------------------------- header bar
    local header = CreateFrame("Frame", nil, f)
    Backdrop(header, C.header, 1)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(30)

    -- Dragging, from the shared nugsMove.lua. Read the note at the top of that file
    -- before changing anything here.
    NPT.InstallMove(f, { label = "the portals window", handle = header, body = true,
                         onEnd = SavePosition })

    local accent = header:CreateTexture(nil, "OVERLAY")
    accent:SetPoint("BOTTOMLEFT", 0, 0)
    accent:SetPoint("BOTTOMRIGHT", 0, 0)
    accent:SetHeight(3)
    accent:SetColorTexture(unpack(C.accent))

    local icon = header:CreateTexture(nil, "OVERLAY")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 10, 0)
    icon:SetTexture(ADDON_ICON)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText("nugsPortals |cff8cd2ffv" .. NPT.version .. "|r")
    title:SetTextColor(unpack(C.gold))

    local close = Button(header, "x", 22, 18, function() f:Hide() end)
    close:SetPoint("RIGHT", -6, 0)

    -- Shown only when nugsSuite is absent. A note, never a dependency.
    if not _G.nugsSuite then
        local suite = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        suite:SetPoint("RIGHT", close, "LEFT", -10, 0)
        suite:SetText("Part of the |cff8cd2ffnugs suite|r")
        suite:SetTextColor(unpack(C.faint))
    end

    --------------------------------------------------------------- summary
    local seasonFS = Label(f, "", "GameFontNormalLarge", C.text)
    seasonFS:SetPoint("TOPLEFT", 14, -42)
    f.seasonFS = seasonFS

    local countFS = Label(f, "", "GameFontHighlightSmall", C.text)
    countFS:SetPoint("TOPRIGHT", -14, -46)
    countFS:SetJustifyH("RIGHT")
    f.countFS = countFS

    local unearnedBtn = Button(f, "", 108, 22, function()
        NPT.db.showUnearned = not NPT.db.showUnearned
        Window:Refresh()
    end)
    unearnedBtn:SetPoint("TOPRIGHT", -12, -70)
    f.unearnedBtn = unearnedBtn

    local search = SearchBox(f, "Find a dungeon, portal or expansion", function(text)
        filterText = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        Window:Refresh()
    end)
    search:SetPoint("TOPLEFT", 12, -70)
    search:SetPoint("RIGHT", unearnedBtn, "LEFT", -6, 0)
    f.search = search

    --------------------------------------------------------------- the list
    local panel = CreateFrame("Frame", nil, f)
    Backdrop(panel, C.panel, 1)
    panel:SetPoint("TOPLEFT", 12, -100)
    panel:SetPoint("BOTTOMRIGHT", -12, 34)

    scroll = ScrollArea(panel)
    scroll:SetPoint("TOPLEFT", 6, -4)
    scroll:SetPoint("BOTTOMRIGHT", -4, 4)
    -- A deliberate width at creation. See the note in ScrollArea.
    scroll.content:SetWidth(LIST_W)

    --------------------------------------------------------------- footer
    local hint = Label(f, "Click a portal to teleport.", "GameFontDisableSmall", C.faint)
    hint:SetPoint("BOTTOMLEFT", 14, 13)

    -- The switch for the panel beside the Mythic+ page. Here rather than buried in a
    -- settings page, because this window IS the settings for an addon this small, and
    -- a feature that opens on its own needs its off switch where people look first.
    local attachBtn = Button(f, "", 196, 20, function()
        NPT.SetAttach(not NPT.db.attachToMythicPage)
    end)
    attachBtn:SetPoint("BOTTOMRIGHT", -12, 8)
    attachBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Portals beside the Mythic+ page")
        GameTooltip:AddLine("When the Mythic+ Dungeons page is open, a small panel beside "
            .. "it lists this season's portals. Click one to teleport.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    attachBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    f.attachBtn = attachBtn

    -- Cooldowns tick down while the window is open. Once a second, and only the text:
    -- nothing secure is touched, so this is safe whenever it runs.
    --
    -- HookScript, NOT SetScript. InstallMove above already put the drag invariant into
    -- this frame's OnUpdate, and SetScript would replace it outright - silently - which
    -- is the exact mechanism that killed the drag fix twice in the sibling addons.
    local elapsed = 0
    f:HookScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 1 then return end
        elapsed = 0
        for _, row in ipairs(liveRows) do
            if row.portal and row.portal.known then row.state:SetText(StateText(row)) end
        end
    end)

    -- A frame created with CreateFrame is shown from birth, so without this the first
    -- /np builds a visible window and then toggles it straight back off.
    f:Hide()

    window = f
    return f
end

local function EnsureWindow()
    if window then return end
    BuildWindow()
    window:HookScript("OnShow", function()
        -- Map info is asked for again on every open: it is cheap, and a season that
        -- had not arrived at login has usually arrived by now.
        if C_MythicPlus and C_MythicPlus.RequestMapInfo then pcall(C_MythicPlus.RequestMapInfo) end
    end)
    window:HookScript("OnHide", function()
        if window.search then window.search:ClearFocus() end
        GameTooltip:Hide()
    end)
end

function Window:Toggle()
    if InCombatLockdown() then
        NPT.Print("not in combat - the buttons that cast portals are locked by the game "
                  .. "until the fight ends.")
        return
    end
    EnsureWindow()
    if window:IsShown() then
        window:Hide()
    else
        window:Show()
        Window:Refresh()
    end
end

function Window:IsShown()
    return window and window:IsShown() or false
end

-- PLAYER_REGEN_DISABLED fires just before the lockdown begins; this is the last
-- moment hiding a frame full of secure buttons is allowed. Nothing reopens it
-- afterwards - a window popping up at the end of every pull would be worse than
-- having to open it again.
function Window:OnCombatStart()
    if window and window:IsShown() then window:Hide() end
end

--------------------------------------------------------------------------------
-- A stub in the Blizzard settings list so the addon is findable there.
--------------------------------------------------------------------------------

function NPT.InitOptions()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end

    local panel = CreateFrame("Frame")
    panel.name = "nugsPortals"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("nugsPortals")

    local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    note:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    note:SetJustifyH("LEFT")
    note:SetText("Every Mythic+ dungeon teleport, listed by the dungeon it goes to."
        .. "\n\nOpen the list with the button below, the minimap button, or "
        .. "|cffffd479/np|r. A key can be bound to it under Key Bindings, AddOns.")

    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(220, 24)
    open:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -16)
    open:SetText("Open the portal list")
    open:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        Window:Toggle()
    end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    category.ID = panel.name
    Settings.RegisterAddOnCategory(category)
end
