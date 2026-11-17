--------------------------------------------------------------------------------
-- nugsPortals
-- Copyright (c) 2026 nugs. All Rights Reserved.
-- Unauthorized copying, distribution, or modification is prohibited. See LICENSE.
--------------------------------------------------------------------------------
-- nugsPortals  -  Minimap.lua
-- A self-contained minimap button (no external libraries). Draggable around the
-- minimap edge; its angle persists in SavedVariables. Either click opens the list.
--------------------------------------------------------------------------------
local ADDON_NAME, NPT = ...

-- Place the button on the minimap edge, adapting to the minimap's CURRENT size and
-- shape, so it works with resized/reshaped minimaps and not just the default.
local function PositionButton(btn, angle)
    local a = math.rad(angle)
    local cos, sin = math.cos(a), math.sin(a)
    local w = (Minimap:GetWidth()  / 2) + 5
    local h = (Minimap:GetHeight() / 2) + 5
    local shape = (type(GetMinimapShape) == "function") and GetMinimapShape() or "ROUND"
    local x, y
    if shape == "ROUND" then
        x, y = cos * w, sin * h
    else
        local diag = 1.41421356
        x = math.max(-w, math.min(cos * w * diag, w))
        y = math.max(-h, math.min(sin * h * diag, h))
    end
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- While dragging, follow the cursor around the minimap edge.
local function OnDragUpdate(btn)
    local mx, my = Minimap:GetCenter()
    if not mx then return end
    local scale = Minimap:GetEffectiveScale()
    local px, py = GetCursorPosition()
    px, py = px / scale, py / scale
    local angle = math.deg(math.atan2(py - my, px - mx))
    NPT.db.minimapAngle = angle
    PositionButton(btn, angle)
end

function NPT.InitMinimap()
    if NPT.minimapButton or not NPT.db then return end

    local btn = CreateFrame("Button", "nugsPortalsMinimapButton", Minimap)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetSize(31, 31)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    -- A dark disc behind the icon: the tracking border's hole is wider than the icon
    -- and the gap would otherwise show the world scrolling past.
    local backing = btn:CreateTexture(nil, "BACKGROUND")
    backing:SetSize(23, 23)
    backing:SetPoint("CENTER", 0, 1)
    backing:SetTexture("Interface\\Buttons\\WHITE8X8")
    backing:SetVertexColor(0.05, 0.06, 0.08, 1)
    backing:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(21, 21)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\AddOns\\nugsPortals\\icon")
    icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Drops the drag handler if this is hidden mid-drag. A hidden frame never gets
    -- OnDragStop, and this one drags from an OnUpdate - so it would go on chasing
    -- the cursor for the rest of the session.
    btn:HookScript("OnHide", function(s) s:SetScript("OnUpdate", nil) end)

    btn:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
    btn:SetScript("OnDragStop",  function(self) self:SetScript("OnUpdate", nil) end)

    btn:SetScript("OnClick", function()
        NPT.Window:Toggle()
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("nugsPortals")
        GameTooltip:AddLine("Click to open the portal list", 1, 1, 1)
        GameTooltip:AddLine("Drag to move this button", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    NPT.minimapButton = btn
    PositionButton(btn, NPT.db.minimapAngle)
    NPT.SetMinimapShown(not NPT.db.minimapHidden)
end

function NPT.SetMinimapShown(shown)
    if not NPT.minimapButton then return end
    NPT.minimapButton:SetShown(shown and true or false)
end
