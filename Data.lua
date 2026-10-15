local _, ns = ...

-- The quests of the dungeons and raids, and the quests that lead to them
-- (QuestData.lua, the names in Names_*.lua), with where you stand with each:
-- the game says what is done or in your log; the rest (who gives it, what
-- comes before, for whom) is in the data. The places of the givers are areas
-- (0 to 100); the game's maps are found by their names.

local W = Wanderer
local U = W and W.Util
local Safe, Clean = U and U.Safe, U and U.Clean

local MAX_DEPTH = 25 -- quests before quests, at most
-- The category of each class's own quests (class id -> its quest sort), and the bands of levels they go by.
local CLASS_SORT = { [1] = -81, [2] = -141, [3] = -261, [4] = -162, [5] = -262, [7] = -82, [8] = -161, [9] = -61, [11] = -263 }
local BANDS = { { 1, 9 }, { 10, 19 }, { 20, 29 }, { 30, 39 }, { 40, 49 }, { 50, 60 } }
local ALLIANCE, HORDE = 77, 178 -- the races of each side (humans, dwarves, night elves, gnomes; the others)

-- The data comes as text (QuestData.lua, Names_*.lua): nearly nothing to read at login. Only English
-- (the fallback) and your client's names are kept; the rest is let go at once.
local language = GetLocale and GetLocale() or "enUS"
for locale in pairs(ns.NAME_SOURCES or {}) do
	if locale ~= "enUS" and locale ~= language then ns.NAME_SOURCES[locale] = nil end
end

-- A chunk of text made into its table (nil when it cannot be).
local function Read(source)
	local compile = loadstring or load
	local made = type(source) == "string" and compile and compile(source)
	if not made then return nil end
	local ok, value = pcall(made)
	return ok and type(value) == "table" and value or nil
end

-- The tables made when first needed (the window opened), then the text let go.
local function LoadData()
	if ns.QUESTS or not ns.QUEST_SOURCE then return end
	local data = Read(ns.QUEST_SOURCE)
	ns.QUEST_SOURCE = nil
	if not data then return end
	ns.DUNGEONS, ns.ZONES, ns.QUESTS, ns.UNITS, ns.OBJECTS = data.dungeons, data.zones, data.quests, data.units, data.objects
	-- The names: English, your language's over them (a name it lacks stays English).
	local sources = ns.NAME_SOURCES or {}
	local names = Read(sources.enUS) or { quests = {}, units = {}, objects = {} }
	local yours = language ~= "enUS" and Read(sources[language]) or nil
	for kind, list in pairs(yours or {}) do
		names[kind] = names[kind] or {}
		for id, name in pairs(list) do names[kind][id] = name end
	end
	ns.NAMES, ns.NAME_SOURCES = names, nil
end

function ns.HasData()
	LoadData()
	return type(ns.QUESTS) == "table"
end

local function Names(kind) return ns.NAMES and ns.NAMES[kind] or {} end

-- Reading -----------------------------------------------------------------------------------

local EMPTY = {} -- (shared, never written)
local quests = {}
function ns.Quest(id)
	if quests[id] ~= nil then return quests[id] or nil end
	local row = ns.QUESTS and ns.QUESTS[id]
	if not row then
		quests[id] = false
		return nil
	end
	quests[id] = {
		id = id, name = Names("quests")[id], questLevel = row.lvl, requiredLevel = row.min,
		requiredRaces = row.races or 0, requiredClasses = row.classes or 0, zone = row.zone,
		before = row.before or EMPTY, any = row.any or false, exclusiveTo = row.excl or EMPTY, row = row,
	}
	return quests[id]
end

-- A quest's name in your language: the game's when it knows it (kept once given), else the data's.
function ns.QuestName(quest)
	if not quest.title and C_QuestLog then quest.title = Clean(Safe(C_QuestLog.GetTitleForQuestID, quest.id)) end
	return quest.title or quest.name or ("#" .. quest.id)
end

-- You ------------------------------------------------------------------------------------------

local function Has(mask, flag) return (mask % (2 * flag)) >= flag end

