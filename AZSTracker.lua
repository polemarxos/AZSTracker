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

local function MakePanel(name, width, height)
	local f = CreateFrame("Frame", name, UIParent)
	f:SetWidth(width)
	f:SetHeight(height)
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
local NATIVE_MM = { "MinimapBorderTop", "MinimapBorder", "MinimapBackdrop", "MinimapToggleButton", "MinimapZoneTextButton", "GameTimeFrame" }

local function SetMinimapMask(path)
	if not Minimap or not Minimap.SetMaskTexture then return end
	if pcall(Minimap.SetMaskTexture, Minimap, path) then return end
	pcall(Minimap.SetMaskTexture, Minimap, "Interface\\ChatFrame\\ChatFrameBackground")
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
		SetMinimapMask(MINIMAP_MASK)
		-- gold square rim around the map
		if not Minimap.azsRim then
			Minimap.azsRim = {}
			for i = 1, 4 do
				local t = Minimap:CreateTexture(nil, "OVERLAY")
				t:SetTexture(FLAT)
				Minimap.azsRim[i] = t
			end
		end
		local rim = Minimap.azsRim
		local th = 1
		rim[1]:ClearAllPoints(); rim[1]:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -th, th); rim[1]:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", th, th); rim[1]:SetHeight(th)
		rim[2]:ClearAllPoints(); rim[2]:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", -th, -th); rim[2]:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", th, -th); rim[2]:SetHeight(th)
		rim[3]:ClearAllPoints(); rim[3]:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -th, 0); rim[3]:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", -th, 0); rim[3]:SetWidth(th)
		rim[4]:ClearAllPoints(); rim[4]:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", th, 0); rim[4]:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", th, 0); rim[4]:SetWidth(th)
		for i = 1, 4 do rim[i]:SetVertexColor(0.67, 0.57, 0.36, 1); rim[i]:Show() end
		minimapStyled = true
	elseif not on and minimapStyled then
		for name, shown in pairs(minimapNative) do
			local f = getglobal(name)
			if f and shown == 1 then f:Show() end
		end
		minimapNative = {}
		SetMinimapMask(DEFAULT_MASK)
		if Minimap.azsRim then
			for i = 1, 4 do Minimap.azsRim[i]:Hide() end
		end
		minimapStyled = false
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
	for i = 1, 3 do
		local h = FS(oddsPanel, "GameFontNormalSmall", "RIGHT")
		h:SetPoint("RIGHT", oddsPanel, "TOPLEFT", COL_RIGHT[i], -O_TOP + 8)
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
		end
		local ic = CreateFrame("Frame", nil, oddsPanel)
		ic:SetWidth(15); ic:SetHeight(15)
		ic:SetPoint("LEFT", oddsPanel, "TOPLEFT", 12, y - O_ROW_H / 2)
		local it = ic:CreateTexture(nil, "ARTWORK")
		it:SetAllPoints(ic)
		it:SetTexture("Interface\\Icons\\" .. ODDS_ROWS[n].icon)
		it:SetTexCoord(0.07, 0.93, 0.07, 0.93)
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

local meterPanel = MakePanel("AZSTrackerMeterFrame", METER_W, 43 + METER_ROWS * (METER_BAR_H + METER_ROW_GAP) + 13)
PanelTitle(meterPanel, "Biggest Hits")
meterPanel.sub = meterPanel.inner:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
meterPanel.sub:SetPoint("TOPRIGHT", meterPanel.inner, "TOPRIGHT", -10, -8)
meterPanel.rows = {}
for i = 1, METER_ROWS do
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

meterPanel:SetScript("OnDragStop", function()
	this:StopMovingOrSizing()
	if not db then return end
	local p, _, rp, x, y = this:GetPoint()
	db.meterPoint = { p, rp, x, y }
end)

-- Resolve skill icons in priority order:
-- spellbook (including pet/tabs), action bars, AZS spell IDs, fuzzy name match,
-- keyword map, talents, then generic fallback. Unknown "?" entries stay question marks.
local spellbookCache, actionCache, azsCache, talentCache = {}, {}, {}, {}
local BOOK = BOOKTYPE_SPELL or "spell"
local DEFAULT_ICON = "Interface\\\\Icons\\\\Spell_Holy_HolyBolt"
local QUESTION_ICON = "Interface\\\\Icons\\\\INV_Misc_QuestionMark"

