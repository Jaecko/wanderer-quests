local ADDON, ns = ...
local L = ns.L

-- The window: the places of a tab on the left (your class's levels, the
-- dungeons, the zones), their levels and how many of their quests you have
-- done; the one chosen on the right: its entrance, its quests as a tree (the
-- quests that open them above them, wherever they are), each with where you
-- stand; a quest clicked opens its sheet beside the window. Its pieces are
-- Wanderer's own (Wanderer.Skin: the window, its heading, its tables, its
-- corner).

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin

local WIDTH, HEIGHT = 900, 600 -- at first; then as you leave it
local MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT = 720, 440, 1600, 1100
local ROW = 24
local LEFT_WIDTH = 290
local GAP = 24
local TOP = 70 -- the heading, above the lists
local HEADER = 46 -- the place chosen, above its quests
local MAX_ROWS = 44 -- rows made once; those that fit are shown
local INDENT = 14
local MAX_INDENT = 5 -- a long chain steps right no further

-- Where you stand with a quest, in a color.
local STATUS = {
	done = { 0.45, 0.75, 0.45 }, passed = { 0.45, 0.75, 0.45 }, active = { 1, 0.82, 0 }, available = { 1, 1, 1 },
	locked = { 0.55, 0.55, 0.55 }, level = { 1, 0.4, 0.35 }, closed = { 0.45, 0.45, 0.45 },
}
ns.STATUS_COLORS = STATUS -- (the quest sheet's too)
local FAINT = { 0.55, 0.5, 0.44 }
-- The bags' green arrow (the game's), else a green plus.
local UPGRADE = CreateAtlasMarkup and CreateAtlasMarkup("bags-greenarrow", 12, 12) or "|cff40ff40+|r"

local window, dungeonList, questList, header, gearView
local wantedQuest -- a quest asked from the game's log: chosen when its place is drawn
local places, tree = {}, {}
local chosenDungeon, chosenQuest = nil, nil
local kind -- the tab shown: "class", "dungeons" or "zones" (the last one shown, kept)
local chosenBy = {} -- each tab: the place chosen (its id)
local tabs = {}
local TABS = { { "class", "CLASS" }, { "dungeons", "DUNGEONS" }, { "zones", "TAB_ZONES" }, { "gear", "GEAR" } }

-- A tab's name: the class one says your class.
local function TabName(tab)
	if tab[1] == "class" then
		local name = UnitClass and UnitClass("player")
		if type(name) == "string" and name ~= "" then return name end
	end
	return L[tab[2]]
end

local function Settings() return W and W.Settings and W.Settings("quests") or nil end

local function Colorize(text, c) return U.Colorize(text, c[1], c[2], c[3]) end

