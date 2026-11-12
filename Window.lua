local ADDON, ns = ...
local L = ns.L

-- The window: the places of a tab on the left (your class's levels, the
-- dungeons, the zones), their levels, a small bar of what you have done there
-- and how many quests you could take; the one chosen on the right: what is
-- there for you (to take, in your log, done), one main action, a filter, then
-- its quests as a tree (the quests that open them above them, wherever they
-- are), each with the game's own sign, its level and a chip of where you
-- stand; a quest clicked opens its sheet beside the window. Its pieces are
-- Wanderer's own (Wanderer.Skin: the window, its heading, its tables, its
-- corner).

local W = Wanderer
local U = W.Util
local Skin = W.Skin

local WIDTH, HEIGHT = 900, 600 -- at first; then as you leave it
local MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT = 720, 540, 1600, 1100
local KIT_ROW = rawget(Skin, "ROW") -- (the kit's row heights; read raw: an older Wanderer has none)
local ROW = KIT_ROW and KIT_ROW.compact or 24 -- the places
local QUEST_ROW = KIT_ROW and KIT_ROW.compact or 24 -- the quests
local LEFT_WIDTH = 290
local GAP = 24
local TOP = 70 -- the heading, above the lists
local HEADER = 126 -- the place chosen (its name, what is there, its entrance, its bar, the filter), above its quests
local MAX_ROWS = 44 -- rows made once; those that fit are shown
local INDENT = 12 -- a chain's step
local MAX_INDENT = 4 -- a long chain steps right no further
local SIGN, LEVEL_WIDTH = 16, 24
local BAR_WIDTH = 40 -- a place's small bar, on the left

-- The game's own signs: a quest to take, a quest in your log.
local AVAILABLE_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local ACTIVE_ICON = "Interface\\GossipFrame\\ActiveQuestIcon"
local DONE_ICON = "Interface\\RaidFrame\\ReadyCheck-Ready"
ns.AVAILABLE_ICON = AVAILABLE_ICON

-- Where you stand with a quest, in a color.
local C = Skin.COLORS
local STATUS = {
	done = C.good, passed = C.good, active = C.gold, available = C.text,
	locked = C.muted, level = C.bad, closed = C.done,
}
ns.STATUS_COLORS = STATUS -- (the quest sheet's too)
local FAINT = C.muted
-- The bags' green arrow (the game's), else a green plus.
-- (read at loading: nothing of a newer Wanderer's kit here)
local UPGRADE = CreateAtlasMarkup and CreateAtlasMarkup("bags-greenarrow", 12, 12) or "|cff1eff00+|r"

local window, dungeonList, questList, header, gearView, libraryView
local wantedQuest -- a quest asked from the game's log: chosen when its place is drawn
local places, tree, shown = {}, {}, {} -- shown: the tree as the filter leaves it
local chosenDungeon, chosenQuest = nil, nil
local shownPlace -- the place drawn last ("kind:id")
local kind -- the tab shown: "class", "dungeons" or "zones" (the last one shown, kept)
local chosenBy = {} -- each tab: the place chosen (its id)
local tabs = {}
local TABS = { { "class", "CLASS" }, { "dungeons", "DUNGEONS" }, { "zones", "TAB_ZONES" }, { "books", "BOOKS" }, { "gear", "GEAR" } }

-- A tab's name: the class one says your class.
local function TabName(tab)
	if tab[1] == "class" then
		local name = UnitClass and UnitClass("player")
		if type(name) == "string" and name ~= "" then return name end
	end
	return L[tab[2]]
end

local function Settings() return W.Settings("quests") end

-- The window's own state (its tab, its size, its filter): this character's, kept here and not in a profile
-- (written from the window, it held in the profile shown only: another came back in town or on the road).
-- The values an older save kept in the profile are read once.
local FILTERS = { all = true, take = true, log = true }
function ns.WindowState()
	WandererQuestsDB = type(WandererQuestsDB) == "table" and WandererQuestsDB or {}
	local all = type(WandererQuestsDB.view) == "table" and WandererQuestsDB.view or {}
	WandererQuestsDB.view = all
	local key = W.CharacterKey and W.CharacterKey() or "?"
	local mine = all[key]
	if type(mine) ~= "table" then
		local old = Settings() or {}
		mine = { tab = old.tab, filter = old.filter, hideDone = old.hideDone, size = old.size }
		all[key] = mine
	end
	if type(mine.tab) ~= "string" then mine.tab = nil end
	if not FILTERS[mine.filter] then mine.filter = nil end
	if type(mine.hideDone) ~= "boolean" then mine.hideDone = nil end
	local size = mine.size
	if not (type(size) == "table" and tonumber(size[1]) and tonumber(size[2])) then mine.size = nil end
	return mine
end
local State = ns.WindowState

-- Wanderer off: said, no window (an open one can still be closed).
local function Off()
	if Settings() then return false end
	W.Print(L.EXT_TURNED_OFF:format(L.QUESTS))
	return true
end

local function Colorize(text, c) return U.Colorize(text, c[1], c[2], c[3]) end

-- A quest level's difficulty color, as the game's quest log colors it (Wanderer's rule).
local function Difficulty(level) return { W.QuestLevelColor(level or 1) } end

-- Where you stand with a quest, in words (the sheet's too).
function ns.StatusText(quest, status)
	if status == "level" then return L.LEVEL:format(quest.requiredLevel or 0) end
	return L["STATUS_" .. status:upper()]
end
local function StatusText(node) return ns.StatusText(node.quest, node.status) end

-- Where you stand, as a chip: its words and its tone (nil: no chip, the sign says enough).
function ns.StatusChip(quest, status)
	if status == "available" then return L.CHIP_TAKE, "gold" end
	if status == "active" then
		if ns.Ready(quest) then return L.CHIP_READY, "green" end
		return L.CHIP_LOG, "blue"
	end
	if status == "level" then return L.CHIP_LEVEL:format(quest.requiredLevel or 0), "red" end
	return nil
end

-- A quest's sign, the game's own: "!" to take, "?" in your log (bright when ready to hand in), a check when
-- done, a dot when it waits (another quest before it, a level), nothing when another one was chosen.
function ns.SetSign(texture, quest, status)
	texture:SetAlpha(1)
	texture:SetTexCoord(0, 1, 0, 1)
	texture:SetVertexColor(1, 1, 1)
	if status == "available" then
		texture:SetTexture(AVAILABLE_ICON)
	elseif status == "active" then
		texture:SetTexture(ACTIVE_ICON)
		texture:SetAlpha(ns.Ready(quest) and 1 or 0.45)
	elseif status == "done" or status == "passed" then
		Skin.GlyphOn(texture, "check")
		texture:SetVertexColor(C.good[1], C.good[2], C.good[3])
	elseif status == "locked" or status == "level" then
		Skin.GlyphOn(texture, "dot")
		texture:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
	else
		return texture:Hide()
	end
	texture:Show()
end

-- The quests -----------------------------------------------------------------------------------------

-- The filter: all, to take, in your log; done ones hidden or not (kept for each character).
local function Filter()
	local state = State()
	return state.filter or "all", state.hideDone ~= false
end
local function Kept(node, filter, hideDone)
	local status = node.status
	if filter == "take" then return status == "available" end
	if filter == "log" then return status == "active" end
	if hideDone and (status == "done" or status == "passed" or status == "closed") then return false end
	return true
end

-- The tree as the filter leaves it: each quest stepped right by the quests above it still shown; the lines of
-- its chain (a rail down from each step that goes on below, an elbow to each quest). always: a quest asked for,
-- shown whatever the filter says.
local function Filtered(searched, always)
	local list = {}
	if searched then
		for _, node in ipairs(tree) do
			node.drawDepth = 0
			list[#list + 1] = node
		end
	else
		local filter, hideDone = Filter()
		local stack = {}
		for _, node in ipairs(tree) do
			while stack[1] and stack[#stack].depth >= node.depth do table.remove(stack) end
			local depth = 0
			for _, above in ipairs(stack) do if above.kept then depth = depth + 1 end end
			local kept = Kept(node, filter, hideDone) or node.quest.id == always
			stack[#stack + 1] = { depth = node.depth, kept = kept }
			if kept then
				node.drawDepth = math.min(depth, MAX_INDENT)
				list[#list + 1] = node
			end
		end
	end
	-- (from the bottom: a column goes on while a quest below hangs from it)
	local open = {}
	for index = #list, 1, -1 do
		local node = list[index]
		local depth = node.drawDepth
		node.rails = {}
		for column = 0, depth - 2 do node.rails[column] = open[column] or false end
		node.goesOn = depth > 0 and open[depth - 1] or false
		for column = depth, MAX_INDENT do open[column] = false end
		if depth > 0 then open[depth - 1] = true end
	end
	return list
end

-- A row's own pieces (made once): the sign, the level, the chain's lines, the chip.
local function Pieces(row)
	if row.sign then return row end
	row.sign = row:CreateTexture(nil, "ARTWORK")
	row.sign:SetSize(SIGN, SIGN)
	row.level = Skin.Text(row, "GameTooltipTextSmall", "soft")
	row.level:SetWidth(LEVEL_WIDTH)
	row.level:SetJustifyH("RIGHT")
	row.rails = {}
	for column = 0, MAX_INDENT - 1 do
		local rail = row:CreateTexture(nil, "BORDER")
		rail:SetColorTexture(C.label[1], C.label[2], C.label[3], 0.3)
		rail:SetWidth(1)
		row.rails[column] = rail
	end
	row.elbow = row:CreateTexture(nil, "BORDER")
	row.elbow:SetColorTexture(C.label[1], C.label[2], C.label[3], 0.3)
	row.elbow:SetSize(6, 1)
	row.status = Skin.Chip(row)
	row.status:SetPoint("RIGHT", row.cells.chip, "RIGHT", 0, 0)
	return row
end

-- The chain's lines of a row: rails going down, the last one ending at the row's middle with an elbow.
local function Rails(row, node)
	local depth = node and node.drawDepth or 0
	for column = 0, MAX_INDENT - 1 do
		local rail = row.rails[column]
		local x = 6 + column * INDENT + 4
		local own = column == depth - 1
		local through = node and (column < depth - 1 and node.rails[column] or own)
		rail:SetShown(through and true or false)
		if through then
			rail:ClearAllPoints()
			rail:SetPoint("TOPLEFT", row, "TOPLEFT", x, 2)
			if own and not node.goesOn then
				rail:SetPoint("BOTTOMLEFT", row, "LEFT", x, 0)
			else
				rail:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, -2)
			end
		end
	end
	row.elbow:SetShown(depth > 0)
	if depth > 0 then
		row.elbow:ClearAllPoints()
		row.elbow:SetPoint("LEFT", row, "LEFT", 6 + (depth - 1) * INDENT + 4, 0)
	end
end

-- Each quest: its sign, its level in its difficulty's color, its name (the place's own brighter than the ones
-- that lead to them), a chip of where you stand; stepped right by its place in its chain.
local function DrawQuests()
	if not questList then return end
	local offset = questList:Clamp(#shown)
	for index, row in ipairs(questList.rows) do
		Pieces(row)
		local node = shown[index + offset]
		local chip, tone
		if node then
			local quest = node.quest
			local depth = node.drawDepth or 0
			node.name = ns.QuestName(quest)
			node.indent = depth * INDENT + SIGN + 4 + LEVEL_WIDTH + 8
			local done = node.status == "done" or node.status == "passed"
			node.color = done and STATUS.closed or node.dungeon and C.text or C.soft
			-- A reward better for you: the green arrow (not on a quest behind you).
			local better = not done and node.status ~= "closed" and ns.RewardUpgrade(quest)
			if better then node.name = node.name .. "  " .. UPGRADE end
			-- (one of Forever's own: its level when the game said it)
			local level = quest.questLevel
			row.level:SetText(level and tostring(level) or (quest.seen and "?" or ""))
			local c = level and Difficulty(level) or C.muted
			row.level:SetTextColor(c[1], c[2], c[3])
			row.sign:ClearAllPoints()
			row.sign:SetPoint("LEFT", row, "LEFT", 6 + depth * INDENT, 0)
			row.level:ClearAllPoints()
			row.level:SetPoint("LEFT", row.sign, "RIGHT", 4, 0)
			ns.SetSign(row.sign, quest, node.status)
			row.level:Show()
			chip, tone = ns.StatusChip(quest, node.status)
			-- (another of a choice taken: the whole row faded)
			row:SetAlpha(node.status == "closed" and 0.4 or 1)
			-- (hovered: its whole name, where you stand, its levels, its step in its chain, what holds it back,
			-- who was seen giving it)
			local tip = { ns.QuestName(quest), StatusText(node) }
			if quest.seen then
				if quest.questLevel then tip[#tip + 1] = L.LEVEL:format(quest.questLevel) end
				tip[#tip + 1] = L.SEEN_AT:format(quest.seen.name or "?")
			else
				tip[#tip + 1] = L.LEVELS_LINE:format(quest.questLevel or 0, quest.requiredLevel or 0)
			end
			local step, steps = ns.ChainStep(quest)
			if step then tip[#tip + 1] = L.CHAIN_STEP:format(step, steps) end
			if node.status == "locked" then
				local holds = ns.Missing(quest)
				if holds[1] then tip[#tip + 1] = L.STILL_NEEDS:format(table.concat(holds, quest.any and " / " or ", ")) end
			end
			if better then tip[#tip + 1] = L.HAS_UPGRADE end
			if node.place then tip[#tip + 1] = node.place end
			node.tip = tip
		else
			row.sign:Hide()
			row.level:Hide()
		end
		Rails(row, node)
		row:Fill(node, node ~= nil and node == chosenQuest, node and { chip = "" })
		row.status:Set(node and chip or nil, tone)
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

-- The header ------------------------------------------------------------------------------------------------

-- What a place holds for you: its own quests to take, in your log, done, of how many.
local function Counts(list)
	local counts = { take = 0, log = 0, done = 0, total = 0 }
	for _, node in ipairs(list) do
		if node.dungeon then
			counts.total = counts.total + 1
			local status = node.status
			if status == "available" then counts.take = counts.take + 1
			elseif status == "active" then counts.log = counts.log + 1
			elseif status == "done" or status == "passed" then counts.done = counts.done + 1 end
		end
	end
	return counts
end

local function Sign(file, size) return ("|T%s:%d:%d|t"):format(file, size or 14, size or 14) end
local function Number(value) return Colorize(tostring(value), C.text) end

-- The counts in words, each after the game's sign: "! 4 to take   ? 2 in log   (check) 9 done".
local function CountsLine(counts)
	return table.concat({
		Sign(AVAILABLE_ICON) .. " " .. L.COUNT_TAKE:format(Number(counts.take)),
		Sign(ACTIVE_ICON) .. " " .. L.COUNT_LOG:format(Number(counts.log)),
		Sign(DONE_ICON, 12) .. " " .. L.COUNT_DONE:format(Number(counts.done)),
	}, "     ")
end

-- The header's pieces in place: the main action at the right of the name; the counts; the entrance on a line
-- of its own, its quiet pin at the line's right; the bar; the filter.
function ns.PlaceHeaderButtons()
	header.name:ClearAllPoints()
	header.name:SetPoint("TOPLEFT")
	if header.main:IsShown() then
		header.name:SetPoint("RIGHT", header.main, "LEFT", -10, 0)
	else
		header.name:SetPoint("RIGHT", header, "RIGHT", 0, 0)
	end
	header.entrance:ClearAllPoints()
	header.entrance:SetPoint("TOPLEFT", header, "TOPLEFT", 0, -54)
	if header.pin:IsShown() then
		header.entrance:SetPoint("RIGHT", header.pin, "LEFT", -8, 0)
	else
		header.entrance:SetPoint("RIGHT", header, "RIGHT", 0, 0)
	end
end

-- A progress bar (the kit's line): done of all.
local function DrawBar(bar, done, total) bar:Set(total > 0 and done / total or 0) end

-- The place chosen: its entrance, its quests. The same one drawn again (a quest taken or given back):
-- the list stays where it was, the quest chosen with it.
local function ShowDungeon()
	local entry = chosenDungeon
	header:SetShown(entry ~= nil)
	questList:SetShown(entry ~= nil)
	window.pick:SetShown(entry == nil)
	if not entry then
		shownPlace, wantedQuest = nil, nil
		return
	end
	local place = kind .. ":" .. entry.dungeon.id
	local same, before = place == shownPlace, chosenQuest and chosenQuest.quest.id
	shownPlace = place
	tree = ns.Tree(entry.dungeon.id, kind)
	-- (a quest asked from elsewhere is shown whatever the filter says)
	shown = Filtered(false, wantedQuest)
	header.name:SetText(entry.dungeon.name)
	local counts = Counts(tree)
	header.counts:SetText(CountsLine(counts))
	header.counts:Show()
	header.progress:SetText(("%d / %d"):format(counts.done, counts.total))
	header.bar:Show()
	header.progress:Show()
	DrawBar(header.bar, counts.done, counts.total)
	header.filter:Show()
	header.hideDone:Show()
	local entrance = kind == "dungeons" and ns.Entrance(entry.dungeon) or nil
	local around = kind == "dungeons" and ns.AreaName(entrance and entrance.area or entry.dungeon.zone) or ""
	header.entrance:SetText(entrance and L.ENTRANCE:format(L.WHERE:format(around or "?", entrance.x, entrance.y)) or "")
	-- One main action: the route through its quests with Wanderer Maps, else the way to its door.
	local maps = ns.Maps() ~= nil and ns.Maps().Route ~= nil
	header.main.action = maps and "route" or entrance and "pin" or nil
	header.main:SetText(maps and L.QUEST_ROUTE or L.PIN_ENTRANCE)
	header.main:Fit()
	header.main:SetShown(header.main.action ~= nil)
	header.pin:SetShown(maps and entrance ~= nil)
	ns.PlaceHeaderButtons()
	local filter = Filter()
	header.filter:Select(filter)
	header.hideDone:Refresh()
	header.hideDone:SetEnabled(filter == "all")
	header.hideDone:SetAlpha(filter == "all" and 1 or 0.4)
	questList.empty:SetText(#tree == 0 and (kind == "zones" and L.NONE_ZONE or kind == "class" and L.NONE_CLASS or L.NONE) or L.FILTER_EMPTY)
	questList.empty:SetShown(#shown == 0)
	chosenQuest = nil
	local wanted = wantedQuest
	wantedQuest = nil
	if wanted or same then
		local target = wanted or before
		for _, node in ipairs(shown) do
			if node.quest.id == target then chosenQuest = node end
		end
	end
	if not chosenQuest or wanted then
		chosenQuest = chosenQuest or FirstQuest(shown)
		-- (the list from the top, down to it when it is further)
		local at = 0
		for index, node in ipairs(shown) do
			if node == chosenQuest then at = index end
		end
		questList.offset = at > questList.count and at - 1 or 0
	end
	DrawQuests()
	-- (the quest asked: its sheet opened)
	if wanted and chosenQuest and chosenQuest.quest.id == wanted then ns.ShowSheet(chosenQuest.quest, window) else ns.RefreshSheet() end
end

-- The places -----------------------------------------------------------------------------------------

-- A place's row: its small bar of what is done there (made once).
local function PlaceBar(row)
	if row.bar then return row.bar end
	local bar = Skin.ProgressLine(row, 3)
	bar:SetWidth(BAR_WIDTH)
	bar:SetPoint("RIGHT", row.cells.bar, "RIGHT", 0, 0)
	row.bar = bar
	return bar
end

local function DrawPlaces()
	if not dungeonList then return end
	local offset = dungeonList:Clamp(#places)
	for index, row in ipairs(dungeonList.rows) do
		local entry = places[index + offset]
		local values
		local bar = PlaceBar(row)
		if entry then
			local levels = entry.levels
			local finished = levels.done == levels.total
			entry.name = entry.dungeon.raid and (entry.dungeon.name .. "  " .. Colorize(L.RAID, FAINT)) or entry.dungeon.name
			entry.color = finished and STATUS.closed or levels.low and Difficulty(levels.low) or C.text
			local range = levels.low and (levels.low == levels.high and tostring(levels.low) or (levels.low .. "-" .. levels.high)) or ""
			values = {
				range = Colorize(range, FAINT),
				take = (levels.take or 0) > 0 and Colorize(tostring(levels.take), C.gold) or "",
				bar = "",
			}
			entry.tip = { entry.dungeon.name, L.PLACE_TIP:format(levels.take or 0, levels.log or 0, levels.done, levels.total) }
			DrawBar(bar, levels.done, levels.total)
		end
		bar:SetShown(entry ~= nil)
		row:Fill(entry, entry ~= nil and entry == chosenDungeon, values)
	end
end

local SearchQuests
local searching -- the words searched, while some are

local function ChooseDungeon(entry)
	-- (a place clicked: the search let go, its quests shown)
	if searching then
		searching = nil
		window.search:SetText("")
	end
	chosenDungeon = entry
	chosenBy[kind] = entry.dungeon.id
	DrawPlaces()
	ShowDungeon()
end

-- The tabs' links: the one shown in gold.
local function DrawTabs()
	for _, tab in ipairs(TABS) do tabs:SetLabel(tab[1], TabName(tab)) end
	tabs:Select(kind)
	window.pick:SetText(kind == "zones" and L.PICK_ZONE or kind == "class" and L.PICK_CLASS or L.PICK)
end

-- Every place of the tab with quests for you, by level (where you stand as last read: ns.ReadYou).
local function Fill()
	if searching then return SearchQuests(searching) end
	kind = kind or State().tab or "class"
	DrawTabs()
	-- The gear tab: two character sheets in place of the places and their quests; the books' tab: the books.
	local gear, books = kind == "gear", kind == "books"
	dungeonList:SetShown(not (gear or books))
	window.rule:SetShown(not (gear or books))
	window.right:SetShown(not (gear or books))
	gearView:SetShown(gear)
	libraryView:SetShown(books)
	-- (a sheet open from either: where you stand with its quest, drawn again too)
	if gear or books then ns.RefreshSheet() end
	if gear then return ns.DrawGear() end
	if books then return ns.DrawLibrary() end
	places = {}
	for _, dungeon in ipairs(ns.Places(kind)) do
		-- (its summary only: the tree is made for the place chosen)
		local levels = ns.Summary(dungeon.id, kind)
		if levels.total > 0 then places[#places + 1] = { dungeon = dungeon, levels = levels } end
	end
	-- (the places by level)
	table.sort(places, function(a, b)
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

-- The place's quests as a route of Wanderer Maps: who gives the ones you may take, who takes back the ones
-- you carry; ordered from where you stand. Each step says why (to take, to hand in) and which quest.
function ns.QuestRoute()
	local maps = ns.Maps()
	if not (maps and maps.Route and tree) then return end
	local stops, seen = {}, {}
	local function Add(who, title, step, quest)
		if not (who and who.x and who.y and who.zone) then return end
		local map = ns.MapOf(who.zone)
		if not map then return end
		local key = map .. ":" .. who.x .. ":" .. who.y
		if seen[key] then return end
		seen[key] = true
		stops[#stops + 1] = { map = map, x = who.x / 100, y = who.y / 100, title = title, kind = step, quest = quest.id,
			label = ns.QuestName(quest) }
	end
	for _, node in ipairs(tree) do
		if node.status == "available" then
			local giver = ns.Giver(node.quest)
			Add(giver, giver and giver.name or ns.QuestName(node.quest), "take", node.quest)
		elseif node.status == "active" then
			local ender = ns.Ender(node.quest)
			Add(ender, ender and ender.name or ns.QuestName(node.quest), "handin", node.quest)
		end
	end
	-- (Wanderer Maps says the route made, or asks first when one of several steps would go)
	if not stops[1] or maps.Route(stops) == 0 then return W.Print(L.QUEST_ROUTE_NONE) end
end

-- The quests whose name holds the words, from every place of every tab (the first eighty), listed in the
-- right part, each with its place; nothing searched: the tab as it was.
local SEARCH_MOST = 80
function SearchQuests(text)
	text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if #text < 2 then
		if searching then
			searching = nil
			Fill()
		end
		return
	end
	-- (from the gear or the books: the places of the dungeons on the left, as the results are theirs)
	if kind == "gear" or kind == "books" then
		searching = nil
		kind = "dungeons"
		Fill()
	end
	-- (the same words again, a quest taken meanwhile: the list stays where it was)
	local again = searching == text
	searching = text
	-- (accents and capitals aside: "foret" finds "Forêt"; each place's own quests only, no tree built)
	local Fold = U.Fold or U.Upper
	tree = ns.Search(Fold(text), Fold, SEARCH_MOST)
	shown = Filtered(true)
	gearView:Hide()
	libraryView:Hide()
	dungeonList:Show()
	window.rule:Show()
	window.right:Show()
	header:Show()
	header.name:SetText(L.SEARCH_RESULTS:format(#tree))
	-- (a search: every quest found, whatever the filter)
	header.entrance:SetText("")
	for _, piece in ipairs({ header.main, header.pin, header.counts, header.bar, header.progress, header.filter, header.hideDone }) do
		piece:Hide()
	end
	ns.PlaceHeaderButtons()
	window.pick:Hide()
	questList:Show()
	questList.empty:SetText(L.SEARCH_NONE)
	questList.empty:SetShown(#tree == 0)
	-- (the same words again: the quest chosen found again in the new list)
	local before = again and chosenQuest and chosenQuest.quest.id
	chosenQuest = nil
	if before then
		for _, node in ipairs(tree) do
			if node.quest.id == before then chosenQuest = node end
		end
	else
		questList.offset = 0
	end
	DrawQuests()
	ns.RefreshSheet()
end

-- A tab shown: its places, the one chosen there.
local function ShowTab(name)
	local cleared = false
	if window and (window.search:GetText() or "") ~= "" then
		cleared = searching ~= nil
		searching = nil
		window.search:SetText("")
	end
	if name == kind then
		if cleared then Fill() end
		return
	end
	kind = name
	State().tab = name
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
	libraryView:Fit(height)
end

-- Shown: where you stand read again, the lists. (the rewards of your log are read when the window opens, not at
-- each quest taken or given back)
local function Shown()
	if not ns.HasData() then return end
	ns.ReadYou()
	-- (your gear, role or weights may have changed meanwhile)
	if kind == "gear" then ns.ForgetGear() end
	Fill()
end

-- The filter changed: kept for this character, the list drawn again.
local function SetFilter(key, value)
	State()[key] = value
	questList.offset = 0
	ShowDungeon()
end

-- The header of the place chosen: its name and main action; what is there for you, its entrance; a bar of
-- what is done; the filter.
local function MakeHeader(right)
	header = CreateFrame("Frame", nil, right)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(HEADER - 8)
	header:Hide()
	header.name = Skin.Text(header, "GameTooltipHeaderText", "gold")
	header.name:SetPoint("TOPLEFT")
	header.name:SetJustifyH("LEFT")
	if header.name.SetWordWrap then header.name:SetWordWrap(false) end
	-- (the main action: the route through its quests with Wanderer Maps, else the way to the door)
	-- (the way to the door of the place chosen: the main action without Wanderer Maps, the quiet pin with it)
	local function GoEntrance()
		local entrance = chosenDungeon and ns.Entrance(chosenDungeon.dungeon)
		if entrance then ns.GoOrSay(entrance.map, entrance.x, entrance.y, chosenDungeon.dungeon.name) end
	end
	header.main = Skin.Button(header, L.QUEST_ROUTE, function(self)
		if self.action == "route" then return ns.QuestRoute() end
		GoEntrance()
	end, "main")
	header.main:SetHeight(28)
	header.main:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
	Skin.Tooltip(header.main, function(self) return self.action == "route" and L.QUEST_ROUTE_DESC or L.PIN_DESC end)
	header.counts = Skin.Text(header, "GameTooltipTextSmall", "soft")
	header.counts:SetPoint("TOPLEFT", header, "TOPLEFT", 0, -34)
	-- The entrance, on a line of its own (one line, never under the button).
	header.entrance = Skin.Text(header, "GameTooltipTextSmall", "muted")
	header.entrance:SetJustifyH("LEFT")
	if header.entrance.SetWordWrap then header.entrance:SetWordWrap(false) end
	-- (with Wanderer Maps the route is the main action: the door's pin stays at hand, quiet, at the line's right)
	header.pin = Skin.SmallButton(header, L.PIN_ENTRANCE, GoEntrance, L.PIN_DESC, 20)
	header.pin:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, -50)
	header.pin:Hide()
	-- The bar: what is done of all its quests.
	header.bar = Skin.ProgressLine(header, 4)
	header.bar:SetPoint("TOPLEFT", header, "TOPLEFT", 0, -76)
	header.bar:SetPoint("RIGHT", header, "RIGHT", -64, 0)
	header.progress = Skin.Text(header, "GameTooltipTextSmall", "soft")
	header.progress:SetPoint("LEFT", header.bar, "RIGHT", 10, 0)
	-- The filter: all, to take, in your log; the done ones hidden (with all).
	header.filter = Skin.Choices(header, { { "all", L.FILTER_ALL }, { "take", L.FILTER_TAKE }, { "log", L.FILTER_LOG } },
		function(key) SetFilter("filter", key) end, 24)
	header.filter:SetPoint("TOPLEFT", header, "TOPLEFT", 0, -90)
	header.hideDone = Skin.Check(header, L.HIDE_DONE, function() return State().hideDone ~= false end,
		function(value) SetFilter("hideDone", value and true or false) end, L.HIDE_DONE_DESC)
	header.hideDone:SetPoint("LEFT", header.filter, "RIGHT", 16, 0)
end

local function Create()
	window = Skin.CreateWindow("WandererQuestsWindow", "MEDIUM")
	Skin.Sounds(window, Skin.SOUNDS.open, Skin.SOUNDS.close)
	Skin.Dress(window, { "CENTER", UIParent, "CENTER", 0, 40 }, "questsPos")
	local saved = State().size
	-- (never taller than the screen: its foot always in reach)
	local maxHeight = math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, (UIParent:GetHeight() or MAX_HEIGHT) - 48))
	window:SetSize(Skin.Within(saved and saved[1] or WIDTH, MIN_WIDTH, MAX_WIDTH), Skin.Within(saved and saved[2] or HEIGHT, MIN_HEIGHT, maxHeight))
	local _, title, margin = Skin.Header(window, "Wanderer", L.QUESTS, { settings = "ext:quests" })
	local list = {}
	for _, tab in ipairs(TABS) do list[#list + 1] = { tab[1], TabName(tab) } end
	tabs = Skin.Tabs(window, list, ShowTab)
	tabs:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, 0)
	-- A quest by its name, from every tab.
	local searchSoon = U.Debounce(0.3, function() SearchQuests(window.search:GetText()) end)
	window.search = Skin.CreateInput(window, nil, 60, { hint = L.QUEST_SEARCH, onChange = function() searchSoon() end })
	window.search:SetSize(200, 24)
	window.search:SetPoint("TOPRIGHT", window, "TOPRIGHT", -(margin + 74), -(margin + 6))
	-- (the help beside the cog, the search left of it; a controller reads its own keys)
	local help = Skin.Help and Skin.Help(window, L.HELP_TIP, "HEADING")
	if help then
		help:HookScript("OnEnter", function(self)
			if U.UsingPad and U.UsingPad() then Skin.ShowTip(self, L.HELP_TIP_PAD, "ANCHOR_BOTTOM") end
		end)
	end
	-- Left: the places, their levels, how many to take, a small bar of what is done.
	dungeonList = Skin.Table(window, {
		width = LEFT_WIDTH, rows = MAX_ROWS, rowHeight = ROW, titles = false, icon = false, onClick = ChooseDungeon, onDraw = DrawPlaces,
		columns = { { key = "range", width = 46 }, { key = "take", width = 20 }, { key = "bar", width = BAR_WIDTH } },
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
	MakeHeader(right)
	questList = Skin.Table(right, {
		width = WIDTH - LEFT_WIDTH - GAP - margin * 2, rows = MAX_ROWS, rowHeight = QUEST_ROW, titles = false, icon = false,
		onClick = ChooseQuest, onDraw = DrawQuests, columns = { { key = "chip", width = 84 } },
	})
	questList:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
	questList:SetPoint("RIGHT", right, "RIGHT", 0, 0)
	questList:Hide()
	-- The gear tab's sheets, across the window.
	gearView = ns.GearView(window, window:GetWidth() - margin * 2)
	gearView:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -(margin + TOP))
	gearView:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin, margin)
	-- The books' tab, across the window.
	libraryView = ns.LibraryView(window, window:GetWidth() - margin * 2)
	libraryView:SetPoint("TOPLEFT", window, "TOPLEFT", margin, -(margin + TOP))
	libraryView:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin, margin)
	-- Its corner: dragged, the window grows or shrinks, the lists with it; its size and place kept.
	Skin.Resizable(window, {
		minWidth = MIN_WIDTH, minHeight = MIN_HEIGHT, maxWidth = MAX_WIDTH, maxHeight = maxHeight,
		onResized = function(width, height)
			State().size = { width, height }
			window:SetScale(Skin.FitScale(window))
		end,
	})
	window:HookScript("OnSizeChanged", function(self)
		local skin = Skin.Get(window)
		if skin then skin:Layout() end
		Fit()
		if gearView then gearView:Resize((self:GetWidth() or WIDTH) - margin * 2) end
	end)
	Fit()
	-- Each time it shows: its scale (smaller when it would not fit the screen), where you stand.
	window:HookScript("OnShow", function(self)
		self:SetScale(Skin.FitScale(self))
		ns.HearItems(true)
		ns.LearnAllLog()
		Shown()
	end)
	window:HookScript("OnHide", function() ns.HearItems(false) end)
	Skin.Get(window):Layout()
end

function ns.Window() return window end
function ns.ShownQuests() return shown end -- (tests: the list as the filter leaves it)

function ns.Toggle()
	if window and window:IsShown() then return window:Hide() end
	if Off() then return end
	if not window then Create() end
	window:Show()
end

function ns.Open()
	if Off() then return end
	if not window then Create() end
	if window:IsShown() then Shown() else window:Show() end
end

-- A place shown here: its tab, it chosen (a search going on let go, the place shown instead).
function ns.RevealPlace(tab, place)
	if not ns.HasData() or Off() then return end
	if not window then Create() end
	if searching then
		searching = nil
		window.search:SetText("")
	end
	kind = tab
	State().tab = tab
	chosenBy[tab] = place
	if window:IsShown() then Shown() else window:Show() end
end

-- A quest of your log shown here: its tab, its place, it chosen, its sheet open (said when no list has it).
function ns.Reveal(questID)
	questID = tonumber(questID)
	if not (questID and ns.HasData()) or Off() then return end
	ns.ReadYou()
	local tab, place = ns.PlaceOf(questID)
	if not tab then
		return W.Print(L.NOT_LISTED)
	end
	wantedQuest = questID
	ns.RevealPlace(tab, place)
end

-- The game's quest log ----------------------------------------------------------------------------------

-- Beside a quest's details (the map's log, and its window apart), a small button; in the right-click menus of
-- the log and the tracker, a line: the quest opened here. The data is read only when it is asked.
local function LogButton(parent, place, questOf)
	local button = Skin.Button(parent, L.SHOW_HERE, function() ns.Reveal(questOf()) end)
	place(button)
	button:SetFrameLevel(parent:GetFrameLevel() + 10)
	Skin.Tooltip(button, L.SHOW_HERE_DESC, "ANCHOR_TOP")
	-- (Wanderer off: none on the game's windows)
	button:SetShown(Settings() ~= nil)
	parent:HookScript("OnShow", function() button:SetShown(Settings() ~= nil) end)
	return button
end

local attached = {}
-- Wanderer turned off or on again: the buttons on the game's windows with it.
local function LogButtonsShown()
	for _, which in ipairs({ "map", "popup" }) do
		if attached[which] then attached[which]:SetShown(Settings() ~= nil) end
	end
end
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
		local function AddLine(owner, root, tracker)
			-- (Questie's tracker in the game's place: its menu left alone)
			if tracker and W.Yields and W.Yields("questTracker") then return end
			if not Settings() then return end -- (Wanderer off)
			local id = type(owner) == "table" and Clean(owner.questID or owner.id)
			if type(id) ~= "number" or not (root and root.CreateButton) then return end
			if root.CreateDivider then root:CreateDivider() end
			root:CreateButton(L.SHOW_HERE, function() ns.Reveal(id) end)
		end
		pcall(Menu.ModifyMenu, "MENU_QUEST_MAP_LOG_TITLE", function(owner, root) AddLine(owner, root, false) end)
		pcall(Menu.ModifyMenu, "MENU_QUEST_OBJECTIVE_TRACKER", function(owner, root) AddLine(owner, root, true) end)
	end
	return attached.map and attached.popup and attached.menus
end

-- Init --------------------------------------------------------------------------------------------------

-- fn run once, a moment after the last call (made at the first call, never at loading: an older Wanderer
-- loads Wanderer Quests too, which then stays asleep).
local function Later(delay, fn)
	local run
	return function()
		run = run or U.Debounce(delay, fn)
		run()
	end
end

-- A quest taken, given back, a level gained: where you stand, drawn again (once, a moment after).
local Again = Later(0.5, function()
	if window and window:IsShown() then Shown() end
end)
-- An item the game was fetching (a reward): the quests drawn again, their arrows with them.
local Redraw = Later(0.3, function()
	if window and window:IsShown() then DrawQuests() end
end)

-- A reward arrived on the gear tab: the gear read again, only it (once, a moment after).
local GearAgain = Later(0.5, function()
	if window and window:IsShown() and kind == "gear" then Fill() end
end)

-- A book's name arrived, a book picked up: the books drawn again (once, a moment after).
local BooksAgain = Later(0.3, function()
	if window and window:IsShown() and kind == "books" then ns.DrawLibrary() end
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
		if not told[dungeon.id] and zone and ns.Plain(zone) == here then
			local count, levels = ns.Waiting(dungeon)
			if count > 0 and levels.low and level >= levels.low - 5 and level <= (levels.high or 60) + 2 then
				told[dungeon.id] = true
				local id = dungeon.id
				W.Toast(dungeon.name, L.REMIND_TEXT:format(count), { kicker = L.QUESTS, duration = 6, corner = true,
					kind = "questsDungeon", kindName = L.REMIND, onClick = function() ns.RevealPlace("dungeons", id) end })
			end
		end
	end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
	if event == "ZONE_CHANGED_NEW_AREA" then return NearDungeon() end
	if event == "BAG_UPDATE_DELAYED" then return BooksAgain() end
	-- (the game's quest windows loaded later: the buttons put there then)
	if event == "ADDON_LOADED" then
		if Attach() then events:UnregisterEvent("ADDON_LOADED") end
		return
	end
	if event == "GET_ITEM_INFO_RECEIVED" then -- (heard only while the window is shown)
		-- (a reward arrived: the gear tab read again, only it; an item the server could not send: nothing)
		local itemID, success = ...
		if not ns.Awaited(itemID, success) then return end
		ns.ForgetGear()
		if kind == "gear" then
			GearAgain()
		elseif kind == "books" then
			BooksAgain()
		else
			Redraw()
		end
		return
	end
	if event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_LEVEL_UP" or event == "QUEST_TURNED_IN" then ns.ForgetGear() end
	-- (the givers on the world map: one quest less or more to take)
	if event ~= "PLAYER_EQUIPMENT_CHANGED" then ns.MapPinsSoon() end
	if window and window:IsShown() then Again() end
end)

-- The names and rewards the game sends (often, everywhere): heard only while the window is shown.
function ns.HearItems(on)
	if on then events:RegisterEvent("GET_ITEM_INFO_RECEIVED") else events:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
end

function ns.Init()
	if not (W and W.RegisterExtension) then return end
	-- (API 21: the tracker's title, objective and done roles; API 19: Util.MapOfArea, Skin.Beside; API 17: W.ChangeEverywhere; API 16: Util.ChatInsert; API 15: the kit's "⋯" and cards, its progress lines, the screen-fitted scale, Util.AfterFight)
	if (W.API or 1) < 21 then return W.Print(L.NEEDS_WANDERER) end
	-- (a weight, what you play, your talents changed: the gear judged again, at once when shown)
	W.OnComparisonChanged(function()
		ns.ForgetGear()
		if window and window:IsShown() then Shown() end
	end)
	W.RegisterExtension({
		key = "quests",
		slash = "/wquests",
		addon = ADDON,
		title = L.QUESTS,
		news = L.NEWS_LINES,
		defaults = { remind = false, foldStory = true, filter = "all", hideDone = true, mapGivers = false, mapLow = false,
			-- The quests followed on the screen, in the game's list's place.
			tracker = true, trackerGroup = true, trackerCompact = false, trackerRest = true, trackerCombat = true,
			trackerHeight = 420, trackerScale = 1, trackerBackground = false },
		ranges = { ["quests.trackerHeight"] = { 200, 800, 20 }, ["quests.trackerScale"] = { 0.8, 1.6, 0.05 } },
		-- (its list in the game's place: Wanderer's own look of the game's list has nothing to dress then)
		takes = { trackerLook = function() return ns.TrackerOn() end },
		launcher = { label = L.QUESTS, open = function() ns.Toggle() end },
		-- (Wanderer turned off or on, another profile: the list on the screen, the givers on the map, the buttons
		-- on the game's windows as it says now)
		refresh = function()
			ns.RefreshTracker()
			ns.RefreshMapPins()
			LogButtonsShown()
		end,
		-- (the window on top; then the world map, the quest sheet, the notices)
		options = function(o)
			o.Button(L.QUESTS, L.OPEN, L.OPEN_DESC, function()
				o.CloseSettings()
				ns.Open()
			end)
			-- The quests followed on the screen.
			o.Header(L.SECTION_TRACKER)
			local function RedrawTracker() ns.RefreshTracker() end
			local tracker = o.Checkbox("quests", "tracker", L.TRACKER, L.TRACKER_DESC, RedrawTracker)
			o.Yield(tracker, "questTracker")
			local trackerOn = o.IsOn("quests", "tracker")
			for _, key in ipairs({ "trackerGroup", "trackerCompact", "trackerRest", "trackerCombat", "trackerBackground" }) do
				local upper = key:gsub("^tracker", "TRACKER_"):upper()
				local row = o.Checkbox("quests", key, L[upper], L[upper .. "_DESC"], RedrawTracker)
				o.Under(row, tracker, trackerOn)
			end
			o.Under(o.Slider("QUESTS_TRACKER_HEIGHT", L.TRACKER_HEIGHT, "quests.trackerHeight", "%d", RedrawTracker), tracker, trackerOn)
			o.Under(o.Slider("QUESTS_TRACKER_SCALE", L.TRACKER_SCALE, "quests.trackerScale", function(value)
				return ("%d %%"):format(math.floor(value * 100 + 0.5))
			end, RedrawTracker), tracker, trackerOn)
			-- (placing is a mouse's: not offered under the pad, whenever it is taken up)
			if W.PlaceMode then
				local place = o.Under(o.Button(L.TRACKER_PLACE, L.TRACKER_PLACE_BUTTON, L.TRACKER_PLACE_DESC, function()
					o.CloseSettings()
					if W.PlaceMode then W.PlaceMode() end
				end), tracker, trackerOn)
				if type(place) == "table" then place.hidden = function() return U.UsingPad and U.UsingPad() or false end end
			end
			o.Header(L.SECTION_WORLD_MAP)
			-- (the givers on the world map: a display, on, left to Questie when it draws its own; the lower
			-- quests a choice under it)
			local givers = o.Checkbox("quests", "mapGivers", L.MAP_GIVERS, L.MAP_GIVERS_DESC, function() ns.RefreshMapPins() end)
			o.Yield(givers, "questGivers")
			o.Under(o.Checkbox("quests", "mapLow", L.MAP_LOW, L.MAP_LOW_DESC, function() ns.RefreshMapPins() end), givers,
				o.IsOn("quests", "mapGivers"))
			o.Header(L.SECTION_SHEET)
			o.Checkbox("quests", "foldStory", L.FOLD_STORY, L.FOLD_STORY_DESC, function() ns.RefreshSheet() end)
			o.Header(L.SECTION_NOTICES)
			o.Checkbox("quests", "remind", L.REMIND, L.REMIND_DESC)
		end,
	})
	-- (where the items asked come from: under their tooltips, a card on a click)
	if ns.InitSources then ns.InitSources() end
	-- For the other addons (Wanderer Maps): a quest shown here, its sheet open.
	-- (Wanderer off: each answers nothing, quietly: no sheet, no quest, empty lists)
	local function Live() return Settings() ~= nil end
	_G.WandererQuests = { Reveal = function(id) if Live() then ns.Reveal(id) end end,
		-- (Wanderer Maps' atlas: the dungeon doors { name, map, x, y, raid } and the givers on a map { name, x, y, quests })
		Front = function(id) if Live() then ns.PutInFront(id) end end,
		-- (the quest in front of the list, the one you pinned: nil when none)
		InFront = function() return Live() and ns.InFront and ns.InFront() or nil end,
		-- (a quest's sheet beside another addon's window, the atlas: false when this addon does not know the quest)
		Sheet = function(id, beside)
			local quest = Live() and id and ns.HasData() and ns.Quest(id)
			if not (quest and beside) then return false end
			ns.ShowSheet(quest, beside)
			return true
		end,
		HideSheet = function(beside) if ns.SheetOwner() == beside then ns.HideSheet() end end,
		-- (the quest on the sheet beside that window now: nil when closed or beside another)
		SheetQuest = function(beside)
			local quest = Live() and ns.SheetOwner() == beside and ns.SheetQuest()
			return quest and quest.id or nil
		end,
		-- (the map a quest of your log belongs on, when the game does not say)
		QuestMap = function(id)
			local quest = Live() and ns.HasData() and ns.Quest(id)
			return quest and quest.zone and ns.MapOf(quest.zone) or nil
		end,
		Entrances = function() return Live() and ns.EntranceList() or {} end,
		-- (where the creatures your quests ask for stand, who takes a finished one back, on a map)
		Objectives = function(map) return Live() and ns.ObjectivesOn(map) or {} end,
		Givers = function(map)
			local out, settings = {}, W.Settings("quests")
			if not settings then return out end
			ns.ReadYou()
			for _, giver in ipairs(ns.GiversOn(map, settings and settings.mapLow)) do
				local titles = {}
				for _, quest in ipairs(giver.quests) do titles[#titles + 1] = ns.QuestName(quest) end
				out[#out + 1] = { name = giver.who.name or "?", x = giver.x, y = giver.y, count = #giver.quests, titles = titles, quest = giver.quests[1].id }
			end
			return out
		end }
	-- Wanderer's reader, when it has one: a library book says who takes it, or that it was handed in.
	-- (the reading window gives what it knows of the text: its title, the item when read from the bags)
	if W.ReaderNote then W.ReaderNote(function(info) return ns.BookNote(info.title, info.item) end) end
	-- Wanderer's label, when it can: a creature dropping an item one of your quests asks for is one of its objectives.
	if W.QuestUnitDrops then W.QuestUnitDrops(ns.UnitDrops) end
	ns.InitLearn()
	ns.InitGivers()
	ns.InitMapPins()
	ns.InitTracker()
	SLASH_WANDERERQUESTS1 = "/wquests"
	SlashCmdList.WANDERERQUESTS = function() ns.Toggle() end
	ns.ready = true
	for _, event in ipairs({ "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA",
		"PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	if not Attach() then events:RegisterEvent("ADDON_LOADED") end
end

-- Wanderer's key binding (the game's key options, "Wanderer Quests"; none set by default).
BINDING_HEADER_WANDERERQUESTS = "Wanderer Quests"
BINDING_NAME_WANDERERQUESTS_TOGGLE = L.QUESTS
-- (the key does nothing until Wanderer Quests is set up: an older Wanderer leaves it asleep)
function WandererQuests_Toggle() if ns.ready then ns.Toggle() end end

-- (an older Wanderer, without it: said once)
if W and W.WhenLoaded then W.WhenLoaded(ADDON, ns.Init) elseif W and W.Print then W.Print(L.NEEDS_WANDERER) end
