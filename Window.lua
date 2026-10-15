local ADDON, ns = ...
local L = ns.L

-- The window: the dungeons on the left (their levels, how many of their
-- quests you have done), the one chosen on the right: its entrance, its
-- quests as a tree (the quests that open them above them, wherever they
-- are), each with where you stand; a quest chosen, who gives it and where,
-- and a pin on the map.

local W = Wanderer
local U = W and W.Util
local unpack = unpack or rawget(table, "unpack") -- (the game has the first, the tests the second)

local WIDTH, HEIGHT = 780, 540 -- at first; then as you leave it
local MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT = 640, 420, 1600, 1100
local ROW = 22
local LEFT_WIDTH = 250
local GAP = 24
local TOP = 70 -- the heading, above the lists
local BOTTOM = 18 -- the credit, under them
local HEADER = 46 -- the dungeon chosen, above its quests
local MAX_ROWS = 48 -- rows made once; those that fit are shown
local BAR = 12 -- the room of a list's scroll bar, on its right
local THUMB_MIN = 18
local INDENT = 14
local MAX_INDENT = 5 -- a long chain steps right no further

-- The colors, by role.
local P = {
	title = { 1, 0.82, 0 }, kicker = { 0.85, 0.75, 0.5 }, text = { 0.9, 0.88, 0.82 }, muted = { 0.6, 0.6, 0.6 },
	label = { 0.75, 0.68, 0.5 }, soft = { 0.7, 0.66, 0.58 }, faint = { 0.55, 0.5, 0.44 }, right = { 0.75, 0.75, 0.75 },
	source = { 0.5, 0.5, 0.5 }, rule = { 1, 0.82, 0, 0.2 }, chosen = { 1, 0.82, 0, 0.12 }, hover = { 1, 1, 1, 0.05 },
	thumb = { 1, 0.82, 0, 0.4 }, thumbHover = { 1, 0.82, 0, 0.75 },
	status = { done = { 0.45, 0.75, 0.45 }, passed = { 0.45, 0.75, 0.45 }, active = { 1, 0.82, 0 }, available = { 1, 1, 1 },
		locked = { 0.55, 0.55, 0.55 }, level = { 1, 0.4, 0.35 }, closed = { 0.45, 0.45, 0.45 } },
}

local window, dungeonList, questList, header, right
local chosenDungeon, chosenQuest = nil, nil
local kind -- the tab shown: "class", "dungeons" or "zones" (the last one shown, kept)
local chosenBy = {} -- each tab: the place chosen (its id)
local tabs = {}
local TABS = { { "class", "TAB_CLASS" }, { "dungeons", "TAB_DUNGEONS" }, { "zones", "TAB_ZONES" } }

-- A tab's name: the class one says your class.
local function TabName(tab)
	if tab[1] == "class" then
		local name = UnitClass and UnitClass("player")
		if type(name) == "string" and name ~= "" then return name end
	end
	return L[tab[2]]
end

local function Settings() return W and W.Settings and W.Settings("quests") or nil end

local function Color(text, color) return U.ColorCode(color[1], color[2], color[3]) .. text .. "|r" end

-- A text in a role (its color).
local function Text(parent, template, role)
	local c = P[role]
	return W.Skin.CreateText(parent, template, c[1], c[2], c[3])
end

-- A thin line or a tint in a role.
local function Tint(texture, role)
	texture:SetColorTexture(unpack(P[role]))
	return texture
end

-- A quest level's difficulty color, the game's (r, g, b).
local function Difficulty(level)
	local color = GetQuestDifficultyColor and GetQuestDifficultyColor(level or 1)
	if not color then return 1, 1, 1 end
	return color.r or 1, color.g or 1, color.b or 1
end

-- A row's name, stepped right by its place in the tree, in a color (r, g, b).
local function Paint(row, indent, r, g, b)
	if row.indent ~= indent then
		row.indent = indent
		row.name:SetPoint("LEFT", row, "LEFT", 4 + indent, 0)
	end
	row.name:SetTextColor(r, g, b)
end

local function StatusText(node)
	local status = node.status
	if status == "level" then return L.LEVEL:format(node.quest.requiredLevel or 0) end
	return L["STATUS_" .. status:upper()]
end

