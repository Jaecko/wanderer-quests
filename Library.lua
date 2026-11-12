local _, ns = ...
local L = ns.L

-- The books tab: the books of the libraries (LibraryData.lua), each with where it lies and where you stand
-- with it: to find, in your bags (to hand in), handed in; those not in the game yet, apart. On top, how many
-- you have handed in and the next reward; your librarian on the map; with Wanderer Maps, a route through the
-- books still to find. A book clicked: followed (Wanderer Maps) or the game's own pin on it, one in your bags
-- to whoever takes it (the librarian, or for some the mage trainer); right click: its menu.

local W = Wanderer
local U = W.Util
local Skin = W.Skin
local Safe, Clean = U.Safe, U.Clean

local ROW = rawget(Skin, "ROW") and Skin.ROW.compact or 24 -- (read raw: an older Wanderer has none)
local MAX_ROWS = 40
local ICON = "Interface\\Icons\\INV_Misc_Book_07"

local view, list
local rows = {}

local function Side() return Clean(Safe(UnitFactionGroup, "player")) end

local function Done(quest) return Clean(Safe(C_QuestLog.IsQuestFlaggedCompleted, quest)) and true or false end

local function BookName(book)
	local name = U.ItemName(book.item)
	if name then return name end
	ns.AskItem(book.item)
	return Clean(Safe(C_QuestLog.GetTitleForQuestID, book.quest)) or ("#" .. book.item)
end

local function MapName(map) return U.MapName(map) or "?" end

-- Where you stand with a book: "done", "carried", "find", "soon".
local function State(book)
	if Done(book.quest) then return "done" end
	if U.ItemCount(book.item, true) > 0 then return "carried" end
	if book.soon then return "soon" end
	return "find"
end

local ORDER = { carried = 1, find = 2, soon = 3, done = 4 }
local CHIPS = {
	done = { "LIBRARY_DONE", "green" }, carried = { "LIBRARY_CARRIED", "gold" },
	soon = { "LIBRARY_SOON", "grey" },
}

