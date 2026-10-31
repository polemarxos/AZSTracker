-- AZS Tracker: minimap markers, odds, damage meter, stats, boss timers
-- WoW 1.12 / Lua 5.0. Azeroth Survivors.

local chestPins, lairPins = {}, {}
local markersEnabled = true
local PIN = 16
local ZOOM_YD = { [0] = 466.6667, 400, 333.3333, 266.6667, 200, 133.3333 }
local driver = CreateFrame("Frame", "AZSTrackerFrame", UIParent)
local db
local minimapStyled = false

-- Solid panel skin (KeijinUI-style): no tooltip backdrop — pure WHITE8X8 fill + rim.
-- Tooltip/Dialog backdrops are transparent or stripped on many AS clients.
local FLAT = "Interface\\Buttons\\WHITE8X8"

local skinnedPanels = {}

local function SkinPanel(frame, bg, border)
	if frame.SetBackdrop then frame:SetBackdrop({}) end
	local cut = 1
	if not frame._skin then
		frame._skin = true
		local fill = frame:CreateTexture(nil, "BACKGROUND")
		fill:SetTexture(FLAT)
		fill:SetPoint("TOPLEFT", frame, "TOPLEFT", cut, -cut)
		fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -cut, cut)
		frame._fill = fill
		local edges = {}
		for i = 1, 8 do
			local t = frame:CreateTexture(nil, "BORDER")
			t:SetTexture(FLAT)
			edges[i] = t
		end
		frame._edges = edges
		table.insert(skinnedPanels, frame)
	end
	frame._bg = bg
	frame._border = border
	local a = 1
	if db and db.panelAlpha then a = db.panelAlpha end
	local r, g, b = bg[1], bg[2], bg[3]
	frame._fill:SetVertexColor(r, g, b, a)
	local br, bgc, bb, ba = border[1], border[2], border[3], border[4] or 1
	local e = frame._edges
	e[1]:ClearAllPoints(); e[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", cut, 0); e[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -cut, 0); e[1]:SetHeight(cut)
	e[2]:ClearAllPoints(); e[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", cut, 0); e[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -cut, 0); e[2]:SetHeight(cut)
	e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -cut); e[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, cut); e[3]:SetWidth(cut)
	e[4]:ClearAllPoints(); e[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -cut); e[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, cut); e[4]:SetWidth(cut)
	e[5]:ClearAllPoints(); e[5]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0); e[5]:SetWidth(cut); e[5]:SetHeight(cut)
	e[6]:ClearAllPoints(); e[6]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0); e[6]:SetWidth(cut); e[6]:SetHeight(cut)
	e[7]:ClearAllPoints(); e[7]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0); e[7]:SetWidth(cut); e[7]:SetHeight(cut)
	e[8]:ClearAllPoints(); e[8]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0); e[8]:SetWidth(cut); e[8]:SetHeight(cut)
	for i = 1, 8 do e[i]:SetVertexColor(br, bgc, bb, ba) end
end

local function ApplyPanelAlpha()
	local a = (db and db.panelAlpha) or 0.5
	if a < 0.2 then a = 0.2 end
	if a > 1 then a = 1 end
	for i = 1, table.getn(skinnedPanels) do
		local f = skinnedPanels[i]
		if f and f._fill and f._bg then
			f._fill:SetVertexColor(f._bg[1], f._bg[2], f._bg[3], a)
		end
	end
end

-- ---------------------------------------------------------------- panel resizing
-- Corner grip on every panel:
--   drag          = free resize (width and height independently)
--   Shift + drag  = scale the whole panel (keeps proportions)
--   mouse wheel   = scale up / down in 5% steps
--   right-click   = reset size and scale
local MIN_SCALE, MAX_SCALE = 0.5, 2.5

local function SavePanelPoint(f)
	if not db or not f._pointKey then return end
	local p, _, rp, x, y = f:GetPoint()
	db[f._pointKey] = { p, rp, x, y }
end

-- Re-anchor by TOPLEFT so resizing/scaling grows right and down.
local function AnchorTopLeft(f)
	local left, top = f:GetLeft(), f:GetTop()
	if not left or not top then return end
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

local function SavePanelSize(f)
	if not db then return end
	if type(db.panelSize) ~= "table" then db.panelSize = {} end
	db.panelSize[f:GetName()] = { math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5) }
	SavePanelPoint(f)
end

-- Change a panel's scale while keeping its top-left corner where it is.
local function SetPanelScale(f, s, save)
	s = tonumber(s) or 1
	if s < MIN_SCALE then s = MIN_SCALE end
	if s > MAX_SCALE then s = MAX_SCALE end
	local old = f:GetScale() or 1
	local left, top = f:GetLeft(), f:GetTop()
	f:SetScale(s)
	if left and top then
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / s, top * old / s)
	end
	if save and db then
		if type(db.panelScale) ~= "table" then db.panelScale = {} end
		db.panelScale[f:GetName()] = s
		SavePanelPoint(f)
	end
end

local function SetPanelSize(f, w, h, save)
	w = math.max(f._minW or 60, math.min(1200, w))
	h = math.max(f._minH or 30, math.min(1000, h))
	f:SetWidth(w); f:SetHeight(h)
	if f.Layout then f:Layout() end
	if save then SavePanelSize(f) end
end

local function ResetPanel(f)
	AnchorTopLeft(f)
	SetPanelSize(f, f._defW, f._defH, false)
	SetPanelScale(f, 1, false)
	if db then
		if type(db.panelScale) == "table" then db.panelScale[f:GetName()] = nil end
		if type(db.panelSize) == "table" then db.panelSize[f:GetName()] = nil end
	end
	SavePanelPoint(f)
end

local function GripScaleUpdate()
	local f = this.panel
	local cx, cy = GetCursorPosition()
	local eff = f:GetEffectiveScale()
	local left, top = f:GetLeft(), f:GetTop()
	if not left or not top then return end
	local w, h = f:GetWidth(), f:GetHeight()
	if w <= 0 or h <= 0 then return end
	local ew = (cx - left * eff) / w
	local eh = (top * eff - cy) / h
	local want = math.max(ew, eh) / UIParent:GetEffectiveScale()
	if math.abs(want - f:GetScale()) > 0.005 then SetPanelScale(f, want, false) end
end

local function GripSizeUpdate()
	local f = this.panel
	local cx, cy = GetCursorPosition()
	local eff = f:GetEffectiveScale()
	local left, top = f:GetLeft(), f:GetTop()
	if not left or not top then return end
	local w = cx / eff - left + this.offX
	local h = top - cy / eff + this.offY
	if math.abs(w - f:GetWidth()) > 0.5 or math.abs(h - f:GetHeight()) > 0.5 then
		SetPanelSize(f, w, h, false)
	end
end

local function AddResizeGrip(f)
	local g = CreateFrame("Button", nil, f)
	g:SetWidth(14); g:SetHeight(14)
	g:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
	g:SetFrameLevel(f:GetFrameLevel() + 10)
	g:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	g:EnableMouseWheel(true)
	g.panel = f
	-- staircase of dots, like a classic size grabber
	g.dots = {}
	local pos = { {9, 0}, {5, 0}, {1, 0}, {9, 4}, {5, 4}, {9, 8} }
	for i = 1, 6 do
		local d = g:CreateTexture(nil, "OVERLAY")
		d:SetTexture(FLAT)
		d:SetWidth(2); d:SetHeight(2)
		d:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", pos[i][1] + 1, pos[i][2] + 2)
		d:SetVertexColor(0.85, 0.7, 0.35, 0.6)
		g.dots[i] = d
	end
	local function Tint(a)
		for i = 1, 6 do g.dots[i]:SetVertexColor(0.85, 0.7, 0.35, a) end
	end
	g:SetScript("OnEnter", function()
		Tint(1)
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Resize", 1, 0.82, 0)
		if not this.panel._noFree then
			GameTooltip:AddLine("Drag: change width and height", 1, 1, 1)
			GameTooltip:AddLine("Shift + drag: scale everything", 1, 1, 1)
		else
			GameTooltip:AddLine("Drag: scale the window", 1, 1, 1)
		end
		GameTooltip:AddLine("Mouse wheel: scale in 5% steps", 1, 1, 1)
		GameTooltip:AddLine("Right-click: reset size", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	g:SetScript("OnLeave", function()
		if not this.mode then Tint(0.6) end
		GameTooltip:Hide()
	end)
	g:SetScript("OnMouseDown", function()
		if arg1 ~= "LeftButton" then return end
		local pf = this.panel
		GameTooltip:Hide()
		AnchorTopLeft(pf)
		if IsShiftKeyDown() or pf._noFree then
			this.mode = "scale"
			this:SetScript("OnUpdate", GripScaleUpdate)
		else
			-- keep the grab offset so the corner doesn't jump to the cursor
			local cx, cy = GetCursorPosition()
			local eff = pf:GetEffectiveScale()
			this.offX = pf:GetRight() - cx / eff
			this.offY = cy / eff - pf:GetBottom()
			this.mode = "size"
			this:SetScript("OnUpdate", GripSizeUpdate)
		end
	end)
	g:SetScript("OnMouseUp", function()
		if not this.mode then return end
		local pf = this.panel
		this:SetScript("OnUpdate", nil)
		if this.mode == "scale" then
			SetPanelScale(pf, pf:GetScale(), true)
		else
			SavePanelSize(pf)
		end
		this.mode = nil
		if not MouseIsOver(this) then Tint(0.6) end
	end)
	g:SetScript("OnMouseWheel", function()
		local pf = this.panel
		AnchorTopLeft(pf)
		SetPanelScale(pf, pf:GetScale() + (arg1 or 0) * 0.05, true)
	end)
	g:SetScript("OnClick", function()
		if arg1 == "RightButton" then ResetPanel(this.panel) end
	end)
	f.grip = g
	return g
end

-- Number of list rows that fit in a panel of the current height.
local function RowsThatFit(f, top, rowH, bottomPad, maxRows)
	local n = math.floor(((f:GetHeight() or 0) - top - (bottomPad or 12)) / rowH)
	if n < 1 then n = 1 end
	if n > maxRows then n = maxRows end
	return n
end

local function MakePanel(name, width, height)
	local f = CreateFrame("Frame", name, UIParent)
	f:SetWidth(width)
	f:SetHeight(height)
	f._defW, f._defH = width, height
	f._minW = math.max(60, math.floor(width * 0.5))
	f._minH = math.max(30, math.floor(height * 0.4))
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	SkinPanel(f, { 0.05, 0.05, 0.06, 1 }, { 0.67, 0.57, 0.36, 1 })
	-- header strip (like KeijinUI panel.strip)
	local strip = f:CreateTexture(nil, "ARTWORK")
	strip:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
	strip:SetVertexColor(0.6, 0.53, 0.36, 0.55)
	strip:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -5)
	strip:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
	strip:SetHeight(22)
	f.strip = strip
	f.inner = f
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function() this:StartMoving() end)
	AddResizeGrip(f)
	f:Hide()
	return f
end

local function PanelTitle(panel, title)
	local t = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	t:SetPoint("TOP", panel, "TOP", 0, -10)
	t:SetText(title)
	t:SetTextColor(1, 0.82, 0.28)
	panel.titleFS = t
	return t
end



local function HideList(list)
	for i = 1, table.getn(list) do if list[i] then list[i]:Hide() end end
end

local function SetGameFlagShown(shown)
	if AZS_SetHudShown then
		AZS_SetHudShown("flag", shown)
	elseif SetCVar then
		SetCVar("hudFlag", shown and "1" or "0")
	end
end

local function IsSquare()
	if minimapStyled then return true end
	if type(GetMinimapShape) == "function" then
		local ok, shape = pcall(GetMinimapShape)
		if ok and shape then return shape == "SQUARE" end
	end
	return DFRL ~= nil or minimapStyled
end

local function InRun()
	local ph = AZS_GetPhase and AZS_GetPhase()
	return ph and ph ~= "ready"
end

local function FormatNum(n)
	n = math.floor((n or 0) + 0.5)
	if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
	if n >= 1000 then return string.format("%.1fk", n / 1000) end
	return tostring(n)
end

local function FormatTime(sec)
	sec = math.max(0, math.floor(sec + 0.5))
	return string.format("%d:%02d", math.floor(sec / 60), math.mod(sec, 60))
end

local function FS(parent, font, justify)
	local t = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	t:SetJustifyH(justify or "LEFT")
	return t
end

-- ---------------------------------------------------------------- square minimap (KeijinUI-inspired)
local minimapNative = {}
local MINIMAP_MASK = "Interface\\AddOns\\AZSTracker\\Textures\\MinimapMask"
local DEFAULT_MASK = "Textures\\MinimapMask"
local NATIVE_MM = { "MinimapBorderTop", "MinimapBorder", "MinimapBackdrop", "MinimapToggleButton",
	"MinimapZoneTextButton", "GameTimeFrame", "MinimapNorthTag", "MinimapZoomIn", "MinimapZoomOut" }
-- small minimap buttons that sit on the round border; tucked into the square's corners
local MM_CORNERS = {
	{ "MiniMapTrackingFrame", "TOPLEFT", 1, -1 },
	{ "MiniMapMailFrame", "BOTTOMRIGHT", 2, -2 },
	{ "MiniMapBattlefieldFrame", "BOTTOMLEFT", -1, 1 },
	{ "MiniMapMeetingStoneFrame", "TOPRIGHT", 2, 2 },
}

local function SetMinimapMask(path)
	if not Minimap or not Minimap.SetMaskTexture then return end
	if pcall(Minimap.SetMaskTexture, Minimap, path) then return end
	pcall(Minimap.SetMaskTexture, Minimap, "Interface\\Buttons\\WHITE8X8")
end

local minimapSavedSize = nil
local savedPoints = {}

local function SavePoints(f)
	if not f or savedPoints[f] then return end
	local pts = {}
	for i = 1, (f:GetNumPoints() or 0) do
		local p, rel, rp, x, y = f:GetPoint(i)
		pts[i] = { p, rel, rp, x, y }
	end
	savedPoints[f] = pts
end

local function RestorePoints(f)
	local pts = f and savedPoints[f]
	if not pts then return end
	f:ClearAllPoints()
	for i = 1, table.getn(pts) do
		local q = pts[i]
		f:SetPoint(q[1], q[2], q[3], q[4], q[5])
	end
	savedPoints[f] = nil
end

local function MinimapSide()
	if db and tonumber(db.minimapSide) then return tonumber(db.minimapSide) end
	return 210
end

local function RefreshMinimapRender()
	-- nudge the zoom so the client redraws the map at the new size/mask
	if not Minimap.GetZoom then return end
	local z = Minimap:GetZoom() or 0
	local zmax = (Minimap.GetZoomLevels and Minimap:GetZoomLevels()) or 6
	if z + 1 < zmax then Minimap:SetZoom(z + 1) else Minimap:SetZoom(z - 1) end
	Minimap:SetZoom(z)
end

local function SquareShape() return "SQUARE" end

local function UpdateMinimapZone()
	if Minimap and Minimap.azsZone and GetMinimapZoneText then
		Minimap.azsZone:SetText(GetMinimapZoneText() or "")
		local pvp = GetZonePVPInfo and GetZonePVPInfo()
		if pvp == "sanctuary" then Minimap.azsZone:SetTextColor(0.41, 0.8, 0.94)
		elseif pvp == "friendly" then Minimap.azsZone:SetTextColor(0.1, 1, 0.1)
		elseif pvp == "hostile" then Minimap.azsZone:SetTextColor(1, 0.1, 0.1)
		elseif pvp == "contested" then Minimap.azsZone:SetTextColor(1, 0.7, 0)
		else Minimap.azsZone:SetTextColor(1, 0.82, 0) end
	end
end

local function BuildMinimapChrome()
	if Minimap.azsRim then return end
	-- 3-layer frame: dark outer shadow, gold rim, dark inner line
	Minimap.azsRim = {}
	local layers = {
		{ 4, 0, 0, 0, 0.85 },          -- outer shadow
		{ 3, 0.78, 0.64, 0.36, 1 },    -- gold
		{ 1, 0.05, 0.04, 0.02, 1 },    -- inner dark line
	}
	for L = 1, 3 do
		local th, r, g, b, a = layers[L][1], layers[L][2], layers[L][3], layers[L][4], layers[L][5]
		for side = 1, 4 do
			local t = Minimap:CreateTexture(nil, "OVERLAY")
			t:SetTexture(FLAT)
			t:SetVertexColor(r, g, b, a)
			if side == 1 then
				t:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -th, th); t:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", th, th); t:SetHeight(1)
			elseif side == 2 then
				t:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", -th, -th); t:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", th, -th); t:SetHeight(1)
			elseif side == 3 then
				t:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -th, th); t:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", -th, -th); t:SetWidth(1)
			else
				t:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", th, th); t:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", th, -th); t:SetWidth(1)
			end
			table.insert(Minimap.azsRim, t)
		end
	end
	-- gold band: the gold layer is 1px per line above; thicken it to 2px with a second pass
	for side = 1, 4 do
		local t = Minimap:CreateTexture(nil, "OVERLAY")
		t:SetTexture(FLAT)
		t:SetVertexColor(0.62, 0.5, 0.27, 1)
		if side == 1 then
			t:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -2, 2); t:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", 2, 2); t:SetHeight(1)
		elseif side == 2 then
			t:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", -2, -2); t:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 2, -2); t:SetHeight(1)
		elseif side == 3 then
			t:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -2, 2); t:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", -2, -2); t:SetWidth(1)
		else
			t:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", 2, 2); t:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 2, -2); t:SetWidth(1)
		end
		table.insert(Minimap.azsRim, t)
	end
	-- zone name strip across the top, inside the map
	local strip = Minimap:CreateTexture(nil, "OVERLAY")
	strip:SetTexture(FLAT)
	strip:SetGradientAlpha("VERTICAL", 0, 0, 0, 0, 0, 0, 0, 0.7)
	strip:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)
	strip:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", 0, 0)
	strip:SetHeight(18)
	Minimap.azsStrip = strip
	local zone = Minimap:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	zone:SetPoint("TOP", Minimap, "TOP", 0, -4)
	zone:SetShadowOffset(1, -1)
	Minimap.azsZone = zone
	local ev = CreateFrame("Frame", nil, Minimap)
	ev:RegisterEvent("ZONE_CHANGED")
	ev:RegisterEvent("ZONE_CHANGED_INDOORS")
	ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	ev:RegisterEvent("PLAYER_ENTERING_WORLD")
	ev:SetScript("OnEvent", function() if minimapStyled then UpdateMinimapZone() end end)
