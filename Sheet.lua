local _, ns = ...
local L = ns.L

-- A quest's sheet, beside the window (a quest clicked). On top, its facts: a
-- chip of where you stand, its levels, its step in its chain as dots, what
-- comes before it, a "Ready?" line (your level, the quests before, what you
-- carry), and one main action that follows where you stand (to the giver, to
-- the objective, to hand it in). Then what it asks, in its own words, the
-- items with how many you carry and who drops them, the creatures and objects;
-- its rewards; who gives it and who takes it back; what comes after; its
-- story. A line with a place is followed by a click (Shift+click: a map link
-- in the chat's box, never sent; Ctrl+click: a step of Wanderer Maps' route);
-- its small actions show under the mouse. Below, quietly: everything to
-- Wanderer's reminders, every item to Wanderer Auction's shopping list. Read
-- ahead: a quest still far off is prepared as well as one in your log.

local W = Wanderer
local U = W.Util

local WIDTH = 420
local GAP = 4 -- from the window
local ICON = 16
local DROPPERS = 3 -- creatures named under an item; the others in its "..."
local DOT, DOT_GAP, DOTS_MOST = 6, 4, 12
local ACTIONS = 70 -- room kept at a line's right for its actions under the mouse

local sheet, scroll, content, owner, bar
local shown -- the quest shown
local texts, rows, rules = {}, {}, {} -- made once, used again at each drawing
local used = { texts = 0, rows = 0, rules = 0 }
local pending = {} -- the items shown without a name yet (not refused): drawn again when one comes
local UNTAKEN = { available = true, locked = true, level = true } -- (not taken yet: its story may wait)
local unfolded = {} -- the stories opened anyway, this session
local hooked = {} -- the windows the sheet follows

local C = W.Skin.COLORS -- (Wanderer's colors, by role)
local READY_YES = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"
local READY_NO = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t"

local function Todo() return W.AddTodo ~= nil end
-- Wanderer Auction's list, only while Auction is on (off: nothing it would take is offered). evenOff: the
-- addon itself, to have it say it is off.
local function Shopping(evenOff)
	local auction = _G.WandererAuction
	if not (type(auction) == "table" and auction.AddToShopping) then return nil end
	if not evenOff and auction.IsOn and not auction.IsOn() then return nil end
	return auction
end

-- A place of the data for the reminders: { map, x, y (0 to 1), zone }.
local function TodoPlace(who)
	local map = who and who.zone and who.x and ns.MapOf(who.zone)
	if not map then return nil end
	return { map = map, x = who.x / 100, y = who.y / 100, zone = ns.AreaName(who.zone) }
end

local function Said(added, why)
	if added then
		W.Print(L.ADDED_TODO)
	elseif why == "full" then
		W.Print(L.FULL_TODO)
	else
		W.Print(L.KNOWN_TODO)
	end
end

-- What it asks, to the reminders: an item (how many, you will see how many you carry), a creature or an
-- object; nothing asked: the quest itself, where to go.
local function AddAsk(quest, ask)
	local name = ask.name or ("#" .. ask.id)
	if ask.kind == "Item" then
		return W.AddTodo(L.TODO_LINE:format(name, ns.QuestName(quest)),
			{ key = "wquests:" .. quest.id .. ":i:" .. ask.id, item = ask.id, count = ask.count })
	end
	local text = L.TODO_LINE:format(ask.count > 1 and L.COUNT:format(name, ask.count) or name, ns.QuestName(quest))
	return W.AddTodo(text, { key = "wquests:" .. quest.id .. ":k:" .. ask.id, place = TodoPlace(ask) })
end

local function AddQuest(quest)
	local status = ns.Status(quest)
	local who = status == "active" and ns.Ender(quest) or ns.Giver(quest)
	return W.AddTodo(L.TODO_QUEST:format(ns.QuestName(quest)), { key = "wquests:" .. quest.id, place = TodoPlace(who) })
end

-- Why a step of the route goes there: { kind, quest, label } (Wanderer Maps says it on the step).
local function Why(quest, kind) return { kind = kind, quest = quest.id, label = ns.QuestName(quest) } end

local function Where(who)
	if who.zone and who.x then return L.WHERE:format(ns.AreaName(who.zone) or "?", who.x, who.y) end
	return who.zone and ns.AreaName(who.zone) or nil
end

-- The actions on a place: follow it, a step of the route, a map link in the chat (each said when it cannot).
local Follow, ToRoute, LinkInChat = ns.Follow, ns.SayToRoute, ns.SayLinkInChat

-- Drawing ----------------------------------------------------------------------------------------
-- Nothing is ever cut: each text as wide as the sheet, on as many lines as it needs.

local y -- where the next line goes, from the top of the content
local function Muted(text) return W.Skin.Colorize(text, "muted") end

local function Text(template, color, gap)
	used.texts = used.texts + 1
	local text = texts[used.texts]
	if not text then
		text = W.Skin.CreateText(content, template)
		text:SetJustifyH("LEFT")
		text:SetWordWrap(true)
		texts[used.texts] = text
	end
	text:SetFontObject(W.Skin.FontFor(template))
	text:SetTextColor(color[1], color[2], color[3])
	text:ClearAllPoints()
	y = y + (gap or 0)
	text:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
	text:SetWidth(content:GetWidth())
	text:Show()
	return text
end

local function Line(template, color, words, gap)
	local text = Text(template, color, gap)
	text:SetText(words or "")
	y = y + U.Measure(text, "GetStringHeight", 14) + 2
	return text
end

-- A section: its name in small capitals over a thin golden rule.
local function Section(label)
	Line("GameTooltipTextSmall", C.label, U.Upper(label), 16)
	used.rules = used.rules + 1
	local rule = rules[used.rules]
	if not rule then
		rule = W.Skin.Rule(content)
		rules[used.rules] = rule
	end
	rule:ClearAllPoints()
	rule:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(y + 1))
	rule:SetPoint("RIGHT", content, "RIGHT", 0, 0)
	rule:Show()
	y = y + 7