-- A quest level's difficulty color, as the game's quest log colors it (Wanderer's rule).
local function Difficulty(level) return { W.QuestLevelColor(level or 1) } end

local function StatusText(node)
	local status = node.status
	if status == "level" then return L.LEVEL:format(node.quest.requiredLevel or 0) end
	return L["STATUS_" .. status:upper()]
end

-- The quests -----------------------------------------------------------------------------------------

-- Each quest: stepped right by its place in the tree; the place's own in their difficulty's color, the
-- ones that lead to them softer, the done ones faded.
local function DrawQuests()
	if not questList then return end
	local offset = questList:Clamp(#tree)
	for index, row in ipairs(questList.rows) do
		local node = tree[index + offset]
		if node then
			node.name = ("[%d] %s"):format(node.quest.questLevel or 0, ns.QuestName(node.quest))
			node.indent = math.min(node.depth, MAX_INDENT) * INDENT
			local done = node.status == "done" or node.status == "passed"
			node.color = done and STATUS.closed or node.dungeon and Difficulty(node.quest.questLevel) or Skin.COLORS.soft
			-- A reward better for you: the green arrow (not on a quest behind you).
			local better = not done and node.status ~= "closed" and ns.RewardUpgrade(node.quest)
			if better then node.name = node.name .. "  " .. UPGRADE end
			-- (the gear tab: how much better, beside it)
			local gain = kind == "gear" and node.dungeon and ns.GearGain(node.quest.id)
			if gain then node.name = node.name .. "  " .. U.Colorize("+" .. gain.gain .. " %", 0.56, 0.88, 0.64) end
			-- (hovered: its whole name, where you stand, its levels)
			node.tip = { ns.QuestName(node.quest), StatusText(node),
				L.LEVELS_LINE:format(node.quest.questLevel or 0, node.quest.requiredLevel or 0), better and L.HAS_UPGRADE or nil }
		end
		row:Fill(node, node ~= nil and node == chosenQuest, node and { status = Colorize(StatusText(node), STATUS[node.status]) })
	end
end

local function ChooseQuest(node)
	chosenQuest = node
	-- Its sheet beside the window: all it says and asks.
	ns.ShowSheet(node.quest, window)
	DrawQuests()
end

-- The quest to choose first: one of the place's own you can take (in your log, or to take), else one
-- that leads to them, else one not behind you, else the first.
local function Takeable(node) return node.status == "active" or node.status == "available" end
local FIRST = {
	function(node) return node.dungeon and Takeable(node) end,
	Takeable,
	function(node) return node.status ~= "done" and node.status ~= "passed" and node.status ~= "closed" end,
}
local function FirstQuest(list)
	for _, test in ipairs(FIRST) do
		for _, node in ipairs(list) do
			if test(node) then return node end
		end
	end
	return list[1]
end

-- The place chosen: its entrance, its quests. The same one drawn again (a quest taken or given back):
-- the list stays where it was, the quest chosen with it.
local shownPlace
local function ShowDungeon()
	local entry = chosenDungeon
	header:SetShown(entry ~= nil)
	questList:SetShown(entry ~= nil)
	window.pick:SetShown(entry == nil)
	if not entry then
		shownPlace = nil
		return
	end
	local place = kind .. ":" .. entry.dungeon.id
	local same, before = place == shownPlace, chosenQuest and chosenQuest.quest.id
	shownPlace = place
	tree = ns.Tree(entry.dungeon.id, kind)
	header.name:SetText(entry.dungeon.name)
	local entrance = kind == "dungeons" and ns.Entrance(entry.dungeon) or nil
	local around = kind == "dungeons" and ns.AreaName(entrance and entrance.area or entry.dungeon.zone) or kind == "class" and TabName(TABS[1])
		or kind == "gear" and L.GEAR_NOTE or ""
	header.entrance:SetText(entrance and L.ENTRANCE:format(L.WHERE:format(around or "?", entrance.x, entrance.y)) or around or "")
	header.pin:SetShown(entrance ~= nil)
	questList.empty:SetShown(#tree == 0)
	chosenQuest = nil
	local wanted = wantedQuest
	wantedQuest = nil
	if wanted or same then
		local target = wanted or before
		for _, node in ipairs(tree) do
			if node.quest.id == target then chosenQuest = node end
		end
	end
	if not chosenQuest or wanted then
		chosenQuest = chosenQuest or FirstQuest(tree)
		-- (the list from the top, down to it when it is further)
		local at = 0
		for index, node in ipairs(tree) do
			if node == chosenQuest then at = index end
		end
		questList.offset = at > questList.count and at - 1 or 0
	end
	DrawQuests()
	-- (the quest asked: its sheet opened)
	if wanted and chosenQuest and chosenQuest.quest.id == wanted then ns.ShowSheet(chosenQuest.quest, window) else ns.RefreshSheet() end
end

-- The places -----------------------------------------------------------------------------------------

local function DrawPlaces()
	if not dungeonList then return end
	local offset = dungeonList:Clamp(#places)
	for index, row in ipairs(dungeonList.rows) do
		local entry = places[index + offset]
		local values
		if entry then
			local levels = entry.levels
			local finished = levels.done == levels.total
			entry.name = entry.dungeon.raid and (entry.dungeon.name .. "  " .. Colorize(L.RAID, FAINT)) or entry.dungeon.name
			entry.color = finished and STATUS.closed or levels.low and Difficulty(levels.low) or Skin.COLORS.text
			local count = levels.done .. "/" .. levels.total
			values = {
				range = Colorize(levels.low and (levels.low == levels.high and tostring(levels.low) or (levels.low .. "-" .. levels.high)) or "", FAINT),
				count = finished and Colorize(count, STATUS.done) or count,
			}
		end
		row:Fill(entry, entry ~= nil and entry == chosenDungeon, values)
	end
end

local function ChooseDungeon(entry)
	chosenDungeon = entry
	chosenBy[kind] = entry.dungeon.id
	DrawPlaces()
	ShowDungeon()
end

-- The tabs' links: the one shown in gold.
local function DrawTabs()
	for _, tab in ipairs(TABS) do
		local link, label = tabs[tab[1]], TabName(tab)
		if link then link:SetLabel(tab[1] == kind and Colorize(label, Skin.COLORS.gold) or label) end
	end
	window.pick:SetText(kind == "zones" and L.PICK_ZONE or kind == "class" and L.PICK_CLASS or kind == "gear" and L.PICK_GEAR or L.PICK)
	questList.empty:SetText(kind == "zones" and L.NONE_ZONE or kind == "class" and L.NONE_CLASS or kind == "gear" and L.NONE_GEAR or L.NONE)
end

-- Every place of the tab with quests for you, by level (where you stand as last read: ns.ReadYou).
local function Fill()
	kind = kind or (Settings() and Settings().tab) or "class"
	DrawTabs()
	-- The gear tab: two character sheets in place of the places and their quests.
	local gear = kind == "gear"
	dungeonList:SetShown(not gear)
	window.rule:SetShown(not gear)
	window.right:SetShown(not gear)
	gearView:SetShown(gear)
	if gear then return ns.DrawGear() end
	places = {}
	for _, dungeon in ipairs(ns.Places(kind)) do
		-- (its summary only: the tree is made for the place chosen)
		local levels = ns.Summary(dungeon.id, kind)
		if levels.total > 0 then places[#places + 1] = { dungeon = dungeon, levels = levels } end
	end
	-- (the slots of your gear in their order; the places by level)
	table.sort(places, function(a, b)
		if a.dungeon.order or b.dungeon.order then return (a.dungeon.order or 0) < (b.dungeon.order or 0) end
		if a.levels.low ~= b.levels.low then return (a.levels.low or 0) < (b.levels.low or 0) end
		return a.dungeon.name < b.dungeon.name
	end)
	-- The one chosen kept; else (a zone) the one you are in; else the first one near your level.
	local keep
	local wanted = chosenBy[kind] or (kind == "zones" and ns.Here(kind)) or nil
	for _, entry in ipairs(places) do
		if wanted and entry.dungeon.id == wanted then keep = entry end
	end
	if not keep then
		local level = ns.YourLevel()
		for _, entry in ipairs(places) do
			if not keep and (entry.levels.high or 0) >= level and entry.levels.done < entry.levels.total then keep = entry end
		end
	end
	chosenDungeon = keep or places[1]
	chosenBy[kind] = chosenDungeon and chosenDungeon.dungeon.id or nil
	-- (the place chosen in sight in the list)
	for index, entry in ipairs(places) do
		if entry == chosenDungeon and (index <= dungeonList.offset or index > dungeonList.offset + dungeonList.count) then
			dungeonList.offset = index - 1
		end
	end
	DrawPlaces()
	ShowDungeon()
end

-- A tab shown: its places, the one chosen there.
local function ShowTab(name)
	if name == kind then return end
	kind = name
	if Settings() then Settings().tab = name end
	dungeonList.offset = 0
	Fill()
end

-- The window ------------------------------------------------------------------------------------------

-- The lists as tall as the window lets them.
local function Fit()
	if not window then return end
	local margin = Skin.Margin() + 8
	local height = window:GetHeight() - (margin + TOP) - margin
	dungeonList:Fit(height)
	questList:Fit(height - HEADER)
end

-- Shown: where you stand read again, the lists.
local function Shown()
	if not ns.HasData() then return end
	ns.ReadYou()
	ns.LearnAllLog()
	-- (your gear, role or weights may have changed meanwhile)
	if kind == "gear" then ns.ForgetGear() end
	Fill()
end

local function Create()
	window = Skin.CreateWindow("WandererQuestsWindow", "MEDIUM")
	Skin.Dress(window, { "CENTER", UIParent, "CENTER", 0, 40 }, "questsWindow")
	local saved = Settings() and Settings().size
	window:SetSize(Skin.Within(saved and saved[1] or WIDTH, MIN_WIDTH, MAX_WIDTH), Skin.Within(saved and saved[2] or HEIGHT, MIN_HEIGHT, MAX_HEIGHT))
	local _, title, margin = Skin.Header(window, "Wanderer", L.QUESTS)
	local previous
	for _, tab in ipairs(TABS) do
		local link = Skin.CreateLink(window, TabName(tab), function()
			if U.PlaySound then U.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON") end
			ShowTab(tab[1])
		end)
		if previous then link:SetPoint("LEFT", previous, "RIGHT", 4, 0) else link:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -5, -4) end
		tabs[tab[1]] = link
		previous = link
	end
	-- Left: the places.
	dungeonList = Skin.Table(window, {
		width = LEFT_WIDTH, rows = MAX_ROWS, rowHeight = ROW, titles = false, icon = false, onClick = ChooseDungeon, onDraw = DrawPlaces,
		columns = { { key = "range", width = 46 }, { key = "count", width = 50 } },
	})
	dungeonList:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -(margin + TOP))
	local rule = Skin.Rule(window, true, 0.2)
	window.rule = rule
	rule:SetPoint("TOPLEFT", dungeonList, "TOPRIGHT", GAP / 2, 0)
	rule:SetPoint("BOTTOM", window, "BOTTOM", 0, margin)
	-- Right: the place chosen, its quests.
	local right = CreateFrame("Frame", nil, window)
	window.right = right
	right:SetPoint("TOPLEFT", dungeonList, "TOPRIGHT", GAP, 0)
	right:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin, margin)
	window.pick = Skin.Text(right, "GameTooltipText", "muted")
	window.pick:SetPoint("TOP", right, "TOP", 0, -60)
	window.pick:SetText(L.PICK)
	header = CreateFrame("Frame", nil, right)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(HEADER - 6)
	header:Hide()
	header.name = Skin.Text(header, "GameTooltipHeaderText", "gold")
	header.name:SetPoint("TOPLEFT")
	header.entrance = Skin.Text(header, "GameTooltipTextSmall", "label")
	header.entrance:SetPoint("TOPLEFT", header.name, "BOTTOMLEFT", 0, -4)
	-- (the way to its door: the game's own pin, followed on the map and the minimap)
	header.pin = Skin.Button(header, L.PIN_ENTRANCE, function()
		local entrance = chosenDungeon and ns.Entrance(chosenDungeon.dungeon)
		if entrance and not ns.PinMap(entrance.map, entrance.x, entrance.y) and W.Print then W.Print(L.PIN_FAILED) end
	end)
	header.pin:SetHeight(24)
	header.pin:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, -2)
	Skin.Tooltip(header.pin, L.PIN_DESC)
	header.name:SetPoint("RIGHT", header.pin, "LEFT", -10, 0)
	header.name:SetJustifyH("LEFT")
	questList = Skin.Table(right, {
		width = WIDTH - LEFT_WIDTH - GAP - margin * 2, rows = MAX_ROWS, rowHeight = ROW, titles = false, icon = false,
		onClick = ChooseQuest, onDraw = DrawQuests, columns = { { key = "status", width = 140 } },
	})
	questList:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
	questList:SetPoint("RIGHT", right, "RIGHT", 0, 0)
	questList.empty:SetText(L.NONE)
	questList:Hide()
	-- The gear tab's sheets, across the window.
	gearView = ns.GearView(window, window:GetWidth() - margin * 2)
	gearView:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -(margin + TOP))
	gearView:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin, margin)
	-- Its corner: dragged, the window grows or shrinks, the lists with it; its size and place kept.
	Skin.Resizable(window, {
		minWidth = MIN_WIDTH, minHeight = MIN_HEIGHT, maxWidth = MAX_WIDTH, maxHeight = MAX_HEIGHT,
		onResized = function(width, height)
			local settings = Settings()
			if settings then settings.size = { width, height } end
		end,
	})
	window:HookScript("OnSizeChanged", function()
		local skin = Skin.Get(window)
		if skin then skin:Layout() end
		Fit()
	end)
	Fit()
	-- Each time it shows: its scale, where you stand.
	window:HookScript("OnShow", function(self)
		self:SetScale(Skin.Scale())
		if ns.HearItems then ns.HearItems(true) end
		Shown()
	end)
	window:HookScript("OnHide", function() if ns.HearItems then ns.HearItems(false) end end)
	Skin.Get(window):Layout()