end

-- The square map is locked at its widest zoom so it never zooms in/out.
local function MinimapWheel() end -- swallow the wheel so it does nothing

local function LockMinimapZoom()
	if minimapStyled and Minimap and Minimap.GetZoom and (Minimap:GetZoom() or 0) ~= 0 then
		Minimap:SetZoom(0)
	end
end

local function ApplySquareLayout()
	local side = MinimapSide()
	Minimap:SetWidth(side)
	Minimap:SetHeight(side)
	-- keep the whole square on screen (the round default position pushes a big map off the top/right)
	SavePoints(Minimap)
	Minimap:ClearAllPoints()
	Minimap:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -16, -16)
	-- buffs default to x=-180 from the right edge; move them left of the bigger map
	if TemporaryEnchantFrame then
		SavePoints(TemporaryEnchantFrame)
		TemporaryEnchantFrame:ClearAllPoints()
		TemporaryEnchantFrame:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", -14, 3)
	end
	for i = 1, table.getn(MM_CORNERS) do
		local c = MM_CORNERS[i]
		local f = getglobal(c[1])
		if f then
			SavePoints(f)
			f:ClearAllPoints()
			f:SetPoint(c[2], Minimap, c[2], c[3], c[4])
		end
	end
	SetMinimapMask(MINIMAP_MASK)
	RefreshMinimapRender()
	Minimap:SetZoom(0)
end

local function StyleMinimap(on)
	if not Minimap then return end
	if on and not minimapStyled then
		for i = 1, table.getn(NATIVE_MM) do
			local f = getglobal(NATIVE_MM[i])
			if f then
				minimapNative[NATIVE_MM[i]] = f:IsShown() and 1 or 0
				f:Hide()
			end
		end
		if not minimapSavedSize then
			minimapSavedSize = { mw = Minimap:GetWidth() or 140, mh = Minimap:GetHeight() or 140 }
		end
		BuildMinimapChrome()
		for i = 1, table.getn(Minimap.azsRim) do Minimap.azsRim[i]:Show() end
		Minimap.azsStrip:Show(); Minimap.azsZone:Show()
		Minimap.azsOldWheel = Minimap:GetScript("OnMouseWheel")
		Minimap:EnableMouseWheel(true)
		Minimap:SetScript("OnMouseWheel", MinimapWheel)
		if GetMinimapShape == nil then GetMinimapShape = SquareShape end
		minimapStyled = true
		ApplySquareLayout()
		UpdateMinimapZone()
	elseif not on and minimapStyled then
		for name, shown in pairs(minimapNative) do
			local f = getglobal(name)
			if f and shown == 1 then f:Show() end
		end
		minimapNative = {}
		SetMinimapMask(DEFAULT_MASK)
		if minimapSavedSize then
			Minimap:SetWidth(minimapSavedSize.mw)
			Minimap:SetHeight(minimapSavedSize.mh)
		end
		RestorePoints(Minimap)
		RestorePoints(TemporaryEnchantFrame)
		for i = 1, table.getn(MM_CORNERS) do RestorePoints(getglobal(MM_CORNERS[i][1])) end
		if Minimap.azsRim then
			for i = 1, table.getn(Minimap.azsRim) do Minimap.azsRim[i]:Hide() end
			Minimap.azsStrip:Hide(); Minimap.azsZone:Hide()
		end
		Minimap:SetScript("OnMouseWheel", Minimap.azsOldWheel)
		if not Minimap.azsOldWheel then Minimap:EnableMouseWheel(false) end
		if GetMinimapShape == SquareShape then GetMinimapShape = nil end
		minimapStyled = false
		RefreshMinimapRender()
	elseif on and minimapStyled then
		-- re-apply (size option changed, or the client reset the mask on a zone load)
		for i = 1, table.getn(NATIVE_MM) do
			local f = getglobal(NATIVE_MM[i])
			if f and f:IsShown() then f:Hide() end
		end
		ApplySquareLayout()
		UpdateMinimapZone()
	end
end

-- ---------------------------------------------------------------- minimap pins (chests / lairs)
-- PIN size scales with minimap zoom: smaller when zoomed out, larger when zoomed in.
-- Chests draw above lairs. Empty lairs show a short countdown until next spawn.

local function PinSize(zoom)
	-- zoom 0 (most out) -> smaller, zoom 5 (most in) -> larger; bias from options
	zoom = zoom or 0
	if zoom < 0 then zoom = 0 end
	if zoom > 5 then zoom = 5 end
	local bias = (db and db.pinSizeBias) or 0
	local s = 10 + zoom * 1.2 + bias
	if s < 8 then s = 8 end
	if s > 22 then s = 22 end
	return s
end

local function NewPin(list, idx, texture, label, levelOffset, withTimer)
	local p = CreateFrame("Frame", nil, Minimap)
	p:SetWidth(PIN); p:SetHeight(PIN)
	p:SetFrameLevel(Minimap:GetFrameLevel() + (levelOffset or 8))
	p.icon = p:CreateTexture(nil, "OVERLAY")
	p.icon:SetAllPoints(p)
	p.icon:SetTexture(texture)
	p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	if withTimer then
		-- GameFontNormalSmall always has a font set (FRIZQT may be missing on some clients)
		p.timer = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		p.timer:SetPoint("BOTTOM", p, "TOP", 0, 2)
		p.timer:SetTextColor(1, 0.85, 0.2)
		p.timer:SetText("")
		p.timer:SetJustifyH("CENTER")
	end
	p:EnableMouse(true)
	p:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_LEFT")
		GameTooltip:AddLine(this.label or label or "Marker", 1, 0.82, 0)
		if this.dist then GameTooltip:AddLine(math.floor(this.dist + 0.5) .. " yd away", 1, 1, 1) end
		GameTooltip:Show()
	end)
	p:SetScript("OnLeave", function() GameTooltip:Hide() end)
	list[idx] = p
	return p
end

local function Place(p, ox, oy, limit, square, size)
	local reach
	if square then reach = math.max(math.abs(ox), math.abs(oy)) else reach = math.sqrt(ox * ox + oy * oy) end
	if reach > limit then p:Hide(); return false end
	if size then
		p:SetWidth(size); p:SetHeight(size)
	end
	p:ClearAllPoints()
	p:SetPoint("CENTER", Minimap, "CENTER", ox, oy)
	p:Show()
	return true
end

local function RefreshMarkers()
	if not markersEnabled or not Minimap then
		HideList(chestPins); HideList(lairPins)
		return
	end
	SetGameFlagShown(false)
	local run = AZS_RUN
	local hx = type(run) == "table" and tonumber(run.px)
	local hy = type(run) == "table" and tonumber(run.py)
	if not hx or not hy or not AZS_GetPhase or not AZS_GetPhase() then
		HideList(chestPins); HideList(lairPins); return
	end
	local width = Minimap:GetWidth() or 140
	local zoom = Minimap:GetZoom() or 0
	local scale = width / (ZOOM_YD[zoom] or 333.3333)
	local size = PinSize(zoom)
	local limit = width / 2 - size / 2
	local square = IsSquare()

	-- Lairs first (lower frame level), chests after so chests stay on top
	-- Prefer AZS_LAIRS so `left` (respawn seconds) is always present
	local lairs = AZS_LAIRS or (AZS_GetLairs and AZS_GetLairs()) or {}
	local used = 0
	local showTimers = not db or db.lairTimers ~= false
	for i = 1, table.getn(lairs) do
		local l = lairs[i]
		local lx, ly = tonumber(l.x), tonumber(l.y)
		local state = l.state
		if not state then
			if l.active then state = "asleep" else state = "empty" end
		end
		local left = tonumber(l.left)
		if left == nil then left = -1 end
		-- held lairs, or empty ones that are counting down / due
		local show = lx and ly and (state == "asleep" or state == "awake" or (state == "empty" and left >= 0))
		if show then
			local north, east = lx - hx, hy - ly
			local p = lairPins[used + 1] or NewPin(lairPins, used + 1, "Interface\\AddOns\\AZSTracker\\Textures\\Skull", "Guardian Lair", 8, true)
			p:SetFrameLevel(Minimap:GetFrameLevel() + 8)
			if Place(p, east * scale, north * scale, limit, square, size) then
				used = used + 1
				p.dist = math.sqrt(north * north + east * east)
				if state == "awake" then
					p.icon:SetVertexColor(1, 0.3, 0.3)
					p.label = (l.name or "Guardian Lair") .. " - fighting"
					if p.timer then p.timer:SetText("") end
				elseif state == "asleep" then
					p.icon:SetVertexColor(1, 1, 1)
					p.label = (l.name or "Guardian Lair") .. " - asleep"
					if p.timer then p.timer:SetText("") end
				else
					p.icon:SetVertexColor(0.55, 0.55, 0.55)
					local secs = math.ceil(left)
					if left > 0 then
						p.label = (l.name or "Guardian Lair") .. " - " .. secs .. "s"
						if p.timer and showTimers then
							p.timer:SetText(secs .. "s")
							p.timer:SetTextColor(1, 0.85, 0.2)
						elseif p.timer then
							p.timer:SetText("")
						end
					else
						p.label = (l.name or "Guardian Lair") .. " - due"
						if p.timer and showTimers then
							p.timer:SetText("!")
							p.timer:SetTextColor(1, 0.3, 0.2)
						elseif p.timer then
							p.timer:SetText("")
						end
					end
				end
			end
		end
	end
	for i = used + 1, table.getn(lairPins) do
		if lairPins[i] then
			lairPins[i]:Hide()
			if lairPins[i].timer then lairPins[i].timer:SetText("") end
		end
	end

	local chests = AZS_CHESTS or {}
	used = 0
	for i = 1, table.getn(chests) do
		local c = chests[i]
		local cx, cy = tonumber(c.x), tonumber(c.y)
		if cx and cy then
			local north, east = cx - hx, hy - cy
			local p = chestPins[used + 1] or NewPin(chestPins, used + 1, "Interface\\AddOns\\AZSTracker\\Textures\\Chest", "Battleground Cache", 7, false)
			if Place(p, east * scale, north * scale, limit, square, size) then
				-- Normally keep lairs above chests. Raise a chest only if its icon
				-- physically overlaps a visible lair icon.
				local baseLevel = Minimap:GetFrameLevel() + 7
				p:SetFrameLevel(baseLevel)
				local px, py = p:GetCenter()
				for li = 1, table.getn(lairPins) do
					local lp = lairPins[li]
					if lp and lp:IsShown() then
						local lx2, ly2 = lp:GetCenter()
						if px and py and lx2 and ly2 then
							local dx, dy = px - lx2, py - ly2
							local overlap = math.max(10, size * 0.78)
							if dx * dx + dy * dy < overlap * overlap then
								p:SetFrameLevel(lp:GetFrameLevel() + 1)
								break
							end
						end
					end
				end
				used = used + 1
				p.label = "Battleground Cache"
				p.dist = math.sqrt(north * north + east * east)
			end
		end
	end
	for i = used + 1, table.getn(chestPins) do if chestPins[i] then chestPins[i]:Hide() end end
end

-- ---------------------------------------------------------------- odds panel

local RARITY = {
	{ name = "RARE", r = 0.00, g = 0.44, b = 0.87 },
	{ name = "EPIC", r = 0.64, g = 0.21, b = 0.93 },
	{ name = "LEGEND", r = 1.00, g = 0.50, b = 0.00 },
}
local ODDS_ROWS = {
	{ label = "Spells", icon = "Spell_Holy_HolyBolt", bonus = 0 },
	{ label = "Rings", icon = "INV_Jewelry_Ring_15", bonus = 0 },
	{ label = "Trinkets", icon = "INV_Misc_StoneTablet_11", bonus = 0 },
	{ label = "Amulets", icon = "INV_Jewelry_Talisman_07", bonus = 0.5 },
}
local O_WIDTH, O_ROW_H, O_TOP = 246, 18, 43
local COL_RIGHT = { 158, 204, 252 }

local function Odds(k)
	local w = { 60, 25 * k, 10 * k * k, 4 * k * k * k, k * k * k * k }
	local total = w[1] + w[2] + w[3] + w[4] + w[5]
	return { w[3] * 100 / total, w[4] * 100 / total, w[5] * 100 / total }
end

local function Luck()
	local s = AZS_STATS
	return type(s) == "table" and tonumber(s.luck) or nil
end

local function LevelBonus()
	local lvl
	if type(AZS_RUN) == "table" and tonumber(AZS_RUN.lvl) then
		lvl = tonumber(AZS_RUN.lvl)
	else
		lvl = UnitLevel("player") or 0
	end
	return math.min(0.30, math.max(0, lvl) * 0.01)
end

local oddsPanel = MakePanel("AZSTrackerOddsFrame", O_WIDTH + 18, O_TOP + table.getn(ODDS_ROWS) * O_ROW_H + 31)
oddsPanel:SetScript("OnDragStop", function()
	this:StopMovingOrSizing()
	if not db then return end
	local p, _, rp, x, y = this:GetPoint()
	db.point = { p, rp, x, y }
end)

do
	local icon = CreateFrame("Frame", nil, oddsPanel)
	icon:SetWidth(22); icon:SetHeight(22)
	icon:SetPoint("TOPLEFT", oddsPanel, "TOPLEFT", 10, -9)
	local tex = icon:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints(icon)
	tex:SetTexture("Interface\\Icons\\INV_Jewelry_Necklace_26")
	tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	oddsPanel.luck = FS(oddsPanel, "GameFontNormal")
	oddsPanel.luck:SetPoint("LEFT", icon, "RIGHT", 8, 5)
	oddsPanel.level = FS(oddsPanel, "GameFontDisableSmall")
	oddsPanel.level:SetPoint("LEFT", icon, "RIGHT", 8, -7)
	oddsPanel.heads = {}
	for i = 1, 3 do
		local h = FS(oddsPanel, "GameFontNormalSmall", "RIGHT")
		h:SetPoint("RIGHT", oddsPanel, "TOPLEFT", COL_RIGHT[i], -O_TOP + 8)
		oddsPanel.heads[i] = h
		h:SetText(RARITY[i].name)
		h:SetTextColor(RARITY[i].r, RARITY[i].g, RARITY[i].b)
	end
	local rule = oddsPanel:CreateTexture(nil, "ARTWORK")
	rule:SetTexture("Interface\\Buttons\\WHITE8X8")
	rule:SetVertexColor(0.62, 0.52, 0.32, 0.5)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", oddsPanel, "TOPLEFT", 8, -O_TOP + 1)
	rule:SetPoint("TOPRIGHT", oddsPanel, "TOPRIGHT", -8, -O_TOP + 1)
	oddsPanel.rows = {}
	for n = 1, table.getn(ODDS_ROWS) do
		local y = -O_TOP - (n - 1) * O_ROW_H
		local row = {}
		if math.mod(n, 2) == 0 then
			local band = oddsPanel:CreateTexture(nil, "BACKGROUND")
			band:SetTexture("Interface\\Buttons\\WHITE8X8")
			band:SetVertexColor(1, 1, 1, 0.04)
			band:SetHeight(O_ROW_H)
			band:SetPoint("TOPLEFT", oddsPanel, "TOPLEFT", 6, y)
			band:SetPoint("TOPRIGHT", oddsPanel, "TOPRIGHT", -6, y)
			row.band = band
		end
		local ic = CreateFrame("Frame", nil, oddsPanel)
		ic:SetWidth(15); ic:SetHeight(15)
		ic:SetPoint("LEFT", oddsPanel, "TOPLEFT", 12, y - O_ROW_H / 2)
		local it = ic:CreateTexture(nil, "ARTWORK")
		it:SetAllPoints(ic)
		it:SetTexture("Interface\\Icons\\" .. ODDS_ROWS[n].icon)
		it:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		row.ic = ic
		local name = FS(oddsPanel, "GameFontHighlightSmall")
		name:SetPoint("LEFT", ic, "RIGHT", 6, 0)
		name:SetText(ODDS_ROWS[n].label)
		row.cells = {}
		for i = 1, 3 do
			local c = FS(oddsPanel, "GameFontHighlightSmall", "RIGHT")
			c:SetPoint("RIGHT", oddsPanel, "TOPLEFT", COL_RIGHT[i], y - O_ROW_H / 2)
			row.cells[i] = c
		end
		oddsPanel.rows[n] = row
	end