end

-- A line's card ("..." or its right click): what it can go to (reminders, the shopping list, the chat), the
-- other droppers. data.menu: card rows { text, glyph, hint, onClick }.
local function RowMenu(row, atCursor)
	local data = row.data
	if not (data and data.menu and data.menu[1]) then return end
	W.Skin.ActionCard(row.more, { title = data.title or "", rows = data.menu, atCursor = atCursor })
end

-- A small action at a line's right, under the mouse: the kit's glyph button, its one sentence.
local function Action(row, glyph, tip, run)
	local button = W.Skin.GlyphButton(row, glyph, 11, tip, function()
		if row.data and row.data.who then run(row.data.who, row.data.info) end
	end)
	button:HookScript("OnLeave", function() row:Hover() end)
	button:SetFrameLevel(row:GetFrameLevel() + 2)
	button:Hide()
	return button
end

-- A line: an icon (an item's) and its words on the whole width; with a place, followed by a click, its small
-- actions under the mouse (follow, to the route, "..."). data: { who, info, title, menu, open, tip }.
local function Row()
	used.rows = used.rows + 1
	local row = rows[used.rows]
	if not row then
		row = CreateFrame("Button", nil, content)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(ICON, ICON)
		row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.text = W.Skin.CreateText(row, "GameTooltipText", C.text[1], C.text[2], C.text[3])
		row.text:SetJustifyH("LEFT")
		row.text:SetWordWrap(true)
		row.hover = row:CreateTexture(nil, "BACKGROUND")
		row.hover:SetPoint("TOPLEFT", row, "TOPLEFT", -4, 2)
		row.hover:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 4, -2)
		row.hover:SetColorTexture(1, 1, 1, 0.04)
		row.hover:Hide()
		row.more = W.Skin.RowMore(row, RowMenu)
		row.route = Action(row, "plus", L.ACTION_ROUTE, ToRoute)
		row.go = Action(row, "chevron", L.ACTION_FOLLOW, Follow)
		function row:Hover()
			local over = (U.Hovered and U.Hovered(self) or self:IsMouseOver()) or self.go:IsMouseOver() or self.route:IsMouseOver() or self.more:IsMouseOver()
			local data = self.data
			local active = over and data ~= nil and (data.who ~= nil or data.open ~= nil or data.menu ~= nil)
			local placed = active and data.who ~= nil and data.who.x ~= nil
			self.hover:SetShown(active and true or false)
			self.go:SetShown(placed and true or false)
			self.route:SetShown(placed and ns.Maps() ~= nil or false)
			self.more:SetShown(active and data.menu ~= nil and data.menu[1] ~= nil or false)
		end
		row:HookScript("OnEnter", function(self)
			self:Hover()
			local data = self.data
			if self.item or not (data and data.tip) then return end
			local lines = { data.tip[1] }
			for index = 2, #data.tip do lines[index] = ns.TipLine(data.tip[index], "text") end
			ns.ShowTip(self, lines, sheet.onLeft and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
		end)
		row:HookScript("OnLeave", function(self)
			self:Hover()
			if not self.item then GameTooltip:Hide() end
		end)
		row.more:HookScript("OnLeave", function() row:Hover() end)
		W.Skin.ItemTooltip(row, function(self) return self.item end)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp") row.padRight = true
		row:SetScript("OnClick", function(self, button)
			local data = self.data
			if not data then return end
			if button == "RightButton" then return RowMenu(self, true) end
			local who = data.who and data.who.x and data.who or nil
			if IsShiftKeyDown() then
				if who then LinkInChat(who) end
				return
			end
			if IsControlKeyDown() then
				if who and ns.Maps() then ToRoute(who, data.info) end
				return
			end
			if data.open then
				W.Skin.Play("click")
				return ns.ShowSheet(data.open, owner)
			end
			if who then
				W.Skin.Play("click")
				Follow(who, data.info)
			end
		end)
		rows[used.rows] = row
	end
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
	row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
	row.item, row.data = nil, nil
	row.icon:Hide()
	row.text:SetFontObject(W.Skin.FontFor("GameTooltipText"))
	row.text:SetTextColor(C.text[1], C.text[2], C.text[3])
	if row.story then row.story:Hide() end
	row:Hover()
	row:Show()
	return row
end

-- A line's words, as tall as they need; its actions at its right (room kept for them).
local function Finish(row, indent)
	local width = content:GetWidth()
	local left = (row.icon:IsShown() and ICON + 6 or 0) + (indent or 0)
	row.text:ClearAllPoints()
	row.text:SetPoint("TOPLEFT", row, "TOPLEFT", left, -2)
	row.text:SetWidth(width - left - (row.data and ACTIONS or 0))
	row.more:ClearAllPoints()
	row.more:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, 0)
	row.route:ClearAllPoints()
	row.route:SetPoint("RIGHT", row.more, "LEFT", -2, 0)
	row.go:ClearAllPoints()
	row.go:SetPoint("RIGHT", row.route, "LEFT", -2, 0)
	local height = math.max(ICON + 2, U.Measure(row.text, "GetStringHeight", 14) + 4)
	row:SetHeight(height)
	y = y + height + 6