-- The books your side can take, in the order to see them: in your bags, to find (by level), not yet, handed in.
local function Books()
	local side, found = Side(), {}
	for _, book in ipairs(ns.LIBRARY_BOOKS or {}) do
		if not book.side or book.side == side then
			found[#found + 1] = { book = book, state = State(book), name = BookName(book) }
		end
	end
	table.sort(found, function(a, b)
		if a.state ~= b.state then return ORDER[a.state] < ORDER[b.state] end
		if a.book.level ~= b.book.level then return a.book.level < b.book.level end
		return a.name < b.name
	end)
	return found
end

-- A book's place (its first), followed or pinned.
local function Spot(book)
	local at = book.at[1]
	return at[1], at[2], at[3]
end

-- Who takes a book: { name, map, x, y (0 to 100), librarian (your librarian) }; nil when your side has none.
local function HandIn(book)
	local side = Side() or ""
	local npc = book.to == "mage" and ns.LIBRARY_MAGES and ns.LIBRARY_MAGES[side]
	if npc then
		local who = ns.Npc(npc)
		local map = who and ns.MapOf(who.zone)
		return { name = who and who.name or ("#" .. npc), map = map, x = map and who.x, y = map and who.y }
	end
	local at = ns.LIBRARIANS and ns.LIBRARIANS[side]
	return at and { librarian = true, map = at[1], x = at[2], y = at[3] } or nil
end

-- "Hand it to ... (where)".
local function HandText(to)
	local where = to.map and MapName(to.map) or "?"
	if to.librarian then return L.LIBRARY_HAND_LIBRARIAN:format(where) end
	return L.LIBRARY_HAND_TO:format(to.name, where)
end

local function GoHandIn(book)
	local to = HandIn(book) or {}
	ns.GoOrSay(to.map, to.x, to.y, to.librarian and L.LIBRARY_LIBRARIAN or to.name)
end

-- A book clicked: carried, to whoever takes it; else to where it lies.
local function GoTo(entry)
	if entry.state == "carried" then return GoHandIn(entry.book) end
	local map, x, y = Spot(entry.book)
	ns.GoOrSay(map, x, y, entry.name)
end

-- For Wanderer's reader: a library book of your side says who takes it, or that it was handed in (nil: not one).
function ns.BookNote(title, item)
	local side = Side()
	for _, book in ipairs(ns.LIBRARY_BOOKS or {}) do
		if (item and item == book.item) or (title and title ~= "" and title == U.ItemName(book.item)) then
			if book.side and book.side ~= side then return nil end
			if Done(book.quest) then return L.LIBRARY_NOTE_DONE end
			local to = HandIn(book)
			return to and L.LIBRARY_NOTE:format(HandText(to)) or nil
		end
	end
	return nil
end

-- A book's card (its right click, its "..."): to whoever takes it, then each of its places (go there, a step of
-- the route).
local function BookMenu(owner, entry)
	local maps = ns.Maps()
	local choices = {}
	local to = entry.state ~= "done" and HandIn(entry.book)
	if to then choices[#choices + 1] = { text = HandText(to), glyph = "home", onClick = function() GoHandIn(entry.book) end } end
	-- (the step tied to its quest only when Quests can show it: a library's quest is not in its lists, and Wanderer
	-- Maps' "Open the quest" would then only say so; its name says the book)
	local info = ns.PlaceOf(entry.book.quest) and { quest = entry.book.quest } or nil
	for _, at in ipairs(entry.book.at) do
		local where = L.WHERE:format(MapName(at[1]), at[2], at[3])
		choices[#choices + 1] = { text = maps and L.GO_THERE or L.LIBRARY_PIN, glyph = "chevron", hint = where,
			onClick = function() ns.GoOrSay(at[1], at[2], at[3], entry.name) end }
		if maps and maps.AddStep then
			choices[#choices + 1] = { text = L.TO_ROUTE, glyph = "plus", hint = where,
				onClick = function() ns.SayToRoute({ map = at[1], x = at[2], y = at[3], name = entry.name }, info) end }
		end
	end
	Skin.ActionCard(owner, { title = entry.name, rows = choices, atCursor = true })
end

-- On top: how many handed in, the next reward.
local function Summary(found)
	local done, total = 0, 0
	for _, entry in ipairs(found) do
		if entry.state ~= "soon" then total = total + 1 end
		if entry.state == "done" then done = done + 1 end
	end
	local parts = { L.LIBRARY_COUNT:format(done, total) }
	for _, reward in ipairs(ns.LIBRARY_REWARDS or {}) do
		if not Done(reward.quest) then
			-- (enough books, but a level still to reach: said with it)
			if done >= reward.books and ns.YourLevel() < (reward.level or 1) then
				parts[#parts + 1] = L.LIBRARY_REWARD_LEVEL:format(reward.books, reward.level)
			elseif done >= reward.books then
				parts[#parts + 1] = Skin.Colorize(L.LIBRARY_REWARD_READY:format(reward.books), "good")
			else
				parts[#parts + 1] = L.LIBRARY_REWARD_NEXT:format(reward.books - done, reward.books)
			end
			break
		end
	end
	return table.concat(parts, U.SEPARATOR)
end

function ns.DrawLibrary()
	if not (view and view:IsShown()) then return end
	rows = Books()
	view.summary:SetText(Summary(rows))
	view.route:SetShown(ns.Maps() ~= nil and ns.Maps().Route ~= nil)
	local offset = list:Clamp(#rows)
	for index, row in ipairs(list.rows) do
		local entry = rows[index + offset]
		-- (the "⋯" under the mouse, as every row of Wanderer: its right click's choices)
		if not row.menu then row.menu = Skin.RowMore(row, function(owner) if owner.entry then BookMenu(owner, owner.entry) end end) end
		if entry then
			local book, map = entry.book, entry.book.at[1][1]
			entry.icon = ICON
			entry.color = entry.state == "done" and ns.STATUS_COLORS.closed or entry.state == "soon" and Skin.COLORS.muted or nil
			local where = MapName(map) .. (book.at[2] and (" / " .. MapName(book.at[2][1])) or "")
			local chip = CHIPS[entry.state]
			-- (hovered: who takes it, where it lies)
			local to = entry.state ~= "done" and HandIn(book)
			entry.tip = { entry.name, to and HandText(to) or nil }
			if book.unsure then entry.tip[#entry.tip + 1] = L.LIBRARY_UNSURE end
			row:Fill(entry, false, {
				zone = Skin.Colorize(where, "label"),
				level = Skin.Colorize(tostring(book.level), "muted"),
				sure = book.unsure and Skin.Colorize(L.LIBRARY_UNSURE, "muted") or "",
			}, chip and L[chip[1]] or nil, chip and chip[2] or nil)
		else
			row:Fill(nil)
		end
	end
	list.empty:SetShown(#rows == 0)
end

-- The books still to find as a route of Wanderer Maps (each the nearest from the last).
local function BooksRoute()
	local maps = ns.Maps()
	if not (maps and maps.Route) then return end
	local places = {}
	for _, entry in ipairs(rows) do
		if entry.state == "find" and not entry.book.unsure then
			local map, x, y = Spot(entry.book)
			places[#places + 1] = { map = map, x = x / 100, y = y / 100, title = entry.name }
		end
	end
	if not places[1] or maps.Route(places) == 0 then W.Print(L.LIBRARY_ROUTE_NONE) end
end

local function Librarian()
	local at = ns.LIBRARIANS and ns.LIBRARIANS[Side() or ""]
	if not at then return end
	ns.GoOrSay(at[1], at[2], at[3], L.LIBRARY_LIBRARIAN)
end

function ns.LibraryView(parent, width)
	view = CreateFrame("Frame", nil, parent)
	view.summary = Skin.Text(view, "GameTooltipText", "text")
	view.summary:SetPoint("TOPLEFT", view, "TOPLEFT", 0, -10)
	view.summary:SetJustifyH("LEFT")
	view.librarian = Skin.Button(view, L.LIBRARY_LIBRARIAN, Librarian)
	view.librarian:SetHeight(24)
	view.librarian:SetPoint("TOPRIGHT", view, "TOPRIGHT", 0, -4)
	Skin.Tooltip(view.librarian, L.LIBRARY_LIBRARIAN_DESC)
	view.route = Skin.Button(view, L.LIBRARY_ROUTE, BooksRoute)
	view.route:SetHeight(24)
	view.route:SetPoint("RIGHT", view.librarian, "LEFT", -6, 0)
	Skin.Tooltip(view.route, L.LIBRARY_ROUTE_DESC)
	view.summary:SetPoint("RIGHT", view.route, "LEFT", -10, 0)
	list = Skin.Table(view, {
		width = width, rows = MAX_ROWS, rowHeight = ROW, titles = false, icon = true,
		onClick = function(entry, mouse)
			if mouse == "RightButton" then
				for _, row in ipairs(list.rows) do
					if row.entry == entry then return BookMenu(row, entry) end
				end
				return
			end
			if entry.state ~= "done" then GoTo(entry) end
		end,
		onDraw = ns.DrawLibrary,
		padRight = true, padRightWord = "MORE", -- (its right click: the book's choices)
		columns = { { key = "sure", width = 110 }, { key = "zone", width = 230 }, { key = "level", width = 40, justify = "RIGHT" },
			{ key = "pad", width = Skin.ROW_MORE } },
	})
	list:SetPoint("TOPLEFT", view, "TOPLEFT", 0, -40)
	list:SetPoint("RIGHT", view, "RIGHT", 0, 0)
	list.empty:SetText(L.LIBRARY_NONE)
	function view:Fit(height) list:Fit(height - 40) end
	view:Hide()
	return view
end