local you = {}
-- Asked of the game once per drawing; forYou and your class's quests, once per character.
local statuses, passed, done, inLog, forYou = {}, {}, {}, {}, {}
local bands
function ns.ReadYou()
	statuses, passed, done, inLog = {}, {}, {}, {}
	local _, _, race = Safe(UnitRace, "player")
	local _, _, class = Safe(UnitClass, "player")
	race, class = Clean(race), Clean(class)
	you.race = race and race <= 8 and 2 ^ (race - 1) or nil -- the original races (others: by their side)
	you.class = class and 2 ^ (class - 1) or nil
	you.classId = class
	you.faction = Clean(Safe(UnitFactionGroup, "player")) == "Horde" and "H" or "A"
	you.level = Clean(Safe(UnitLevel, "player")) or 1
	-- Another character (or race, class, side): who may take what, asked again.
	local who = tostring(race) .. ":" .. tostring(class) .. ":" .. you.faction
	if who ~= you.who then forYou, bands, you.who = {}, nil, who end
end

function ns.YourLevel() return you.level or 1 end

-- A race mask for you: your race in it; a race the original game did not know, by its side.
local function YourRace(mask)
	if you.race then return Has(mask, you.race) end
	local side = you.faction == "H" and HORDE or ALLIANCE
	for bit = 0, 7 do
		local flag = 2 ^ bit
		if Has(side, flag) and Has(mask, flag) then return true end
	end
	return false
end

-- An NPC or an object of the data: { kind, id, name, x, y, zone, faction } (nil when unknown).
local function Someone(kind, id)
	local entry = (kind == "Npc" and ns.UNITS or ns.OBJECTS or EMPTY)[id]
	local names = Names(kind == "Npc" and "units" or "objects")
	local place = entry and entry[1] or EMPTY
	return { kind = kind, id = id, name = names[id] or ("#" .. id), x = place[1], y = place[2], zone = place[3],
		faction = entry and entry[2] ~= "" and entry[2] or nil }
end

-- Who gives it (u, o, i) or takes it back (eu, eo): an NPC, an object (the first of your side, when some
-- are of one), or (giving) an item found.
local GIVERS = { { "u", "UNITS", "units", "Npc" }, { "o", "OBJECTS", "objects", "Object" } }
local ENDERS = { { "eu", "UNITS", "units", "Npc" }, { "eo", "OBJECTS", "objects", "Object" } }
local function Who(quest, kinds, items)
	local row = quest.row
	local first
	for _, kind in ipairs(kinds) do
		local all = ns[kind[2]]
		for _, id in ipairs(row[kind[1]] or EMPTY) do
			local entry = all and all[id]
			if entry then
				local side = entry[2] ~= "" and entry[2] or nil
				local open = side ~= "A" and side ~= "H" or side == you.faction
				if open then return Someone(kind[4], id) end
				first = first or Someone(kind[4], id)
			end
		end
	end
	if first then return first end
	local item = items and (row.i or EMPTY)[1]
	if item then
		return { kind = "Item", id = item, name = U.ItemName(item) or ("#" .. item) }
	end
	return nil
end

function ns.Giver(quest) return Who(quest, GIVERS, true) end
function ns.Ender(quest) return Who(quest, ENDERS, false) end