end

-- The hover words of a place line: what it is, where, then how its clicks work.
local function PlaceTip(title, who)
	local tip = { title }
	local where = who and Where(who)
	if where then tip[#tip + 1] = where end
	if who and who.x then tip[#tip + 1] = ns.Maps() and L.ROW_TIP or L.ROW_TIP_PLAIN end
	return tip
end

-- A place line's menu: what it adds (reminders, the shopping list), a map link in the chat (with Wanderer Maps).
local function PlaceMenu(who, extra)
	local menu = {}
	for _, entry in ipairs(extra or {}) do menu[#menu + 1] = entry end
	local maps = ns.Maps()
	if who and who.x and maps and maps.ChatLink then
		menu[#menu + 1] = { text = L.ACTION_LINK, glyph = "chevron", onClick = function() LinkInChat(who) end }
	end
	return menu
end

-- Someone (an NPC, an object, an item): who, where under it; followed by a click.
local function Someone(label, who, info)
	if not who then return end
	local row = Row()
	-- (an item that starts it, its name not come yet: drawn again when it comes)
	if who.kind == "Item" and not U.ItemName(who.id) and not ns.ItemRefused(who.id) then
		pending[who.id] = true
		ns.AskItem(who.id)
	end
	local where = Where(who)
	local words = label:format(who.name or "?")
	row.text:SetText(words .. (where and ("\n" .. Muted(where)) or ""))
	if who.x then row.data = { who = who, info = info, title = who.name, tip = PlaceTip(words, who), menu = PlaceMenu(who) } end
	Finish(row)
end

-- The facts ------------------------------------------------------------------------------------------

-- The chip of where you stand (made once, placed at the top).
local function Chip(quest, status)
	if not sheet.chip then sheet.chip = W.Skin.Chip(content) end
	local words, tone = ns.StatusChip(quest, status)
	if not words then words, tone = ns.StatusText(quest, status), "grey" end
	sheet.chip:Set(words, tone)
	sheet.chip:ClearAllPoints()
	sheet.chip:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
	return sheet.chip
end

-- Its step in its chain as dots (gold: done and this one; muted: to come), its words after them.
local function Dots(step, steps)
	sheet.dots = sheet.dots or {}
	local count = steps <= DOTS_MOST and steps or 0
	for index = 1, count do
		local dot = sheet.dots[index] or W.Skin.Glyph(content, "dot", DOT)
		sheet.dots[index] = dot
		local c = index <= step and C.gold or C.muted
		dot:SetVertexColor(c[1], c[2], c[3])
		dot:ClearAllPoints()
		dot:SetPoint("LEFT", content, "TOPLEFT", (index - 1) * (DOT + DOT_GAP), -(y + 8))
		dot:Show()
	end
	for index = count + 1, #sheet.dots do sheet.dots[index]:Hide() end
	local text = Text("GameTooltipTextSmall", C.label)
	local left = count > 0 and count * (DOT + DOT_GAP) + 6 or 0
	text:ClearAllPoints()
	text:SetPoint("LEFT", content, "TOPLEFT", left, -(y + 8))
	text:SetWidth(content:GetWidth() - left)
	text:SetText(L.CHAIN_STEP:format(step, steps))
	y = y + 18
end

-- "Ready?": your level, the quests before it; in your log, what you carry of the items it asks.
local function Ready(quest, status, asks)
	local parts = {}
	local function Add(ok, words) parts[#parts + 1] = (ok and READY_YES or READY_NO) .. " " .. words end
	if status == "available" or status == "level" or status == "locked" then
		Add((quest.requiredLevel or 0) <= ns.YourLevel(), L.READY_LEVEL:format(quest.requiredLevel or 1))
		local holds = ns.Missing(quest)
		if holds[1] then
			Add(false, holds[1])
		elseif quest.before[1] then
			local first = ns.Quest(quest.before[1])
			if first then Add(true, ns.QuestName(first)) end
		end
	elseif status == "active" then
		for _, ask in ipairs(asks) do
			if ask.kind == "Item" and #parts < 3 then
				local have = U.ItemCount(ask.id) or 0
				Add(have >= ask.count, ("%d / %d %s"):format(math.min(have, ask.count), ask.count, ask.name or "..."))
			end
		end
	end
	if not parts[1] then return end
	Line("GameTooltipTextSmall", C.soft, Muted(L.READY) .. "   " .. table.concat(parts, "    "), 6)
end

-- The one thing to do now: to the giver (to take), to the objective (in your log), to hand it in (ready);
-- nothing for a quest behind you. Its words, who, why, its sentence.
local function MainAction(quest, status, asks)
	if status == "available" then
		local giver = ns.Giver(quest)
		if giver and giver.x then return L.GO_GIVER, giver, Why(quest, "take"), L.GO_GIVER_DESC end
	elseif status == "active" then
		if ns.Ready(quest) then
			local ender = ns.Ender(quest)
			if ender and ender.x then return L.GO_HANDIN, ender, Why(quest, "handin"), L.GO_HANDIN_DESC end
			return nil
		end
		for _, ask in ipairs(asks) do
			if ask.kind ~= "Item" and ask.x then return L.GO_OBJECTIVE, ask, Why(quest, "objective"), L.GO_OBJECTIVE_DESC end
		end
		for _, ask in ipairs(asks) do
			if ask.kind == "Item" then
				local first = ns.DropSources(ask.id)[1]
				if first and first.x then return L.GO_OBJECTIVE, first, Why(quest, "objective"), L.GO_OBJECTIVE_DESC end
			end
		end
	end
	return nil
end

local function Facts(quest, status, asks)
	-- Where you stand (a chip), its levels.
	local chip = Chip(quest, status)
	local levels = Text("GameTooltipTextSmall", C.soft)
	levels:ClearAllPoints()
	levels:SetPoint("LEFT", chip, "RIGHT", 10, 0)
	levels:SetWidth(content:GetWidth() - chip:GetWidth() - 10)
	if quest.seen then
		levels:SetText(quest.questLevel and L.LEVEL:format(quest.questLevel) or "")
	else
		levels:SetText(L.FACTS_LEVELS:format(quest.questLevel or 0, quest.requiredLevel or 0))
	end
	y = y + 22
	if quest.seen then Line("GameTooltipTextSmall", C.soft, L.SEEN_AT:format(quest.seen.name or "?"), 2) end
	-- Its step in its chain.
	local step, steps = ns.ChainStep(quest)
	if step then Dots(step, steps) end
	-- The quests before it: a click opens the first one's sheet.
	local before, first = {}, nil
	for _, id in ipairs(quest.before) do
		local other = ns.Quest(id)
		if ns.ForYou(other) then
			before[#before + 1] = ns.QuestName(other)
			first = first or other
		end
	end
	if first then
		y = y + 2
		local row = Row()
		row.text:SetFontObject(W.Skin.FontFor("GameTooltipTextSmall"))
		row.text:SetTextColor(C.soft[1], C.soft[2], C.soft[3])
		row.text:SetText(L.AFTER:format(table.concat(before, quest.any and " / " or ", ")))
		row.data = { open = first, tip = { ns.QuestName(first), L.OPEN_SHEET_TIP } }
		Finish(row)
		y = y - 4
	end
	Ready(quest, status, asks)
	-- The main action.
	local words, who, info, tip = MainAction(quest, status, asks)
	sheet.main.who, sheet.main.info, sheet.main.tip = who, info, tip
	sheet.main:SetShown(words ~= nil)
	if words then
		sheet.main:SetText(words)
		sheet.main:ClearAllPoints()
		sheet.main:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(y + 8))
		sheet.main:SetPoint("RIGHT", content, "RIGHT", 0, 0)
		y = y + 8 + 28 + 4
	end
end

-- An item asked: its square, how many you carry; under it, the nearest creatures that drop it (each followed by
-- a click), the others in its "...".
local function ItemAsk(quest, ask, menu)
	local row = Row()
	row.item = ask.id
	row.icon:SetTexture(U.ItemIcon(ask.id))
	row.icon:Show()
	if not ask.name then
		ns.AskItem(ask.id)
		if not ns.ItemRefused(ask.id) then pending[ask.id] = true end
	end
	row.text:SetText((ask.name or "...") .. "   " .. U.HaveNeed(U.ItemCount(ask.id), ask.count))
	local auction = Shopping()
	if auction then
		menu[#menu + 1] = { text = L.ADD_SHOPPING, glyph = "plus",
			onClick = function() auction.AddToShopping(ask.id, ask.count, ns.QuestName(quest)) end }
	end
	local droppers = ns.DropSources(ask.id)
	for index = DROPPERS + 1, #droppers do
		local who = droppers[index]
		if who.x then
			menu[#menu + 1] = { text = L.DROPPER_GO:format(who.name, ns.AreaName(who.zone) or "?"), glyph = "chevron",
				onClick = function() Follow(who, Why(quest, "objective")) end }
		end
	end
	row.data = { title = ask.name, menu = menu }
	Finish(row)
	for index = 1, math.min(DROPPERS, #droppers) do
		local who = droppers[index]
		local line = Row()
		line.text:SetFontObject(W.Skin.FontFor("GameTooltipTextSmall"))
		line.text:SetTextColor(C.soft[1], C.soft[2], C.soft[3])
		local where = Where(who)
		local words = (index == 1 and L.DROPPED_BY or L.DROPPED_ALSO):format(who.name)
		line.text:SetText(words .. (where and ("  " .. Muted(where)) or ""))
		if who.x then
			line.data = { who = who, info = Why(quest, "objective"), title = who.name, tip = PlaceTip(who.name, who), menu = PlaceMenu(who) }
		end
		Finish(line, ICON + 6)
		y = y - 4
	end
	if #droppers > DROPPERS then
		local more = Text("GameTooltipTextSmall", C.muted)
		more:ClearAllPoints()
		more:SetPoint("TOPLEFT", content, "TOPLEFT", ICON + 6, -y)
		more:SetWidth(content:GetWidth() - ICON - 6)
		more:SetText(L.DROPPED_MORE:format(#droppers - DROPPERS))
		y = y + U.Measure(more, "GetStringHeight", 14) + 2
	end
	if droppers[1] then y = y + 6 end
end

-- What it asks: items (how many you carry, who drops them), creatures or objects (where).
local function Asks(quest, asks)
	Section(L.ASKS)
	for _, ask in ipairs(asks) do
		local menu = {}
		if Todo() then menu[#menu + 1] = { text = L.ADD_TODO, glyph = "bell", onClick = function() Said(AddAsk(quest, ask)) end } end
		if ask.kind == "Item" then
			ItemAsk(quest, ask, menu)
		else
			local row = Row()
			local where = ask.zone and Where(ask)
			local words = L.COUNT:format(ask.name or "?", ask.count)
			row.text:SetText(words .. (where and ("\n" .. Muted(where)) or ""))
			local who = ask.x and ask or nil
			row.data = { who = who, info = Why(quest, "objective"), title = ask.name, tip = PlaceTip(words, ask), menu = PlaceMenu(who, menu) }
			Finish(row)
		end
	end
end

local function Rewards(quest, status)
	-- What it gives: one item of a choice, items given, money. Each item says what it is worth to you
	-- (Wanderer's comparison with what you wear, for your branch), or that your class cannot wear it.
	-- (a quest of your log: its rewards read from the game first)
	if status == "active" then ns.LearnLog(quest.id) end
	local rewards = ns.Rewards(quest)
	if not (rewards.choice[1] or rewards.given[1] or rewards.money > 0) then return end
	Section(L.REWARDS)
	if not rewards.seen then Line("GameTooltipTextSmall", C.muted, L.REWARDS_BASE) end
	local function Reward(item)
		local row = Row()
		row.item = item.id
		row.icon:SetTexture(item.icon)
		row.icon:Show()
		if not item.name and not ns.ItemRefused(item.id) then pending[item.id] = true end
		local name = item.name or "..."
		if item.count > 1 then name = L.COUNT:format(name, item.count) end
		local words = U.Colorize(name, U.QualityColor(item.quality or 1))
		local worth = item.link and W.UpgradeLines and W.UpgradeLines(item.link)[1]
		if worth then
			words = words .. "\n" .. U.ColorCode(worth[2], worth[3], worth[4]) .. worth[1] .. "|r"
		elseif item.link and W.CanWear and W.CanWear(item.link) == false then
			words = Muted(name .. "\n" .. L.NOT_FOR_YOU)
		end
		row.text:SetText(words)
		Finish(row)
	end
	if rewards.choice[1] then
		Line("GameTooltipTextSmall", C.soft, rewards.choice[2] and L.REWARD_CHOICE or L.REWARD_GIVEN, 2)
		y = y + 4
		for _, item in ipairs(rewards.choice) do Reward(item) end
	end
	if rewards.given[1] then
		Line("GameTooltipTextSmall", C.soft, rewards.choice[1] and L.REWARD_ALSO or L.REWARD_GIVEN, 4)
		y = y + 4
		for _, item in ipairs(rewards.given) do Reward(item) end
	end
	if rewards.money > 0 then Line("GameTooltipText", C.text, L.REWARD_MONEY:format(U.Coins(rewards.money)), 4) end
end

-- What comes after it: each quest it opens (a click: its sheet), where you stand with it, what still holds it
-- back, who gives it (its actions under the mouse).
local function After(quest)
	local after = ns.Next(quest)
	if not after[1] then return end
	Section(L.NEXT)
	for _, other in ipairs(after) do
		local row = Row()
		local words = ns.QuestName(other) .. "\n" .. Muted(ns.StatusText(other, ns.Status(other)))
		local holds = ns.Missing(other)
		if holds[1] then words = words .. "\n" .. Muted(L.STILL_NEEDS:format(table.concat(holds, other.any and " / " or ", "))) end
		local from = ns.Giver(other)
		if from and from.name then words = words .. "\n" .. Muted(L["GIVER_" .. from.kind:upper()]:format(from.name)) end
		row.text:SetText(words)
		local who = from and from.x and from or nil
		row.data = { open = other, who = who, info = Why(other, "take"), title = ns.QuestName(other),
			tip = { ns.QuestName(other), L.OPEN_SHEET_TIP }, menu = PlaceMenu(who) }
		Finish(row)
	end
end

local function Draw()
	if not (sheet and shown) then return end
	local quest = shown
	used.texts, used.rows, used.rules, y = 0, 0, 0, 0
	local status = ns.Status(quest)
	sheet.title:SetText(ns.QuestName(quest))
	local asks = ns.Asks(quest)
	wipe(pending)
	Facts(quest, status, asks)
	local objective, story = ns.Texts(quest)
	if objective then
		Section(L.OBJECTIVE)
		Line("GameTooltipText", C.text, objective)
	end
	if asks[1] then Asks(quest, asks) end
	Rewards(quest, status)
	-- Who gives it, who takes it back.
	local giver, ender = ns.Giver(quest), ns.Ender(quest)
	if giver or ender then
		Section(L.PEOPLE)
		if giver then Someone(L["GIVER_" .. giver.kind:upper()], giver, Why(quest, "take")) end
		if ender then Someone(L.ENDER, ender, Why(quest, "handin")) end
	end
	After(quest)
	if story then
		Section(L.STORY)
		-- (an option: the story of a quest not taken yet kept for its giver, unless asked)
		local settings = W.Settings("quests")
		if settings and settings.foldStory and UNTAKEN[status] and not unfolded[quest.id] then
			local row = Row()
			row.text:SetText(Muted(L.STORY_LATER))
			Finish(row)
			row.story = row.story or W.Skin.SmallButton(row, L.STORY_READ, function()
				-- (the quest shown now: this button stays with its row, from one quest to the next)
				if shown then unfolded[shown.id] = true end
				Draw()
			end)
			row.story:ClearAllPoints()
			row.story:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -6)
			row.story:Show()
			row:SetHeight(row:GetHeight() + 28)
			y = y + 28
		else
			Line("GameTooltipText", C.soft, story)
		end
	end
	if not (objective or story) then Line("GameTooltipTextSmall", C.soft, quest.seen and L.SEEN_NOTE or L.NO_TEXT, 12) end
	for index = used.texts + 1, #texts do texts[index]:Hide() end
	for index = used.rows + 1, #rows do
		rows[index]:Hide()
		rows[index].data = nil
	end
	for index = used.rules + 1, #rules do rules[index]:Hide() end
	content:SetHeight(math.max(1, y + 8))
	-- The quiet line under: everything to the reminders, every item to the shopping list (when they apply).
	local items = 0
	for _, ask in ipairs(asks) do if ask.kind == "Item" then items = items + 1 end end
	sheet.allTodo:SetShown(Todo() and true or false)
	sheet.allShopping:SetShown(items > 0 and Shopping() ~= nil)
	local margin = W.Skin.Margin() + 8
	local left = nil
	for _, button in ipairs({ sheet.allTodo, sheet.allShopping }) do
		if button:IsShown() then
			button:ClearAllPoints()
			if left then button:SetPoint("LEFT", left, "RIGHT", 8, 0) else button:SetPoint("BOTTOMLEFT", sheet, "BOTTOMLEFT", margin, margin) end
			left = button
		end
	end
	scroll:SetPoint("BOTTOMRIGHT", sheet, "BOTTOMRIGHT", -margin, margin + (left and 22 + 10 or 0))
	scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), math.max(0, content:GetHeight() - scroll:GetHeight())))
	if bar then bar:Set(content:GetHeight(), scroll:GetHeight(), scroll:GetVerticalScroll()) end
	sheet.asks = asks
end

-- The sheet's frame: beside the window, on the side the screen leaves room for (its right first). Room on
-- neither (a 1080p screen, the window in the middle): the window slides aside for this time only (its kept
-- place comes back next time), the sheet on its right.
local function Place()
	if not (sheet and owner) then return end
	sheet:ClearAllPoints()
	-- (on the screen's scale: the window's edges, the sheet's width, the screen's)
	local scale = owner:GetEffectiveScale()
	local left, right = (owner:GetLeft() or 0) * scale, (owner:GetRight() or 0) * scale
	local screen = (UIParent:GetRight() or 0) * UIParent:GetEffectiveScale()
	local need = (GAP + WIDTH) * scale
	local onLeft = false
	if right + need > screen then
		if left - need >= 0 then
			onLeft = true
		elseif scale > 0 and owner:GetTop() then
			-- (the window and the sheet side by side, against the screen's right edge)
			local top = owner:GetTop()
			owner:ClearAllPoints()
			owner:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", math.max(0, screen - need - (right - left)) / scale, top)
		end
	end
	sheet.onLeft = onLeft
	if onLeft then
		sheet:SetPoint("TOPRIGHT", owner, "TOPLEFT", -GAP, 0)
		sheet:SetPoint("BOTTOMRIGHT", owner, "BOTTOMLEFT", -GAP, 0)
	else
		sheet:SetPoint("TOPLEFT", owner, "TOPRIGHT", GAP, 0)
		sheet:SetPoint("BOTTOMLEFT", owner, "BOTTOMRIGHT", GAP, 0)
	end
end

local function Create()
	sheet = W.Skin.CreateWindow("WandererQuestsSheet", "MEDIUM", owner)
	if W.Skin.PadWindow then W.Skin.PadWindow(sheet, { side = true }) end
	sheet:SetWidth(WIDTH)
	sheet:EnableMouse(true)
	-- (never half off the screen, whatever the window does)
	sheet:SetClampedToScreen(true)
	local margin = W.Skin.Margin() + 8
	W.Skin.CloseButton(sheet, function() ns.HideSheet() end)
	local _, title = W.Skin.Header(sheet, L.SHEET)
	sheet.title = title
	sheet.title:SetPoint("RIGHT", sheet, "RIGHT", -margin - 18, 0)
	sheet.title:SetWordWrap(true)
	-- The quiet line under (placed as each quest needs it).
	sheet.allTodo = W.Skin.SmallButton(sheet, L.ALL_TODO, function()
		if not shown then return end
		local any, added, why = false, false, nil
		for _, ask in ipairs(sheet.asks or {}) do
			any = true
			local one, reason = AddAsk(shown, ask)
			added, why = one or added, why or reason
		end
		if not any then added, why = AddQuest(shown) end
		Said(added, why)
	end, L.ALL_TODO_DESC)
	sheet.allShopping = W.Skin.SmallButton(sheet, L.ALL_SHOPPING, function()
		local auction = Shopping(true)
		if not (auction and shown) then return end
		-- (each added quietly, one line for all; only those Auction really took counted)
		local count, first = 0, nil
		for _, ask in ipairs(sheet.asks or {}) do
			if ask.kind == "Item" then
				first = first or ask
				if auction.AddToShopping(ask.id, ask.count, ns.QuestName(shown), true) then count = count + 1 end
			end
		end
		if count > 0 then
			W.Print(L.SHOPPING_ADDED:format(count))
		elseif first and not Shopping() then
			-- (Auction turned off since the sheet was drawn: Auction says so, nothing taken, the button gone)
			auction.AddToShopping(first.id, first.count, ns.QuestName(shown))
			Draw()
		end
	end, L.ALL_SHOPPING_DESC)
	-- What it says, scrolled by the wheel.
	scroll = CreateFrame("ScrollFrame", nil, sheet)
	scroll:SetPoint("TOPLEFT", sheet.title, "BOTTOMLEFT", 0, -10)
	scroll:SetPoint("BOTTOMRIGHT", sheet, "BOTTOMRIGHT", -margin, margin + 30)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(WIDTH - margin * 2, 1)
	scroll:SetScrollChild(content)
	-- The main action (placed under the facts).
	sheet.main = W.Skin.Button(content, "", function(self)
		if self.who then Follow(self.who, self.info) end
	end, "main")
	sheet.main:SetHeight(28)
	W.Skin.Tooltip(sheet.main, function(self) return self.tip end)
	-- (the bar beside, in the margin: the words keep their width)
	bar = W.Skin.ScrollBar(sheet, function(offset)
		scroll:SetVerticalScroll(offset)
		bar:Set(content:GetHeight(), scroll:GetHeight(), offset)
	end)
	bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", W.Skin.SCROLL_WIDTH, 0)
	bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", W.Skin.SCROLL_WIDTH, 0)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local most = math.max(0, content:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.max(0, math.min(most, self:GetVerticalScroll() - delta * 40)))
		bar:Set(content:GetHeight(), self:GetHeight(), self:GetVerticalScroll())
	end)
	-- Items the game had not yet: drawn again when they come; what you carry, as it changes.
	local drawSoon = U.Debounce(0.2, function() if sheet:IsShown() then Draw() end end)
	sheet:SetScript("OnEvent", function(_, event, itemID, success)
		if event == "GET_ITEM_INFO_RECEIVED" then
			if not pending[itemID] then return end
			pending[itemID] = nil
			if success == false then return end
		end
		drawSoon()
	end)
	sheet:HookScript("OnShow", function(self)
		self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		self:RegisterEvent("BAG_UPDATE_DELAYED")
	end)
	sheet:HookScript("OnHide", function(self)
		self:UnregisterAllEvents()
		-- (the givers on the world map: none faded any more)
		ns.RefreshMapPins()
	end)
	sheet:Hide()
	W.Skin.Get(sheet):Layout()
end

-- A quest shown on the sheet, beside a window (on the side the screen leaves room for, again when it moves).
function ns.ShowSheet(quest, window)
	if not quest then return end
	owner = window
	if not sheet then Create() end
	if owner and not hooked[owner] then
		hooked[owner] = true
		owner:HookScript("OnDragStop", Place)
		owner:HookScript("OnSizeChanged", Place)
	end
	local changed = shown ~= quest
	shown = quest
	Place()
	sheet:Show()
	if changed then scroll:SetVerticalScroll(0) end
	Draw()
	W.Skin.Get(sheet):Layout()
	-- (the givers on the world map: the others step back)
	if changed then ns.RefreshMapPins() end
end

function ns.HideSheet()
	shown = nil
	if sheet then sheet:Hide() end
end

function ns.SheetShown() return sheet and sheet:IsShown() and shown ~= nil or false end

-- The quest on the sheet now (nil: none shown).
function ns.SheetQuest() return ns.SheetShown() and shown or nil end

-- Where you stand changed: drawn again.
function ns.RefreshSheet()
	if ns.SheetShown() then Draw() end
end
