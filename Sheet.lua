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
local Safe, Clean = U and U.Safe, U and U.Clean

local WIDTH = 360
local GAP = 4 -- from the window
local ROW = 20
local ICON = 16

local sheet, scroll, content, owner
local shown -- the quest shown
local texts, rows = {}, {} -- made once, used again at each drawing
local used = { texts = 0, rows = 0 }
local waiting = false -- items the game is still looking up: drawn again when they come

local C = {
	title = { 1, 0.82, 0 }, label = { 0.75, 0.68, 0.5 }, text = { 0.9, 0.88, 0.82 }, soft = { 0.7, 0.66, 0.58 },
	ok = { 0.4, 0.87, 0.4 }, rule = { 1, 0.82, 0, 0.2 },
}

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
		if row.text.SetWordWrap then row.text:SetWordWrap(false) end
		row.links = {}
		for index = 1, 2 do
			local link = W.Skin.CreateLink(row, "", function(self) if self.run then self.run() end end)
			link:Hide()
			row.links[index] = link
		end
		row:SetScript("OnEnter", function(self)
			if not self.item then return end
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetItemByID(self.item)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		rows[used.rows] = row
	end
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
	row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
	y = y + ROW
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
	row.text:ClearAllPoints()
	row.text:SetPoint("LEFT", row.icon:IsShown() and row.icon or row, row.icon:IsShown() and "RIGHT" or "LEFT", row.icon:IsShown() and 6 or 0, 0)
	row.text:SetPoint("RIGHT", previous or row, previous and "LEFT" or "RIGHT", -4, 0)
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
				local icon = Clean(Safe(C_Item and C_Item.GetItemIconByID, ask.id))
				row.icon:SetTexture(icon)
				row.icon:Show()
				if not ask.name then
					missing = true
					if C_Item and C_Item.RequestLoadItemDataByID then Safe(C_Item.RequestLoadItemDataByID, ask.id) end
				end
				local have = Clean(Safe(C_Item and C_Item.GetItemCount or GetItemCount, ask.id)) or 0
				local count = (have >= ask.count and "|cff66dd66" or "|cffb0a080") .. math.min(have, ask.count) .. "/" .. ask.count .. "|r"
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
	-- Who gives it, who takes it back.
	Section(L.PEOPLE)
	local giver, ender = ns.Giver(quest), ns.Ender(quest)
	if giver then Someone(L["GIVER_" .. giver.kind:upper()], giver) end
	if ender then Someone(L.ENDER, ender) end
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
	local close = CreateFrame("Button", nil, sheet, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", sheet, "TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function() ns.HideSheet() end)
	local kicker = W.Skin.CreateKicker(sheet, L.SHEET)
	kicker:SetPoint("TOPLEFT", sheet, "TOPLEFT", margin, -margin)
	sheet.title = W.Skin.CreateText(sheet, "GameTooltipHeaderText", C.title[1], C.title[2], C.title[3])
	sheet.title:SetPoint("TOPLEFT", kicker, "BOTTOMLEFT", 0, -3)
	sheet.title:SetPoint("RIGHT", sheet, "RIGHT", -margin - 18, 0)
	if sheet.title.SetWordWrap then sheet.title:SetWordWrap(true) end
	-- The buttons under.
	sheet.allTodo = CreateFrame("Button", nil, sheet, "UIPanelButtonTemplate")
	sheet.allTodo:SetText(L.ALL_TODO)
	sheet.allTodo:SetSize(U.Measure(sheet.allTodo:GetFontString() or sheet.allTodo, "GetStringWidth", 120) + 30, 22)
	sheet.allTodo:SetPoint("BOTTOMRIGHT", sheet, "BOTTOMRIGHT", -margin, margin)
	sheet.allTodo:SetScript("OnClick", function()
		if not shown then return end
		local any, added = false, false
		for _, ask in ipairs(sheet.asks or {}) do
			any = true
			added = AddAsk(shown, ask) or added
		end
		if not any then added = AddQuest(shown) end
		Said(added)
	end)
	sheet.allShopping = CreateFrame("Button", nil, sheet, "UIPanelButtonTemplate")
	sheet.allShopping:SetText(L.ALL_SHOPPING)
	sheet.allShopping:SetSize(U.Measure(sheet.allShopping:GetFontString() or sheet.allShopping, "GetStringWidth", 120) + 30, 22)
	sheet.allShopping:SetPoint("RIGHT", sheet.allTodo, "LEFT", -6, 0)
	sheet.allShopping:SetScript("OnClick", function()
		local auction = Shopping()
		if not (auction and shown) then return end
		for _, ask in ipairs(sheet.asks or {}) do
			if ask.kind == "Item" then auction.AddToShopping(ask.id, ask.count, ns.QuestName(shown)) end
		end
	end)
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
	sheet:SetScript("OnEvent", function(_, event)
		if event == "GET_ITEM_INFO_RECEIVED" and not waiting then return end
		if sheet.soon then return end
		sheet.soon = true
		C_Timer.After(0.2, function()
			sheet.soon = false
			if sheet:IsShown() then Draw() end
		end)
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