-- A list: rows of a given height, the wheel scrolling it (list.offset), each filled by fill(row, entry).
local function NewList(parent, count, width, fill, onClick)
	local list = CreateFrame("Frame", nil, parent)
	list:SetSize(width, count * ROW)
	list:EnableMouseWheel(true)
	list.offset, list.rows, list.entries, list.count = 0, {}, {}, count
	-- The scroll bar: a thin rail, a thumb as long as the part shown.
	local bar = CreateFrame("Button", nil, list)
	bar:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)
	bar:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)
	bar:SetWidth(BAR - 4)
	local rail = Tint(bar:CreateTexture(nil, "BACKGROUND"), "rule")
	rail:SetWidth(2)
	rail:SetPoint("TOP")
	rail:SetPoint("BOTTOM")
	local thumb = CreateFrame("Button", nil, bar)
	thumb:SetWidth(BAR - 6)
	thumb.fill = Tint(thumb:CreateTexture(nil, "ARTWORK"), "thumb")
	thumb.fill:SetAllPoints()
	bar.thumb = thumb
	list.bar = bar
	-- The offset that puts the thumb's top at a height from the bar's top.
	local function OffsetAt(top)
		local free = bar:GetHeight() - thumb:GetHeight()
		local total = #list.entries - list.count
		if free <= 0 or total <= 0 then return 0 end
		return math.floor(math.max(0, math.min(1, top / free)) * total + 0.5)
	end
	local function CursorTop()
		local _, y = GetCursorPosition()
		return (bar:GetTop() or 0) - y / bar:GetEffectiveScale()
	end
	thumb:SetScript("OnMouseDown", function(self)
		self.grab = CursorTop() - ((self:GetTop() and bar:GetTop()) and (bar:GetTop() - self:GetTop()) or 0)
		self:SetScript("OnUpdate", function(own)
			-- Let go anywhere: the drag ends.
			if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then return own:SetScript("OnUpdate", nil) end
			local offset = OffsetAt(CursorTop() - own.grab)
			if offset ~= list.offset then
				list.offset = offset
				list:Draw()
			end
		end)
	end)
	thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
	thumb:SetScript("OnEnter", function(self) self.fill:SetColorTexture(unpack(P.thumbHover)) end)
	thumb:SetScript("OnLeave", function(self) self.fill:SetColorTexture(unpack(P.thumb)) end)
	-- The rail clicked: a page toward where it was.
	bar:SetScript("OnClick", function()
		local below = CursorTop() > (bar:GetTop() or 0) - (thumb:GetTop() or 0) + thumb:GetHeight()
		list.offset = list.offset + (below and list.count or -list.count)
		list:Draw()
	end)
	function list:Draw()
		self.offset = math.max(0, math.min(self.offset, #self.entries - self.count))
		for index, row in ipairs(self.rows) do
			local entry = index <= self.count and self.entries[index + self.offset] or nil
			row.entry = entry
			row:SetShown(entry ~= nil)
			if entry then fill(row, entry) end
		end
		-- The bar, when there is more than is shown.
		local total = #self.entries
		local more = total > self.count
		bar:SetShown(more)
		if more then
			local height = self.count * ROW
			local size = math.max(THUMB_MIN, math.floor(height * self.count / total))
			local top = math.floor((height - size) * self.offset / (total - self.count) + 0.5)
			thumb:SetHeight(size)
			thumb:ClearAllPoints()
			thumb:SetPoint("TOP", bar, "TOP", 0, -top)
		end
	end
	-- Rows that fit in a height (drawn again only when their number changes).
	function list:Fit(height)
		local fit = math.max(1, math.min(#self.rows, math.floor(height / ROW)))
		if fit == self.count then return end
		self.count = fit
		self:SetHeight(fit * ROW)
		self:Draw()
	end
	list:SetScript("OnMouseWheel", function(self, delta)
		self.offset = self.offset - delta * 3
		self:Draw()
	end)
	for index = 1, MAX_ROWS do
		local row = CreateFrame("Button", nil, list)
		row:SetHeight(ROW)
		row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(index - 1) * ROW)
		row:SetPoint("RIGHT", list, "RIGHT", -BAR, 0)
		row.chosen = Tint(row:CreateTexture(nil, "BACKGROUND"), "chosen")
		row.chosen:SetAllPoints()
		row.chosen:Hide()
		row.hover = Tint(row:CreateTexture(nil, "BACKGROUND", nil, 1), "hover")
		row.hover:SetAllPoints()
		row.hover:Hide()
		row.right = Text(row, "GameTooltipTextSmall", "right")
		row.right:SetPoint("RIGHT", row, "RIGHT", -2, 0)
		row.name = Text(row, "GameTooltipText", "text")
		row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
		row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
		if row.name.SetWordWrap then row.name:SetWordWrap(false) end
		row.name:SetJustifyH("LEFT")
		row:SetScript("OnEnter", function(self) self.hover:Show() end)
		row:SetScript("OnLeave", function(self) self.hover:Hide() end)
		row:SetScript("OnClick", function(self)
			if not self.entry then return end
			if U.PlaySound then U.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON") end
			onClick(self.entry)
		end)
		row:Hide()
		list.rows[index] = row
	end
	return list
end

local function FillQuest(row, node)
	local indent = math.min(node.depth, MAX_INDENT) * INDENT
	row.name:SetText(("[%d] %s"):format(node.quest.questLevel or 0, ns.QuestName(node.quest)))
	-- The place's own in their difficulty's color; the ones that lead to them, softer; the done ones, faded.
	local done = node.status == "done" or node.status == "passed"
	if done then
		Paint(row, indent, unpack(P.status.closed))
	elseif node.dungeon then
		Paint(row, indent, Difficulty(node.quest.questLevel))
	else
		Paint(row, indent, unpack(P.soft))
	end
	row.right:SetText(Color(StatusText(node), P.status[node.status]))
	row.chosen:SetShown(node == chosenQuest)
end

local function ChooseQuest(node)
	chosenQuest = node
	-- Its sheet beside the window: all it says and asks.
	ns.ShowSheet(node.quest, window)
	questList:Draw()
end

-- The quest to choose first: one of the place's own you can take (in your log, or to take), else one
-- that leads to them, else one not behind you, else the first.
local function Takeable(node) return node.status == "active" or node.status == "available" end
local FIRST = {
	function(node) return node.dungeon and Takeable(node) end,
	Takeable,
	function(node) return node.status ~= "done" and node.status ~= "passed" and node.status ~= "closed" end,
}
local function FirstQuest(tree)
	for _, test in ipairs(FIRST) do
		for _, node in ipairs(tree) do
			if test(node) then return node end
		end
	end
	return tree[1]
end

-- The dungeon chosen: its entrance, its quests. The same one drawn again (a quest taken or given back):
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
	entry.tree = ns.Tree(entry.dungeon.id, kind)
	header.name:SetText(entry.dungeon.name)
	local entrance = kind == "dungeons" and ns.Entrance(entry.dungeon) or nil
	local around = kind == "dungeons" and ns.AreaName(entry.dungeon.zone) or kind == "class" and TabName(TABS[1]) or ""
	header.entrance:SetText(entrance and L.ENTRANCE:format(L.WHERE:format(around or "?", entrance.x, entrance.y)) or around or "")
	header.pin:SetShown(entrance ~= nil)
	questList.entries = entry.tree
	questList.empty:SetShown(#entry.tree == 0)
	chosenQuest = nil
	if same then
		for _, node in ipairs(entry.tree) do
			if node.quest.id == before then chosenQuest = node end
		end
	end
	if not chosenQuest then
		chosenQuest = FirstQuest(entry.tree)
		-- (the list from the top, down to it when it is further)
		local at = 0
		for index, node in ipairs(entry.tree) do
			if node == chosenQuest then at = index end
		end
		questList.offset = at > questList.count and at - 1 or 0
	end
	questList:Draw()
	ns.RefreshSheet()
end

local function FillDungeon(row, entry)
	local levels = entry.levels
	row.name:SetText(entry.dungeon.raid and (entry.dungeon.name .. "  " .. Color(L.RAID, P.faint)) or entry.dungeon.name)
	local finished = levels.done == levels.total
	if finished then
		Paint(row, 0, unpack(P.status.closed))
	elseif levels.low then
		Paint(row, 0, Difficulty(levels.low))
	else
		Paint(row, 0, unpack(P.text))
	end
	local range = levels.low and (levels.low == levels.high and tostring(levels.low) or (levels.low .. "-" .. levels.high)) or ""
	local count = levels.done .. "/" .. levels.total
	if finished then count = Color(count, P.status.done) end
	row.right:SetText(Color(range, P.faint) .. "  " .. count)
	row.chosen:SetShown(entry == chosenDungeon)
end

local function ChooseDungeon(entry)
	chosenDungeon = entry
	chosenBy[kind] = entry.dungeon.id
	dungeonList:Draw()
	ShowDungeon()
end

-- The tabs' links: the one shown in the title's color.
local function DrawTabs()
	for _, tab in ipairs(TABS) do
		local link, label = tabs[tab[1]], TabName(tab)
		if link then link:SetLabel(tab[1] == kind and Color(label, P.title) or label) end
	end
	window.pick:SetText(kind == "zones" and L.PICK_ZONE or kind == "class" and L.PICK_CLASS or L.PICK)
	questList.empty:SetText(kind == "zones" and L.NONE_ZONE or kind == "class" and L.NONE_CLASS or L.NONE)
end

-- Every place of the tab with quests for you, by level (where you stand as last read: ns.ReadYou).
local function Fill()
	kind = kind or (Settings() and Settings().tab) or "class"
	DrawTabs()
	local rows = {}
	for _, dungeon in ipairs(ns.Places(kind)) do
		-- (its summary only: the tree is made for the place chosen)
		local levels = ns.Summary(dungeon.id, kind)
		if levels.total > 0 then rows[#rows + 1] = { dungeon = dungeon, levels = levels } end
	end
	table.sort(rows, function(a, b)
		if a.levels.low ~= b.levels.low then return (a.levels.low or 0) < (b.levels.low or 0) end
		return a.dungeon.name < b.dungeon.name
	end)
	dungeonList.entries = rows
	-- The one chosen kept; else (a zone) the one you are in; else the first one near your level.
	local keep
	local wanted = chosenBy[kind] or (kind == "zones" and ns.Here(kind)) or nil
	for _, entry in ipairs(rows) do
		if wanted and entry.dungeon.id == wanted then keep = entry end
	end
	if not keep then
		local level = ns.YourLevel()
		for _, entry in ipairs(rows) do
			if not keep and (entry.levels.high or 0) >= level and entry.levels.done < entry.levels.total then keep = entry end
		end
	end
	chosenDungeon = keep or rows[1]
	chosenBy[kind] = chosenDungeon and chosenDungeon.dungeon.id or nil
	dungeonList:Draw()
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


-- The lists as tall as the window lets them.
local function Fit()
	if not window then return end
	local margin = W.Skin.Margin() + 8
	local height = window:GetHeight() - (margin + TOP) - (margin + BOTTOM)
	dungeonList:Fit(height)
	questList:Fit(height - HEADER)
end

-- Shown: where you stand read again, the lists.
local function Shown()
	if not ns.HasData() then return end
	ns.ReadYou()
	Fill()
end

local function Create()
	window = W.Skin.CreateWindow("WandererQuestsWindow", "MEDIUM")
	W.Skin.Dress(window, { "CENTER", UIParent, "CENTER", 0, 40 }, "questsWindow")
	local saved = Settings() and Settings().size
	local function Within(value, low, high) return math.max(low, math.min(high, value)) end
	window:SetSize(Within(saved and saved[1] or WIDTH, MIN_WIDTH, MAX_WIDTH), Within(saved and saved[2] or HEIGHT, MIN_HEIGHT, MAX_HEIGHT))
	local margin = W.Skin.Margin() + 8
	local kicker = W.Skin.CreateKicker(window, "Wanderer")
	kicker:SetTextColor(unpack(P.kicker))
	kicker:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -margin)
	local title = Text(window, "GameTooltipHeaderText", "title")
	title:SetPoint("TOPLEFT", kicker, "BOTTOMLEFT", 0, -3)
	title:SetText(L.TITLE)
	local previous
	for _, tab in ipairs(TABS) do
		local link = W.Skin.CreateLink(window, TabName(tab), function()
			if U.PlaySound then U.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON") end
			ShowTab(tab[1])
		end)
		if previous then link:SetPoint("LEFT", previous, "RIGHT", 4, 0) else link:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -5, -4) end
		tabs[tab[1]] = link
		previous = link
	end
	-- Left: the dungeons.
	dungeonList = NewList(window, 18, LEFT_WIDTH, FillDungeon, ChooseDungeon)
	dungeonList:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -(margin + TOP))
	local rule = Tint(window:CreateTexture(nil, "ARTWORK"), "rule")
	rule:SetWidth(1)
	rule:SetPoint("TOPLEFT", dungeonList, "TOPRIGHT", GAP / 2, 0)
	rule:SetPoint("BOTTOM", window, "BOTTOM", 0, margin + BOTTOM)
	-- Right: the dungeon chosen, its quests, the quest chosen.
	right = CreateFrame("Frame", nil, window)
	right:SetPoint("TOPLEFT", dungeonList, "TOPRIGHT", GAP, 0)
	right:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin, margin + BOTTOM)
	window.pick = Text(right, "GameTooltipText", "muted")
	window.pick:SetPoint("TOP", right, "TOP", 0, -60)
	window.pick:SetText(L.PICK)
	header = CreateFrame("Frame", nil, right)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(HEADER - 6)
	header:Hide()
	header.name = Text(header, "GameTooltipHeaderText", "title")
	header.name:SetPoint("TOPLEFT")
	header.entrance = Text(header, "GameTooltipTextSmall", "label")
	header.entrance:SetPoint("TOPLEFT", header.name, "BOTTOMLEFT", 0, -4)
	header.pin = W.Skin.CreateLink(header, L.PIN, function()
		local entrance = chosenDungeon and ns.Entrance(chosenDungeon.dungeon)
		if entrance and not ns.PinMap(entrance.map, entrance.x, entrance.y) and W.Print then W.Print(L.PIN_FAILED) end
	end, L.PIN_DESC)
	header.pin:SetPoint("LEFT", header.entrance, "RIGHT", 4, 0)
	questList = NewList(right, 12, WIDTH - LEFT_WIDTH - GAP - margin * 2, FillQuest, ChooseQuest)
	questList:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
	questList:SetPoint("RIGHT", right, "RIGHT", 0, 0)
	questList.empty = Text(questList, "GameTooltipText", "muted")
	questList.empty:SetPoint("TOP", questList, "TOP", 0, -20)
	questList.empty:SetText(L.NONE)
	questList.empty:Hide()
	questList:Hide()
	-- Where the quests come from.
	local source = Text(window, "GameTooltipTextSmall", "source")
	source:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", margin, margin)
	source:SetText(L.SOURCE)
	-- Its corner: dragged, the window grows or shrinks, the lists with it; its size and place kept.
	window:SetResizable(true)
	if window.SetResizeBounds then
		window:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
	elseif window.SetMinResize then
		window:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
	end
	local grip = CreateFrame("Button", nil, window)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -3, 3)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then window:StartSizing("BOTTOMRIGHT") end
	end)
	grip:SetScript("OnMouseUp", function()
		window:StopMovingOrSizing()
		local settings = Settings()
		if settings then settings.size = { math.floor(window:GetWidth() + 0.5), math.floor(window:GetHeight() + 0.5) } end
		-- Its place kept as it is now (sizing may anchor it again).
		local keep = window:GetScript("OnDragStop")
		if keep then keep(window) end
	end)
	window:HookScript("OnSizeChanged", function()
		local skin = W.Skin.Get(window)
		if skin then skin:Layout() end
		Fit()
	end)
	Fit()
	-- Each time it shows: its scale, where you stand.
	window:HookScript("OnShow", function(self)
		self:SetScale(W.Skin.Scale())
		Shown()
	end)
	W.Skin.Get(window):Layout()