local function Norm(s)
    if not s then return "" end
    s = string.lower(s)
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    s = string.gsub(s, "%s+", " ")
    return s
end

local KEYWORDS = {
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
    cache[name] = tex
    cache[Norm(name)] = tex
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

local function ScanAZSSpells()
    if type(AZS_SPELLS) ~= "table" then return end
    for i = 1, table.getn(AZS_SPELLS) do
        local sp = AZS_SPELLS[i]
        if sp and sp.spell then
            local tex = SafeSpellTexture(sp.spell, BOOK)
            local spellName
            if type(GetSpellInfo) == "function" then
                local ok, n, _, icon = pcall(GetSpellInfo, sp.spell)
                if ok then
                    spellName = n
                    if not tex and type(icon) == "string" then tex = icon end
                end
            end
            if tex then
                if spellName then Cache(azsCache, spellName, tex) end
                if sp.key then Cache(azsCache, tostring(sp.key), tex) end
                Cache(azsCache, tostring(sp.spell), tex)
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
        for talent = 1, 30 do
            local ok, name, icon = pcall(GetTalentInfo, tab, talent)
            if not ok or not name then
                -- talent slots are sequential, so stop at the first empty slot
                break
            end
            if type(icon) == "string" and icon ~= "" then Cache(talentCache, name, icon) end
        end
    end
end

local function WarmIcons()
    ScanSpellbook()
    ScanActionBars()
    ScanAZSSpells()
    ScanTalents()
end

local function FindIcon(cache, name, allowPartial)
    local n = Norm(name)
    if cache[n] then return cache[n] end
    if not allowPartial then return nil end
    for k, tex in pairs(cache) do
        if type(k) == "string" and type(tex) == "string" then
            local kn = Norm(k)
            if kn == n or (string.len(kn) > 3 and
                (string.find(n, kn, 1, true) or string.find(kn, n, 1, true))) then
                return tex
            end
        end
    end
    return nil
end

local function KeywordIcon(name)
    local n = Norm(name)
    for i = 1, table.getn(KEYWORDS) do
        if string.find(n, KEYWORDS[i][1], 1, true) then
            return "Interface\\Icons\\" .. KEYWORDS[i][2]
        end
    end
    return nil
end

local function SkillIcon(name)
    if not name then return DEFAULT_ICON end
    local n = Norm(name)
    -- Do not turn unresolved/question-mark entries into a misleading holy-bolt icon.
    if n == "?" or n == "??" or string.find(n, "?", 1, true) then
        return QUESTION_ICON
    end
    local tex = FindIcon(spellbookCache, name, false)
    if tex then return tex end
    tex = FindIcon(actionCache, name, false)
    if tex then return tex end
    tex = FindIcon(azsCache, name, false)
    if tex then return tex end
    -- Case-insensitive / partial name matching, in the same source priority.
    tex = FindIcon(spellbookCache, name, true)
    if not tex then tex = FindIcon(actionCache, name, true) end
    if not tex then tex = FindIcon(azsCache, name, true) end
    if tex then return tex end
    tex = KeywordIcon(name)
    if tex then return tex end
    -- Talents are a last real-icon source, after the requested five lookups.
    tex = FindIcon(talentCache, name, true)
    if tex then return tex end
    return DEFAULT_ICON
end

local function NoteHit(skill, amount)
	if not skill or not amount or amount <= 0 then return end
	skill = string.gsub(skill, "^%s+", "")
	skill = string.gsub(skill, "%s+$", "")
	if string.len(skill) < 2 or string.len(skill) > 36 then return end
	local cur = maxHits[skill]
	if not cur or amount > cur then maxHits[skill] = amount end
end

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
	end
end

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
combatFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
combatFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE")
combatFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
combatFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE")
combatFrame:SetScript("OnEvent", OnCombatText)

local function RefreshMeter()
	if not db or not db.meterShown then meterPanel:Hide(); return end

	meterPanel:Show()
	if not meterPanel._warmed then
		WarmIcons()
		meterPanel._warmed = true
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
					table.insert(lines, { name = name, max = maxHits[name] or 0, proc = ml[i].proc })
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
	local barW = METER_W - 44
	for i = 1, METER_ROWS do
		local row = meterPanel.rows[i]
		local e = shown[i]
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
			row.val:SetText(FormatNum(e.max))
			row.icon:SetTexture(SkillIcon(e.name))
		else
			row:Hide()
		end
	end
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
local bossPanel = MakePanel("AZSTrackerBossFrame", 258, 43 + BOSS_ROWS * 15 + 14)
PanelTitle(bossPanel, "Bosses")
bossPanel.rows = {}
for i = 1, BOSS_ROWS do
	local y = -32 - (i - 1) * 15
	local row = {}
	row.name = FS(bossPanel, "GameFontHighlightSmall")
	row.name:SetPoint("TOPLEFT", bossPanel.inner, "TOPLEFT", 10, y)
	row.name:SetWidth(142)
	row.info = FS(bossPanel, "GameFontHighlightSmall", "RIGHT")
	row.info:SetPoint("TOPRIGHT", bossPanel.inner, "TOPRIGHT", -10, y)
	row.info:SetWidth(82)
	bossPanel.rows[i] = row
end
bossPanel:SetScript("OnDragStop", function()
	this:StopMovingOrSizing()
	if not db then return end
	local p, _, rp, x, y = this:GetPoint()
	db.bossPoint = { p, rp, x, y }
end)

local function RefreshBosses()
	if not db or not db.bossShown then bossPanel:Hide(); return end

	bossPanel:Show()

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

	for i = 1, BOSS_ROWS do
		local row = bossPanel.rows[i]
		local e = entries[i]
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

-- ---------------------------------------------------------------- options menu + single minimap button
-- One compass button opens this menu anytime (including before a run starts).

local opt = MakePanel("AZSTrackerOptionsFrame", 300, 440)
opt:SetFrameStrata("DIALOG")
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
	RefreshStats()
	RefreshBosses()
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
table.insert(checks, MakeCheck(opt.inner, -36, "Minimap chests & lairs", "markersShown", true,
	"Show cache and guardian lair icons on the minimap."))
table.insert(checks, MakeCheck(opt.inner, -60, "Odds panel", "oddsShown", true,
	"Rare / Epic / Legendary chances from your luck."))
table.insert(checks, MakeCheck(opt.inner, -84, "Damage meter", "meterShown", false,
	"Bar-style damage meter by ability."))
table.insert(checks, MakeCheck(opt.inner, -108, "Attributes", "statsShown", false,
	"Character stats from the run."))
table.insert(checks, MakeCheck(opt.inner, -132, "Boss timers", "bossShown", true,
	"Alive bosses and countdown to upcoming bosses."))

-- customization: lair respawn timers on minimap
table.insert(checks, MakeCheck(opt.inner, -156, "Lair spawn countdown on minimap", "lairTimers", true,
	"Show a small timer above empty lairs waiting to respawn."))
table.insert(checks, MakeCheck(opt.inner, -180, "Square minimap", "squareMinimap", true,
	"Square minimap with gold rim  Keeps AZS Tracker icons."))

-- pin size bias
local sizeLabel = FS(opt.inner, "GameFontHighlight")
sizeLabel:SetPoint("TOPLEFT", opt.inner, "TOPLEFT", 14, -236)
sizeLabel:SetText("Minimap icon size")
local sizeVal = FS(opt.inner, "GameFontNormal")
sizeVal:SetPoint("TOPRIGHT", opt.inner, "TOPRIGHT", -14, -236)

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
minus:SetPoint("TOPLEFT", opt.inner, "TOPLEFT", 14, -256)
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
alphaLabel:SetPoint("TOPLEFT", opt.inner, "TOPLEFT", 14, -284)
alphaLabel:SetText("Panel opacity")
local alphaVal = FS(opt.inner, "GameFontNormal")
alphaVal:SetPoint("TOPRIGHT", opt.inner, "TOPRIGHT", -14, -284)

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
aMinus:SetPoint("TOPLEFT", opt.inner, "TOPLEFT", 14, -328)
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

hint:SetPoint("TOPLEFT", opt.inner, "TOPLEFT", 14, -356)
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

local function SyncChecks()
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

local function PlaceMinimapButton()
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
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("CHAT_MSG_ADDON")
driver:RegisterEvent("VARIABLES_LOADED")
driver:SetScript("OnEvent", function()
	if event == "VARIABLES_LOADED" then
		if type(AZSTrackerDB) ~= "table" then AZSTrackerDB = {} end
		db = AZSTrackerDB
		if db.markersShown == nil then db.markersShown = true end
		if db.oddsShown == nil then db.oddsShown = (db.shown ~= false) end
		if db.shown == nil then db.shown = db.oddsShown end
		if db.meterShown == nil then db.meterShown = false end
		if db.statsShown == nil then db.statsShown = false end
		if db.bossShown == nil then db.bossShown = true end
		if db.lairTimers == nil then db.lairTimers = true end
		if db.squareMinimap == nil then db.squareMinimap = true end
		if db.pinSizeBias == nil then db.pinSizeBias = 0 end
		if db.panelAlpha == nil then db.panelAlpha = 0.5 end
		if db.btnAngle == nil then db.btnAngle = 255 end
		markersEnabled = db.markersShown ~= false
		db.shown = db.oddsShown ~= false
		RestorePanel(oddsPanel, "point", "TOPRIGHT", "TOPRIGHT", -230, -260)
		RestorePanel(meterPanel, "meterPoint", "TOPLEFT", "TOPLEFT", 20, -180)
		RestorePanel(statsPanel, "statsPoint", "TOPLEFT", "TOPLEFT", 20, -420)
		RestorePanel(bossPanel, "bossPoint", "TOP", "TOP", 0, -80)
		RestorePanel(opt, "optPoint", "CENTER", "CENTER", 0, 40)
		PlaceMinimapButton()
		StyleMinimap(db.squareMinimap ~= false)
		ApplyPanelAlpha()
		SyncChecks()
		return
	end
	if event == "PLAYER_ENTERING_WORLD" then
		maxHits = {}
		PlaceMinimapButton()
		if db then StyleMinimap(db.squareMinimap ~= false) end
	end
	if event == "PLAYER_ENTERING_WORLD" or arg1 == "AZSCHESTS" or arg1 == "AZSLAIRS"
			or arg1 == "AZSRUN" or arg1 == "AZSZONE" or arg1 == "AZS"
			or arg1 == "AZSMETER" or arg1 == "AZSBOSSES" or arg1 == "AZSUNITS" then
		if arg1 == "AZSZONE" then
            maxHits = {}
            spellbookCache, actionCache, azsCache, talentCache = {}, {}, {}, {}
            if meterPanel then meterPanel._warmed = nil end
        end
		RefreshMarkers()
		RefreshOdds()
		RefreshMeter()
		RefreshStats()
		RefreshBosses()
	end
end)
driver:SetScript("OnUpdate", function()
	elapsed = elapsed + arg1
	if elapsed < 0.05 then return end
	elapsed = 0
	RefreshMarkers()
	RefreshBosses()
	if not db then return end
	if not this._slow then this._slow = 0 end
	this._slow = this._slow + 0.05
	if this._slow >= 0.5 then
		this._slow = 0
		RefreshOdds()
		RefreshMeter()
		RefreshStats()
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
	elseif msg == "debug" then
		local run = AZS_RUN or {}
		local chests = AZS_CHESTS or {}
		local lairs = (AZS_GetLairs and AZS_GetLairs()) or AZS_LAIRS or {}
		DEFAULT_CHAT_FRAME:AddMessage("|cff62a032AZS Tracker|r: phase=" .. tostring(AZS_GetPhase and AZS_GetPhase())
			.. ", luck=" .. tostring(Luck())
			.. ", chests=" .. table.getn(chests)
			.. ", lairs=" .. table.getn(lairs))
	else
		DEFAULT_CHAT_FRAME:AddMessage("|cff62a032AZS Tracker|r: /azst options | show | hide | debug")
	end
end
