local _, ns = ...
local L = ns.L

-- Where an item your quests ask for comes from: the creatures that drop it, the merchants that sell it, the objects
-- of the world that hold it. Under the item's tooltip while a quest of your log still asks for it (in your bags, on
-- the sheet, on the objectives' list): the nearest of each, with its zone. A click on the item (the sheet, the
-- objectives' list) opens a card: the way to the nearest, a step of the route (with Wanderer Maps), its card in the
-- bestiary (with Wanderer Bestiary), the others. Nothing of it needs another addon.

local W = Wanderer
local U = W and W.Util

local HOW = { drop = "SOURCE_DROP", sold = "SOURCE_SOLD", held = "SOURCE_HELD" }
local OTHERS_MOST = 5

-- The items the quests of your log still ask for (item -> its quest), made again when the log changes.
local asked
local function Asked()
	if asked then return asked end
	asked = {}
	local log = C_QuestLog
	if not (ns.HasData() and log and log.GetNumQuestLogEntries and log.GetInfo) then return asked end
	for at = 1, U.Clean(U.Safe(log.GetNumQuestLogEntries)) or 0 do
		local info = U.Safe(log.GetInfo, at)
		local id = type(info) == "table" and not U.Clean(info.isHeader) and U.Clean(info.questID)
		if id and not U.Clean(U.Safe(log.IsComplete, id)) then
			local quest = ns.Quest(id)
			if quest and quest.row then
				for _, ask in ipairs(ns.Asks(quest)) do
					if ask.kind == "Item" and not asked[ask.id] then asked[ask.id] = quest end
				end
			end
		end
	end
	return asked
end


-- One line of a source: how it comes ("Dropped by"), its name, its zone.
local function SourceLine(how, who)
	local where = who.zone and ns.AreaName(who.zone)
	return W.Skin.Colorize(L[HOW[how]], "label") .. "  " .. W.Skin.Colorize(who.name, "text")
		.. (where and W.Skin.Colorize("  \194\183  " .. where, "muted") or "")
end

-- The nearest of each way it comes, at most three lines.
function ns.SourceLines(item)
	local lines, said = {}, {}
	for _, source in ipairs(ns.ItemSources(item)) do
		if not said[source.how] then
			said[source.how] = true
			lines[#lines + 1] = SourceLine(source.how, source.who)
		end
	end
	return lines
end

-- (under an item's tooltip: where it comes from, while a quest asks for it; the hint on our own lines)
local function OnTooltip(tooltip, id)
	if not (id and Asked()[id]) then return false end
	local lines = ns.SourceLines(id)
	if not lines[1] then return false end
	for _, line in ipairs(lines) do tooltip:AddLine(line, 1, 1, 1) end
	local owner = tooltip.GetOwner and tooltip:GetOwner()
	if type(owner) == "table" and owner.questsSources then tooltip:AddLine(W.Skin.Colorize(L.SOURCE_CLICK, "blue"), 1, 1, 1) end
	return true
end

-- The card of an item's sources, at the line clicked (or the mouse).
function ns.SourceCard(item, anchor)
	local sources = item and ns.ItemSources(item) or {}
	if not sources[1] then return false end
	local quest = Asked()[item]
	local info = quest and { kind = "objective", quest = quest.id, label = ns.QuestName(quest) } or nil
	local rows = {}
	local first = sources[1]
	if first.who.x then
		rows[#rows + 1] = { text = L.SOURCE_NEAREST:format(first.who.name), glyph = "chevron", onClick = function() ns.Follow(first.who, info) end }
		if ns.Maps() then rows[#rows + 1] = { text = L.ACTION_ROUTE_MENU, glyph = "plus", onClick = function() ns.SayToRoute(first.who, info) end } end
	end
	-- (the nearest creature that drops it: its card in the bestiary)
	local bestiary = _G.WandererBestiary
	if type(bestiary) == "table" and bestiary.Show then
		for _, source in ipairs(sources) do
			if source.how == "drop" and bestiary.Known(source.who.id) then
				rows[#rows + 1] = { text = L.SOURCE_BESTIARY:format(source.who.name), glyph = "grid",
					onClick = function() bestiary.Show(source.who.id, ns.SheetShown() and ns.SheetFrame() or nil) end }
				break
			end
		end
	end
	local others = 0
	for at = 2, #sources do
		local who = sources[at].who
		if who.x and others < OTHERS_MOST then
			others = others + 1
			rows[#rows + 1] = { text = L.SOURCE_GO:format(L[HOW[sources[at].how]], who.name, ns.AreaName(who.zone) or "?"), glyph = "chevron",
				onClick = function() ns.Follow(who, info) end }
		end
	end
	if not rows[1] then return false end
	W.Skin.Play("click")
	W.Skin.ActionCard(anchor, { title = U.ItemName(item) or "", rows = rows, atCursor = anchor == nil })
	return true
end

-- Started with the addon (a Wanderer recent enough): the log listened to, the items' tooltips.
function ns.InitSources()
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("QUEST_LOG_UPDATE")
	watcher:SetScript("OnEvent", function() asked = nil end)
	if U.OnItemTooltip then U.OnItemTooltip(OnTooltip) end
end