end

oddsPanel._minW = 200
function oddsPanel:Layout()
	local w, h = self:GetWidth(), self:GetHeight()
	local n = table.getn(ODDS_ROWS)
	local rowH = math.max(14, (h - O_TOP - 31) / n)
	local function ColX(i) return 12 + (w - 24) * (COL_RIGHT[i] - 12) / 240 end
	for i = 1, 3 do
		self.heads[i]:ClearAllPoints()
		self.heads[i]:SetPoint("RIGHT", self, "TOPLEFT", ColX(i), -O_TOP + 8)
	end
	for r = 1, n do
		local row = self.rows[r]
		local y = -O_TOP - (r - 1) * rowH
		if row.band then
			row.band:ClearAllPoints()
			row.band:SetHeight(rowH)
			row.band:SetPoint("TOPLEFT", self, "TOPLEFT", 6, y)
			row.band:SetPoint("TOPRIGHT", self, "TOPRIGHT", -6, y)
		end
		row.ic:ClearAllPoints()
		row.ic:SetPoint("LEFT", self, "TOPLEFT", 12, y - rowH / 2)
		for i = 1, 3 do
			row.cells[i]:ClearAllPoints()
			row.cells[i]:SetPoint("RIGHT", self, "TOPLEFT", ColX(i), y - rowH / 2)
		end
	end
end

local function RefreshOdds()
	if not db then return end
	local luck = Luck()
	if not db.shown or not luck then oddsPanel:Hide(); return end
	oddsPanel:Show()
	local lvl = LevelBonus()
	oddsPanel.luck:SetText("Luck  |cffffffff" .. math.floor(luck * 100 + 0.5) .. "%|r")
	oddsPanel.level:SetText("+" .. math.floor(lvl * 100 + 0.5) .. "% from your level")
	local k = 1 + luck + lvl
	for n = 1, table.getn(ODDS_ROWS) do
		local odds = Odds(k + ODDS_ROWS[n].bonus)
		for i = 1, 3 do
			local c = oddsPanel.rows[n].cells[i]
			c:SetText(string.format("%.1f%%", odds[i]))
			local a = 0.55 + math.min(0.45, odds[i] / 40)
			c:SetTextColor(
				1 - (1 - RARITY[i].r) * 0.45 * a,
				1 - (1 - RARITY[i].g) * 0.45 * a,
				1 - (1 - RARITY[i].b) * 0.45 * a
			)
		end
	end
end

-- ---------------------------------------------------------------- damage meter (biggest hit per skill)

local maxHits = {}
local METER_ROWS = 8
local METER_W = 278
local METER_BAR_H = 13
local METER_ROW_GAP = 2
local METER_MAX = 24

