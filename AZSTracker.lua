-- AZS Tracker: minimap chest/lair markers + rarity odds panel
-- Odds weights from LuckyOdds: Common 60, Uncommon 25k, Rare 10k^2, Epic 4k^3,
-- Legendary k^4; k = 1 + luck + level bonus (+1%/level, 30% max) + source bonus (+0.5 amulets).
-- WoW 1.12 / Lua 5.0.

local chestPins, lairPins = {}, {}
local markersEnabled = true
local PIN = 16
local ZOOM_YD = { [0] = 466.6667, 400, 333.3333, 266.6667, 200, 133.3333 }
local driver = CreateFrame("Frame", "AZSTrackerFrame", UIParent)
local db

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
	return DFRL ~= nil
end

-- ---------------------------------------------------------------- minimap pins

local function NewPin(list, idx, texture, label, levelOffset)
	local p = CreateFrame("Frame", nil, Minimap)
	p:SetWidth(PIN); p:SetHeight(PIN)
	p:SetFrameLevel(Minimap:GetFrameLevel() + (levelOffset or 8))
	p.icon = p:CreateTexture(nil, "OVERLAY")
	p.icon:SetAllPoints(p)
	p.icon:SetTexture(texture)
	p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
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

local function Place(p, ox, oy, limit, square)
	local reach
	if square then reach = math.max(math.abs(ox), math.abs(oy)) else reach = math.sqrt(ox * ox + oy * oy) end
	if reach > limit then p:Hide(); return false end
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
	local limit = width / 2 - PIN / 2
	local square = IsSquare()

	local chests = AZS_CHESTS or {}
	local used = 0
	for i = 1, table.getn(chests) do
		local c = chests[i]
		local cx, cy = tonumber(c.x), tonumber(c.y)
		if cx and cy then
			local north, east = cx - hx, hy - cy
			local p = chestPins[used + 1] or NewPin(chestPins, used + 1, "Interface\\AddOns\\AZSTracker\\Textures\\Chest", "Battleground Cache", 8)
			p:SetFrameLevel(Minimap:GetFrameLevel() + 8)
			if Place(p, east * scale, north * scale, limit, square) then
				used = used + 1
				p.label = "Battleground Cache"
				p.dist = math.sqrt(north * north + east * east)
			end
		end
	end
	for i = used + 1, table.getn(chestPins) do if chestPins[i] then chestPins[i]:Hide() end end

	local lairs = (AZS_GetLairs and AZS_GetLairs()) or AZS_LAIRS or {}
	used = 0
	for i = 1, table.getn(lairs) do
		local l = lairs[i]
		local lx, ly = tonumber(l.x), tonumber(l.y)
		local state = l.state or (l.active and "awake" or "empty")
		if lx and ly and (state == "asleep" or state == "awake") then
			local north, east = lx - hx, hy - ly
			local p = lairPins[used + 1] or NewPin(lairPins, used + 1, "Interface\\AddOns\\AZSTracker\\Textures\\Skull", "Guardian Lair", 12)
			p:SetFrameLevel(Minimap:GetFrameLevel() + 12)
			if Place(p, east * scale, north * scale, limit, square) then
				used = used + 1
				p.dist = math.sqrt(north * north + east * east)
				if state == "awake" then p.icon:SetVertexColor(1, 0.3, 0.3) else p.icon:SetVertexColor(1, 1, 1) end
				p.label = (l.name or "Guardian Lair") .. (state == "awake" and " - fighting" or " - asleep")
			end
		end
	end
	for i = used + 1, table.getn(lairPins) do if lairPins[i] then lairPins[i]:Hide() end end
end

-- ---------------------------------------------------------------- odds panel (from LuckyOdds)

local RARITY = {
	{ name = "RARE", r = 0.00, g = 0.44, b = 0.87 },
	{ name = "EPIC", r = 0.64, g = 0.21, b = 0.93 },
	{ name = "LEGEND", r = 1.00, g = 0.50, b = 0.00 },
}
local ROWS = {
	{ label = "Spells", icon = "Spell_Holy_HolyBolt", bonus = 0 },
	{ label = "Rings", icon = "INV_Jewelry_Ring_15", bonus = 0 },
	{ label = "Trinkets", icon = "INV_Misc_StoneTablet_11", bonus = 0 },
	{ label = "Amulets", icon = "INV_Jewelry_Talisman_07", bonus = 0.5 },
}
local WIDTH, ROW_H, TOP = 266, 20, 46
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