end

function ns.Window() return window end

function ns.Toggle()
	if not window then Create() end
	window:SetShown(not window:IsShown())
end

function ns.Open()
	if not window then Create() end
	if window:IsShown() then Shown() else window:Show() end
end

-- A quest of your log shown here: its tab, its place, it chosen, its sheet open (said when no list has it).
function ns.Reveal(questID)
	questID = tonumber(questID)
	if not (questID and ns.HasData()) then return end
	ns.ReadYou()
	local tab, place = ns.PlaceOf(questID)
	if not tab then
		if W.Print then W.Print(L.NOT_LISTED) end
		return
	end
	if not window then Create() end
	kind = tab
	if Settings() then Settings().tab = tab end
	chosenBy[tab] = place
	wantedQuest = questID
	if window:IsShown() then Shown() else window:Show() end
end

-- The game's quest log ----------------------------------------------------------------------------------

-- Beside a quest's details (the map's log, and its window apart), a small button; in the right-click menus of
-- the log and the tracker, a line: the quest opened here. The data is read only when it is asked.
local function LogButton(parent, place, questOf)
	local button = Skin.Button(parent, L.SHOW_HERE, function() ns.Reveal(questOf()) end)
	place(button)
	button:SetFrameLevel(parent:GetFrameLevel() + 10)
	Skin.Tooltip(button, L.SHOW_HERE_DESC, "ANCHOR_TOP")
	return button