local meterPanel = MakePanel("AZSTrackerMeterFrame", METER_W, 43 + METER_ROWS * (METER_BAR_H + METER_ROW_GAP) + 13)
PanelTitle(meterPanel, "Highest Damage")
meterPanel.sub = meterPanel.inner:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
meterPanel.sub:SetPoint("TOPRIGHT", meterPanel.inner, "TOPRIGHT", -10, -8)
meterPanel.rows = {}
for i = 1, METER_MAX do
	local y = -32 - (i - 1) * (METER_BAR_H + METER_ROW_GAP)
	local row = CreateFrame("Frame", nil, meterPanel.inner)
	row:SetWidth(METER_W - 44)
	row:SetHeight(METER_BAR_H)
	row:SetPoint("TOPLEFT", meterPanel.inner, "TOPLEFT", 8, y)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints(row)
	row.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
	row.bg:SetVertexColor(0.08, 0.08, 0.1, 0.95)
	row.bar = row:CreateTexture(nil, "ARTWORK")
	row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	row.bar:SetWidth(1)
	row.bar:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
	row.bar:SetVertexColor(0.85, 0.2, 0.15, 1)
	row.icon = row:CreateTexture(nil, "OVERLAY")
	row.icon:SetWidth(METER_BAR_H - 2)
	row.icon:SetHeight(METER_BAR_H - 2)
	row.icon:SetPoint("LEFT", row, "LEFT", 1, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetTextColor(1, 0.95, 0.85)
	row.val = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.val:SetPoint("RIGHT", row, "RIGHT", -5, 0)
	row.val:SetJustifyH("RIGHT")
	row.val:SetTextColor(1, 0.9, 0.5)
	row:Hide()
	meterPanel.rows[i] = row
end
meterPanel.nrows = METER_ROWS
meterPanel.barW = METER_W - 44
meterPanel._minW = 140
function meterPanel:Layout()
	self.barW = math.max(60, self:GetWidth() - 18)
	self.nrows = RowsThatFit(self, 32, METER_BAR_H + METER_ROW_GAP, 12, METER_MAX)
	for i = 1, METER_MAX do
		self.rows[i]:SetWidth(self.barW)
		if i > self.nrows then self.rows[i]:Hide() end
	end
end

meterPanel:SetScript("OnDragStop", function()
	this:StopMovingOrSizing()
	if not db then return end
	local p, _, rp, x, y = this:GetPoint()
	db.meterPoint = { p, rp, x, y }
end)

-- Resolve skill icons in priority order:
-- spellbook (including pet/tabs), action bars, AZS spell IDs, fuzzy name match,
-- keyword map, talents, then generic fallback. Unknown "?" entries stay question marks.
local spellbookCache, actionCache, azsCache, talentCache, meterIconCache = {}, {}, {}, {}, {}
local resolvedIcons = {}
local resolvedSrc = {}
local gameScanCache = {}
local builtinCache = nil -- AZSTrackerIcons.lua: the game's own skill/talent/item icons
local BOOK = BOOKTYPE_SPELL or "spell"
local DEFAULT_ICON = "Interface\\Icons\\Spell_Holy_HolyBolt"
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function Norm(s)
    if not s then return "" end
    s = string.lower(tostring(s))
    s = string.gsub(s, "%(rank %d+%)", "")
    s = string.gsub(s, "%s+rank %d+$", "")
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    s = string.gsub(s, "%s+", " ")
    return s
end

local KEYWORDS = {
	-- summons / pets / totems
	{ "imp", "Spell_Shadow_SummonImp" },
	{ "voidwalker", "Spell_Shadow_SummonVoidWalker" },
	{ "succubus", "Spell_Shadow_SummonSuccubus" },
	{ "felhunter", "Spell_Shadow_SummonFelHunter" },
	{ "infernal", "Spell_Shadow_SummonInfernal" },
	{ "doomguard", "INV_Stone_WeightStone_08" },
	{ "water elemental", "Spell_Frost_SummonWaterElemental" },
	{ "fire elemental", "Spell_Fire_Elemental_Totem" },
	{ "earth elemental", "Spell_Nature_EarthElemental_Totem" },
	{ "elemental", "Spell_Fire_Elemental_Totem" },
	{ "treant", "Ability_Druid_ForceofNature" },
	{ "force of nature", "Ability_Druid_ForceofNature" },
	{ "spirit wolf", "Spell_Shaman_FeralSpirit" },
	{ "feral spirit", "Spell_Nature_SpiritWolf" },
	{ "wolf", "Ability_Hunter_Pet_Wolf" },
	{ "bear", "Ability_Hunter_Pet_Bear" },
	{ "cat", "Ability_Hunter_Pet_Cat" },
	{ "boar", "Ability_Hunter_Pet_Boar" },
	{ "raptor", "Ability_Hunter_Pet_Raptor" },
	{ "spider", "Ability_Hunter_Pet_Spider" },
	{ "bat", "Ability_Hunter_Pet_Bat" },
	{ "owl", "Ability_Hunter_Pet_Owl" },
	{ "hawk", "Ability_Hunter_Pet_Owl" },
	{ "scorpid", "Ability_Hunter_Pet_Scorpid" },
	{ "gorilla", "Ability_Hunter_Pet_Gorilla" },
	{ "crocolisk", "Ability_Hunter_Pet_Crocolisk" },
	{ "turtle", "Ability_Hunter_Pet_Turtle" },
	{ "skeleton", "Spell_Shadow_RaiseDead" },
	{ "ghoul", "Spell_Shadow_RaiseDead" },
	{ "undead", "Spell_Shadow_RaiseDead" },
	{ "shadowfiend", "Spell_Shadow_Shadowfiend" },
	{ "searing totem", "Spell_Fire_SearingTotem" },
	{ "magma totem", "Spell_Fire_SelfDestruct" },
	{ "fire nova", "Spell_Fire_SealOfFire" },
	{ "stoneclaw", "Spell_Nature_StoneClawTotem" },
	{ "totem", "Spell_Nature_StoneClawTotem" },
	{ "golem", "INV_Misc_Gear_01" },
	{ "dragonling", "INV_Misc_Head_Dragon_Bronze" },
	{ "mechanical", "INV_Misc_Gear_01" },
	{ "bomb", "INV_Misc_Bomb_04" },
	{ "explosive", "INV_Misc_Bomb_04" },
	{ "guardian", "Spell_Holy_SealOfProtection" },
	{ "spirit", "Spell_Nature_SpiritWolf" },
	{ "fireball", "Spell_Fire_FlameBolt" },
	{ "fire blast", "Spell_Fire_Fireball" },
	{ "pyroblast", "Spell_Fire_Fireball02" },
	{ "scorch", "Spell_Fire_SoulBurn" },
	{ "flamestrike", "Spell_Fire_SelfDestruct" },
	{ "immolate", "Spell_Fire_Immolation" },
	{ "conflagrat", "Spell_Fire_Fireball" },
	{ "shadow bolt", "Spell_Shadow_ShadowBolt" },
	{ "corruption", "Spell_Shadow_AbominationExplosion" },
	{ "curse of agony", "Spell_Shadow_CurseOfSargeras" },
	{ "curse of", "Spell_Shadow_CurseOfSargeras" },
	{ "siphon life", "Spell_Shadow_Requiem" },
	{ "drain life", "Spell_Shadow_LifeDrain02" },
	{ "drain soul", "Spell_Shadow_Haunting" },
	{ "death coil", "Spell_Shadow_DeathCoil" },
	{ "shadow word: pain", "Spell_Shadow_ShadowWordPain" },
	{ "shadow word", "Spell_Shadow_ShadowWordPain" },
	{ "mind flay", "Spell_Shadow_SiphonMana" },
	{ "mind blast", "Spell_Shadow_UnholyFrenzy" },
	{ "devouring plague", "Spell_Shadow_BlackPlague" },
	{ "holy fire", "Spell_Holy_SearingLight" },
	{ "smite", "Spell_Holy_HolySmite" },
	{ "holy nova", "Spell_Holy_HolyNova" },
	{ "moonfire", "Spell_Nature_StarFall" },
	{ "wrath", "Spell_Nature_AbolishMagic" },
	{ "starfire", "Spell_Arcane_StarFire" },
	{ "insect swarm", "Spell_Nature_InsectSwarm" },
	{ "rake", "Ability_Druid_Disembowel" },
	{ "rip", "Ability_GhoulFrenzy" },
	{ "shred", "Spell_Shadow_VampiricAura" },
	{ "ferocious bite", "Ability_Druid_FerociousBite" },
	{ "claw", "Ability_Druid_Rake" },
	{ "rend", "Ability_Gouge" },
	{ "heroic strike", "Ability_Rogue_Ambush" },
	{ "mortal strike", "Ability_Warrior_SavageBlow" },
	{ "bloodthirst", "Spell_Nature_BloodLust" },
	{ "whirlwind", "Ability_Whirlwind" },
	{ "execute", "INV_Sword_48" },
	{ "sinister strike", "Spell_Shadow_RitualOfSacrifice" },
	{ "eviscerate", "Ability_Rogue_Eviscerate" },
	{ "backstab", "Ability_BackStab" },
	{ "rupture", "Ability_Rogue_Rupture" },
	{ "garrote", "Ability_Rogue_Garrote" },
	{ "arcane shot", "Ability_ImpalingBolt" },
	{ "serpent sting", "Ability_Hunter_CriticalShot" },
	{ "multi-shot", "Ability_UpgradeMoonGlaive" },
	{ "aimed shot", "INV_Spear_07" },
	{ "auto shot", "Ability_Marksmanship" },
	{ "frostbolt", "Spell_Frost_FrostBolt02" },
	{ "frost nova", "Spell_Frost_FrostNova" },
	{ "cone of cold", "Spell_Frost_Glacier" },
	{ "blizzard", "Spell_Frost_IceStorm" },
	{ "lightning bolt", "Spell_Nature_Lightning" },
	{ "chain lightning", "Spell_Nature_ChainLightning" },
	{ "flame shock", "Spell_Fire_FlameShock" },
	{ "earth shock", "Spell_Nature_EarthShock" },
	{ "stormstrike", "Ability_Shaman_Stormstrike" },
	{ "crusader strike", "Spell_Holy_CrusaderStrike" },
	{ "judgment", "Spell_Holy_RighteousFury" },
	{ "consecration", "Spell_Holy_InnerFire" },
	{ "exorcism", "Spell_Holy_Excorcism_02" },
	{ "melee", "Ability_DualWield" },
	{ "auto attack", "Ability_DualWield" },
	{ "attack", "Ability_DualWield" },
	{ "thorns", "Spell_Nature_Thorns" },
	{ "lightning shield", "Spell_Nature_LightningShield" },
	{ "fire", "Spell_Fire_Fire" },
	{ "frost", "Spell_Frost_FrostBolt02" },
	{ "shadow", "Spell_Shadow_ShadowBolt" },
	{ "nature", "Spell_Nature_AbolishMagic" },
	{ "holy", "Spell_Holy_HolyBolt" },
	{ "arcane", "Spell_Nature_StarFall" },
	{ "bleed", "Ability_Druid_Disembowel" },
	{ "poison", "Ability_PoisonSting" },
	{ "amulet", "INV_Jewelry_Amulet_01" },
	{ "ring", "INV_Jewelry_Ring_01" },
	{ "trinket", "INV_Misc_StoneTablet_11" },
	{ "proc", "Spell_Holy_WeaponMastery" },
	{ "talent", "Spell_Holy_WeaponMastery" },
	{ "pet", "Ability_Hunter_Pet_Wolf" },
	{ "summon", "Spell_Shadow_SummonImp" },
}

local function SafeSpellTexture(slot, book)
    local ok, tex = pcall(GetSpellTexture, slot, book or BOOK)
    if ok and type(tex) == "string" and tex ~= "" then return tex end
    ok, tex = pcall(GetSpellTexture, slot)
    if ok and type(tex) == "string" and tex ~= "" then return tex end
    return nil
end

local function Cache(cache, name, tex)
    if not name or not tex then return end
    name = tostring(name)
    cache[name] = tex
    cache[Norm(name)] = tex
    -- "Summon Imp" also answers for the summon itself ("Imp")
    local _, _, summoned = string.find(Norm(name), "^summon (.+)$")
    if summoned and not cache[summoned] then cache[summoned] = tex end
end

local function ScanSpellbook()
    local i = 1
    while i < 600 do
        local ok, spellName = pcall(GetSpellName, i, BOOK)
        if not ok or not spellName then break end
        local tex = SafeSpellTexture(i, BOOK)
        if tex then Cache(spellbookCache, spellName, tex) end
        i = i + 1
    end
    if BOOKTYPE_PET then
        i = 1
        while i < 200 do
            local ok, spellName = pcall(GetSpellName, i, BOOKTYPE_PET)
            if not ok or not spellName then break end
            local ok2, tex = pcall(GetSpellTexture, i, BOOKTYPE_PET)
            if ok2 and type(tex) == "string" and tex ~= "" then Cache(spellbookCache, spellName, tex) end
            i = i + 1
        end
    end
    if GetNumSpellTabs then
        local tabs = GetNumSpellTabs() or 0
        for t = 1, tabs do
            local ok, _, _, offset, num = pcall(GetSpellTabInfo, t)
            if ok and offset and num then
                for slot = offset + 1, offset + num do
                    local okn, spellName = pcall(GetSpellName, slot, BOOK)
                    if okn and spellName then
                        local tex = SafeSpellTexture(slot, BOOK)
                        if tex then Cache(spellbookCache, spellName, tex) end
                    end
                end
            end
        end
    end
end

local function ScanActionBars()
    for slot = 1, 120 do
        local ok, tex = pcall(GetActionTexture, slot)
        if ok and type(tex) == "string" and tex ~= "" then
            local ok2, name = pcall(GetActionText, slot)
            if ok2 and name then Cache(actionCache, name, tex) end
        end
    end
end

-- Full texture path from whatever the game gives us ("Spell_Fire_X" or a full path).
local function IconPath(t)
    if type(t) ~= "string" or t == "" then return nil end
    if string.find(t, "\\", 1, true) or string.find(t, "/", 1, true) then return t end
    return "Interface\\Icons\\" .. t
end

-- Spell ID -> icon. Only uses APIs that take a spell ID. (GetSpellTexture in 1.12
-- takes a *spellbook slot*, so passing an ID to it returns some unrelated icon.)
local function IconFromSpellId(id)
    id = tonumber(id)
    if not id or id <= 0 then return nil end
    if type(SpellInfo) == "function" then -- SuperWoW
        local ok, n, _, tex = pcall(SpellInfo, id)
        if ok and type(tex) == "string" and tex ~= "" then return IconPath(tex), n end
    end
    if type(GetSpellInfo) == "function" then
        local ok, n, _, tex = pcall(GetSpellInfo, id)
        if ok and type(tex) == "string" and tex ~= "" then return IconPath(tex), n end
    end
    return nil
end

local function EntryIcon(e)
    if type(e) ~= "table" then return nil end
    local t = IconPath(e.icon) or IconPath(e.tex) or IconPath(e.texture) or IconPath(e.ic)
    if t then return t end
    return (IconFromSpellId(e.spell or e.spellId or e.id))
end

-- Icons supplied by the game itself (AZS_SPELLS / meter lines) — most trustworthy source.
local function LearnName(name, tex)
    if not name then return end
    name = tostring(name)
    local n = Norm(name)
    if azsCache[n] ~= tex then
        Cache(azsCache, name, tex)
        resolvedIcons = {} -- a new game icon can also fix partial matches
    end
end

local function LearnEntry(e, name)
    local tex = EntryIcon(e)
    if not tex then return end
    local _, idName = IconFromSpellId(e.spell or e.spellId or e.id)
    LearnName(name, tex)
    LearnName(e.name, tex)
    LearnName(e.key, tex)
    LearnName(idName, tex)
end

local function ScanAZSSpells()
    if type(AZS_SPELLS) == "table" then
        for i = 1, table.getn(AZS_SPELLS) do LearnEntry(AZS_SPELLS[i]) end
    end
    if AZS_GetMeter then
        local ok, ml = pcall(AZS_GetMeter)
        if ok and type(ml) == "table" then
            for i = 1, table.getn(ml) do
                if type(ml[i]) == "table" then LearnEntry(ml[i], ml[i].name) end
            end
        end
    end
end

local function ScanTalents()
    if not GetTalentInfo then return end
    local tabs = 0
    if GetNumTalentTabs then
        local ok, n = pcall(GetNumTalentTabs)
        if ok then tabs = n or 0 end
    end
    for tab = 1, tabs do
        local count = 40
        if GetNumTalents then
            local ok, n = pcall(GetNumTalents, tab)
            if ok and n then count = n end
        end
        for talent = 1, count do
            local ok, name, icon = pcall(GetTalentInfo, tab, talent)
            if ok and name and type(icon) == "string" and icon ~= "" then
                Cache(talentCache, name, IconPath(icon))
            end
        end
    end
end

-- Walk every AZS_* table the game exposes (talents, summons, items, spells ...)
-- and learn any entry that has both a name and an icon / spell ID.
local AZS_NAME_FIELDS = { "name", "key", "title", "label", "n", "spellName", "summon", "unit" }
local function LearnTable(t, depth, seen, budget)
    if depth > 3 or seen[t] or budget[1] <= 0 then return end
    seen[t] = true
    local tex = EntryIcon(t)
    if tex then
        for i = 1, table.getn(AZS_NAME_FIELDS) do
            local nm = t[AZS_NAME_FIELDS[i]]
            if type(nm) == "string" and nm ~= "" then Cache(gameScanCache, nm, tex) end
        end
    end
    for k, v in pairs(t) do
        budget[1] = budget[1] - 1
        if budget[1] <= 0 then return end
        if type(v) == "table" then
            -- keyed tables: { ["Fire Ring"] = { icon = ... } }
            if type(k) == "string" then
                local vt = EntryIcon(v)
                if vt then Cache(gameScanCache, k, vt) end
            end
            LearnTable(v, depth + 1, seen, budget)
        elseif type(k) == "string" and type(v) == "string" and depth >= 1
                and string.find(v, "^Interface[\\/][Ii]cons[\\/]") then
            -- name -> icon path maps
            Cache(gameScanCache, k, v)
        end
    end
end

local function ScanGameTables()
    if not builtinCache then
        builtinCache = {}
        if type(AZST_BUILTIN_ICONS) == "table" then
            for k, v in pairs(AZST_BUILTIN_ICONS) do
                builtinCache[Norm(k)] = IconPath(v)
            end
        end
    end
    gameScanCache = {}
    local seen, budget = {}, { 40000 }
    for k, v in pairs(getfenv(0)) do
        if type(k) == "string" and type(v) == "table" and string.sub(k, 1, 4) == "AZS_" then
            LearnTable(v, 0, seen, budget)
        end
    end
end

local function WarmIcons()
    resolvedIcons = {}
    resolvedSrc = {}
    ScanSpellbook()
    ScanGameTables()
    ScanActionBars()
    ScanAZSSpells()
    ScanTalents()
end

local function IsWordChar(c)
    return c ~= nil and c ~= "" and string.find(c, "%w") ~= nil
end

-- needle found in hay starting at a word boundary (and ending at one if needEnd)
local function FindWord(hay, needle, needEnd)
    local init = 1
    while true do
        local a, b = string.find(hay, needle, init, true)
        if not a then return false end
        local before = (a > 1) and string.sub(hay, a - 1, a - 1) or ""
        local after = string.sub(hay, b + 1, b + 1)
        if not IsWordChar(before) and (not needEnd or not IsWordChar(after)) then return true end
        init = a + 1
    end
end

local function FindIcon(cache, name, allowPartial)
    local n = Norm(name)
    if cache[n] then return cache[n] end
    if not allowPartial then return nil end
    -- whole-word match only; the longest matching name wins (deterministic)
    local best, bestKey = nil, nil
    for k, tex in pairs(cache) do
        if type(k) == "string" and type(tex) == "string" and k == Norm(k) and string.len(k) >= 3 then
            if FindWord(n, k, true) or FindWord(k, n, true) then
                if not bestKey or string.len(k) > string.len(bestKey)
                        or (string.len(k) == string.len(bestKey) and k < bestKey) then
                    best, bestKey = tex, k
                end
            end
        end
    end
    return best
end

local function KeywordIcon(name)
    local n = Norm(name)
    for i = 1, table.getn(KEYWORDS) do
        -- short words must match whole words ("cat" must not hit "catastrophe")
        local kw = KEYWORDS[i][1]
        if FindWord(n, kw, string.len(kw) <= 5) then
            return "Interface\\Icons\\" .. KEYWORDS[i][2]
        end
    end
    return nil
end

-- Alternative names to try: "Imp's Firebolt" -> "Firebolt", "Imp";
-- "Summoned Treant" / "Summon Treant" -> "Treant"; "X (Talent)" -> "X".
local function Candidates(name)
    local list = { name }
    local n = Norm(name)
    local _, _, owner, skill = string.find(n, "^(.-)'s (.+)$")
    if skill then table.insert(list, skill); table.insert(list, owner) end
    local _, _, rest = string.find(n, "^summon[ed]* (.+)$")
    if rest then table.insert(list, rest) end
    local stripped = string.gsub(n, "%s*%b()", "")
    if stripped ~= n and stripped ~= "" then table.insert(list, stripped) end
    return list
end

local ICON_SOURCES = {
    { "game", false }, { "scan", false }, { "meter", false }, { "builtin", false },
    { "spellbook", false }, { "talent", false }, { "action", false },
    { "game", true }, { "scan", true }, { "builtin", true }, { "spellbook", true }, { "talent", true },
}

local function SourceCache(key)
    if key == "game" then return azsCache
    elseif key == "scan" then return gameScanCache
    elseif key == "meter" then return meterIconCache
    elseif key == "builtin" then return builtinCache or {}
    elseif key == "spellbook" then return spellbookCache
    elseif key == "talent" then return talentCache
    end
    return actionCache
end

local function ResolveIcon(name)
    local cands = Candidates(name)
    for s = 1, table.getn(ICON_SOURCES) do
        local src, partial = ICON_SOURCES[s][1], ICON_SOURCES[s][2]
        local cache = SourceCache(src)
        for c = 1, table.getn(cands) do
            local tex = FindIcon(cache, cands[c], partial)
            if tex then return tex, src .. (partial and " (partial)" or "") end
        end
    end
    for c = 1, table.getn(cands) do
        local tex = KeywordIcon(cands[c])
        if tex then return tex, "keyword" end
    end
    return nil, "none"
end

local function SkillIcon(name)
    if not name then return QUESTION_ICON end
    local n = Norm(name)
    -- Do not turn unresolved/question-mark entries into a misleading icon.
    if n == "" or string.find(n, "?", 1, true) then
        return QUESTION_ICON
    end
    local tex = resolvedIcons[n]
    if tex then return tex end
    local src
    tex, src = ResolveIcon(name)
    tex = tex or QUESTION_ICON
    resolvedIcons[n] = tex
    resolvedSrc[n] = src
    return tex
end

-- /azst icons: show where each meter skill's icon came from
local function DebugIcons()
    WarmIcons()
    local out = DEFAULT_CHAT_FRAME
    out:AddMessage("|cff62a032AZS Tracker|r icon sources:")
    local ml = AZS_GetMeter and AZS_GetMeter()
    local names = {}
    if type(ml) == "table" then
        for i = 1, table.getn(ml) do if ml[i] and ml[i].name then table.insert(names, ml[i].name) end end
    end
    for k in pairs(maxHits) do table.insert(names, k) end
    for i = 1, table.getn(names) do
        local nm = names[i]
        local tex = SkillIcon(nm)
        local short = string.gsub(tex or "", "^.*[\\/]", "")
        out:AddMessage("  " .. nm .. " -> " .. short .. " [" .. (resolvedSrc[Norm(nm)] or "?") .. "]")
    end
end

local function NoteHit(skill, amount)
	if not skill or not amount or amount <= 0 then return end
	skill = string.gsub(skill, "^%s+", "")
	skill = string.gsub(skill, "%s+$", "")
	if string.len(skill) < 2 or string.len(skill) > 56 then return end
	local cur = maxHits[skill]
	if not cur or amount > cur then maxHits[skill] = amount end
end

local Summons -- defined below (summon / talent-proc helpers)

-- Direct hits + DoT ticks. Skill name only (never the mob).
-- Tracks the biggest single hit/tick per skill.
local function OnCombatText()
	local msg = arg1
	if not msg then return end
	local sk, am
	local _
	-- Direct: Your Skill critically hits/crits/hits Target for N
	_, _, sk, am = string.find(msg, "[Yy]our (.+) critically hits .+ for (%d+)")
	if not sk then _, _, sk, am = string.find(msg, "[Yy]our (.+) crits .+ for (%d+)") end
	if not sk then _, _, sk, am = string.find(msg, "[Yy]our (.+) hits .+ for (%d+)") end
	-- DoT / periodic (English 1.12 forms)
	-- "X suffers N School damage from your Skill."
	if not sk then _, _, am, sk = string.find(msg, "suffers (%d+) .- damage from your (.+)%.") end
	if not sk then _, _, am, sk = string.find(msg, "suffers (%d+) .- damage from your (.+)$") end
	-- "Your Skill deals N School damage to X."
	if not sk then _, _, sk, am = string.find(msg, "[Yy]our (.+) deals (%d+) .- damage to ") end
	-- "Your Skill damages X for N."
	if not sk then _, _, sk, am = string.find(msg, "[Yy]our (.+) damages .+ for (%d+)") end
	-- "X is afflicted by Skill" has no damage — ignore
	-- Melee
	if not sk then
		_, _, am = string.find(msg, "[Yy]ou critically hit .+ for (%d+)")
		if am then sk = "Melee" end
	end
	if not sk then
		_, _, am = string.find(msg, "[Yy]ou hit .+ for (%d+)")
		if am then sk = "Melee" end
	end
	if not sk then
		_, _, am = string.find(msg, "[Yy]ou crit .+ for (%d+)")
		if am then sk = "Melee" end
	end
	if sk and am then
		sk = string.gsub(sk, "%s+hits$", "")
		sk = string.gsub(sk, "%s+crits$", "")
		sk = string.gsub(sk, "%.$", "")
		NoteHit(sk, tonumber(am))
		return
	end
	-- summons, pets, totems and "<YourName>'s Talent" procs
	local petEvent = (event == "CHAT_MSG_COMBAT_PET_HITS" or event == "CHAT_MSG_SPELL_PET_DAMAGE")
	local me = UnitName("player")
	local src
	_, _, src, sk, am = string.find(msg, "^(.-)'s (.-) crits .- for (%d+)")
	if not src then _, _, src, sk, am = string.find(msg, "^(.-)'s (.-) hits .- for (%d+)") end
	if not src then _, _, am, src, sk = string.find(msg, "suffers (%d+) .-damage from (.-)'s (.-)%.") end
	if src and sk and am then
		if me and src == me then
			NoteHit(sk, tonumber(am))
		elseif Summons.IsMine(src, petEvent) then
			NoteHit(sk .. " (" .. src .. ")", tonumber(am))
		end
		return
	end
	_, _, src, am = string.find(msg, "^(.-) crits .- for (%d+)")
	if not src then _, _, src, am = string.find(msg, "^(.-) hits .- for (%d+)") end
	if src and am and src ~= "You" and Summons.IsMine(src, petEvent) then
		NoteHit(src, tonumber(am))
	end
end

-- ---- summons / pets / totems / talent procs for the Highest Damage panel
Summons = { estimated = {} }
do
	local KNOWN = {
		["imp"] = 1, ["voidwalker"] = 1, ["succubus"] = 1, ["felhunter"] = 1, ["infernal"] = 1,
		["doomguard"] = 1, ["water elemental"] = 1, ["fire elemental"] = 1, ["earth elemental"] = 1,
		["treant"] = 1, ["spirit wolf"] = 1, ["feral spirit"] = 1, ["shadowfiend"] = 1, ["lightwell"] = 1,
		["skeleton"] = 1, ["ghoul"] = 1, ["mirror image"] = 1, ["army of the dead"] = 1,
		["felguard"] = 1, ["spectral hound"] = 1,
	}
	-- Is this combat-log source one of the player's own summons?
	function Summons.IsMine(src, fromPetEvent)
		if not src or src == "" then return false end
		if fromPetEvent then return true end -- pet/guardian channel: always ours
		if src == UnitName("pet") then return true end
		for i = 1, 4 do
			if src == UnitName("partypet" .. i) then return false end
		end
		local n = string.lower(src)
		if KNOWN[n] then return true end
		if string.find(n, " totem$") or string.find(n, "^totem ") then return true end
		-- names the game's own meter lists (summons the game tracks for us)
		if AZS_GetMeter then
			local ok, ml = pcall(AZS_GetMeter)
			if ok and type(ml) == "table" then
				for i = 1, table.getn(ml) do
					if ml[i] and ml[i].name and string.lower(ml[i].name) == n then return true end
				end
			end
		end
		return false
	end

	-- Fallback for talent/proc skills that never show up in the combat log:
	-- use a max-hit field from the game's meter, or the biggest damage added
	-- in one 0.1 s window (divided by hits added, when the game counts hits).
	local last = {}
	local MAX_FIELDS = { "max", "maxHit", "maxhit", "big", "biggest", "top", "high", "best", "hi", "crit" }
	local HIT_FIELDS = { "hits", "n", "cnt", "count", "num" }
	local acc = 0
	function Summons.Sample(dt)
		acc = acc + (dt or 0)
		if acc < 0.1 then return end
		acc = 0
		if not AZS_GetMeter then return end
		local ok, ml = pcall(AZS_GetMeter)
		if not ok or type(ml) ~= "table" then return end
		for i = 1, table.getn(ml) do
			local e = ml[i]
			if type(e) == "table" and e.name then
				local name = e.name
				local direct
				for f = 1, table.getn(MAX_FIELDS) do
					local v = tonumber(e[MAX_FIELDS[f]])
					if v and v > 0 then direct = v; break end
				end
				if direct then
					if not Summons.estimated[name] or direct > Summons.estimated[name].v then
						Summons.estimated[name] = { v = direct, exact = true }
					end
				else
					local dmg = tonumber(e.dmg) or 0
					local hits
					for f = 1, table.getn(HIT_FIELDS) do
						hits = tonumber(e[HIT_FIELDS[f]]); if hits then break end
					end
					local prev = last[name]
					if prev and dmg > prev.d then
						local per = dmg - prev.d
						if hits and prev.h and hits > prev.h then per = per / (hits - prev.h) end
						local cur = Summons.estimated[name]
						if not cur or (not cur.exact and per > cur.v) then
							Summons.estimated[name] = { v = per, exact = false }
						end
					end
					last[name] = { d = dmg, h = hits }
				end
			end
		end
	end

	function Summons.Reset()
		Summons.estimated = {}
		last = {}
	end
end

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
combatFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
combatFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE")
combatFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
combatFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE")
combatFrame:RegisterEvent("CHAT_MSG_COMBAT_PET_HITS")
combatFrame:RegisterEvent("CHAT_MSG_SPELL_PET_DAMAGE")
combatFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS")
combatFrame:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE")
combatFrame:SetScript("OnEvent", OnCombatText)

local function RefreshMeter()
	if not db or not db.meterShown then meterPanel:Hide(); return end

	meterPanel:Show()
	local now = GetTime()
	if not meterPanel._warmAt or now - meterPanel._warmAt > 5 then
		WarmIcons()
		meterPanel._warmAt = now
	else
		ScanAZSSpells()
	end

	-- Prefer biggest hits keyed by skill name only (never by mob).
	-- Seed rows from the player's meter/spell list so selected skills appear.
	local lines = {}
	local seen = {}
	if AZS_GetMeter then
		local ml = AZS_GetMeter()
		if type(ml) == "table" then
			for i = 1, table.getn(ml) do
				local name = ml[i].name
				if name and not seen[name] then
					seen[name] = true
					local mx, est = maxHits[name] or 0, nil
					local se = Summons.estimated[name]
					if mx <= 0 and se and se.v > 0 then
						-- talent/proc skills the combat log doesn't report
						mx = se.v
						if not se.exact then est = true end
					end
					table.insert(lines, { name = name, max = mx, proc = ml[i].proc, est = est })
				end
			end
		end
	end
	for name, mh in pairs(maxHits) do
		if not seen[name] and mh and mh > 0 then
			seen[name] = true
			table.insert(lines, { name = name, max = mh })
		end
	end
	-- only show skills that have a recorded biggest hit
	local shown = {}
	for i = 1, table.getn(lines) do
		if lines[i].max and lines[i].max > 0 then
			table.insert(shown, lines[i])
		end
	end
	for i = 1, table.getn(shown) do
		for j = i + 1, table.getn(shown) do
			if shown[j].max > shown[i].max then shown[i], shown[j] = shown[j], shown[i] end
		end
	end
	local top = (shown[1] and shown[1].max) or 0
	if top <= 0 then top = 1 end
	meterPanel.sub:SetText(table.getn(shown) > 0 and ("top " .. FormatNum(top)) or "")
	local barW = meterPanel.barW
	for i = 1, METER_MAX do
		local row = meterPanel.rows[i]
		local e = (i <= meterPanel.nrows) and shown[i] or nil
		if e then
			row:Show()
			local frac = e.max / top
			if frac < 0.04 then frac = 0.04 end
			row.bar:SetWidth(barW * frac)
			if e.proc and e.proc == 1 then
				row.bar:SetVertexColor(0.3, 0.5, 0.95, 1)
			else
				local t = 0.5 + 0.5 * frac
				row.bar:SetVertexColor(0.9 * t, 0.18, 0.12, 1)
			end
			row.name:SetText(e.name)
			row.val:SetText((e.est and "~" or "") .. FormatNum(e.max))
			row.icon:SetTexture(SkillIcon(e.name))
		else
			row:Hide()
		end
	end
end


-- ---------------------------------------------------------------- DPS meter (cumulative skill damage)
local skillDmgTotals = {}
local DPS_ROWS = 10
local DPS_MAX = 24
local dpsPanel = MakePanel("AZSTrackerDpsFrame", 240, 48 + DPS_ROWS * 16 + 14)
PanelTitle(dpsPanel, "DPS")
dpsPanel.sub = dpsPanel.inner:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
dpsPanel.sub:SetPoint("TOPRIGHT", dpsPanel.inner, "TOPRIGHT", -10, -8)
dpsPanel.rows = {}
for i = 1, DPS_MAX do
	local y = -34 - (i - 1) * 16
	local row = CreateFrame("Frame", nil, dpsPanel.inner)
	row:SetWidth(196); row:SetHeight(14)
	row:SetPoint("TOPLEFT", dpsPanel.inner, "TOPLEFT", 8, y)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints(row); row.bg:SetTexture(FLAT); row.bg:SetVertexColor(0.08, 0.08, 0.1, 0.95)
	row.bar = row:CreateTexture(nil, "ARTWORK")
	row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	row.bar:SetWidth(1); row.bar:SetTexture(FLAT); row.bar:SetVertexColor(0.85, 0.25, 0.12, 1)
	row.icon = row:CreateTexture(nil, "OVERLAY")
	row.icon:SetWidth(12); row.icon:SetHeight(12)
	row.icon:SetPoint("LEFT", row, "LEFT", 1, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 3, 0); row.name:SetTextColor(1, 0.95, 0.85)
	row.val = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.val:SetPoint("RIGHT", row, "RIGHT", -4, 0); row.val:SetTextColor(1, 0.9, 0.5)
	row:Hide(); dpsPanel.rows[i] = row
end
dpsPanel.nrows = DPS_ROWS
dpsPanel.barW = 196
dpsPanel._minW = 130
function dpsPanel:Layout()
	self.barW = math.max(60, self:GetWidth() - 18)
	self.nrows = RowsThatFit(self, 34, 16, 12, DPS_MAX)
	for i = 1, DPS_MAX do
		self.rows[i]:SetWidth(self.barW)
		if i > self.nrows then self.rows[i]:Hide() end
	end
end
dpsPanel:SetScript("OnDragStop", function()
	this:StopMovingOrSizing()
	if not db then return end
	local p, _, rp, x, y = this:GetPoint()
	db.dpsPoint = { p, rp, x, y }
end)

local function RefreshDps()
	if not db or db.dpsShown == false then dpsPanel:Hide(); return end
	dpsPanel:Show()
	local rows, total, dps = {}, 0, 0
	local now = GetTime()
	if not dpsPanel._warmAt or now - dpsPanel._warmAt > 5 then
		WarmIcons()
		dpsPanel._warmAt = now
	else
		ScanAZSSpells()
	end
	if AZS_GetMeter then
		local ml, tot, dp = AZS_GetMeter()
		total = tonumber(tot) or 0; dps = tonumber(dp) or 0
		if type(ml) == "table" then
			for i = 1, table.getn(ml) do
				local e = ml[i]
				if e and e.name then
					local dmg = tonumber(e.dmg) or 0
					local prev = skillDmgTotals[e.name] or 0
					if dmg > prev then skillDmgTotals[e.name] = dmg end
					local shown = skillDmgTotals[e.name] or dmg
					if shown > 0 then table.insert(rows, { name = e.name, dmg = shown }) end
					-- icon straight from the meter line, if the game provides one
					local etex = EntryIcon(e)
					if etex and meterIconCache[Norm(e.name)] ~= etex then
						meterIconCache[Norm(e.name)] = etex
						resolvedIcons[Norm(e.name)] = nil
					end
				end
			end
		end
	end
	for i = 1, table.getn(rows) do
		for j = i + 1, table.getn(rows) do
			if rows[j].dmg > rows[i].dmg then rows[i], rows[j] = rows[j], rows[i] end
		end
	end
	local top = (rows[1] and rows[1].dmg) or 1
	if top < 1 then top = 1 end
	local sub = FormatNum(total)
	if dps > 0 then sub = sub .. "  ·  " .. string.format("%.0f", dps) .. " dps" end
	dpsPanel.sub:SetText(sub)
	local barW = dpsPanel.barW
	for i = 1, DPS_MAX do
		local row = dpsPanel.rows[i]
		local e = (i <= dpsPanel.nrows) and rows[i] or nil
		if e then
			row:Show()
			local frac = e.dmg / top
			if frac < 0.04 then frac = 0.04 end
			row.bar:SetWidth(barW * frac)
			row.name:SetText(e.name)
			row.val:SetText(FormatNum(e.dmg))
			if row.icon then
				row.icon:SetTexture(SkillIcon(e.name))
			end
		else
			row:Hide()
		end
	end
end

-- ---------------------------------------------------------------- Party DPS meter
-- Damage per group member (you + party/raid + pets) from the combat log.
-- Pets are merged into their owner. DPS uses each member's active combat time.
local PartyMeter = {}
do
	local PARTY_MAX = 24
	local PARTY_ROWS = 6
	local GAP = 3.5 -- seconds without damage before a member counts as idle
	local members = {}   -- name -> { total, active, last, unit }
	local roster = {}    -- source name -> owner name ("You"/pet/party names)
	local units = {}     -- owner name -> unit token (for class color)

	local panel = MakePanel("AZSTrackerPartyFrame", 240, 48 + PARTY_ROWS * 16 + 14)
	PanelTitle(panel, "Party DPS")
	panel.sub = panel.inner:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	panel.sub:SetPoint("TOPRIGHT", panel.inner, "TOPRIGHT", -10, -8)
	panel.rows = {}
	for i = 1, PARTY_MAX do
		local row = CreateFrame("Frame", nil, panel.inner)
		row:SetWidth(222); row:SetHeight(14)
		row:SetPoint("TOPLEFT", panel.inner, "TOPLEFT", 8, -34 - (i - 1) * 16)
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints(row); row.bg:SetTexture(FLAT); row.bg:SetVertexColor(0.08, 0.08, 0.1, 0.95)
		row.bar = row:CreateTexture(nil, "ARTWORK")
		row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
		row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
		row.bar:SetWidth(1); row.bar:SetTexture(FLAT)
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.name:SetPoint("LEFT", row, "LEFT", 3, 0); row.name:SetTextColor(1, 1, 1)
		row.val = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.val:SetPoint("RIGHT", row, "RIGHT", -4, 0); row.val:SetTextColor(1, 0.95, 0.8)
		row:Hide(); panel.rows[i] = row
	end
	panel.nrows = PARTY_ROWS
	panel.barW = 222
	panel._minW = 130
	function panel:Layout()
		self.barW = math.max(60, self:GetWidth() - 18)
		self.nrows = RowsThatFit(self, 34, 16, 12, PARTY_MAX)
		for i = 1, PARTY_MAX do
			self.rows[i]:SetWidth(self.barW)
			if i > self.nrows then self.rows[i]:Hide() end
		end
	end
	panel:SetScript("OnDragStop", function()
		this:StopMovingOrSizing()
		if not db then return end
		local p, _, rp, x, y = this:GetPoint()
		db.partyPoint = { p, rp, x, y }
	end)

	-- small "reset" link in the header
	local rb = CreateFrame("Button", nil, panel)
	rb:SetWidth(34); rb:SetHeight(14)
	rb:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -9)
	rb:SetFrameLevel(panel:GetFrameLevel() + 5)
	rb.t = rb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	rb.t:SetPoint("LEFT", rb, "LEFT", 0, 0)
	rb.t:SetText("reset")
	rb:SetScript("OnEnter", function() this.t:SetTextColor(1, 0.82, 0) end)
	rb:SetScript("OnLeave", function() this.t:SetTextColor(0.5, 0.5, 0.5) end)

	local function UpdateRoster()
		roster, units = {}, {}
		local me = UnitName("player")
		if me then roster[me] = me; units[me] = "player" end
		roster["You"] = me or "You"
		local pet = UnitName("pet")
		if pet and pet ~= "Unknown" then roster[pet] = me or "You" end
		local nRaid = (GetNumRaidMembers and GetNumRaidMembers()) or 0
		if nRaid > 0 then
			for i = 1, nRaid do
				local n = UnitName("raid" .. i)
				if n then
					roster[n] = n; units[n] = "raid" .. i
					local pn = UnitName("raidpet" .. i)
					if pn and pn ~= "Unknown" then roster[pn] = n end
				end
			end
		else
			for i = 1, 4 do
				local n = UnitName("party" .. i)
				if n then
					roster[n] = n; units[n] = "party" .. i
					local pn = UnitName("partypet" .. i)
					if pn and pn ~= "Unknown" then roster[pn] = n end
				end
			end
		end
	end

	local function Add(source, amount)
		amount = tonumber(amount)
		if not source or not amount or amount <= 0 then return end
		local owner = roster[source]
		if not owner then return end -- not someone in our group
		local now = GetTime()
		local m = members[owner]
		if not m then
			m = { total = 0, active = 1, last = now }
			members[owner] = m
		else
			local gap = now - m.last
			if gap <= GAP then m.active = m.active + gap else m.active = m.active + 1 end
			m.last = now
		end
		m.total = m.total + amount
	end

	-- 1.12 English combat-log forms
	local function Parse()
		local msg = arg1
		if not msg then return end
		local _, src, am
		-- self
		_, _, am = string.find(msg, "^Your .- crits .- for (%d+)")
		if not am then _, _, am = string.find(msg, "^Your .- hits .- for (%d+)") end
		if not am then _, _, am = string.find(msg, "^You crit .- for (%d+)") end
		if not am then _, _, am = string.find(msg, "^You hit .- for (%d+)") end
		if not am then _, _, am = string.find(msg, "suffers (%d+) .-damage from your ") end
		if not am then _, _, am = string.find(msg, "^You reflect (%d+) ") end
		if am then Add("You", am); return end
		-- "Mob suffers 50 Fire damage from Name's Immolate."
		_, _, am, src = string.find(msg, "suffers (%d+) .-damage from (.-)'s ")
		if src then Add(src, am); return end
		-- "Name's Fireball crits/hits Mob for 300."
		_, _, src, am = string.find(msg, "^(.-)'s .- crits .- for (%d+)")
		if not src then _, _, src, am = string.find(msg, "^(.-)'s .- hits .- for (%d+)") end
		-- "Name crits/hits Mob for 120."
		if not src then _, _, src, am = string.find(msg, "^(.-) crits .- for (%d+)") end
		if not src then _, _, src, am = string.find(msg, "^(.-) hits .- for (%d+)") end
		-- "Name reflects 20 Fire damage to Mob."
		if not src then _, _, src, am = string.find(msg, "^(.-) reflects (%d+) ") end
		if src then Add(src, am) end
	end

	local function Reset()
		members = {}
		panel.sub:SetText("")
	end
	rb:SetScript("OnClick", Reset)

	local ev = CreateFrame("Frame")
	local EVENTS = {
		"CHAT_MSG_COMBAT_SELF_HITS", "CHAT_MSG_SPELL_SELF_DAMAGE",
		"CHAT_MSG_COMBAT_PET_HITS", "CHAT_MSG_SPELL_PET_DAMAGE",
		"CHAT_MSG_COMBAT_PARTY_HITS", "CHAT_MSG_SPELL_PARTY_DAMAGE",
		"CHAT_MSG_COMBAT_FRIENDLYPLAYER_HITS", "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE",
		"CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS", "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
		"CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE", "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE",
		"CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF", "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS",
		"PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "UNIT_PET", "PLAYER_ENTERING_WORLD",
	}
	for i = 1, table.getn(EVENTS) do pcall(ev.RegisterEvent, ev, EVENTS[i]) end
	ev:SetScript("OnEvent", function()
		if event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE"
				or event == "UNIT_PET" or event == "PLAYER_ENTERING_WORLD" then
			UpdateRoster()
			return
		end
		if db and db.partyShown == false then return end
		Parse()
	end)

	local function ClassColor(name)
		local unit = units[name]
		if unit and UnitClass and RAID_CLASS_COLORS then
			local _, cls = UnitClass(unit)
			local c = cls and RAID_CLASS_COLORS[cls]
			if c then return c.r, c.g, c.b end
		end
		return 0.6, 0.6, 0.6
	end

	function PartyMeter.Refresh()
		if not db or db.partyShown == false then panel:Hide(); return end
		panel:Show()
		local list, sumDps = {}, 0
		for name, m in pairs(members) do
			local dps = m.total / math.max(1, m.active)
			table.insert(list, { name = name, total = m.total, dps = dps })
			sumDps = sumDps + dps
		end
		table.sort(list, function(a, b) return a.total > b.total end)
		local top = (list[1] and list[1].total) or 1
		if top < 1 then top = 1 end
		panel.sub:SetText(table.getn(list) > 0 and (string.format("%.0f", sumDps) .. " dps") or "")
		for i = 1, PARTY_MAX do
			local row = panel.rows[i]
			local e = (i <= panel.nrows) and list[i] or nil
			if e then
				row:Show()
				local frac = e.total / top
				if frac < 0.04 then frac = 0.04 end
				row.bar:SetWidth(panel.barW * frac)
				local r, g, b = ClassColor(e.name)
				row.bar:SetVertexColor(r * 0.75, g * 0.75, b * 0.75, 1)
				row.name:SetText(i .. ". " .. e.name)
				row.val:SetText(FormatNum(e.total) .. " (" .. FormatNum(e.dps) .. ")")
			else
				row:Hide()
			end
		end
	end

	PartyMeter.Reset = Reset
	PartyMeter.UpdateRoster = UpdateRoster
	PartyMeter.panel = panel