local panel = CreateFrame("Frame", "AZSTrackerOddsFrame", UIParent)
panel:SetWidth(WIDTH)
panel:SetHeight(TOP + table.getn(ROWS) * ROW_H + 10)
panel:SetBackdrop({
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
panel:SetBackdropColor(0.04, 0.04, 0.06, 0.92)
panel:SetBackdropBorderColor(0.62, 0.52, 0.32, 1)
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", function() this:StartMoving() end)
panel:SetScript("OnDragStop", function()
	this:StopMovingOrSizing()
	if not db then return end
	local p, _, rp, x, y = this:GetPoint()
	db.point = { p, rp, x, y }
end)
panel:Hide()

local function PText(font, justify)
	local t = panel:CreateFontString(nil, "OVERLAY", font)
	t:SetJustifyH(justify or "LEFT")
	return t
end

local function PTex(layer, path)
	local t = panel:CreateTexture(nil, layer)
	t:SetTexture(path)
	return t
end

local function IconFrame(size)
	local fr = CreateFrame("Frame", nil, panel)
	fr:SetWidth(size); fr:SetHeight(size)
	fr.tex = fr:CreateTexture(nil, "ARTWORK")
	fr.tex:SetAllPoints(fr)
	fr.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	return fr
end

local headerIcon = IconFrame(22)
headerIcon.tex:SetTexture("Interface\\Icons\\INV_Jewelry_Necklace_26")
headerIcon:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -9)
panel.luck = PText("GameFontNormal")
panel.luck:SetPoint("LEFT", headerIcon, "RIGHT", 8, 5)
panel.level = PText("GameFontDisableSmall")
panel.level:SetPoint("LEFT", headerIcon, "RIGHT", 8, -7)

for i = 1, 3 do
	local h = PText("GameFontNormalSmall", "RIGHT")
	h:SetPoint("RIGHT", panel, "TOPLEFT", COL_RIGHT[i], -TOP + 8)
	h:SetText(RARITY[i].name)
	h:SetTextColor(RARITY[i].r, RARITY[i].g, RARITY[i].b)
end
local rule = PTex("ARTWORK", "Interface\\Buttons\\WHITE8X8")
rule:SetVertexColor(0.62, 0.52, 0.32, 0.5)
rule:SetHeight(1)
rule:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -TOP + 1)
rule:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -TOP + 1)

panel.rows = {}
for n = 1, table.getn(ROWS) do
	local y = -TOP - (n - 1) * ROW_H
	local row = {}
	if math.mod(n, 2) == 0 then
		local band = PTex("BACKGROUND", "Interface\\Buttons\\WHITE8X8")
		band:SetVertexColor(1, 1, 1, 0.04)
		band:SetHeight(ROW_H)
		band:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, y)
		band:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, y)
	end
	local ic = IconFrame(15)
	ic.tex:SetTexture("Interface\\Icons\\" .. ROWS[n].icon)
	ic:SetPoint("LEFT", panel, "TOPLEFT", 12, y - ROW_H / 2)
	local name = PText("GameFontHighlightSmall")
	name:SetPoint("LEFT", ic, "RIGHT", 6, 0)
	name:SetText(ROWS[n].label)
	row.cells = {}
	for i = 1, 3 do
		local c = PText("GameFontHighlightSmall", "RIGHT")
		c:SetPoint("RIGHT", panel, "TOPLEFT", COL_RIGHT[i], y - ROW_H / 2)
		row.cells[i] = c
	end
	panel.rows[n] = row
end

local function RefreshOdds()
	if not db then return end
	local luck = Luck()
	if not db.shown or not luck then panel:Hide(); return end
	panel:Show()
	local lvl = LevelBonus()
	panel.luck:SetText("Luck  |cffffffff" .. math.floor(luck * 100 + 0.5) .. "%|r")
	panel.level:SetText("+" .. math.floor(lvl * 100 + 0.5) .. "% from your level")
	local k = 1 + luck + lvl
	for n = 1, table.getn(ROWS) do
		local odds = Odds(k + ROWS[n].bonus)
		for i = 1, 3 do
			local c = panel.rows[n].cells[i]
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

local function TogglePanel()
	if not db then return end
	db.shown = not db.shown
	local msg = db.shown and "odds panel shown." or "odds panel hidden."
	if db.shown and not Luck() then
		msg = "odds panel on; it shows once the game sends your luck (in a run)."
	end
	DEFAULT_CHAT_FRAME:AddMessage("|cff62a032AZS Tracker|r: " .. msg)
	RefreshOdds()
end

-- ---------------------------------------------------------------- minimap button (clover)

