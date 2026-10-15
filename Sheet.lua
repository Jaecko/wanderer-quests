local _, ns = ...
local L = ns.L

-- A quest's sheet, beside the window (a quest clicked): what it asks, in its
-- own words, the items and the creatures with how many, who gives it and who
-- takes it back (a pin for each), the quests before it, its story. What it
-- asks can go to Wanderer's reminders, and its items to Wanderer Auction's
-- shopping list (each, or all at once). Read ahead: a quest still far off is
-- prepared as well as one in your log.

local W = Wanderer
local U = W and W.Util

local WIDTH = 400
local GAP = 4 -- from the window
local ROW = 20
local ICON = 16

local sheet, scroll, content, owner
local shown -- the quest shown
local texts, rows = {}, {} -- made once, used again at each drawing
local used = { texts = 0, rows = 0 }
local waiting = false -- items the game is still looking up: drawn again when they come

local C = W and W.Skin.COLORS -- (Wanderer's colors, by role)

local function Todo() return W and W.AddTodo and (W.API or 1) >= 3 end
local function Shopping()
	local auction = _G.WandererAuction
	return type(auction) == "table" and auction.AddToShopping and auction or nil
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
	local text = L.TODO_LINE:format(ask.count > 1 and L.COUNT:format(name, ask.count) or name, ns.QuestName(quest))
	if ask.kind == "Item" then
		return W.AddTodo(L.TODO_LINE:format(name, ns.QuestName(quest)),
			{ key = "wquests:" .. quest.id .. ":i:" .. ask.id, item = ask.id, count = ask.count })
	end
	return W.AddTodo(text, { key = "wquests:" .. quest.id .. ":k:" .. ask.id, place = TodoPlace(ask) })
end

local function AddQuest(quest)
	local status = ns.Status(quest)
	local who = status == "active" and ns.Ender(quest) or ns.Giver(quest)
	return W.AddTodo(L.TODO_QUEST:format(ns.QuestName(quest)), { key = "wquests:" .. quest.id, place = TodoPlace(who) })
end

-- Drawing ----------------------------------------------------------------------------------------

local y -- where the next line goes, from the top of the content

local function Text(template, color, gap)
	used.texts = used.texts + 1
	local text = texts[used.texts]
	if not text then
		text = W.Skin.CreateText(content, template)
		text:SetJustifyH("LEFT")
		if text.SetWordWrap then text:SetWordWrap(true) end
		texts[used.texts] = text
	end
	text:SetFontObject(template)
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

local function Section(label) return Line("GameTooltipTextSmall", C.label, U.Upper and U.Upper(label) or label, 12) end

-- A row: an icon (an item's), its words, links on the right.
local function Row()
	used.rows = used.rows + 1
	local row = rows[used.rows]
	if not row then
		row = CreateFrame("Button", nil, content)
		row:SetHeight(ROW)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(ICON, ICON)
		row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.text = W.Skin.CreateText(row, "GameTooltipTextSmall", C.text[1], C.text[2], C.text[3])
		if row.text.SetWordWrap then row.text:SetWordWrap(true) end
		row.links = {}
		for index = 1, 2 do
			local link = W.Skin.CreateLink(row, "", function(self) if self.run then self.run() end end)
			link:Hide()
			row.links[index] = link
		end
		W.Skin.ItemTooltip(row, function(self) return self.item end)
		rows[used.rows] = row
	end
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
	row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
	row.item = nil
	for _, link in ipairs(row.links) do link:Hide() end
	row:Show()
	return row
end

-- Links on a row's right, the last one first: { label, run, tip }.
local function Links(row, list)
	local previous
	for index, spec in ipairs(list) do
		local link = row.links[index]
		link:SetLabel(spec[1])
		link.run = spec[2]
		link.tip = spec[3]
		link:ClearAllPoints()
		if previous then link:SetPoint("RIGHT", previous, "LEFT", 2, 0) else link:SetPoint("RIGHT", row, "RIGHT", 5, 0) end
		link:Show()
		previous = link
	end
	-- Its words between the icon and the links, on as many lines as they need (never cut): the row as tall.
	local left = row.icon:IsShown() and ICON + 6 or 0
	local right = 0
	for _, link in ipairs(row.links) do
		if link:IsShown() then right = right + link:GetWidth() - 2 end
	end
	row.text:ClearAllPoints()
	row.text:SetPoint("LEFT", row, "LEFT", left, 0)
	row.text:SetWidth(math.max(60, content:GetWidth() - left - right - 6))
	local height = math.max(ROW, U.Measure(row.text, "GetStringHeight", 14) + 6)
	row:SetHeight(height)
	y = y + height
end

local function Pin(who)
	return { L.PIN, function()
		if not ns.Pin(who.zone, who.x, who.y) then W.Print(L.PIN_FAILED) end
	end }
end

local function Where(who)
	if who.zone and who.x then return L.WHERE:format(ns.AreaName(who.zone) or "?", who.x, who.y) end
	return who.zone and ns.AreaName(who.zone) or nil
end

-- Someone (an NPC, an object, an item), with where and a pin.
local function Someone(label, who)
	if not who then return end
	local row = Row()
	row.icon:Hide()
	local where = Where(who)
	row.text:SetText(label:format(who.name or "?") .. (where and ("|cff9a9080, " .. where .. "|r") or ""))
	Links(row, who.x and { Pin(who) } or {})
end

local function Draw()
	if not (sheet and shown) then return end
	local quest = shown
	used.texts, used.rows, y = 0, 0, 0
	local status = ns.Status(quest)
	sheet.title:SetText(ns.QuestName(quest))
	-- Its level, where you stand.
	local color = C.text
	Line("GameTooltipTextSmall", color, L.LEVELS_LINE:format(quest.questLevel or 0, quest.requiredLevel or 0) .. "   "
		.. (status == "level" and L.LEVEL:format(quest.requiredLevel or 0) or L["STATUS_" .. status:upper()]))
	local objective, story = ns.Texts(quest)
	if objective then
		Section(L.OBJECTIVE)
		Line("GameTooltipText", C.text, objective, 2)
	end
	-- What it asks: items (how many you carry), creatures or objects.
	local asks = ns.Asks(quest)
	local missing = false
	if asks[1] then
		Section(L.ASKS)
		for _, ask in ipairs(asks) do
			local row = Row()
			local list = {}
			if ask.kind == "Item" then
				row.item = ask.id
				local icon = U.ItemIcon(ask.id)
				row.icon:SetTexture(icon)
				row.icon:Show()
				if not ask.name then
					missing = true
					U.LoadItem(ask.id)
				end
				local count = U.HaveNeed(U.ItemCount(ask.id), ask.count)
				row.text:SetText((ask.name or "…") .. "  " .. count)
				local auction = Shopping()
				if auction then
					list[#list + 1] = { L.TO_SHOPPING, function() auction.AddToShopping(ask.id, ask.count, ns.QuestName(quest)) end }
				end
			else
				row.icon:Hide()
				row.text:SetText(L.COUNT:format(ask.name or "?", ask.count))
				if ask.x then list[#list + 1] = Pin(ask) end
			end
			if Todo() then list[#list + 1] = { L.TO_TODO, function() Said(AddAsk(quest, ask)) end } end
			Links(row, list)
		end
	end
	-- What it gives: one item of a choice, items given, money. Each item says what it is worth to you
	-- (Wanderer's comparison with what you wear, for your branch), or that your class cannot wear it.
	-- (a quest of your log: its rewards read from the game first)
	if ns.Status(quest) == "active" then ns.LearnLog(quest.id) end
	local rewards = ns.Rewards(quest)
	if rewards.choice[1] or rewards.given[1] or rewards.money > 0 then
		Section(L.REWARDS)
		if not rewards.seen then Line("GameTooltipTextSmall", C.muted, L.REWARDS_BASE, 2) end
		local function Reward(item)
			local row = Row()
			row.item = item.id
			row.icon:SetTexture(item.icon)
			row.icon:Show()
			if not item.name then missing = true end
			local name = item.name or "..."
			if item.count > 1 then name = L.COUNT:format(name, item.count) end
			local words = U.Colorize(name, U.QualityColor(item.quality or 1))
			local worth = item.link and W.UpgradeLines and W.UpgradeLines(item.link)[1]
			if worth then
				words = words .. "  " .. U.ColorCode(worth[2], worth[3], worth[4]) .. worth[1] .. "|r"
			elseif item.link and W.CanWear and W.CanWear(item.link) == false then
				words = "|cff808080" .. name .. "  " .. L.NOT_FOR_YOU .. "|r"
			end
			row.text:SetText(words)
			Links(row, {})
		end
		if rewards.choice[1] then
			Line("GameTooltipTextSmall", C.soft, rewards.choice[2] and L.REWARD_CHOICE or L.REWARD_GIVEN, 4)
			for _, item in ipairs(rewards.choice) do Reward(item) end
		end
		if rewards.given[1] then
			Line("GameTooltipTextSmall", C.soft, rewards.choice[1] and L.REWARD_ALSO or L.REWARD_GIVEN, 6)
			for _, item in ipairs(rewards.given) do Reward(item) end
		end
		if rewards.money > 0 then Line("GameTooltipText", C.text, L.REWARD_MONEY:format(U.Coins(rewards.money)), 6) end
	end
	-- Who gives it, who takes it back.
	Section(L.PEOPLE)
	local giver, ender = ns.Giver(quest), ns.Ender(quest)
	if giver then Someone(L["GIVER_" .. giver.kind:upper()], giver) end
	if ender then Someone(L.ENDER, ender) end
	-- What comes after it: each quest it opens, where you stand with it, and what still holds it back.
	local after = ns.Next(quest)
	if after[1] then
		Section(L.NEXT)
		for _, other in ipairs(after) do
			local its = ns.Status(other)
			local why = its == "level" and L.LEVEL:format(other.requiredLevel or 0) or L["STATUS_" .. its:upper()]
			local row = Row()
			row.icon:Hide()
			local words = ns.QuestName(other) .. "  |cff9a9080" .. why .. "|r"
			local holds = ns.Missing(other)
			if holds[1] then words = words .. "\n|cff9a9080" .. L.STILL_NEEDS:format(table.concat(holds, other.any and " / " or ", ")) .. "|r" end
			local from = ns.Giver(other)
			if from and from.name then words = words .. "\n|cff9a9080" .. L["GIVER_" .. from.kind:upper()]:format(from.name) .. "|r" end
			row.text:SetText(words)
			Links(row, from and from.x and { Pin(from) } or {})
		end
	end
	-- The quests before it.
	local before = {}
	for _, id in ipairs(quest.before) do
		local other = ns.Quest(id)
		if ns.ForYou(other) then before[#before + 1] = ns.QuestName(other) end
	end
	if before[1] then Line("GameTooltipTextSmall", C.soft, L.AFTER:format(table.concat(before, quest.any and " / " or ", ")), 6) end
	if story then
		Section(L.STORY)
		Line("GameTooltipText", C.soft, story, 2)
	end
	if not (objective or story) then Line("GameTooltipTextSmall", C.soft, L.NO_TEXT, 12) end
	for index = used.texts + 1, #texts do texts[index]:Hide() end
	for index = used.rows + 1, #rows do rows[index]:Hide() end
	content:SetHeight(math.max(1, y))
	scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), math.max(0, y - scroll:GetHeight())))
	-- The buttons under: everything to the reminders, every item to the shopping list.
	local items = 0
	for _, ask in ipairs(asks) do if ask.kind == "Item" then items = items + 1 end end
	sheet.allTodo:SetShown(Todo() and true or false)
	sheet.allShopping:SetShown(items > 0 and Shopping() ~= nil)
	sheet.asks = asks
	waiting = missing
end

-- The sheet's frame: beside the window (on its left when the screen ends on its right).
local function Place()
	sheet:ClearAllPoints()
	-- (on the screen's scale: the window's right edge, the sheet's width, the screen's)
	local scale = owner:GetEffectiveScale()
	local right = (owner:GetRight() or 0) * scale
	local room = (UIParent:GetRight() or 0) * UIParent:GetEffectiveScale()
	if right + (GAP + WIDTH) * scale > room then
		sheet:SetPoint("TOPRIGHT", owner, "TOPLEFT", -GAP, 0)
		sheet:SetPoint("BOTTOMRIGHT", owner, "BOTTOMLEFT", -GAP, 0)
	else
		sheet:SetPoint("TOPLEFT", owner, "TOPRIGHT", GAP, 0)
		sheet:SetPoint("BOTTOMLEFT", owner, "BOTTOMRIGHT", GAP, 0)
	end
end

local function Create()
	sheet = W.Skin.CreateWindow("WandererQuestsSheet", "MEDIUM", owner)
	sheet:SetWidth(WIDTH)
	sheet:EnableMouse(true)
	local margin = W.Skin.Margin() + 8
	W.Skin.CloseButton(sheet, function() ns.HideSheet() end)
	local _, title = W.Skin.Header(sheet, L.SHEET)
	sheet.title = title
	sheet.title:SetPoint("RIGHT", sheet, "RIGHT", -margin - 18, 0)
	if sheet.title.SetWordWrap then sheet.title:SetWordWrap(true) end
	-- The buttons under.
	sheet.allTodo = W.Skin.Button(sheet, L.ALL_TODO, function()
		if not shown then return end
		local any, added = false, false
		for _, ask in ipairs(sheet.asks or {}) do
			any = true
			added = AddAsk(shown, ask) or added
		end
		if not any then added = AddQuest(shown) end
		Said(added)
	end)
	sheet.allTodo:SetPoint("BOTTOMRIGHT", sheet, "BOTTOMRIGHT", -margin, margin)
	sheet.allShopping = W.Skin.Button(sheet, L.ALL_SHOPPING, function()
		local auction = Shopping()
		if not (auction and shown) then return end
		for _, ask in ipairs(sheet.asks or {}) do
			if ask.kind == "Item" then auction.AddToShopping(ask.id, ask.count, ns.QuestName(shown)) end
		end
	end)
	sheet.allShopping:SetPoint("RIGHT", sheet.allTodo, "LEFT", -6, 0)
	-- What it says, scrolled by the wheel.
	scroll = CreateFrame("ScrollFrame", nil, sheet)
	scroll:SetPoint("TOPLEFT", sheet.title, "BOTTOMLEFT", 0, -8)
	scroll:SetPoint("BOTTOMRIGHT", sheet, "BOTTOMRIGHT", -margin, margin + 30)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(WIDTH - margin * 2, 1)
	scroll:SetScrollChild(content)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local most = math.max(0, content:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.max(0, math.min(most, self:GetVerticalScroll() - delta * 40)))
	end)
	-- Items the game had not yet: drawn again when they come; what you carry, as it changes.
	local drawSoon = U.Debounce(0.2, function() if sheet:IsShown() then Draw() end end)
	sheet:SetScript("OnEvent", function(_, event)
		if event == "GET_ITEM_INFO_RECEIVED" and not waiting then return end
		drawSoon()
	end)
	sheet:HookScript("OnShow", function(self)
		self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		self:RegisterEvent("BAG_UPDATE_DELAYED")
	end)
	sheet:HookScript("OnHide", function(self) self:UnregisterAllEvents() end)
	sheet:Hide()
	W.Skin.Get(sheet):Layout()
end

-- A quest shown on the sheet, beside a window.
function ns.ShowSheet(quest, window)
	if not quest then return end
	owner = window
	if not sheet then Create() end
	local changed = shown ~= quest
	shown = quest
	Place()
	sheet:Show()
	if changed then scroll:SetVerticalScroll(0) end
	Draw()
	W.Skin.Get(sheet):Layout()
end

function ns.HideSheet()
	shown = nil
	if sheet then sheet:Hide() end
end

function ns.SheetShown() return sheet and sheet:IsShown() and shown ~= nil or false end

-- Where you stand changed: drawn again.
function ns.RefreshSheet()
	if ns.SheetShown() then Draw() end
end