end

-- ---------------------------------------------------------------- character attributes

local STAT_KEYS = {
	{ key = "hp", label = "Max Health" },
	{ key = "dmg", label = "Damage" },
	{ key = "cd", label = "Cooldown" },
	{ key = "crit", label = "Crit Chance" },
	{ key = "cm", label = "Crit Multiplier" },
	{ key = "arm", label = "Damage Reduction" },
	{ key = "reg", label = "Regen / sec" },
	{ key = "area", label = "Area" },
	{ key = "cnt", label = "Extra Targets" },
	{ key = "echo", label = "Echo" },
	{ key = "spd", label = "Speed" },
	{ key = "pick", label = "Pickup Range" },
	{ key = "xp", label = "XP Gain" },
	{ key = "luck", label = "Luck" },
	{ key = "gold", label = "Gold Find" },
	{ key = "heal", label = "Heal on Kill" },
	{ key = "lch", label = "Leech" },
	{ key = "thn", label = "Thorns" },
	{ key = "liv", label = "Lives" },
}

local statsPanel = MakePanel("AZSTrackerStatsFrame", 220, 43 + table.getn(STAT_KEYS) * 13 + 14)
PanelTitle(statsPanel, "Attributes")
statsPanel.rows = {}
for i = 1, table.getn(STAT_KEYS) do
	local y = -32 - (i - 1) * 13
	local row = {}
	row.label = FS(statsPanel, "GameFontHighlightSmall")
	row.label:SetPoint("TOPLEFT", statsPanel.inner, "TOPLEFT", 10, y)
	row.label:SetText(STAT_KEYS[i].label)
	row.label:SetTextColor(0.75, 0.75, 0.75)
	row.value = FS(statsPanel, "GameFontHighlightSmall", "RIGHT")
	row.value:SetPoint("TOPRIGHT", statsPanel.inner, "TOPRIGHT", -10, y)
	statsPanel.rows[i] = row