end

local attached = {}
local function Attach()
	local Safe, Clean = U.Safe, U.Clean
	local details = QuestMapFrame and QuestMapFrame.DetailsFrame
	if details and not attached.map then
		attached.map = LogButton(details, function(button)
			local back = details.BackFrame and details.BackFrame.BackButton or details.BackButton
			if back then button:SetPoint("LEFT", back, "RIGHT", 8, 0) else button:SetPoint("TOPRIGHT", details, "TOPRIGHT", -8, -6) end
		end, function()
			return Clean(Safe(QuestMapFrame_GetDetailQuestID)) or details.questID or Clean(Safe(C_QuestLog.GetSelectedQuest))
		end)
	end
	local popup = QuestLogPopupDetailFrame
	if popup and not attached.popup then
		attached.popup = LogButton(popup, function(button)
			if popup.ShowMapButton then
				button:SetPoint("RIGHT", popup.ShowMapButton, "LEFT", -6, 0)
			else
				button:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -40, -30)
			end
		end, function() return popup.questID end)
	end
	if Menu and Menu.ModifyMenu and not attached.menus then
		attached.menus = true
		local function AddLine(owner, root)
			local id = type(owner) == "table" and Clean(owner.questID or owner.id)
			if type(id) ~= "number" or not (root and root.CreateButton) then return end
			if root.CreateDivider then root:CreateDivider() end
			root:CreateButton(L.SHOW_HERE, function() ns.Reveal(id) end)
		end
		for _, tag in ipairs({ "MENU_QUEST_MAP_LOG_TITLE", "MENU_QUEST_OBJECTIVE_TRACKER" }) do
			pcall(Menu.ModifyMenu, tag, AddLine)
		end
	end
	return attached.map and attached.popup and attached.menus