end

function ns.Toggle()
	if not window then Create() end
	window:SetShown(not window:IsShown())
end

function ns.Open()
	if not window then Create() end
	if window:IsShown() then Shown() else window:Show() end
end

-- Init ------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
local soon = false
events:SetScript("OnEvent", function()
	-- A quest taken, given back, a level gained: where you stand, drawn again (once, a moment after).
	if soon or not (window and window:IsShown()) then return end
	soon = true
	C_Timer.After(0.5, function()
		soon = false
		if window and window:IsShown() then Shown() end
	end)
end)

function ns.Init()
	if not (W and W.RegisterExtension) then return end
	if (W.API or 1) < 2 then return W.Print(L.NEEDS_WANDERER) end
	W.RegisterExtension({
		key = "quests",
		title = L.TITLE,
		defaults = {},
		launcher = { label = L.TITLE, open = function() ns.Toggle() end },
		options = function(o)
			o.Header(L.TITLE)
			o.Button(L.TITLE, L.OPEN_BUTTON, L.OPEN_DESC, function()
				o.CloseSettings()
				ns.Open()
			end)
		end,
	})
	SLASH_WANDERERQUESTS1 = "/wquests"
	SlashCmdList.WANDERERQUESTS = function() ns.Toggle() end
	for _, event in ipairs({ "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_LEVEL_UP" }) do
		pcall(events.RegisterEvent, events, event)
	end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
	if name ~= ADDON then return end
	self:UnregisterEvent("ADDON_LOADED")
	ns.Init()
end)