end
statsPanel:SetScript("OnDragStop", function()
	this:StopMovingOrSizing()
	if not db then return end
	local p, _, rp, x, y = this:GetPoint()
	db.statsPoint = { p, rp, x, y }
end)

local function FormatStat(key, v)
	if not v then return "—" end
	v = tonumber(v) or 0
	-- ratios shown as percent when they look like multipliers/fractions
	if key == "luck" or key == "crit" or key == "arm" or key == "xp" or key == "gold"
			or key == "cd" or key == "dmg" or key == "cm" or key == "spd" or key == "heal"
			or key == "lch" or key == "echo" or key == "area" then
		if v > 0 and v <= 10 then
			return string.format("%.0f%%", v * 100)
		end
	end
	if v ~= math.floor(v) then return string.format("%.2f", v) end
	return FormatNum(v)
end

local function RefreshStats()
	if not db or not db.statsShown then statsPanel:Hide(); return end

	statsPanel:Show()
	local s = AZS_STATS
	for i = 1, table.getn(STAT_KEYS) do
		local key = STAT_KEYS[i].key
		local v = type(s) == "table" and s[key] or nil
		statsPanel.rows[i].value:SetText(FormatStat(key, v))
		statsPanel.rows[i].value:SetTextColor(1, 0.82, 0)
	end
end

-- ---------------------------------------------------------------- boss timers

local BOSS_ROWS = 8
local BOSS_MAX = 24
local bossPanel = MakePanel("AZSTrackerBossFrame", 258, 43 + 16 + BOSS_ROWS * 15 + 14)
PanelTitle(bossPanel, "Bosses")
-- mission timer line (under the title strip)
bossPanel.timerLabel = FS(bossPanel, "GameFontHighlightSmall")
bossPanel.timerLabel:SetPoint("TOPLEFT", bossPanel.inner, "TOPLEFT", 10, -32)
bossPanel.timerLabel:SetText("Mission time")
bossPanel.timerLabel:SetTextColor(0.75, 0.7, 0.6)
bossPanel.timer = FS(bossPanel, "GameFontNormal", "RIGHT")
bossPanel.timer:SetPoint("TOPRIGHT", bossPanel.inner, "TOPRIGHT", -10, -31)
bossPanel.timer:SetTextColor(1, 1, 1)
bossPanel.timer:SetText("--:--")
bossPanel.sep = bossPanel:CreateTexture(nil, "ARTWORK")
bossPanel.sep:SetTexture(FLAT)
bossPanel.sep:SetVertexColor(0.67, 0.57, 0.36, 0.45)
bossPanel.sep:SetHeight(1)
bossPanel.sep:SetPoint("TOPLEFT", bossPanel.inner, "TOPLEFT", 10, -46)
bossPanel.sep:SetPoint("TOPRIGHT", bossPanel.inner, "TOPRIGHT", -10, -46)
bossPanel.rows = {}
for i = 1, BOSS_MAX do
	local y = -51 - (i - 1) * 15
	local row = {}
	row.name = FS(bossPanel, "GameFontHighlightSmall")
	row.name:SetPoint("TOPLEFT", bossPanel.inner, "TOPLEFT", 10, y)
	row.name:SetWidth(142)
	row.info = FS(bossPanel, "GameFontHighlightSmall", "RIGHT")
	row.info:SetPoint("TOPRIGHT", bossPanel.inner, "TOPRIGHT", -10, y)
	row.info:SetWidth(82)
	bossPanel.rows[i] = row
end
bossPanel.nrows = BOSS_ROWS
bossPanel._minW = 150
function bossPanel:Layout()
	local w = self:GetWidth()
	local infoW = math.min(110, math.max(60, w * 0.32))
	self.nrows = RowsThatFit(self, 51, 15, 12, BOSS_MAX)
	for i = 1, BOSS_MAX do
		self.rows[i].info:SetWidth(infoW)
		self.rows[i].name:SetWidth(math.max(40, w - 26 - infoW))
	end
end
bossPanel:SetScript("OnDragStop", function()
	this:StopMovingOrSizing()
	if not db then return end
	local p, _, rp, x, y = this:GetPoint()
	db.bossPoint = { p, rp, x, y }
end)

-- Mission (run) elapsed time. Uses the game's run clock; falls back to a local
-- clock started when the run begins if the game does not expose one.
local missionLocalStart = nil
local function MissionTime()
	local t = AZS_GetRunTime and tonumber(AZS_GetRunTime())
	if not t and type(AZS_RUN) == "table" then t = tonumber(AZS_RUN.t) end
	if t then
		missionLocalStart = nil
		return t
	end
	if InRun() then
		if not missionLocalStart then missionLocalStart = GetTime() end
		return GetTime() - missionLocalStart
	end
	missionLocalStart = nil
	return nil
end

local function FormatClock(sec)
	sec = math.max(0, math.floor(sec))
	local h = math.floor(sec / 3600)
	if h > 0 then
		return string.format("%d:%02d:%02d", h, math.floor(math.mod(sec, 3600) / 60), math.mod(sec, 60))
	end
	return string.format("%d:%02d", math.floor(sec / 60), math.mod(sec, 60))
end

local function RefreshBosses()
	if not db or not db.bossShown then bossPanel:Hide(); return end

	bossPanel:Show()

	local mt = InRun() and MissionTime() or nil
	bossPanel.timer:SetText(mt and FormatClock(mt) or "--:--")

	local entries = {}
	-- alive bosses first
	if AZS_GetBosses then
		local bosses = AZS_GetBosses() or {}
		for i = 1, table.getn(bosses) do
			local b = bosses[i]
			local pct = (b.hpm and b.hpm > 0) and (100 * b.hp / b.hpm) or 0
			local tag = b.final and "FINAL" or "UP"
			if b.enraged then tag = tag .. " ENRAGE" end
			table.insert(entries, {
				name = b.name or "Boss",
				info = string.format("%s %.0f%%", tag, pct),
				r = b.enraged and 1 or 1, g = b.enraged and 0.3 or 0.2, b = b.enraged and 0.3 or 0.2,
				order = 0,
			})
		end
	end
	-- upcoming with countdown
	if AZS_GetUpcomingBosses then
		local up = AZS_GetUpcomingBosses() or {}
		for i = 1, table.getn(up) do
			local u = up[i]
			local left = u.left or 0
			table.insert(entries, {
				name = u.name or "Boss",
				info = FormatTime(left),
				r = 1, g = 0.82, b = 0,
				order = 1 + (u.index or i),
			})
		end
	elseif type(AZS_SCHEDULE) == "table" then
		local now = (AZS_GetRunTime and AZS_GetRunTime()) or (AZS_RUN and AZS_RUN.t) or 0
		for i = 1, table.getn(AZS_SCHEDULE) do
			local s = AZS_SCHEDULE[i]
			if s.state == "due" then
				table.insert(entries, {
					name = s.name or "Boss",
					info = FormatTime(math.max(0, (s.at or 0) - now)),
					r = 1, g = 0.82, b = 0,
					order = 1 + (s.index or i),
				})
			end
		end
	end

	for i = 1, BOSS_MAX do
		local row = bossPanel.rows[i]
		local e = (i <= bossPanel.nrows) and entries[i] or nil
		if e then
			row.name:SetText(e.name)
			row.name:SetTextColor(e.r, e.g, e.b)
			row.info:SetText(e.info)
			row.info:SetTextColor(e.r, e.g, e.b)
		else
			row.name:SetText("")
			row.info:SetText("")
		end
	end
end


-- ---------------------------------------------------------------- HUD helpers for replaced game parts
local function SetHudPart(part, shown)
	if AZS_SetHudShown then
		AZS_SetHudShown(part, shown)
	elseif SetCVar then
		local map = {
			meter = "hudMeter", bosses = "hudBosses", tally = "hudTally",
			build = "hudBuild", clock = "hudClock",
		}
		local cv = map[part]
		if cv then SetCVar(cv, shown and "1" or "0") end
	end
end

local function ApplyHudReplacements()
	SetHudPart("meter", false)
	if not db or db.tallyShown ~= false then SetHudPart("tally", false) else SetHudPart("tally", true) end
	if not db or db.bossHpShown ~= false then SetHudPart("bosses", false) else SetHudPart("bosses", true) end
	if not db or db.chatShown ~= false then
		for i = 1, 10 do
			local cf = getglobal("ChatFrame" .. i)
			if cf then
				cf:Hide()
				cf:SetScript("OnShow", function() this:Hide() end)
			end
			local ct = getglobal("ChatFrame" .. i .. "Tab")
			if ct then ct:Hide() end
		end
	else
		for i = 1, 7 do
			local cf = getglobal("ChatFrame" .. i)
			if cf then
				cf:SetScript("OnShow", nil)
				cf:Show()
			end
			local ct = getglobal("ChatFrame" .. i .. "Tab")
			if ct then ct:Show() end
		end
	end
end

-- ---------------------------------------------------------------- Enemy HP (bosses / elites) — dark red small bars
local BOSSHP_ROWS = 10
local BOSSHP_MAX = 24
local bossHpPanel = MakePanel("AZSTrackerBossHpFrame", 200, 36 + BOSSHP_ROWS * 13 + 8)
PanelTitle(bossHpPanel, "Enemy HP")
bossHpPanel.rows = {}
for i = 1, BOSSHP_MAX do
	local y = -28 - (i - 1) * 13
	local row = CreateFrame("Frame", nil, bossHpPanel.inner)
	row:SetWidth(176); row:SetHeight(11)
	row:SetPoint("TOPLEFT", bossHpPanel.inner, "TOPLEFT", 10, y)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints(row); row.bg:SetTexture(FLAT); row.bg:SetVertexColor(0.05, 0.02, 0.02, 0.95)
	row.bar = row:CreateTexture(nil, "ARTWORK")
	row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	row.bar:SetWidth(1); row.bar:SetTexture(FLAT); row.bar:SetVertexColor(0.42, 0.05, 0.05, 1)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", row, "LEFT", 2, 0); row.name:SetTextColor(0.85, 0.7, 0.65)
	row.pct = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.pct:SetPoint("RIGHT", row, "RIGHT", -2, 0); row.pct:SetTextColor(0.75, 0.5, 0.45)
	row:Hide(); bossHpPanel.rows[i] = row
end
bossHpPanel.nrows = BOSSHP_ROWS
bossHpPanel._minW = 110
function bossHpPanel:Layout()
	self.nrows = RowsThatFit(self, 28, 13, 8, BOSSHP_MAX)
	for i = 1, BOSSHP_MAX do
		self.rows[i]:SetWidth(math.max(40, self:GetWidth() - 24))
		if i > self.nrows then self.rows[i]:Hide() end
	end
end
bossHpPanel:SetScript("OnDragStop", function()
	this:StopMovingOrSizing()
	if not db then return end
	local p, _, rp, x, y = this:GetPoint()
	db.bossHpPoint = { p, rp, x, y }
end)

local function RefreshBossHp()
	if not db or db.bossHpShown == false then bossHpPanel:Hide(); return end
	bossHpPanel:Show()
	local list = {}
	if AZS_GetBosses then
		local bosses = AZS_GetBosses() or {}
		for i = 1, table.getn(bosses) do
			local b = bosses[i]
			table.insert(list, { name = b.name or "Boss", hp = b.hp or 0, hpm = b.hpm or 1, enraged = b.enraged })
		end
	end
	if AZS_GetGuardians then
		local g = AZS_GetGuardians() or {}
		for i = 1, table.getn(g) do
			local u = g[i]
			table.insert(list, { name = u.name or "Guardian", hp = u.hp or 0, hpm = u.hpm or 1, enraged = u.state == 1 })
		end
	end
	local barW = (bossHpPanel:GetWidth() or 200) - 24
	if barW < 40 then barW = 40 end
	for i = 1, BOSSHP_MAX do
		local row = bossHpPanel.rows[i]
		local e = (i <= bossHpPanel.nrows) and list[i] or nil
		if e then
			row:Show()
			local frac = (e.hpm and e.hpm > 0) and (e.hp / e.hpm) or 0
			if frac < 0 then frac = 0 end
			if frac > 1 then frac = 1 end
			row.bar:SetWidth(math.max(2, barW * frac))
			if e.enraged then
				row.bar:SetVertexColor(0.6, 0.08, 0.08, 1)
			else
				row.bar:SetVertexColor(0.42, 0.05, 0.05, 1)
			end
			row.name:SetText(e.name)
			row.pct:SetText(string.format("%.0f%%", frac * 100))
		else
			row:Hide()
		end
	end
end

-- ---------------------------------------------------------------- Tally (gold, chest cost, kills)
local tallyPanel = MakePanel("AZSTrackerTallyFrame", 112, 34)
if tallyPanel.titleFS then tallyPanel.titleFS:SetText("") end
if tallyPanel.strip then tallyPanel.strip:Hide() end
tallyPanel.icons = {}
local TALLY = {
	{ key = "gold", tex = "Interface\\AddOns\\AZSTracker\\Textures\\Gold" },
	{ key = "chest", tex = "Interface\\AddOns\\AZSTracker\\Textures\\Chest" },
	{ key = "kills", tex = "Interface\\AddOns\\AZSTracker\\Textures\\Skull" },
}
for i = 1, 3 do
	local x = 6 + (i - 1) * 34
	local slot = CreateFrame("Frame", nil, tallyPanel.inner)
	slot:SetWidth(32); slot:SetHeight(26)
	slot:SetPoint("TOPLEFT", tallyPanel.inner, "TOPLEFT", x, -4)
	slot.icon = slot:CreateTexture(nil, "ARTWORK")
	slot.icon:SetWidth(11); slot.icon:SetHeight(11)
	slot.icon:SetPoint("TOP", slot, "TOP", 0, 0)
	slot.icon:SetTexture(TALLY[i].tex)
	slot.val = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	slot.val:SetPoint("TOP", slot.icon, "BOTTOM", 0, 0)
	slot.val:SetTextColor(1, 0.9, 0.5)
	slot.val:SetText("0")
	tallyPanel.icons[i] = slot
end
tallyPanel._minW, tallyPanel._minH = 90, 30
function tallyPanel:Layout()
	local w, h = self:GetWidth(), self:GetHeight()
	local sw = (w - 12) / 3
	for i = 1, 3 do
		local slot = self.icons[i]
		slot:ClearAllPoints()
		slot:SetWidth(sw)
		slot:SetPoint("TOPLEFT", self.inner, "TOPLEFT", 6 + (i - 1) * sw, -math.max(2, (h - 26) / 2))
	end
end
tallyPanel:SetScript("OnDragStop", function()
	this:StopMovingOrSizing()
	if not db then return end
	local p, _, rp, x, y = this:GetPoint()
	db.tallyPoint = { p, rp, x, y }
end)

local function RefreshTally()
	if not db or db.tallyShown == false then tallyPanel:Hide(); return end
	tallyPanel:Show()
	local r = AZS_RUN or {}
	tallyPanel.icons[1].val:SetText(FormatNum(tonumber(r.gold) or 0))
	tallyPanel.icons[2].val:SetText(FormatNum(tonumber(r.chest) or 0))
	tallyPanel.icons[3].val:SetText(FormatNum(tonumber(r.kills) or 0))
end

