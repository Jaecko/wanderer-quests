local _, ns = ...
local L = ns.L

-- The quests you could take, on the world map: the game shows the objectives
-- of the quests in your log and nothing of those still to take, so each giver
-- of a quest near your level (from 3 below to 3 above) gets the game's own "!"
-- where it stands. On a zone's map only (never a continent's, never the
-- minimap: the game shows the givers near you there). Drawn by the game's own
-- map engine (a data provider), so the pins follow its zoom; nothing drawn in
-- a fight (they come back after it). While a quest's sheet is open, the other
-- givers fade. A pin hovered: who and what; clicked: the quest in Quests;
-- Ctrl+click: its giver a step of Wanderer Maps' route; Shift+click: a map
-- link in the chat's box (the grammar of every place of Quests and Maps).
-- Questie drawing its own givers: none of these (no two "!" for one giver).

local W = Wanderer
local U = W.Util
local Skin = W.Skin
local Safe, Clean = U.Safe, U.Clean

local TEMPLATE = "WandererQuestsPinTemplate"
local SIZE = 18
local FADED = 0.35 -- the other givers while a sheet is open
local LOW_ALPHA = 0.6 -- a giver of lower quests only (an option)

local provider

local function Settings() return W.Settings("quests") end
local function Wanted()
	local settings = Settings()
	return settings and settings.mapGivers ~= false and not (W.Yields and W.Yields("questGivers"))
end

-- The pin ---------------------------------------------------------------------------------------------------

_G.WandererQuestsPinMixin = CreateFromMixins and CreateFromMixins(MapCanvasPinMixin or {}) or {}
local Pin = _G.WandererQuestsPinMixin

function Pin:OnLoad()
	if self.SetScalingLimits then self:SetScalingLimits(1, 1.0, 1.25) end
	if self.UseFrameLevelType then self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI") end
end

-- data: { who, x, y, quests, low }
function Pin:OnAcquired(data)
	self.data = data
	self:SetPosition(data.x, data.y)
	self:SetSize(SIZE, SIZE)
	self.icon:SetTexture(ns.AVAILABLE_ICON)
	-- (a giver of lower quests only: greyed)
	if self.icon.SetDesaturated then self.icon:SetDesaturated(data.low and true or false) end
	local alpha = data.low and LOW_ALPHA or 1
	-- (a quest's sheet open: the givers of other quests step back)
	local focus = ns.SheetQuest and ns.SheetQuest()
	if focus then
		local mine = false
		for _, quest in ipairs(data.quests) do
			if quest == focus then mine = true end
		end
		if not mine then alpha = FADED end
	end
	self:SetAlpha(alpha)
end

function Pin:OnMouseEnter()
	local data = self.data
	if not data then return end
	local lines = { data.who.name or "?" }
	for _, quest in ipairs(data.quests) do
		local r, g, b = W.QuestLevelColor(quest.questLevel or ns.YourLevel())
		lines[#lines + 1] = { ("[%s] %s"):format(quest.questLevel or "?", ns.QuestName(quest)), r, g, b }
	end
	-- (a controller has no Shift or Ctrl: its own words)
	local pad = U.UsingPad and U.UsingPad()
	lines[#lines + 1] = ns.TipLine(pad and L.MAP_PIN_TIP_PAD or ns.Maps() and L.MAP_PIN_TIP or L.MAP_PIN_TIP_PLAIN, "blue")
	ns.ShowTip(self, lines)
end

function Pin:OnMouseLeave()
	GameTooltip:Hide()
end

-- A click on a pin (whichever way the map engine passes it on: once). The right button goes on to the map.
local lastClick = 0
function Pin:OnMouseClickAction(button)
	local data = self.data
	if not data or button ~= "LeftButton" or GetTime() - lastClick < 0.05 then return end
	lastClick = GetTime()
	Skin.Play("click")
	local quest = data.quests[1]
	-- (with Wanderer Maps: the route and the map link; without it, a click opens the quest whatever is held)
	if ns.Maps() and IsShiftKeyDown() then return ns.SayLinkInChat(data.who) end
	if ns.Maps() and IsControlKeyDown() then return ns.SayToRoute(data.who, { kind = "take", quest = quest.id, label = ns.QuestName(quest) }) end
	ns.Reveal(quest.id)
end
function Pin:OnMouseUp(button, upInside)
	if upInside == false then return end
	self:OnMouseClickAction(button)
end

-- The provider ----------------------------------------------------------------------------------------------

-- In a fight nothing is drawn (the pins wait for its end).
local function AfterFight() U.AfterFight("questsPins", ns.RefreshMapPins) end

-- A zone's map (or a town's): yes; a continent, the world, an instance: no.
local function ZoneMap(map)
	local info = map and C_Map and Safe(C_Map.GetMapInfo, map)
	local mapType = type(info) == "table" and Clean(info.mapType)
	local zone = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
	local micro = Enum and Enum.UIMapType and Enum.UIMapType.Micro or 5
	return mapType == zone or mapType == micro
end

local function Provider()
	if provider or not (WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin) then return provider end
	provider = CreateFromMixins(MapCanvasDataProviderMixin)
	function provider:RemoveAllData()
		self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
	end
	function provider:RefreshAllData()
		self:RemoveAllData()
		if not Wanted() then return end
		if InCombatLockdown() then return AfterFight() end
		local map = Clean(Safe(self:GetMap().GetMapID, self:GetMap()))
		if not ZoneMap(map) then return end
		local settings = Settings()
		ns.ReadYou()
		for _, giver in ipairs(ns.GiversOn(map, settings and settings.mapLow)) do
			self:GetMap():AcquirePin(TEMPLATE, giver)
		end
	end
	WorldMapFrame:AddDataProvider(provider)
	return provider
end

-- Drawn again now (the map shown), else when it next shows.
function ns.RefreshMapPins()
	local made = Provider()
	if made and WorldMapFrame:IsShown() then pcall(made.RefreshAllData, made) end
end

-- Drawn again a moment after (several quests at once: once).
local soon
function ns.MapPinsSoon()
	if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
	soon = soon or U.Debounce(0.3, ns.RefreshMapPins)
	soon()
end

function ns.InitMapPins()
	if not WorldMapFrame then return end
	Provider()
	-- (a fight begins with the map open: its pins away until it ends)
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:SetScript("OnEvent", function()
		if provider and WorldMapFrame:IsShown() then
			provider:RemoveAllData()
			AfterFight()
		end
	end)
end
