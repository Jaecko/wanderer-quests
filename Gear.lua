local _, ns = ...
local L = ns.L

-- The gear tab: two character sheets side by side. On the left what you wear, slot by slot as on the game's
-- character sheet, and your characteristics; on the right, for each slot, the best piece a quest gives you
-- (from 6 levels below yours to 3 above, Wanderer's comparison for your branch), its gain, and your
-- characteristics if you wore them all. A click on a piece opens its quest's sheet: what to do, where.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin

local ROW = 36
local SIDE_GAP = 30
-- The slots as on the character sheet: two columns (the game's slot ids, Data.lua's groups).
local COLUMNS = {
	{ { 1, "head" }, { 2, "neck" }, { 3, "shoulder" }, { 15, "back" }, { 5, "chest" }, { 9, "wrist" }, { 10, "hand" },
		{ 6, "waist" }, { 7, "legs" } },
	{ { 8, "feet" }, { 11, "finger", 1 }, { 12, "finger", 2 }, { 13, "trinket", 1 }, { 14, "trinket", 2 },
		{ 16, "weapons" }, { 17, "offhand" }, { 18, "ranged" } },
}
-- The characteristics said under each sheet: the game's own names, the item stats that change them.
local STATS = {
	{ "SPELL_STAT1_NAME", "ITEM_MOD_STRENGTH_SHORT", 1 }, { "SPELL_STAT2_NAME", "ITEM_MOD_AGILITY_SHORT", 2 },
	{ "SPELL_STAT3_NAME", "ITEM_MOD_STAMINA_SHORT", 3 }, { "SPELL_STAT4_NAME", "ITEM_MOD_INTELLECT_SHORT", 4 },
	{ "SPELL_STAT5_NAME", "ITEM_MOD_SPIRIT_SHORT", 5 }, { "ARMOR", "RESISTANCE0_NAME" },
}

local view

-- Your characteristics now: { stat key = value }.
local function Current()
	local values = {}
	for _, stat in ipairs(STATS) do
		if stat[3] then
			local _, value = U.Safe(UnitStat, "player", stat[3])
			values[stat[2]] = U.Clean(value) or 0
		else
			local _, value = U.Safe(UnitArmor, "player")
			values[stat[2]] = U.Clean(value) or 0
		end
	end
	return values
end

-- One slot's square: its item's icon in its quality's edge, its name, a line under it.
local function Slot(parent)
	local slot = CreateFrame("Button", nil, parent)
	slot:SetHeight(ROW - 2)
	slot.icon = Skin.Icon(slot, ROW - 6)
	slot.icon:SetPoint("LEFT")
	slot.name = Skin.Text(slot, "GameFontHighlightSmall", "text")
	slot.name:SetPoint("TOPLEFT", slot.icon, "TOPRIGHT", 7, -2)
	slot.name:SetPoint("RIGHT", slot, "RIGHT", -2, 0)
	slot.name:SetJustifyH("LEFT")
	slot.name:SetWordWrap(false)
	slot.under = Skin.Text(slot, "GameTooltipTextSmall", "muted")
	slot.under:SetPoint("TOPLEFT", slot.name, "BOTTOMLEFT", 0, -2)
	slot.under:SetPoint("RIGHT", slot, "RIGHT", -2, 0)
	slot.under:SetJustifyH("LEFT")
	slot.under:SetWordWrap(false)
	slot.mark = slot:CreateTexture(nil, "BACKGROUND")
	slot.mark:SetAllPoints()
	slot.mark:SetColorTexture(0.31, 0.78, 0.43, 0.1)
	slot.mark:Hide()
	Skin.ItemTooltip(slot, function(self) return self.link end, "ANCHOR_RIGHT")
	return slot
end

-- A sheet: its title, its slots in two columns, its characteristics under them.
local function Sheet(parent, title, width)
	local sheet = CreateFrame("Frame", nil, parent)
	sheet:SetWidth(width)
	sheet.title = Skin.Caps(sheet, title, "gold")
	sheet.title:SetPoint("TOPLEFT")
	sheet.slots = {}
	local column = (width - 12) / 2
	for index, list in ipairs(COLUMNS) do
		for row, spec in ipairs(list) do
			local slot = Slot(sheet)
			slot:SetWidth(column)
			slot:SetPoint("TOPLEFT", sheet, "TOPLEFT", (index - 1) * (column + 12), -(18 + (row - 1) * ROW))
			slot.spec = spec
			sheet.slots[#sheet.slots + 1] = slot
		end
	end
	sheet.stats = {}
	local top = -(18 + #COLUMNS[1] * ROW + 12)
	for index, stat in ipairs(STATS) do
		local line = Skin.Text(sheet, "GameTooltipTextSmall", "soft")
		line:SetPoint("TOPLEFT", sheet, "TOPLEFT", ((index - 1) % 3) * (width / 3), top - math.floor((index - 1) / 3) * 16)
		line.stat = stat
		sheet.stats[index] = line
	end
	return sheet
end

-- The best quest pieces: slot group -> { the best, the second (rings, trinkets) }; none before you say what
-- you play.
local function Best()
	local best = {}
	if not (W.PlayChoice and W.PlayChoice()) then return best end
	for _, place in ipairs(ns.Places("gear")) do
		local list = {}
		for _, id in ipairs(ns.GearQuestIds(place.id)) do
			local found = ns.GearGain(id)
			if found and #list < 2 then list[#list + 1] = { id = id, gain = found.gain, link = found.link } end
		end
		best[place.id] = list
	end
	return best
end

local function Fill(slot, link, under, chosen)
	slot.link = link
	if link then
		local name, _, quality = U.ItemInfo(U.ItemID(link) or 0)
		slot.icon:Set(U.ItemIcon(U.ItemID(link) or 0), quality or 1)
		slot.name:SetText(name or "")
		Skin.Quality(slot.name, quality or 1)
	else
		slot.icon:Set(nil, 0)
		slot.name:SetText("")
	end
	slot.under:SetText(under or "")
	slot.mark:SetShown(chosen or false)
end

function ns.DrawGear()
	if not view then return end
	view.chosen = W.PlayChoice and W.PlayChoice() ~= nil
	view.play:Refresh()
	-- (Wanderer's comparison turned off: nothing is judged, said so)
	local tooltips = W.Settings and W.Settings("tooltips")
	local compared = tooltips and tooltips.upgrade
	if not compared then view.chosen = false end
	view.pick:SetText(compared and L.GEAR_PICK or L.GEAR_COMPARE_OFF)
	view.pick:SetShown(not view.chosen)
	local now = Current()
	local projected = {}
	for key, value in pairs(now) do projected[key] = value end
	local best = Best()
	for index, slot in ipairs(view.worn.slots) do
		local id, group, which = slot.spec[1], slot.spec[2], slot.spec[3] or 1
		local worn = U.Clean(U.Safe(GetInventoryItemLink, "player", id))
		Fill(slot, worn, worn and "" or U.Colorize(L.GEAR_EMPTY, unpack(Skin.COLORS.muted)))
		local target = view.quests.slots[index]
		local piece = best[group] and best[group][which]
		target.quest = piece and piece.id
		if piece then
			local quest = ns.Quest(piece.id)
			Fill(target, piece.link, U.Colorize("+" .. piece.gain .. " %", 0.56, 0.88, 0.64) .. "  " .. (quest and ns.QuestName(quest) or ""),
				true)
			-- (what it would change: its stats against what you wear there)
			local mine, theirs = U.ItemStats(piece.link), worn and U.ItemStats(worn) or {}
			for _, stat in ipairs(STATS) do
				projected[stat[2]] = projected[stat[2]] + (mine[stat[2]] or 0) - (theirs[stat[2]] or 0)
			end
		else
			Fill(target, nil, U.Colorize(view.chosen and L.GEAR_NONE or "", unpack(Skin.COLORS.muted)))
		end
	end
	for index, stat in ipairs(STATS) do
		local label = _G[stat[1]] or stat[1]
		view.worn.stats[index]:SetText(label .. " : " .. now[stat[2]])
		local change = projected[stat[2]] - now[stat[2]]
		view.quests.stats[index]:SetText(label .. " : " .. projected[stat[2]]
			.. (change > 0 and U.Colorize("  +" .. change, 0.56, 0.88, 0.64) or ""))
	end
end

-- Built once, in the window's right part and left list's place.
function ns.GearView(parent, width)
	view = CreateFrame("Frame", nil, parent)
	local half = math.floor((width - SIDE_GAP) / 2)
	-- What you play, on top: chosen by you, kept; the best pieces are judged for it.
	local label = Skin.Text(view, "GameTooltipTextSmall", "label")
	label:SetPoint("TOPLEFT", view, "TOPLEFT", 0, -6)
	label:SetText(L.PLAY_CHOICE)
	view.play = Skin.Dropdown(view, W.PlayChoices, function() return W.PlayChoice() end, function(id)
		W.PlayChoice(id)
		ns.ForgetGear()
		ns.DrawGear()
	end, L.PLAY_CHOICE_PICK)
	view.play:SetHeight(24)
	view.play:SetPoint("LEFT", label, "RIGHT", 10, 0)
	Skin.Tooltip(view.play, L.PLAY_CHOICE_DESC)
	view.worn = Sheet(view, L.GEAR_WORN, half)
	view.worn:SetPoint("TOPLEFT", view, "TOPLEFT", 0, -36)
	view.worn:SetPoint("BOTTOM")
	view.quests = Sheet(view, L.GEAR_BEST, half)
	view.quests:SetPoint("TOPLEFT", view.worn, "TOPRIGHT", SIDE_GAP, 0)
	view.quests:SetPoint("BOTTOM")
	-- (before a choice: what to do)
	view.pick = Skin.Text(view.quests, "GameTooltipText", "muted")
	view.pick:SetPoint("TOPLEFT", view.quests, "TOPLEFT", 0, -40)
	view.pick:SetWidth(half)
	view.pick:SetJustifyH("LEFT")
	view.pick:SetText(L.GEAR_PICK)
	local rule = Skin.Rule(view, true, 0.2)
	rule:SetPoint("TOPLEFT", view.worn, "TOPRIGHT", SIDE_GAP / 2, 0)
	rule:SetPoint("BOTTOM", view, "BOTTOM")
	-- A click on a piece: its quest's sheet.
	for _, slot in ipairs(view.quests.slots) do
		slot:SetScript("OnClick", function(self)
			local quest = self.quest and ns.Quest(self.quest)
			if quest and ns.ShowSheet then ns.ShowSheet(quest, ns.Window and ns.Window()) end
		end)
	end
	view.note = Skin.Text(view, "GameTooltipTextSmall", "muted")
	view.note:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 0)
	view.note:SetText(L.GEAR_NOTE)
	view:Hide()
	return view
end