-- ---------------------------------------------------------------- Gear panel
local EQ_SLOTS = {
	{1,"Head"},{2,"Neck"},{3,"Shoulder"},{15,"Back"},{5,"Chest"},{9,"Wrist"},
	{10,"Hands"},{6,"Waist"},{7,"Legs"},{8,"Feet"},{11,"Ring"},{12,"Ring"},
	{13,"Trinket"},{14,"Trinket"},{16,"Main"},{17,"Off"},{18,"Ranged"},
}
local equipPanel = MakePanel("AZSTrackerEquipFrame", 196, 118)
PanelTitle(equipPanel, "Gear")
equipPanel.slots = {}
for i = 1, table.getn(EQ_SLOTS) do
	local col = math.mod(i - 1, 6)
	local rw = math.floor((i - 1) / 6)
	local btn = CreateFrame("Button", nil, equipPanel.inner)
	btn:SetWidth(28); btn:SetHeight(28)
	btn:SetPoint("TOPLEFT", equipPanel.inner, "TOPLEFT", 10 + col * 30, -28 - rw * 30)
	btn.bg = btn:CreateTexture(nil, "BACKGROUND")
	btn.bg:SetAllPoints(btn); btn.bg:SetTexture(FLAT); btn.bg:SetVertexColor(0.1, 0.1, 0.12, 0.9)
	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetWidth(24); btn.icon:SetHeight(24); btn.icon:SetPoint("CENTER", btn, "CENTER")
	btn.slotId = EQ_SLOTS[i][1]
	btn.slotName = EQ_SLOTS[i][2]
	btn:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		local ok = pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", this.slotId)
		if not ok then GameTooltip:SetText(this.slotName) end
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	equipPanel.slots[i] = btn
end
equipPanel._minW, equipPanel._minH = 90, 70
-- Fit all slots inside the panel: try every column count and keep the one that
-- gives the biggest square cells, then size the icons to those cells.
function equipPanel:Layout()
	local n = table.getn(self.slots)
	local availW = self:GetWidth() - 16
	local availH = self:GetHeight() - 28 - 8
	local bestCols, bestCell = 1, 0
	for cols = 1, n do
		local rows = math.ceil(n / cols)
		local cell = math.min(availW / cols, availH / rows)
		if cell > bestCell then bestCols, bestCell = cols, cell end
	end
	local cell = math.max(4, math.floor(bestCell))
	local size = math.max(6, cell - 2)
	local cols = bestCols
	local usedW = cols * cell
	local x0 = 8 + math.floor((availW - usedW) / 2)
	for i = 1, n do
		local col = math.mod(i - 1, cols)
		local rw = math.floor((i - 1) / cols)
		local btn = self.slots[i]
		btn:SetWidth(size); btn:SetHeight(size)
		btn.icon:SetWidth(math.max(4, size - 4)); btn.icon:SetHeight(math.max(4, size - 4))
		btn:ClearAllPoints()
		btn:SetPoint("TOPLEFT", self.inner, "TOPLEFT", x0 + col * cell, -28 - rw * cell)
	end
end

equipPanel:SetScript("OnDragStop", function()
	this:StopMovingOrSizing()
	if not db then return end
	local p, _, rp, x, y = this:GetPoint()
	db.equipPoint = { p, rp, x, y }
end)

local function RefreshEquip()
	if not db or db.equipShown == false then equipPanel:Hide(); return end
	equipPanel:Show()
	for i = 1, table.getn(equipPanel.slots) do
		local btn = equipPanel.slots[i]
		local tex = GetInventoryItemTexture("player", btn.slotId)
		if tex then btn.icon:SetTexture(tex); btn.icon:Show() else btn.icon:Hide() end
	end
end

-- ---------------------------------------------------------------- Compact chat
local CHAT_LINES = 8
local CHAT_MAX = 40
local chatPanel = MakePanel("AZSTrackerChatFrame", 300, 112)
PanelTitle(chatPanel, "Chat")
chatPanel.lines = {}; chatPanel.msgs = {}
for i = 1, CHAT_MAX do
	local fs = chatPanel.inner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", chatPanel.inner, "TOPLEFT", 8, -26 - (i - 1) * 11)
	fs:SetPoint("TOPRIGHT", chatPanel.inner, "TOPRIGHT", -8, -26 - (i - 1) * 11)
	fs:SetJustifyH("LEFT"); fs:SetText(""); fs:SetHeight(11)
	chatPanel.lines[i] = fs
end
chatPanel.nrows = CHAT_LINES
chatPanel._minW = 120
local function ChatRedraw()
	local n = chatPanel.nrows
	local total = table.getn(chatPanel.msgs)
	local first = math.max(1, total - n + 1)
	for i = 1, CHAT_MAX do
		local m = (i <= n) and chatPanel.msgs[first + i - 1] or nil
		if m then
			chatPanel.lines[i]:SetText(m.t)
			chatPanel.lines[i]:SetTextColor(m.r, m.g, m.b)
		else
			chatPanel.lines[i]:SetText("")
		end
	end
end
function chatPanel:Layout()
	self.nrows = RowsThatFit(self, 26, 11, 6, CHAT_MAX)
	ChatRedraw()
end
chatPanel:SetScript("OnDragStop", function()
	this:StopMovingOrSizing()
	if not db then return end
	local p, _, rp, x, y = this:GetPoint()
	db.chatPoint = { p, rp, x, y }
end)

local function ChatPush(msg, r, g, b)
	if not msg then return end
	msg = string.gsub(msg, "|c%x%x%x%x%x%x%x%x", "")
	msg = string.gsub(msg, "|r", "")
	if string.len(msg) > 160 then msg = string.sub(msg, 1, 157) .. "..." end
	table.insert(chatPanel.msgs, { t = msg, r = r or 1, g = g or 1, b = b or 1 })
	while table.getn(chatPanel.msgs) > CHAT_MAX do table.remove(chatPanel.msgs, 1) end
	ChatRedraw()
end

local chatHook = CreateFrame("Frame")
local chatEvents = {"CHAT_MSG_SAY","CHAT_MSG_YELL","CHAT_MSG_PARTY","CHAT_MSG_RAID","CHAT_MSG_GUILD","CHAT_MSG_WHISPER","CHAT_MSG_SYSTEM","CHAT_MSG_CHANNEL","CHAT_MSG_EMOTE","CHAT_MSG_LOOT"}
for i = 1, table.getn(chatEvents) do chatHook:RegisterEvent(chatEvents[i]) end
chatHook:SetScript("OnEvent", function()
	if db and db.chatShown == false then return end
	local msg, sender = arg1 or "", arg2
	local line = (sender and sender ~= "" and event ~= "CHAT_MSG_SYSTEM") and (sender .. ": " .. msg) or msg
	local r, g, b = 0.9, 0.9, 0.9
	if event == "CHAT_MSG_PARTY" then r, g, b = 0.4, 0.7, 1
	elseif event == "CHAT_MSG_WHISPER" then r, g, b = 1, 0.5, 1
	elseif event == "CHAT_MSG_GUILD" then r, g, b = 0.3, 0.9, 0.3
	elseif event == "CHAT_MSG_SYSTEM" then r, g, b = 1, 0.85, 0.3
	elseif event == "CHAT_MSG_LOOT" then r, g, b = 0.2, 1, 0.2 end
	ChatPush(line, r, g, b)
end)

local function RefreshChat()
	if not db or db.chatShown == false then chatPanel:Hide() else chatPanel:Show() end
end

-- ---------------------------------------------------------------- options menu + single minimap button
-- One compass button opens this menu anytime (including before a run starts).

local opt = MakePanel("AZSTrackerOptionsFrame", 310, 686)
opt:SetFrameStrata("DIALOG")
opt._noFree = true
PanelTitle(opt, "AZS Tracker Options")
opt:SetScript("OnDragStop", function()
	this:StopMovingOrSizing()
	if not db then return end
	local p, _, rp, x, y = this:GetPoint()
	db.optPoint = { p, rp, x, y }
end)

local function ApplyOptions()
	if not db then return end
	markersEnabled = db.markersShown ~= false
	if not markersEnabled then
		HideList(chestPins); HideList(lairPins)
		SetGameFlagShown(true)
	end
	StyleMinimap(db.squareMinimap ~= false)
	ApplyPanelAlpha()
	RefreshMarkers()
	RefreshOdds()
	RefreshMeter()
	RefreshDps()
	RefreshStats()
	RefreshBosses()
	if RefreshBossHp then RefreshBossHp() end
	if RefreshTally then RefreshTally() end
	if RefreshEquip then RefreshEquip() end
	if RefreshChat then RefreshChat() end
	PartyMeter.Refresh()
	if ApplyHudReplacements then ApplyHudReplacements() end
end

local function MakeCheck(parent, y, label, key, defaultOn, tip)
	local cb = CreateFrame("CheckButton", nil, parent)
	cb:SetWidth(24); cb:SetHeight(24)
	cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
	cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
	cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
	cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
	cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
	local text = FS(parent, "GameFontHighlight")
	text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
	text:SetText(label)
	cb.tip = tip
	cb:SetScript("OnEnter", function()
		if this.tip then
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
			GameTooltip:AddLine(label, 1, 0.82, 0)
			GameTooltip:AddLine(this.tip, 1, 1, 1, 1)
			GameTooltip:Show()
		end
	end)
	cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
	cb:SetScript("OnClick", function()
		if not db then return end
		db[key] = this:GetChecked() and true or false
		-- db.shown is the odds key used by RefreshOdds
		if key == "oddsShown" then db.shown = db[key] end
		ApplyOptions()
	end)
	cb.key = key
	cb.defaultOn = defaultOn
	return cb
end

local checks = {}
local ROW = 26
local function CY(i) return -30 - (i - 1) * ROW end
table.insert(checks, MakeCheck(opt.inner, CY(1), "Minimap chests & lairs", "markersShown", true,
	"Show cache and guardian lair icons on the minimap."))
table.insert(checks, MakeCheck(opt.inner, CY(2), "Odds panel", "oddsShown", true,
	"Rare / Epic / Legendary chances from your luck."))
table.insert(checks, MakeCheck(opt.inner, CY(3), "Highest Damage Meter", "meterShown", true,
	"Biggest single hit per skill (never decreases)."))
table.insert(checks, MakeCheck(opt.inner, CY(4), "DPS Meter", "dpsShown", true,
	"Total skill damage that only increases (like the game meter)."))
table.insert(checks, MakeCheck(opt.inner, CY(5), "Party DPS Meter", "partyShown", true,
	"Damage and DPS for you, your party/raid and pets (from the combat log)."))
table.insert(checks, MakeCheck(opt.inner, CY(6), "Attributes", "statsShown", false,
	"Character stats from the run."))
table.insert(checks, MakeCheck(opt.inner, CY(7), "Boss timers", "bossShown", true,
	"Alive bosses and countdown to upcoming bosses."))
table.insert(checks, MakeCheck(opt.inner, CY(8), "Enemy HP bars", "bossHpShown", true,
	"Dark-red boss/guardian HP bars (hides the game's)."))
table.insert(checks, MakeCheck(opt.inner, CY(9), "Run tally icons", "tallyShown", true,
	"Gold, chest cost, kills (hides the game's tally)."))
table.insert(checks, MakeCheck(opt.inner, CY(10), "Gear panel", "equipShown", true,
	"Equipment icons; hover for item details."))
table.insert(checks, MakeCheck(opt.inner, CY(11), "Compact chat", "chatShown", true,
	"Compact chat panel (hides the default chat frames)."))
table.insert(checks, MakeCheck(opt.inner, CY(12), "Lair spawn countdown on minimap", "lairTimers", true,
	"Show a small timer above empty lairs waiting to respawn."))
table.insert(checks, MakeCheck(opt.inner, CY(13), "Square minimap", "squareMinimap", true,
	"Full-size square minimap with gold rim."))

-- pin size bias
local sizeLabel = FS(opt.inner, "GameFontHighlight")
sizeLabel:SetPoint("TOPLEFT", opt.inner, "TOPLEFT", 14, -376)
sizeLabel:SetText("Minimap icon size")
local sizeVal = FS(opt.inner, "GameFontNormal")
sizeVal:SetPoint("TOPRIGHT", opt.inner, "TOPRIGHT", -14, -376)

local function SetSizeBias(v)
	if not db then return end
	if v < -2 then v = -2 end
	if v > 4 then v = 4 end
	db.pinSizeBias = v
	sizeVal:SetText(tostring(10 + (db.pinSizeBias or 0)) .. "–" .. tostring(16 + (db.pinSizeBias or 0)) .. " px")
	RefreshMarkers()
end

local minus = CreateFrame("Button", nil, opt)
minus:SetWidth(22); minus:SetHeight(22)
minus:SetPoint("TOPLEFT", opt.inner, "TOPLEFT", 14, -396)
minus:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-UP")
minus:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-DOWN")
minus:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
minus:SetScript("OnClick", function() SetSizeBias((db and db.pinSizeBias or 0) - 1) end)

local plus = CreateFrame("Button", nil, opt)
plus:SetWidth(22); plus:SetHeight(22)
plus:SetPoint("LEFT", minus, "RIGHT", 4, 0)
plus:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-UP")
plus:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-DOWN")
plus:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
plus:SetScript("OnClick", function() SetSizeBias((db and db.pinSizeBias or 0) + 1) end)

local hint = FS(opt, "GameFontDisableSmall")

local alphaLabel = FS(opt.inner, "GameFontHighlight")
alphaLabel:SetPoint("TOPLEFT", opt.inner, "TOPLEFT", 14, -430)
alphaLabel:SetText("Panel opacity")
local alphaVal = FS(opt.inner, "GameFontNormal")
alphaVal:SetPoint("TOPRIGHT", opt.inner, "TOPRIGHT", -14, -430)

local function SetPanelAlpha(v)
	if not db then return end
	v = math.floor(v + 0.5)
	if v < 20 then v = 20 end
	if v > 100 then v = 100 end
	db.panelAlpha = v / 100
	alphaVal:SetText(tostring(v) .. "%")
	ApplyPanelAlpha()
end

local aMinus = CreateFrame("Button", nil, opt)
aMinus:SetWidth(22); aMinus:SetHeight(22)
aMinus:SetPoint("TOPLEFT", opt.inner, "TOPLEFT", 14, -450)
aMinus:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-UP")
aMinus:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-DOWN")
aMinus:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
aMinus:SetScript("OnClick", function()
	SetPanelAlpha(((db and db.panelAlpha) or 0.5) * 100 - 5)
end)

local aPlus = CreateFrame("Button", nil, opt)
aPlus:SetWidth(22); aPlus:SetHeight(22)
aPlus:SetPoint("LEFT", aMinus, "RIGHT", 4, 0)
aPlus:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-UP")
aPlus:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-DOWN")
aPlus:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
aPlus:SetScript("OnClick", function()
	SetPanelAlpha(((db and db.panelAlpha) or 0.5) * 100 + 5)
end)

hint:SetPoint("TOPLEFT", opt.inner, "TOPLEFT", 14, -382)
hint:SetWidth(244)
hint:SetJustifyH("LEFT")
hint:SetText("")

local function StyleBtn(b)
	b:SetWidth(90)
	b:SetHeight(26)
	local ntex = b:CreateTexture(nil, "BACKGROUND")
	ntex:SetTexture("Interface\\Buttons\\WHITE8X8")
	ntex:SetVertexColor(0.2, 0.18, 0.1, 1)
	ntex:SetAllPoints(b)
	b:SetNormalTexture(ntex)
	local ptex = b:CreateTexture(nil, "BACKGROUND")
	ptex:SetTexture("Interface\\Buttons\\WHITE8X8")
	ptex:SetVertexColor(0.35, 0.28, 0.12, 1)
	ptex:SetAllPoints(b)
	b:SetPushedTexture(ptex)
	local htex = b:CreateTexture(nil, "HIGHLIGHT")
	htex:SetTexture("Interface\\Buttons\\WHITE8X8")
	htex:SetVertexColor(0.9, 0.75, 0.3, 0.25)
	htex:SetAllPoints(b)
	b:SetHighlightTexture(htex)
	local border = b:CreateTexture(nil, "BORDER")
	border:SetTexture("Interface\\Buttons\\WHITE8X8")
	border:SetVertexColor(0.75, 0.6, 0.25, 1)
	border:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
	ntex:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
	ntex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
	ptex:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
	ptex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
end

local SyncChecks -- defined below; Cancel needs it

local PlaceMinimapButton -- defined with the minimap button below

do
-- small -/+ pair helper
local function MinusPlus(y, onMinus, onPlus)
	local m = CreateFrame("Button", nil, opt)
	m:SetWidth(22); m:SetHeight(22)
	m:SetPoint("TOPLEFT", opt.inner, "TOPLEFT", 14, y)
	m:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-UP")
	m:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-DOWN")
	m:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
	m:SetScript("OnClick", onMinus)
	local p = CreateFrame("Button", nil, opt)
	p:SetWidth(22); p:SetHeight(22)
	p:SetPoint("LEFT", m, "RIGHT", 4, 0)
	p:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-UP")
	p:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-DOWN")
	p:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
	p:SetScript("OnClick", onPlus)
	return m, p
end

-- panel scale: every panel at once (each panel can also be resized with its corner grip)
local scaleLabel = FS(opt.inner, "GameFontHighlight")
scaleLabel:SetPoint("TOPLEFT", opt.inner, "TOPLEFT", 14, -484)
scaleLabel:SetText("Scale all panels")
opt.scaleVal = FS(opt.inner, "GameFontNormal")
opt.scaleVal:SetPoint("TOPRIGHT", opt.inner, "TOPRIGHT", -14, -484)