end

-- Init --------------------------------------------------------------------------------------------------

-- A quest taken, given back, a level gained: where you stand, drawn again (once, a moment after).
local Again = U and U.Debounce and U.Debounce(0.5, function()
	if window and window:IsShown() then Shown() end
end)
-- An item the game was fetching (a reward): the quests drawn again, their arrows with them.
local Redraw = U and U.Debounce and U.Debounce(0.3, function()
	if window and window:IsShown() then DrawQuests() end
end)

-- A reward arrived on the gear tab: the gear read again, only it (once, a moment after).
local GearAgain = U and U.Debounce and U.Debounce(0.5, function()
	if window and window:IsShown() and kind == "gear" then Fill() end
end)

-- Near a dungeon (in the zone of its entrance), at its levels, with quests of it to take: said once a
-- session, quietly (an option, off).
local told = {}
local function NearDungeon()
	local settings = Settings()
	if not (settings and settings.remind and ns.HasData()) then return end
	local here = U.Clean(U.Safe(GetRealZoneText))
	if not here then return end
	here = ns.Plain(here)
	ns.ReadYou()
	local level = ns.YourLevel()
	for _, dungeon in ipairs(ns.Dungeons()) do
		local zone = ns.AreaName(dungeon.zone)
		if not told[dungeon.id] and zone and zone:lower() == here then
			local count, levels = ns.Waiting(dungeon)
			if count > 0 and levels.low and level >= levels.low - 5 and level <= (levels.high or 60) + 2 then
				told[dungeon.id] = true
				W.Toast(L.REMIND_TITLE:format(dungeon.name), L.REMIND_TEXT:format(count), { duration = 6, corner = true })
			end
		end
	end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
	if event == "ZONE_CHANGED_NEW_AREA" then return NearDungeon() end
	-- (the game's quest windows loaded later: the buttons put there then)
	if event == "ADDON_LOADED" then
		if Attach() then events:UnregisterEvent("ADDON_LOADED") end
		return
	end
	if event == "GET_ITEM_INFO_RECEIVED" then -- (heard only while the window is shown)
		-- (a reward arrived: the gear tab read again, only it; an item the server could not send: nothing)
		local _, success = ...
		if success == false then return end
		if kind == "gear" then
			ns.ForgetGear()
			if GearAgain and window and window:IsShown() then GearAgain() end
		elseif Redraw and window and window:IsShown() then
			Redraw()
		end
		return
	end
	if event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_LEVEL_UP" or event == "QUEST_TURNED_IN" then ns.ForgetGear() end
	if Again and window and window:IsShown() then Again() end
end)