local btn = CreateFrame("Button", "AZSTrackerMinimapButton", Minimap)
btn:SetWidth(31)
btn:SetHeight(31)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(Minimap:GetFrameLevel() + 8)
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local btnIcon = btn:CreateTexture(nil, "BACKGROUND")
btnIcon:SetWidth(20)
btnIcon:SetHeight(20)
btnIcon:SetTexture("Interface\\AddOns\\AZSTracker\\Textures\\Clover")
btnIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
btnIcon:SetPoint("TOPLEFT", btn, "TOPLEFT", 7, -5)
local btnRing = btn:CreateTexture(nil, "OVERLAY")
btnRing:SetWidth(53)
btnRing:SetHeight(53)
btnRing:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
btnRing:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)

local function PlaceButton()
	if not db then return end
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

btn:RegisterForClicks("LeftButtonUp")
btn:RegisterForDrag("LeftButton")
btn:SetScript("OnClick", function() TogglePanel() end)
btn:SetScript("OnDragStart", function()
	this:SetScript("OnUpdate", function()
		if not db then return end
		local mx, my = Minimap:GetCenter()
		local s = Minimap:GetEffectiveScale()
		local cx, cy = GetCursorPosition()
		db.btnAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
		PlaceButton()
	end)
end)
btn:SetScript("OnDragStop", function() this:SetScript("OnUpdate", nil) end)
btn:SetScript("OnEnter", function()
	GameTooltip:SetOwner(this, "ANCHOR_LEFT")
	GameTooltip:AddLine("AZS Tracker", 0.38, 0.63, 0.20)
	GameTooltip:AddLine("Click: show or hide the odds panel", 1, 1, 1)
	GameTooltip:AddLine("Drag: move this button", 1, 1, 1)
	GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ---------------------------------------------------------------- events / update

local elapsed = 0
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("CHAT_MSG_ADDON")
driver:RegisterEvent("VARIABLES_LOADED")
driver:SetScript("OnEvent", function()
	if event == "VARIABLES_LOADED" then
		if type(AZSTrackerDB) ~= "table" then AZSTrackerDB = {} end
		db = AZSTrackerDB
		if db.shown == nil then db.shown = true end
		if db.btnAngle == nil then db.btnAngle = 255 end
		panel:ClearAllPoints()
		if db.point then
			panel:SetPoint(db.point[1], UIParent, db.point[2], db.point[3], db.point[4])
		else
			panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -230, -260)
		end
		PlaceButton()
		return
	end
	if event == "PLAYER_ENTERING_WORLD" or arg1 == "AZSCHESTS" or arg1 == "AZSLAIRS"
			or arg1 == "AZSRUN" or arg1 == "AZSZONE" or arg1 == "AZS" then
		RefreshMarkers()
		RefreshOdds()
	end
end)
driver:SetScript("OnUpdate", function()
	elapsed = elapsed + arg1
	if elapsed < 0.05 then return end
	elapsed = 0
	RefreshMarkers()
	-- odds refresh more slowly
	if not db then return end
	if not this._oddsWait then this._oddsWait = 0 end
	this._oddsWait = this._oddsWait + 0.05
	if this._oddsWait >= 0.5 then
		this._oddsWait = 0
		RefreshOdds()
	end
end)

-- ---------------------------------------------------------------- slash

SLASH_AZSTRACKER1 = "/azst"
SlashCmdList["AZSTRACKER"] = function(msg)
	msg = string.lower(msg or "")
	if msg == "hide" then
		markersEnabled = false
		HideList(chestPins); HideList(lairPins)
		SetGameFlagShown(true)
		DEFAULT_CHAT_FRAME:AddMessage("|cff62a032AZS Tracker|r: minimap markers hidden.")
	elseif msg == "show" then
		markersEnabled = true
		RefreshMarkers()
		DEFAULT_CHAT_FRAME:AddMessage("|cff62a032AZS Tracker|r: minimap markers enabled.")
	elseif msg == "odds" or msg == "panel" then
		TogglePanel()
	elseif msg == "debug" then
		local run = AZS_RUN or {}
		local chests = AZS_CHESTS or {}
		local lairs = (AZS_GetLairs and AZS_GetLairs()) or AZS_LAIRS or {}
		DEFAULT_CHAT_FRAME:AddMessage("|cff62a032AZS Tracker|r: minimap=" .. tostring(Minimap ~= nil)
			.. ", phase=" .. tostring(AZS_GetPhase and AZS_GetPhase())
			.. ", luck=" .. tostring(Luck())
			.. ", chests=" .. table.getn(chests)
			.. ", lairs=" .. table.getn(lairs))
	else
		DEFAULT_CHAT_FRAME:AddMessage("|cff62a032AZS Tracker|r: /azst show | hide | odds | debug")
	end
end