local function ScaleAllPanels(delta)
	local shown = nil
	for i = 1, table.getn(skinnedPanels) do
		local f = skinnedPanels[i]
		if f and f.grip and f ~= opt then
			AnchorTopLeft(f)
			SetPanelScale(f, f:GetScale() + delta, true)
			shown = shown or f:GetScale()
		end
	end
	if shown then opt.scaleVal:SetText(string.format("%d%%", math.floor(shown * 100 + 0.5))) end
end
MinusPlus(-504, function() ScaleAllPanels(-0.05) end, function() ScaleAllPanels(0.05) end)

local resetSizeBtn = CreateFrame("Button", nil, opt)
StyleBtn(resetSizeBtn)
resetSizeBtn:SetPoint("TOPRIGHT", opt.inner, "TOPRIGHT", -14, -502)
local resetSizeTxt = resetSizeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
resetSizeTxt:SetPoint("CENTER", resetSizeBtn, "CENTER")
resetSizeTxt:SetText("Reset sizes")
resetSizeTxt:SetTextColor(1, 0.82, 0)
resetSizeBtn:SetScript("OnClick", function()
	for i = 1, table.getn(skinnedPanels) do
		local f = skinnedPanels[i]
		if f and f.grip and f ~= opt then ResetPanel(f) end
	end
	if db then db.panelScale = {}; db.panelSize = {} end
	opt.scaleVal:SetText("100%")
end)

local sizeHelp2 = FS(opt.inner, "GameFontDisableSmall")
sizeHelp2:SetPoint("TOPLEFT", opt.inner, "TOPLEFT", 14, -532)
sizeHelp2:SetWidth(280)
sizeHelp2:SetJustifyH("LEFT")
sizeHelp2:SetText("Per panel: drag the dotted bottom-right corner to change width/height, Shift+drag or mouse wheel to scale, right-click to reset.")

-- minimap size (square minimap)
local mmLabel = FS(opt.inner, "GameFontHighlight")
mmLabel:SetPoint("TOPLEFT", opt.inner, "TOPLEFT", 14, -572)
mmLabel:SetText("Square minimap size")
opt.mmVal = FS(opt.inner, "GameFontNormal")
opt.mmVal:SetPoint("TOPRIGHT", opt.inner, "TOPRIGHT", -14, -572)
local function SetMinimapSide(v)
	if not db then return end
	v = math.floor(v + 0.5)
	if v < 140 then v = 140 end
	if v > 400 then v = 400 end
	db.minimapSide = v
	opt.mmVal:SetText(v .. " px")
	if db.squareMinimap ~= false then StyleMinimap(true) end
	RefreshMarkers()
	if PlaceMinimapButton then PlaceMinimapButton() end
end
MinusPlus(-592, function() SetMinimapSide(((db and db.minimapSide) or 210) - 10) end,
	function() SetMinimapSide(((db and db.minimapSide) or 210) + 10) end)
end

local okBtn = CreateFrame("Button", nil, opt)
StyleBtn(okBtn)
okBtn:SetPoint("BOTTOMRIGHT", opt, "BOTTOM", -6, 14)
local okTxt = okBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
okTxt:SetPoint("CENTER", okBtn, "CENTER")
okTxt:SetText("OK")
okTxt:SetTextColor(1, 0.82, 0)
okBtn:SetScript("OnClick", function()
	ApplyOptions()
	opt:Hide()
end)

local cancelBtn = CreateFrame("Button", nil, opt)
StyleBtn(cancelBtn)
cancelBtn:SetPoint("BOTTOMLEFT", opt, "BOTTOM", 6, 14)
local cancelTxt = cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
cancelTxt:SetPoint("CENTER", cancelBtn, "CENTER")
cancelTxt:SetText("Cancel")
cancelTxt:SetTextColor(1, 0.82, 0)
-- snapshot of settings when options open; Cancel restores them
local optSnap = nil
cancelBtn:SetScript("OnClick", function()
	if optSnap and db then
		for k, v in pairs(optSnap) do db[k] = v end
		db.shown = db.oddsShown ~= false
		markersEnabled = db.markersShown ~= false
		SyncChecks()
		ApplyOptions()
	end
	opt:Hide()
end)

function SyncChecks()
	if not db then return end
	for i = 1, table.getn(checks) do
		local c = checks[i]
		local v = db[c.key]
		if v == nil then v = c.defaultOn end
		c:SetChecked(v and 1 or nil)
	end
	-- keep odds key in sync
	if db.oddsShown == nil then db.oddsShown = db.shown ~= false end
	db.shown = db.oddsShown ~= false
	SetSizeBias(db.pinSizeBias or 0)
	if SetPanelAlpha then SetPanelAlpha(((db.panelAlpha or 0.5) * 100)) end
	opt.mmVal:SetText((db.minimapSide or 210) .. " px")
	local sc = oddsPanel:GetScale() or 1
	opt.scaleVal:SetText(string.format("%d%%", math.floor(sc * 100 + 0.5)))
end

local function ToggleOptions()
	if opt:IsShown() then
		opt:Hide()
	else
		if db then
			optSnap = {
				markersShown = db.markersShown,
				oddsShown = db.oddsShown,
				shown = db.shown,
				meterShown = db.meterShown,
				statsShown = db.statsShown,
				bossShown = db.bossShown,
				lairTimers = db.lairTimers,
				pinSizeBias = db.pinSizeBias,
				panelAlpha = db.panelAlpha,
			}
		end
		SyncChecks()
		opt:Show()
	end
end

-- single minimap button
local btn = CreateFrame("Button", "AZSTrackerMinimapButton", Minimap)
btn:SetClampedToScreen(true)

function PlaceMinimapButton()
	if not db or not Minimap or not btn then return end
	local a = math.rad(db.btnAngle or 255)
	local x, y = math.cos(a), math.sin(a)
	if IsSquare() then
		local m = math.max(math.abs(x), math.abs(y))
		x, y = x / m, y / m
	end
	local r = (Minimap:GetWidth() or 140) / 2 + 8
	btn:ClearAllPoints()
	btn:SetPoint("CENTER", Minimap, "CENTER", x * r, y * r)
end

btn:SetWidth(31); btn:SetHeight(31)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(Minimap:GetFrameLevel() + 8)
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local btnIcon = btn:CreateTexture(nil, "BACKGROUND")
btnIcon:SetWidth(20); btnIcon:SetHeight(20)
btnIcon:SetTexture("Interface\\AddOns\\AZSTracker\\Textures\\Options")
btnIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
btnIcon:SetPoint("TOPLEFT", btn, "TOPLEFT", 7, -5)
local btnRing = btn:CreateTexture(nil, "OVERLAY")
btnRing:SetWidth(53); btnRing:SetHeight(53)
btnRing:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
btnRing:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
btn:RegisterForClicks("LeftButtonUp")
btn:RegisterForDrag("LeftButton")
btn:SetScript("OnClick", function() ToggleOptions() end)
btn:SetScript("OnDragStart", function()
	this:SetScript("OnUpdate", function()
		if not db then return end
		local mx, my = Minimap:GetCenter()
		local s = Minimap:GetEffectiveScale()
		local cx, cy = GetCursorPosition()
		db.btnAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
		PlaceMinimapButton()
	end)
end)
btn:SetScript("OnDragStop", function() this:SetScript("OnUpdate", nil) end)
btn:SetScript("OnEnter", function()
	GameTooltip:SetOwner(this, "ANCHOR_LEFT")
	GameTooltip:AddLine("AZS Tracker", 0.38, 0.63, 0.20)
	GameTooltip:AddLine("Click: open options", 1, 1, 1)
	GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function RestorePanel(frame, pointKey, defPoint, defRel, defX, defY)
	frame._pointKey = pointKey
	local s = db and type(db.panelScale) == "table" and tonumber(db.panelScale[frame:GetName()])
	if not s or s < MIN_SCALE or s > MAX_SCALE then s = 1 end
	frame:SetScale(s)
	local sz = db and type(db.panelSize) == "table" and db.panelSize[frame:GetName()]
	if type(sz) == "table" and tonumber(sz[1]) and tonumber(sz[2]) and not frame._noFree then
		SetPanelSize(frame, tonumber(sz[1]), tonumber(sz[2]), false)
	elseif frame.Layout then
		frame:Layout()
	end
	frame:ClearAllPoints()
	local pt = db and db[pointKey]
	if pt then
		frame:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
	else
		frame:SetPoint(defPoint, UIParent, defRel, defX, defY)
	end
end

-- ---------------------------------------------------------------- events / update

local elapsed = 0

-- Lua 5.0: max 32 upvalues per function. Pack refs so OnEvent/OnUpdate stay under the limit.
local A = {
	RefreshMarkers = RefreshMarkers,
	RefreshOdds = RefreshOdds,
	RefreshMeter = RefreshMeter,
	RefreshDps = RefreshDps,
	RefreshStats = RefreshStats,
	RefreshBosses = RefreshBosses,
	RefreshBossHp = RefreshBossHp,
	RefreshTally = RefreshTally,
	RefreshEquip = RefreshEquip,
	RefreshChat = RefreshChat,
	PlaceMinimapButton = PlaceMinimapButton,
	StyleMinimap = StyleMinimap,
	ApplyPanelAlpha = ApplyPanelAlpha,
	RestorePanel = RestorePanel,
	ApplyHudReplacements = ApplyHudReplacements,
	Summons = Summons,
	LockMinimapZoom = LockMinimapZoom,
	SyncChecks = SyncChecks,
	oddsPanel = oddsPanel,
	dpsPanel = dpsPanel,
	meterPanel = meterPanel,
	statsPanel = statsPanel,
	bossPanel = bossPanel,
	bossHpPanel = bossHpPanel,
	tallyPanel = tallyPanel,
	equipPanel = equipPanel,
	chatPanel = chatPanel,
	PartyMeter = PartyMeter,
	opt = opt,
}

local function OnVariablesLoaded()
	if type(AZSTrackerDB) ~= "table" then AZSTrackerDB = {} end
	db = AZSTrackerDB
	if db.markersShown == nil then db.markersShown = true end
	if db.oddsShown == nil then db.oddsShown = (db.shown ~= false) end
	if db.shown == nil then db.shown = db.oddsShown end
	if db.meterShown == nil then db.meterShown = true end
	if db.dpsShown == nil then db.dpsShown = true end
	if db.statsShown == nil then db.statsShown = false end
	if db.bossShown == nil then db.bossShown = true end
	if db.bossHpShown == nil then db.bossHpShown = true end
	if db.tallyShown == nil then db.tallyShown = true end
	if db.equipShown == nil then db.equipShown = true end
	if db.chatShown == nil then db.chatShown = true end
	if db.partyShown == nil then db.partyShown = true end
	if db.lairTimers == nil then db.lairTimers = true end
	if db.squareMinimap == nil then db.squareMinimap = true end
	if db.pinSizeBias == nil then db.pinSizeBias = 0 end
	if db.panelAlpha == nil then db.panelAlpha = 0.5 end
	if db.btnAngle == nil then db.btnAngle = 255 end
	markersEnabled = db.markersShown ~= false
	db.shown = db.oddsShown ~= false
	A.RestorePanel(A.oddsPanel, "point", "TOPRIGHT", "TOPRIGHT", -230, -260)
	A.RestorePanel(A.dpsPanel, "dpsPoint", "TOPLEFT", "TOPLEFT", 20, -360)
	A.RestorePanel(A.meterPanel, "meterPoint", "TOPLEFT", "TOPLEFT", 20, -180)
	A.RestorePanel(A.statsPanel, "statsPoint", "TOPLEFT", "TOPLEFT", 20, -420)
	A.RestorePanel(A.bossPanel, "bossPoint", "TOP", "TOP", 0, -80)
	A.RestorePanel(A.bossHpPanel, "bossHpPoint", "CENTER", "CENTER", 200, 0)
	A.RestorePanel(A.tallyPanel, "tallyPoint", "TOP", "TOP", 0, -40)
	A.RestorePanel(A.equipPanel, "equipPoint", "RIGHT", "RIGHT", -20, 0)
	A.RestorePanel(A.chatPanel, "chatPoint", "BOTTOMLEFT", "BOTTOMLEFT", 20, 40)
	A.RestorePanel(A.PartyMeter.panel, "partyPoint", "TOPLEFT", "TOPLEFT", 270, -360)
	A.RestorePanel(A.opt, "optPoint", "CENTER", "CENTER", 0, 40)
	A.PlaceMinimapButton()
	A.StyleMinimap(db.squareMinimap ~= false)
	A.ApplyPanelAlpha()
	A.SyncChecks()
	if A.ApplyHudReplacements then A.ApplyHudReplacements() end
end

local function OnZoneReset()
	A.Summons.Reset()
	A.PartyMeter.Reset()
	maxHits = {}
	skillDmgTotals = {}
	spellbookCache, actionCache, azsCache, talentCache, meterIconCache = {}, {}, {}, {}, {}
	resolvedIcons = {}
	if A.meterPanel then A.meterPanel._warmAt = nil end
	if A.dpsPanel then A.dpsPanel._warmAt = nil end
end

local function OnRefreshAll()
	A.RefreshMarkers()
	A.RefreshOdds()
	A.RefreshMeter()
	A.RefreshDps()
	A.RefreshStats()
	A.RefreshBosses()
	if A.RefreshBossHp then A.RefreshBossHp() end
	if A.RefreshTally then A.RefreshTally() end
	if A.RefreshEquip then A.RefreshEquip() end
	if A.RefreshChat then A.RefreshChat() end
	A.PartyMeter.Refresh()
end

driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("CHAT_MSG_ADDON")
driver:RegisterEvent("VARIABLES_LOADED")
driver:SetScript("OnEvent", function()
	if event == "VARIABLES_LOADED" then
		OnVariablesLoaded()
		return
	end
	if event == "PLAYER_ENTERING_WORLD" then
		maxHits = {}
		A.PlaceMinimapButton()
		if db then A.StyleMinimap(db.squareMinimap ~= false) end
	end
	if event == "PLAYER_ENTERING_WORLD" or arg1 == "AZSCHESTS" or arg1 == "AZSLAIRS"
			or arg1 == "AZSRUN" or arg1 == "AZSZONE" or arg1 == "AZS"
			or arg1 == "AZSMETER" or arg1 == "AZSBOSSES" or arg1 == "AZSUNITS" then
		if arg1 == "AZSZONE" then
			OnZoneReset()
		end
		OnRefreshAll()
	end
end)
driver:SetScript("OnUpdate", function()
	elapsed = elapsed + arg1
	A.Summons.Sample(arg1)
	if elapsed < 0.05 then return end
	elapsed = 0
	A.LockMinimapZoom()
	A.RefreshMarkers()
	A.RefreshBosses()
	if A.RefreshBossHp then A.RefreshBossHp() end
	if not db then return end
	if not this._slow then this._slow = 0 end
	this._slow = this._slow + 0.05
	if this._slow >= 0.5 then
		this._slow = 0
		A.RefreshOdds()
		A.RefreshMeter()
		A.RefreshDps()
		A.RefreshStats()
		if A.RefreshTally then A.RefreshTally() end
		if A.RefreshEquip then A.RefreshEquip() end
		if A.RefreshChat then A.RefreshChat() end
		A.PartyMeter.Refresh()
		if db.chatShown ~= false then
			local cf = getglobal("ChatFrame1")
			if cf and cf:IsVisible() then cf:Hide() end
		end
	end
end)

-- ---------------------------------------------------------------- slash

SLASH_AZSTRACKER1 = "/azst"
SlashCmdList["AZSTRACKER"] = function(msg)
	msg = string.lower(msg or "")
	if msg == "options" or msg == "config" or msg == "opt" or msg == "" then
		ToggleOptions()
	elseif msg == "hide" then
		if db then db.markersShown = false end
		markersEnabled = false
		HideList(chestPins); HideList(lairPins)
		SetGameFlagShown(true)
		SyncChecks()
		DEFAULT_CHAT_FRAME:AddMessage("|cff62a032AZS Tracker|r: minimap markers hidden.")
	elseif msg == "show" then
		if db then db.markersShown = true end
		markersEnabled = true
		RefreshMarkers()
		SyncChecks()
		DEFAULT_CHAT_FRAME:AddMessage("|cff62a032AZS Tracker|r: minimap markers enabled.")
	elseif msg == "partyreset" or msg == "reset" then
		PartyMeter.Reset()
		DEFAULT_CHAT_FRAME:AddMessage("|cff62a032AZS Tracker|r: party DPS meter reset.")
	elseif msg == "icons" then
		DebugIcons()
	elseif msg == "debug" then
		local run = AZS_RUN or {}
		local chests = AZS_CHESTS or {}
		local lairs = (AZS_GetLairs and AZS_GetLairs()) or AZS_LAIRS or {}
		DEFAULT_CHAT_FRAME:AddMessage("|cff62a032AZS Tracker|r: phase=" .. tostring(AZS_GetPhase and AZS_GetPhase())
			.. ", luck=" .. tostring(Luck())
			.. ", chests=" .. table.getn(chests)
			.. ", lairs=" .. table.getn(lairs))
	else
		DEFAULT_CHAT_FRAME:AddMessage("|cff62a032AZS Tracker|r: /azst options | show | hide | icons | partyreset | debug")
	end
end