-- The names and rewards the game sends (often, everywhere): heard only while the window is shown.
function ns.HearItems(on)
	if on then events:RegisterEvent("GET_ITEM_INFO_RECEIVED") else events:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
end

function ns.Init()
	if not (W and W.RegisterExtension) then return end
	if (W.API or 1) < 6 then return W.Print(L.NEEDS_WANDERER) end
	-- (a weight, what you play, your talents changed: the gear judged again, at once when shown)
	W.OnComparisonChanged(function()
		ns.ForgetGear()
		if window and window:IsShown() then Shown() end
	end)
	W.RegisterExtension({
		key = "quests",
		addon = ADDON,
		title = L.QUESTS,
		news = L.NEWS_LINES,
		defaults = { remind = false },
		launcher = { label = L.QUESTS, open = function() ns.Toggle() end },
		options = function(o)
			o.Header(L.QUESTS)
			o.Button(L.QUESTS, L.OPEN, L.OPEN_DESC, function()
				o.CloseSettings()
				ns.Open()
			end)
			o.Checkbox("quests", "remind", L.REMIND, L.REMIND_DESC)
		end,
	})
	SLASH_WANDERERQUESTS1 = "/wquests"
	SlashCmdList.WANDERERQUESTS = function() ns.Toggle() end
	for _, event in ipairs({ "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA",
		"PLAYER_EQUIPMENT_CHANGED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	if not Attach() then events:RegisterEvent("ADDON_LOADED") end
end

-- (an older Wanderer, without it: said once)
if W and W.WhenLoaded then W.WhenLoaded(ADDON, ns.Init) elseif W and W.Print then W.Print(L.NEEDS_WANDERER) end