-- What it asks: { { kind ("Item", "Npc", "Object"), id, count, name (an item's: the game's, nil until it
-- knows it) } }.
function ns.Asks(quest)
	local row, list = quest.row, {}
	local items, kills = row.r or EMPTY, row.k or EMPTY
	for index = 1, #items, 2 do
		local id = items[index]
		list[#list + 1] = { kind = "Item", id = id, count = items[index + 1] or 1, name = U.ItemName(id) }
	end
	for index = 1, #kills, 2 do
		local id = kills[index]
		local who = Someone(id > 0 and "Npc" or "Object", math.abs(id))
		who.count = kills[index + 1] or 1
		list[#list + 1] = who
	end
	return list
end

-- The rewards as the game gives them -------------------------------------------------------------------
-- Forever changed some quests' rewards: what the game shows wins over the old base. Kept for the whole
-- account (WandererQuestsDB.rewards: quest -> { rc, rg, m }, as in the data), only for the quests seen.

local function Seen()
	WandererQuestsDB = type(WandererQuestsDB) == "table" and WandererQuestsDB or {}
	WandererQuestsDB.rewards = type(WandererQuestsDB.rewards) == "table" and WandererQuestsDB.rewards or {}
	return WandererQuestsDB.rewards
end

-- Items as the data keeps them: { id, count, id, count... }; nil when one is not known yet (asked again later).
local function ReadItems(count, read)
	local list = {}
	for index = 1, count do
		local id, amount = read(index)
		if not id then return nil end
		list[#list + 1], list[#list + 2] = id, amount or 1
	end
	return list
end

local function Keep(questID, choice, given, money)
	if not (questID and questID > 0 and choice and given) then return false end
	if choice[1] or given[1] or money > 0 then Seen()[questID] = { rc = choice, rg = given, m = money } end
	return true
end

-- The quest the game's window shows (offered, its progress, given back).
function ns.LearnShown()
	local id = Clean(Safe(GetQuestID))
	local function Reader(kind)
		return function(index)
			local item = U.ItemID(Clean(Safe(GetQuestItemLink, kind, index)))
			local _, _, amount = Safe(GetQuestItemInfo, kind, index)
			return item, Clean(amount)
		end
	end
	local choice = ReadItems(Clean(Safe(GetNumQuestChoices)) or 0, Reader("choice"))
	local given = ReadItems(Clean(Safe(GetNumQuestRewards)) or 0, Reader("reward"))
	return Keep(id, choice, given, Clean(Safe(GetRewardMoney)) or 0)
end

-- A quest of your log (its choices read with it chosen in the log, the one chosen before given back).
function ns.LearnLog(questID)
	local log = C_QuestLog
	if not (log and questID and log.SetSelectedQuest) then return false end
	local index = Clean(Safe(log.GetLogIndexForQuestID, questID))
	if not (index and index > 0) then return false end
	local before = Clean(Safe(log.GetSelectedQuest))
	Safe(log.SetSelectedQuest, questID)
	local choice = ReadItems(Clean(Safe(GetNumQuestLogChoices, questID, false)) or 0, function(i)
		local _, _, amount, _, _, item = Safe(GetQuestLogChoiceInfo, i)
		return Clean(item), Clean(amount)
	end)
	local given = ReadItems(Clean(Safe(GetNumQuestLogRewards, questID)) or 0, function(i)
		local _, _, amount, _, _, item = Safe(GetQuestLogRewardInfo, i, questID)
		return Clean(item), Clean(amount)
	end)
	local money = Clean(Safe(GetQuestLogRewardMoney, questID)) or 0
	if before then Safe(log.SetSelectedQuest, before) end
	return Keep(questID, choice, given, money)
end

-- Every quest of your log.
function ns.LearnAllLog()
	local log = C_QuestLog
	if not (log and log.GetNumQuestLogEntries and log.GetInfo) then return end
	for index = 1, Clean(Safe(log.GetNumQuestLogEntries)) or 0 do
		local info = Safe(log.GetInfo, index)
		local id = type(info) == "table" and not Clean(info.isHeader) and Clean(info.questID)
		if id then ns.LearnLog(id) end
	end
end

do
	local learner = CreateFrame("Frame")
	for _, event in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_ACCEPTED" }) do
		pcall(learner.RegisterEvent, learner, event)
	end
	learner:SetScript("OnEvent", function(_, event, questID)
		if event == "QUEST_ACCEPTED" then
			ns.LearnLog(Clean(questID))
		elseif not ns.LearnShown() then
			-- (an item the game was still fetching: read again a moment after)
			C_Timer.After(0.5, ns.LearnShown)
		end
	end)
end

-- What it gives: { choice = { items, one of them yours }, given = { items }, money (copper), seen (as the game
-- gives them, else the old base's) }; each item { id, count, name, link, icon, quality } (name and link nil
-- until the game knows the item: asked then).
function ns.Rewards(quest)
	local seen = Seen()[quest.id]
	local row = seen or quest.row
	local function Items(list)
		local items = {}
		for index = 1, #list, 2 do
			local id = list[index]
			local name, link, quality = U.ItemInfo(id)
			if not name then U.LoadItem(id) end
			items[#items + 1] = { id = id, count = list[index + 1] or 1, name = name, link = link, quality = quality, icon = U.ItemIcon(id) }
		end
		return items
	end
	return { choice = Items(row.rc or EMPTY), given = Items(row.rg or EMPTY), money = row.m or 0, seen = seen ~= nil }
end

-- One of its rewards better for you (Wanderer's comparison, for your branch): true, false, or nil while the
-- game is still fetching one of them.
function ns.RewardUpgrade(quest)
	if not (W and W.IsUpgrade) then return false end
	local rewards = ns.Rewards(quest)
	local waiting = false
	for _, list in ipairs({ rewards.choice, rewards.given }) do
		for _, item in ipairs(list) do
			if not item.link then
				waiting = true
			elseif W.IsUpgrade(item.link) then
				return true
			end
		end
	end
	if waiting then return nil end
	return false
end

-- A dungeon's own quests you could take now (to take, not in your log), and its levels.
function ns.Waiting(dungeon)
	local count = 0
	for _, id in ipairs(ns.Index()[dungeon.id] or EMPTY) do
		local quest = ns.Quest(id)
		if ns.ForYou(quest) and ns.Status(quest) == "available" then count = count + 1 end
	end
	return count, ns.Summary(dungeon.id, "dungeons")
end

-- Its texts in your language: what to do, its story ($B a new line; your name, class, race; he or she).
local texts
function ns.Texts(quest)
	if texts == nil then
		texts = Read(ns.TEXT_SOURCE) or false
		ns.TEXT_SOURCE = nil
	end
	local entry = texts and texts[quest.id]
	if not entry then return nil, nil end
	local name = Clean(Safe(UnitName, "player")) or ""
	local class = Clean(Safe(UnitClass, "player")) or ""
	local race = Clean(Safe(UnitRace, "player")) or ""
	local female = Clean(Safe(UnitSex, "player")) == 3
	local function Fill(text)
		if not text or text == "" then return nil end
		text = text:gsub("%$[Bb]", "\n"):gsub("%$[Nn]", name):gsub("%$[Cc]", class):gsub("%$[Rr]", race)
		text = text:gsub("%$[Gg]%s*([^:;]*):([^;]*);", function(he, she) return female and she or he end)
		return text
	end
	return Fill(entry[1]), Fill(entry[2])
end

-- Yours to take one day: your race, your class, your side (a giver open to you).
local function ForYou(quest)
	local races, classes = quest.requiredRaces or 0, quest.requiredClasses or 0
	local everyone = races == 0 or races % 256 == 255
	if not everyone and not YourRace(races) then return false end
	if classes > 0 and you.class and not Has(classes, you.class) then return false end
	if everyone then
		local giver = ns.Giver(quest)
		local side = giver and giver.faction
		if (side == "A" or side == "H") and side ~= you.faction then return false end
	end
	return true
end

function ns.ForYou(quest)
	if not quest then return false end
	if forYou[quest.id] == nil then forYou[quest.id] = ForYou(quest) end
	return forYou[quest.id]
end

-- Where you stand -------------------------------------------------------------------------------

-- Done, in your log: asked of the game once per drawing.
local function Done(id)
	local value = done[id]
	if value == nil then
		value = Clean(Safe(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, id)) and true or false
		done[id] = value
	end
	return value
end
local function InLog(id)
	local value = inLog[id]
	if value == nil then
		local index = Clean(Safe(C_QuestLog and C_QuestLog.GetLogIndexForQuestID, id))
		value = index ~= nil and index > 0
		inLog[id] = value
	end
	return value
end

-- What must be done before: all of them, or one when they are the choices of a group.
local function Open(quest)
	local list = quest.before
	if not list[1] then return true end
	for _, id in ipairs(list) do
		local finished = Done(id)
		if quest.any and finished then return true end
		if not quest.any and not finished then return false end
	end
	return not quest.any
end

-- The quests that come after each one and need it (quest -> the ones with it before them, not as one
-- choice among others: reaching those says nothing of this one), read once.
local after
local function After(id)
	if not after then
		after = {}
		for other, row in pairs(ns.QUESTS or EMPTY) do
			if not row.any then
				for _, before in ipairs(row.before or EMPTY) do
					after[before] = after[before] or {}
					table.insert(after[before], other)
				end
			end
		end
	end
	return after[id] or EMPTY
end

-- One of the quests after it done (the game may start a chain further on, or another way). Only a
-- full answer is kept: a walk cut short (too deep, or a loop in the data) is asked again.
local function Passed(id, depth)
	local known = passed[id]
	if known == true or known == false then return known end
	if known == "busy" or depth > MAX_DEPTH then return false, true end
	passed[id] = "busy"
	local cut = false
	for _, later in ipairs(After(id)) do
		local yes, short
		if Done(later) or InLog(later) then yes = true else yes, short = Passed(later, depth + 1) end
		if yes then
			passed[id] = true
			return true
		end
		cut = cut or short
	end
	if cut then passed[id] = nil else passed[id] = false end
	return false, cut
end

-- "done", "active", "closed" (another one of a choice taken), "passed" (one after it done), "locked" (a quest
-- before), "level", "available".
local function Status(quest)
	if Done(quest.id) then return "done" end
	if InLog(quest.id) then return "active" end
	for _, other in ipairs(quest.exclusiveTo) do
		if Done(other) or InLog(other) then return "closed" end
	end
	if Passed(quest.id, 0) then return "passed" end
	if not Open(quest) then return "locked" end
	if (quest.requiredLevel or 0) > (you.level or 1) then return "level" end
	return "available"
end

function ns.Status(quest)
	local status = statuses[quest.id]
	if not status then
		status = Status(quest)
		statuses[quest.id] = status
	end
	return status
end

-- What comes after a quest: the quests (for you) that have it before them (a choice among others too).
local nextOf
function ns.Next(quest)
	if not nextOf then
		nextOf = {}
		for id, row in pairs(ns.QUESTS or EMPTY) do
			for _, before in ipairs(row.before or EMPTY) do
				nextOf[before] = nextOf[before] or {}
				table.insert(nextOf[before], id)
			end
		end
	end
	local list = {}
	for _, id in ipairs(nextOf[quest.id] or EMPTY) do
		local other = ns.Quest(id)
		if ns.ForYou(other) then list[#list + 1] = other end
	end
	table.sort(list, function(a, b) return (a.questLevel or 0) < (b.questLevel or 0) end)
	return list
end

-- What still holds a quest back: the names of the quests before it not done yet (one of them is enough
-- when they are a choice: then none is done).
function ns.Missing(quest)
	local names = {}
	if quest.any then
		for _, id in ipairs(quest.before) do
			if Done(id) then return names end
		end
	end
	for _, id in ipairs(quest.before) do
		local other = ns.Quest(id)
		if other and not Done(id) and ns.ForYou(other) then names[#names + 1] = ns.QuestName(other) end
	end
	return names
end

-- Maps ------------------------------------------------------------------------------------------

-- An area's name in your language (without what the game may add in parentheses, its English name).
function ns.AreaName(area)
	local name = area and Clean(Safe(C_Map and C_Map.GetAreaInfo, area))
	return name and (name:gsub("%s*%b()", "")) or nil
end

-- A place's name made comparable: lower case, without what the game adds in parentheses ("Les Paluns
-- (Wetlands)" is the map "Les Paluns").
local function Plain(name)
	return (name:gsub("%s*%b()", ""):gsub("^%s+", ""):gsub("%s+$", ""):lower())
end
ns.Plain = Plain

-- The game's maps of zones, by their names (in your language, as the areas' names are).
local maps
local mapOf = {} -- area -> its map (false: none), found once
local function FindMap(area)
	if not maps then
		maps = {}
		local zone = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
		local seen = {}
		for _, root in ipairs({ 947, 1414, 1415 }) do
			local children = C_Map and Safe(C_Map.GetMapChildrenInfo, root, nil, true)
			for _, info in ipairs(type(children) == "table" and children or EMPTY) do
				local name, id = Clean(info.name), Clean(info.mapID)
				if name and id and not seen[id] and (Clean(info.mapType) or zone) <= zone then
					seen[id] = true
					maps[#maps + 1] = { Plain(name), id }
				end
			end
		end
	end
	local name = ns.AreaName(area)
	if not name then return nil end
	name = Plain(name)
	-- The same name; else one inside the other (the closest: the longest).
	local best
	for _, map in ipairs(maps) do
		if map[1] == name then return map[2] end
		if map[1] ~= "" and (name:find(map[1], 1, true) or map[1]:find(name, 1, true)) and (not best or #map[1] > #best[1]) then
			best = map
		end
	end
	return best and best[2] or nil
end
local function MapOfArea(area)
	if mapOf[area] == nil then mapOf[area] = FindMap(area) or false end
	return mapOf[area] or nil
end

-- The game's own pin on a map (x, y: 0 to 100); false when it cannot.
function ns.PinMap(map, x, y) return U.Pin(map, x and x / 100, y and y / 100) end

function ns.Pin(area, x, y) return ns.PinMap(area and MapOfArea(area), x, y) end

-- The game's map of an area (nil when none is found).
function ns.MapOf(area) return area and MapOfArea(area) or nil end

-- The places ------------------------------------------------------------------------------------

-- The places of a list (area -> its entry): { id, name, and what extra(entry) adds }, made once.
local function Places(list, extra)
	local places = {}
	for id, entry in pairs(list or EMPTY) do
		local place = { id = id, name = ns.AreaName(id) or ("#" .. id) }
		if extra then extra(place, entry) end
		places[#places + 1] = place
	end
	return places
end

local dungeons, zones
function ns.Dungeons()
	dungeons = dungeons or Places(ns.DUNGEONS, function(place, entry) place.zone, place.raid = entry.zone, entry.raid or false end)
	return dungeons
end

function ns.Zones()
	zones = zones or Places(ns.ZONES)
	return zones
end

-- Its entrance, as the game's dungeon journal places it on the map around it: { map, x, y } or nil.
function ns.Entrance(dungeon)
	if dungeon.entrance ~= nil then return dungeon.entrance or nil end
	dungeon.entrance = false
	local map = MapOfArea(dungeon.zone)
	local journal = C_EncounterJournal
	local list = map and journal and Safe(journal.GetDungeonEntrancesForMap, map)
	-- Its own name; else one inside the other ("Deadmines", "The Deadmines"); else the only one there.
	local only, named, near = nil, nil, nil
	local wanted = Plain(dungeon.name)
	for _, entrance in ipairs(type(list) == "table" and list or EMPTY) do
		local name = Clean(entrance.name)
		name = name and Plain(name)
		if name == wanted then
			named = entrance
		elseif name and name ~= "" and wanted ~= "" and (name:find(wanted, 1, true) or wanted:find(name, 1, true)) then
			near = near or entrance
		end
		only = only == nil and entrance or false
	end
	local found = named or near or only or nil
	local position = found and found.position
	if position then
		local x, y = Safe(position.GetXY, position)
		x, y = Clean(x), Clean(y)
		if x and y then dungeon.entrance = { map = map, x = x * 100, y = y * 100 } end
	end
	return dungeon.entrance or nil
end

-- Your class's quests: those of its own category, and those of a zone only your class may take.
local function ClassQuests()
	local list = {}
	local sort = you.classId and CLASS_SORT[you.classId]
	for id, row in pairs(ns.QUESTS or EMPTY) do
		local classes = row.classes or 0
		if (sort and row.zone == sort) or (classes > 0 and you.class and Has(classes, you.class)) then list[#list + 1] = id end
	end
	return list
end

-- Your class's quests by bands of levels: { id (the band), name, ids }, made once per character.
local function ClassBands()
	if bands then return bands end
	bands = {}
	for index, band in ipairs(BANDS) do bands[index] = { id = index, low = band[1], high = band[2], ids = {} } end
	for _, id in ipairs(ClassQuests()) do
		local row = ns.QUESTS[id]
		local level = (row.lvl or 0) > 1 and row.lvl or row.min or 1
		for _, band in ipairs(bands) do
			if level >= band.low and (level <= band.high or band.high == BANDS[#BANDS][2]) then
				table.insert(band.ids, id)
				break
			end
		end
	end
	local L = ns.L
	for _, band in ipairs(bands) do
		band.name = L.LEVEL_RANGE:format(band.low, band.high)
		table.sort(band.ids)
	end
	return bands
end

-- The places of a kind: "class" (bands of levels), "dungeons" (and raids) or "zones".
function ns.Places(kind)
	if kind == "class" then return ClassBands() end
	return kind == "zones" and ns.Zones() or ns.Dungeons()
end

-- The quests of each place (its area -> quest ids, in order), read once: dungeons and zones alike.
local index
function ns.Index()
	if index then return index end
	index = {}
	for id, row in pairs(ns.QUESTS or EMPTY) do
		if (ns.DUNGEONS and ns.DUNGEONS[row.zone]) or (ns.ZONES and ns.ZONES[row.zone]) then
			index[row.zone] = index[row.zone] or {}
			table.insert(index[row.zone], id)
		end
	end
	for _, ids in pairs(index) do table.sort(ids) end
	return index
end

-- Where a quest is shown: your class's band first, else its dungeon, else its zone (kind, place), or nil.
function ns.PlaceOf(id)
	local quest = ns.Quest(id)
	if not quest then return nil end
	for _, band in ipairs(ClassBands()) do
		for _, other in ipairs(band.ids) do
			if other == id then return "class", band.id end
		end
	end
	if ns.DUNGEONS and ns.DUNGEONS[quest.zone] then return "dungeons", quest.zone end
	if ns.ZONES and ns.ZONES[quest.zone] then return "zones", quest.zone end
	return nil
end

-- The quests of a place.
local function QuestIds(place, kind)
	if kind == "class" then
		local band = ClassBands()[place]
		return band and band.ids or EMPTY
	end
	return ns.Index()[place] or EMPTY
end

-- A place's summary, without its tree: its levels, its quests for you and those done (or passed).
function ns.Summary(place, kind)
	local low, high, finished, total = nil, nil, 0, 0
	for _, id in ipairs(QuestIds(place, kind)) do
		local quest = ns.Quest(id)
		if ns.ForYou(quest) then
			total = total + 1
			local status = ns.Status(quest)
			if status == "done" or status == "passed" then finished = finished + 1 end
			-- (a quest of no set level, like an ale given inside, says nothing of the place's levels)
			local level = quest.questLevel or 0
			if level > 1 then low, high = math.min(low or level, level), math.max(high or level, level) end
		end
	end
	return { low = low, high = high, done = finished, total = total }
end

-- The place you are in, among those of a kind (by its name, as the game says it).
function ns.Here(kind)
	local here = Clean(Safe(GetRealZoneText))
	if not here then return nil end
	here = Plain(here)
	for _, place in ipairs(ns.Places(kind)) do
		if Plain(place.name) == here then return place.id end
	end
	return nil
end

-- A place's quests for you, with the quests that open them (wherever they are), as a tree:
-- { quest, depth, dungeon (one of the place's own), status }, the first ones first; and its summary.
function ns.Tree(place, kind)
	local own = {}
	local nodes, order = {}, {}
	local function Add(id, depth)
		if nodes[id] ~= nil or depth > MAX_DEPTH then return end
		local quest = ns.Quest(id)
		if not ns.ForYou(quest) then nodes[id] = false return end
		nodes[id] = { quest = quest }
		order[#order + 1] = id
		for _, before in ipairs(quest.before) do Add(before, depth + 1) end
	end
	for _, id in ipairs(QuestIds(place, kind)) do
		Add(id, 0)
		if nodes[id] then own[id] = true end
	end
	-- Each one under the first quest before it (one of yours), the others at the top.
	local children, roots = {}, {}
	for _, id in ipairs(order) do
		local node = nodes[id]
		node.dungeon = own[id] or false
		local parent
		for _, before in ipairs(node.quest.before) do
			if nodes[before] then parent = before break end
		end
		if parent then
			children[parent] = children[parent] or {}
			table.insert(children[parent], id)
		else
			roots[#roots + 1] = id
		end
	end
	local function ByLevel(a, b)
		local qa, qb = nodes[a].quest, nodes[b].quest
		if (qa.questLevel or 0) ~= (qb.questLevel or 0) then return (qa.questLevel or 0) < (qb.questLevel or 0) end
		return a < b
	end
	table.sort(roots, ByLevel)
	local list, seen = {}, {}
	local function Walk(id, depth)
		if seen[id] then return end
		seen[id] = true
		local node = nodes[id]
		node.depth, node.status = depth, ns.Status(node.quest)
		list[#list + 1] = node
		local under = children[id] or EMPTY
		table.sort(under, ByLevel)
		for _, child in ipairs(under) do Walk(child, depth + 1) end
	end
	for _, id in ipairs(roots) do Walk(id, 0) end
	-- Quests that wait on each other (a loop in the data): none is a root, each shown at the top all the same.
	for _, id in ipairs(order) do Walk(id, 0) end
	return list, ns.Summary(place, kind)
end
