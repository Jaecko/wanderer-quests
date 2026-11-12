local _, ns = ...

-- The quests of the dungeons and raids, and the quests that lead to them
-- (QuestData.lua, the names in Names_*.lua), with where you stand with each:
-- the game says what is done or in your log; the rest (who gives it, what
-- comes before, for whom) is in the data. The places of the givers are areas
-- (0 to 100); the game's maps are found by their names.

local W = Wanderer
local U = W.Util
local Safe, Clean = U.Safe, U.Clean

local MAX_DEPTH = 25 -- quests before quests, at most
-- The category of each class's own quests (class id -> its quest sort), and the bands of levels they go by.
local CLASS_SORT = { [1] = -81, [2] = -141, [3] = -261, [4] = -162, [5] = -262, [7] = -82, [8] = -161, [9] = -61, [11] = -263 }
local BANDS = { { 1, 9 }, { 10, 19 }, { 20, 29 }, { 30, 39 }, { 40, 49 }, { 50, 60 } }
local ALLIANCE, HORDE = 77, 178 -- the races of each side (humans, dwarves, night elves, gnomes; the others)

-- The data comes as text (QuestData.lua, Names_*.lua): nearly nothing to read at login. Only English
-- (the fallback) and your client's names are loaded (the toc).
local language = GetLocale and GetLocale() or "enUS"

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

-- The creatures that drop what the quests ask (QuestData.lua: item -> creatures), turned around the first time a
-- creature is asked about (a few milliseconds, once): npc id -> { item id, ... }, else nil. Wanderer marks them.
local dropsOf, dropsFrom
local function Drops()
	if not dropsFrom then
		dropsFrom = Read(ns.DROP_SOURCE) or {}
		ns.DROP_SOURCE = nil
	end
	return dropsFrom
end
function ns.UnitDrops(npc)
	if not dropsOf then
		dropsOf = {}
		for item, units in pairs(Drops()) do
			for _, unit in ipairs(units) do
				local list = dropsOf[unit] or {}
				dropsOf[unit] = list
				list[#list + 1] = item
			end
		end
	end
	return dropsOf[npc]
end

-- Reading -----------------------------------------------------------------------------------

local EMPTY = {} -- (shared, never written)
local quests = {}
function ns.Quest(id)
	if quests[id] ~= nil then return quests[id] or nil end
	local row = ns.QUESTS and ns.QUESTS[id]
	if not row then
		-- (one of Forever's own, seen in the game: made from what it showed)
		quests[id] = ns.SeenQuest and ns.SeenQuest(id) or false
		return quests[id] or nil
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
local statuses, passed, done, inLog, forYou, chains, complete = {}, {}, {}, {}, {}, {}, {}
local bands
function ns.ReadYou()
	statuses, passed, done, inLog, chains, complete = {}, {}, {}, {}, {}, {}
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

-- A place of the world on a zone's map: x, y (0 to 100), nil when it lies outside.
local function OnZoneMap(continent, worldX, worldY, map)
	local _, x, y = U.WorldToMap(continent, worldX, worldY, map)
	if not x then return nil end
	return math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10
end

-- On a map Forever redrew, the old map's x and y land wrong: the place in the world (world x, y,
-- continent) is turned into the new map by the game itself. The old x and y when it cannot.
local redrawn = {} -- place -> { x, y } or false
local function OnNewMap(place)
	if redrawn[place] == nil then
		local x, y = OnZoneMap(place[6], place[4], place[5], ns.MapOf(place[3]))
		redrawn[place] = x and { x, y } or false
	end
	return redrawn[place]
end

-- An NPC or an object of the data: { kind, id, name, x, y, zone, faction } (nil when unknown).
local function Someone(kind, id)
	local entry = (kind == "Npc" and ns.UNITS or ns.OBJECTS or EMPTY)[id]
	local names = Names(kind == "Npc" and "units" or "objects")
	local place = entry and entry[1] or EMPTY
	local x, y = place[1], place[2]
	local moved = place[4] and OnNewMap(place)
	if moved then x, y = moved[1], moved[2] end
	return { kind = kind, id = id, name = names[id] or ("#" .. id), x = x, y = y, zone = place[3],
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

-- (a quest of Forever's own: the one seen giving it)
function ns.Giver(quest) return quest.seen or Who(quest, GIVERS, true) end

-- An NPC of the data, as Someone gives it (nil without the data).
function ns.Npc(id) return ns.HasData() and Someone("Npc", id) or nil end
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

-- Where to go on a map ------------------------------------------------------------------------------------
-- For Wanderer Maps' atlas: where the creatures and objects your quests still ask for stand (SpawnData.lua, by
-- packs), and who takes back a quest that is done.

local MOST_MARKS = 180 -- on one map
local SPAWN_CELL = 2 -- percent of the map: one mark per quest and per cell
local REDRAWN_SPAWNS = { -- the old map's bounds of the maps Forever redrew: { continent, min x, min y, max x, max y }
	[1519] = { 0, -9175.2, 36.7, -8278.9, 1381 }, [215] = { 1, -3697.9, -3089.6, -272.9, 2048 },
	[139] = { 0, 1218.8, -6056.3, 3800, -2185.4 }, [44] = { 0, -10022.9, -3741.7, -8575, -1570.8 },
}

local spawns
local function Spawns()
	if not spawns then
		spawns = Read(ns.SPAWN_SOURCE) or { u = {}, o = {} }
		ns.SPAWN_SOURCE = nil
	end
	return spawns
end

-- Its packs on this map, 0 to 100 (each(x, y)).
local function EachSpawn(list, id, map, each)
	local entry = list[id]
	for index = 1, #(entry or EMPTY), 2 do
		local zone, points = entry[index], entry[index + 1]
		if ns.MapOf(zone) == map then
			local old = REDRAWN_SPAWNS[zone]
			for at = 1, #points, 2 do
				local x, y = points[at], points[at + 1]
				if old then
					local wy, wx = old[5] - (x / 100) * (old[5] - old[3]), old[4] - (y / 100) * (old[4] - old[2])
					x, y = OnZoneMap(old[1], wx, wy, map)
				end
				if x then each(x, y) end
			end
		end
	end
end

-- An objective of the game is done: by what it asks for, when its words name it.
local function DoneAsk(ask, objectives)
	for _, objective in ipairs(objectives) do
		local text = Clean(objective.text)
		if text and ask.name and text:find(ask.name, 1, true) then return Clean(objective.finished) and true or false, text end
	end
	return false, nil
end

-- What your quests ask on a map: { { kind = "kill" | "loot" | "use" | "turnin", quest, title, name, x, y (0 to 1), words } },
-- and the list of those quests: nothing on a continent (too many to read).
function ns.ObjectivesOn(map)
	local marks, log = {}, C_QuestLog
	if not (ns.HasData() and map and log and log.GetNumQuestLogEntries and log.GetInfo) then return marks end
	local count = Clean(Safe(log.GetNumQuestLogEntries)) or 0
	local drops = Drops()
	local data = Spawns()
	for index = 1, count do
		local info = Safe(log.GetInfo, index)
		local id = type(info) == "table" and not Clean(info.isHeader) and Clean(info.questID)
		local quest = id and ns.Quest(id)
		if quest and quest.row and #marks < MOST_MARKS then
			local title = Clean(info.title) or ns.QuestName(quest)
			if Clean(Safe(log.IsComplete, id)) then
				local who = ns.Ender(quest)
				if who and who.zone and ns.MapOf(who.zone) == map and who.x then
					marks[#marks + 1] = { kind = "turnin", quest = id, title = title, name = who.name, x = who.x / 100, y = who.y / 100 }
				end
			else
				local objectives = Safe(log.GetQuestObjectives, id)
				objectives = type(objectives) == "table" and objectives or EMPTY
				local cells = {}
				local function Mark(kind, name, words, x, y, unit)
					local cell = math.floor(x / SPAWN_CELL) .. ":" .. math.floor(y / SPAWN_CELL)
					if cells[cell] or #marks >= MOST_MARKS then return end
					cells[cell] = true
					marks[#marks + 1] = { kind = kind, quest = id, title = title, name = name, words = words, x = x / 100, y = y / 100,
						unit = unit }
				end
				for _, ask in ipairs(ns.Asks(quest)) do
					local finished, words = DoneAsk(ask, objectives)
					if not finished then
						if ask.kind == "Npc" then
							EachSpawn(data.u, ask.id, map, function(x, y) Mark("kill", ask.name, words, x, y, ask.id) end)
						elseif ask.kind == "Object" then
							EachSpawn(data.o, ask.id, map, function(x, y) Mark("use", ask.name, words, x, y) end)
						else
							for _, unit in ipairs(drops[ask.id] or EMPTY) do
								local name = Names("units")[unit]
								EachSpawn(data.u, unit, map, function(x, y) Mark("loot", name, words or ask.name, x, y, unit) end)
							end
						end
					end
				end
			end
		end
	end
	return marks
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

-- The game's quest log in sight (its own window, or beside the map): what it shows is never changed.
local LOG_WINDOWS = { "QuestLogFrame", "QuestLogDetailFrame", "QuestLogPopupDetailFrame", "QuestMapFrame", "WorldMapFrame" }
local function LogInSight()
	for _, name in ipairs(LOG_WINDOWS) do
		local frame = _G[name]
		if type(frame) == "table" and frame.IsVisible and frame:IsVisible() then return true end
	end
	return false
end

-- A quest of your log (its choices read with it chosen in the log, the one chosen before given back at once).
-- While the log is in sight, only the quest it already shows is read: another one waits for a later look. Read
-- once (its rewards never change): kept from the game already, or read this session, it is left alone (each
-- change of the log's choice redraws the game's quest windows).
local learned = {}
function ns.LearnLog(questID)
	local log = C_QuestLog
	if not (log and questID and log.SetSelectedQuest) then return false end
	if learned[questID] or Seen()[questID] then return true end
	local index = Clean(Safe(log.GetLogIndexForQuestID, questID))
	if not (index and index > 0) then return false end
	local before = Clean(Safe(log.GetSelectedQuest))
	if before ~= questID and LogInSight() then return false end
	if before ~= questID then Safe(log.SetSelectedQuest, questID) end
	local choice = ReadItems(Clean(Safe(GetNumQuestLogChoices, questID, false)) or 0, function(i)
		local _, _, amount, _, _, item = Safe(GetQuestLogChoiceInfo, i)
		return Clean(item), Clean(amount)
	end)
	local given = ReadItems(Clean(Safe(GetNumQuestLogRewards, questID)) or 0, function(i)
		local _, _, amount, _, _, item = Safe(GetQuestLogRewardInfo, i, questID)
		return Clean(item), Clean(amount)
	end)
	local money = Clean(Safe(GetQuestLogRewardMoney, questID)) or 0
	if before ~= questID then Safe(log.SetSelectedQuest, before or 0) end
	local kept = Keep(questID, choice, given, money)
	if kept then learned[questID] = true end
	return kept
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

-- Heard once Wanderer Quests is set up (ns.Init), never at loading.
function ns.InitLearn()
	local learner = CreateFrame("Frame")
	for _, event in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_ACCEPTED" }) do
		pcall(learner.RegisterEvent, learner, event)
	end
	learner:SetScript("OnEvent", function(_, event, ...)
		if event == "QUEST_ACCEPTED" then
			ns.LearnLog(Clean(select(select("#", ...), ...)))
		elseif not ns.LearnShown() then
			-- (an item the game was still fetching: read again a moment after)
			C_Timer.After(0.5, ns.LearnShown)
		end
	end)
end

-- What the givers really offer you ----------------------------------------------------------------------
-- The data is the original game's: Forever changed who may take some quests and what comes before them, and
-- added quests of its own. What a giver offers this character is kept (WandererQuestsDB.offered: character
-- -> quest -> true; for a quest the data does not know, { npc, kind, name, title, lvl, map, x, y }, the giver
-- as the game showed it): such a quest is yours and open, whatever the data says. Kept once done too (a
-- quest the data says is not yours stays yours).

local offeredAll, offeredMine
local function Offers()
	WandererQuestsDB = type(WandererQuestsDB) == "table" and WandererQuestsDB or {}
	local all = WandererQuestsDB.offered
	if all == offeredAll and offeredMine and type(all) == "table" then return offeredMine end
	all = type(all) == "table" and all or {}
	WandererQuestsDB.offered = all
	local key = W.CharacterKey and W.CharacterKey() or "?"
	all[key] = type(all[key]) == "table" and all[key] or {}
	offeredAll, offeredMine = all, all[key]
	return offeredMine
end

-- Offered to you by a giver, once at least.
function ns.Offered(id) return id ~= nil and Offers()[id] ~= nil end

-- The other way: a quest the data gives to an NPC that NPC did not offer you, although you could take it
-- (Forever changed some, or keeps one closed). Kept with your level then (WandererQuestsDB.notOffered:
-- character -> quest -> level): asked again once you have gone up a level, or as soon as it is offered.
local notAll, notMine
local function NotOffers()
	WandererQuestsDB = type(WandererQuestsDB) == "table" and WandererQuestsDB or {}
	local all = WandererQuestsDB.notOffered
	if all == notAll and notMine and type(all) == "table" then return notMine end
	all = type(all) == "table" and all or {}
	WandererQuestsDB.notOffered = all
	local key = W.CharacterKey and W.CharacterKey() or "?"
	all[key] = type(all[key]) == "table" and all[key] or {}
	notAll, notMine = all, all[key]
	return notMine
end
function ns.NotOffered(id)
	local level = id ~= nil and NotOffers()[id]
	return type(level) == "number" and level >= (you.level or 1)
end
-- What was kept of a giver of Forever's own quest (nil for the others).
function ns.OfferRecord(id)
	local record = Offers()[id]
	return type(record) == "table" and record or nil
end

-- Known to the data (without reading it all when it is still text).
local function Known(id)
	if ns.QUESTS then return ns.QUESTS[id] ~= nil end
	return type(ns.QUEST_SOURCE) == "string" and ns.QUEST_SOURCE:find("\n[" .. id .. "]={lvl=", 1, true) ~= nil
end

local function Tenth(value) return value and math.floor(value * 1000 + 0.5) / 10 or nil end

-- The quests a giver offers: { { id, title, level } }. Only an NPC or an object of the world (a player
-- sharing a quest, an item starting one: no giver).
local function Learn(unit, list, whole)
	local guid = Clean(Safe(UnitGUID, unit))
	local kind = type(guid) == "string" and (guid:find("^Creature") or guid:find("^Vehicle")) and "Npc"
		or type(guid) == "string" and guid:find("^GameObject") and "Object" or nil
	local npc = kind and U.NpcID(guid)
	if not npc then return end
	local mine, unknown = Offers(), false
	for _, offer in ipairs(list) do
		local id = tonumber(offer[1])
		if id and id > 0 and mine[id] == nil then
			if Known(id) then
				mine[id] = true
			else
				local map, x, y = U.HereOnMap()
				mine[id] = { npc = npc, kind = kind, name = Clean(Safe(UnitName, unit)), title = offer[2], lvl = offer[3],
					map = map, x = Tenth(x), y = Tenth(y) }
				unknown = true
			end
			quests[id], forYou[id], statuses[id] = nil, nil, nil
		end
		if id then NotOffers()[id] = nil end
	end
	-- (the whole list of an NPC: what the data gives it and it did not offer, though open to you, is not offered)
	local changed = unknown
	if whole and kind == "Npc" and ns.QUESTS then
		local offered = {}
		for _, offer in ipairs(list) do
			local id = tonumber(offer[1])
			if id then offered[id] = true end
		end
		local closed = NotOffers()
		for id, row in pairs(ns.QUESTS) do
			if not offered[id] and closed[id] == nil and type(row.u) == "table" then
				for _, giver in ipairs(row.u) do
					if giver == npc then
						local quest = ns.Quest(id)
						if quest and ns.ForYou(quest) and ns.Status(quest) == "available" then
							closed[id] = you.level or 1
							quests[id], forYou[id], statuses[id] = nil, nil, nil
							changed = true
						end
						break
					end
				end
			end
		end
	end
	if changed and ns.ForgetSeen then ns.ForgetSeen() end
end

-- Heard once Wanderer Quests is set up (ns.Init), never at loading.
function ns.InitGivers()
	local givers = CreateFrame("Frame")
	for _, event in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL" }) do
		pcall(givers.RegisterEvent, givers, event)
	end
	givers:SetScript("OnEvent", function(_, event)
		local list = {}
		if event == "GOSSIP_SHOW" then
			local offers = C_GossipInfo and Safe(C_GossipInfo.GetAvailableQuests)
			for _, offer in ipairs(type(offers) == "table" and offers or EMPTY) do
				list[#list + 1] = { Clean(offer.questID), Clean(offer.title), Clean(offer.questLevel) }
			end
			Learn("npc", list, true)
		elseif event == "QUEST_GREETING" then
			for index = 1, Clean(Safe(GetNumAvailableQuests)) or 0 do
				list[#list + 1] = { Clean(select(5, Safe(GetAvailableQuestInfo, index))), Clean(Safe(GetAvailableTitle, index)) }
			end
			Learn("npc", list, true)
		else
			Learn("questnpc", { { Clean(Safe(GetQuestID)), Clean(Safe(GetTitleText)) } })
		end
	end)
end

-- The items asked of the game and not come yet (their arrival is worth a drawing, the others' not).
local awaited, refused = {}, {}
function ns.Awaited(id, success)
	if success == false then
		awaited[id] = nil
		refused[id] = true
		return false
	end
	if not awaited[id] then return false end
	awaited[id] = nil
	return true
end

-- An item asked of the game (once; not one it refused): true when asked.
function ns.AskItem(id)
	if not id or refused[id] or awaited[id] then return false end
	awaited[id] = true
	U.LoadItem(id)
	return true
end
function ns.ItemRefused(id) return refused[id] == true end

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
			if not name then ns.AskItem(id) end
			items[#items + 1] = { id = id, count = list[index + 1] or 1, name = name, link = link, quality = quality, icon = U.ItemIcon(id) }
		end
		return items
	end
	return { choice = Items(row.rc or EMPTY), given = Items(row.rg or EMPTY), money = row.m or 0, seen = seen ~= nil }
end

-- One of its rewards better for you (Wanderer's comparison, for your branch): true, false, or nil while the
-- game is still fetching one of them.
function ns.RewardUpgrade(quest)
	if not W.IsUpgrade then return false end
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

-- Yours: as the data says, or offered to you by its giver; one of Forever's own, offered to you or taken.
function ns.ForYou(quest)
	if not quest then return false end
	if quest.seen then return ns.Offered(quest.id) or Done(quest.id) or InLog(quest.id) end
	if forYou[quest.id] == nil then forYou[quest.id] = ForYou(quest) end
	return forYou[quest.id] or ns.Offered(quest.id)
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

-- The quests after each one, read once in one walk of the data: nextOf (quest -> every quest with it before
-- them), after (the same, those that need it: not as one choice among others, as reaching those says nothing
-- of this one).
local nextOf, after
local function Reverse()
	if nextOf then return end
	nextOf, after = {}, {}
	for other, row in pairs(ns.QUESTS or EMPTY) do
		for _, before in ipairs(row.before or EMPTY) do
			nextOf[before] = nextOf[before] or {}
			table.insert(nextOf[before], other)
			if not row.any then
				after[before] = after[before] or {}
				table.insert(after[before], other)
			end
		end
	end
end
local function After(id)
	Reverse()
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
	-- (one after it done: passed, even when offered once, a way in no longer offered)
	if Passed(quest.id, 0) then return "passed" end
	-- (its giver offered it to you: open, whatever the data says comes before or what level it needs)
	if ns.Offered(quest.id) then return "available" end
	-- (its giver did not offer it to you at this level: not open yet)
	if ns.NotOffered(quest.id) then return "locked" end
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

-- A quest of your log whose objectives are all met: to hand in (asked of the game once per drawing).
function ns.Ready(quest)
	if not quest or ns.Status(quest) ~= "active" then return false end
	if complete[quest.id] == nil then
		complete[quest.id] = Clean(Safe(C_QuestLog and C_QuestLog.IsComplete, quest.id)) and true or false
	end
	return complete[quest.id]
end

-- What comes after a quest: the quests (for you) that have it before them (a choice among others too).
function ns.Next(quest)
	Reverse()
	local list = {}
	for _, id in ipairs(nextOf[quest.id] or EMPTY) do
		local other = ns.Quest(id)
		if ns.ForYou(other) then list[#list + 1] = other end
	end
	table.sort(list, function(a, b) return (a.questLevel or 0) < (b.questLevel or 0) end)
	return list
end

-- Its place in its chain, from what comes before in the data: step, steps (back by a quest before it that is
-- yours, the one done first; on by the longest way), nil when it stands alone. Once per drawing.
local function Chain(quest)
	local back, at, seen = 0, quest, { [quest.id] = true }
	while back < MAX_DEPTH do
		local found
		for _, id in ipairs(at.before) do
			local other = not seen[id] and ns.Quest(id)
			if other and ns.ForYou(other) and (not found or (Done(id) and not Done(found.id))) then found = other end
		end
		if not found then break end
		seen[found.id] = true
		back, at = back + 1, found
	end
	local ahead = {}
	local function Ahead(from, depth)
		if ahead[from.id] then return ahead[from.id] end
		ahead[from.id] = 0 -- (a loop in the data ends here)
		if depth >= MAX_DEPTH then return 0 end
		local most = 0
		for _, other in ipairs(ns.Next(from)) do
			if not seen[other.id] then most = math.max(most, 1 + Ahead(other, depth + 1)) end
		end
		ahead[from.id] = most
		return most
	end
	local steps = back + 1 + Ahead(quest, back)
	if steps < 2 then return false end
	return { back + 1, steps }
end

function ns.ChainStep(quest)
	if not quest then return nil end
	if chains[quest.id] == nil then chains[quest.id] = Chain(quest) end
	local chain = chains[quest.id]
	if not chain then return nil end
	return chain[1], chain[2]
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
ns.AreaName = U.AreaName

-- A place's name made comparable: lower case, without what the game adds in parentheses ("Les Paluns
-- (Wetlands)" is the map "Les Paluns").
local Plain = U.PlainName
ns.Plain = Plain

-- An area's map: Wanderer's own search, made once for every addon.
local function MapOfArea(area) return U.MapOfArea(area) end

-- The way to a place of a map (x, y: 0 to 100): Wanderer Maps' arrow (a step that says why: info { kind, quest,
-- label }; a route of several steps is asked about first), else the game's own pin. Said in the chat when it
-- cannot; whether it could.
function ns.GoOrSay(map, x, y, title, info)
	local went = false
	if map and x and y then
		went = U.Go(map, x / 100, y / 100, title, info)
	end
	if not went then W.Print(ns.L.PIN_FAILED) end
	return went
end

-- Wanderer Maps, when it is there and on (its public table; an older one without IsOn counted on).
function ns.Maps()
	local found = _G.WandererMaps
	if not (type(found) == "table" and found.Go) then return nil end
	if found.IsOn and not found.IsOn() then return nil end
	return found
end

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

-- Every door known, for the map of another addon.
function ns.EntranceList()
	local list = {}
	for _, dungeon in ipairs(ns.Dungeons()) do
		local door = ns.Entrance(dungeon)
		if door then list[#list + 1] = { name = dungeon.name, map = door.map or door[1], x = door.x or door[2], y = door.y or door[3], raid = dungeon.raid } end
	end
	return list
end

-- Where each door stands in the world when the game's journal does not say: dungeon area -> { continent,
-- world x, world y, the zone it stands in } (the portal itself; see CREDITS.md). The game turns it into
-- the zone's map, so it stays right on the maps Forever redrew (Stormwind, the Eastern Plaguelands...).
local ENTRANCES = {
	[1581] = { 0, -11073.0, 1529.2, 40 }, [717] = { 0, -8761.8, 848.6, 1519 }, [209] = { 0, -229.5, 1576.3, 130 },
	[133] = { 0, -5183.8, 605.3, 1 }, [796] = { 0, 2819.3, -699.2, 85 }, [1517] = { 0, -6090.2, -3188.6, 3 },
	[1417] = { 0, -10440.5, -3826.2, 8 }, [1584] = { 0, -7778.9, -1127.8, 46 }, [1583] = { 0, -7778.9, -1127.8, 46 },
	[2717] = { 0, -7778.9, -1127.8, 46 }, [2677] = { 0, -7778.9, -1127.8, 46 }, [2057] = { 0, 1282.1, -2548.7, 28 },
	[2017] = { 0, 3392.5, -3396.8, 139 }, [3456] = { 0, 3133.1, -3730.3, 139 }, [1977] = { 0, -11915.8, -1236.4, 33 },
	[2437] = { 1, 1818.4, -4427.3, 1637 }, [718] = { 1, -846.8, -2038.4, 17 }, [719] = { 1, 4127.1, 863.8, 331 },
	[1717] = { 1, -4456.7, -1656.0, 17 }, [722] = { 1, -4666.5, -2536.8, 17 }, [978] = { 1, -6790.9, -2891.9, 440 },
	[2100] = { 1, -1382.0, 2918.7, 405 }, [2557] = { 1, -3700.7, 1091.6, 357 }, [2159] = { 1, -4768.6, -3752.1, 15 },
	[3429] = { 1, -8114.46, 1526.37, 1377 }, [3428] = { 1, -8230.4, 2005.33, 1377 },
}

-- Its entrance: { map, x, y, area (the zone it stands in) } or nil. As the game's dungeon journal places it,
-- else where its door is known to stand.
function ns.Entrance(dungeon)
	if dungeon.entrance ~= nil then return dungeon.entrance or nil end
	dungeon.entrance = false
	local known = ENTRANCES[dungeon.id]
	if known then
		-- (a door between two zones, Blackrock Mountain's: the map it lies on)
		for _, area in ipairs({ known[4], dungeon.zone }) do
			local x, y = OnZoneMap(known[1], known[2], known[3], MapOfArea(area))
			if x then
				dungeon.entrance = { map = MapOfArea(area), x = x, y = y, area = area }
				break
			end
		end
	end
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
	-- (the only entrance of the map: only when none is known by hand, it may be another dungeon's)
	local found = named or near or (not known and only) or nil
	local position = found and found.position
	if position then
		local x, y = Safe(position.GetXY, position)
		x, y = Clean(x), Clean(y)
		if x and y then dungeon.entrance = { map = map, x = x * 100, y = y * 100, area = dungeon.zone } end
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

-- Gear ----------------------------------------------------------------------------------------------------
-- The quests whose reward is better for you: from GEAR_BELOW levels under yours to GEAR_ABOVE over it (a quest
-- far above says nothing yet, one far below is grey), for you, not done; grouped by the slot of their best
-- reward (Wanderer's comparison), the best gain first. Read again when asked after a change (ns.ForgetGear).
local GEAR_ABOVE, GEAR_BELOW = 3, 6
local GEAR_SLOTS = {
	{ "head", { "INVTYPE_HEAD" } }, { "neck", { "INVTYPE_NECK" } }, { "shoulder", { "INVTYPE_SHOULDER" } },
	{ "back", { "INVTYPE_CLOAK" } }, { "chest", { "INVTYPE_CHEST", "INVTYPE_ROBE" } }, { "wrist", { "INVTYPE_WRIST" } },
	{ "hand", { "INVTYPE_HAND" } }, { "waist", { "INVTYPE_WAIST" } }, { "legs", { "INVTYPE_LEGS" } },
	{ "feet", { "INVTYPE_FEET" } }, { "finger", { "INVTYPE_FINGER" } }, { "trinket", { "INVTYPE_TRINKET" } },
	{ "weapons", { "INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND" } },
	{ "offhand", { "INVTYPE_SHIELD", "INVTYPE_HOLDABLE", "INVTYPE_WEAPONOFFHAND" } },
	{ "ranged", { "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN", "INVTYPE_RELIC" } },
}
local SLOT_OF = {}
for _, slot in ipairs(GEAR_SLOTS) do
	for _, equip in ipairs(slot[2]) do SLOT_OF[equip] = slot[1] end
end

local gear -- { places, ids = slot -> quest ids, gain = quest id -> { gain, link } }
function ns.ForgetGear() gear = nil end

local function Gear()
	if gear then return gear end
	gear = { places = {}, ids = {}, gain = {} }
	if not (W.PlayChoice and W.PlayChoice()) then return gear end
	local level = ns.YourLevel()
	for id, row in pairs(ns.QUESTS or EMPTY) do
		local questLevel = row.lvl or 0
		if (row.rc or row.rg) and questLevel <= level + GEAR_ABOVE and questLevel >= level - GEAR_BELOW then
			local quest = ns.Quest(id)
			local status = ns.ForYou(quest) and ns.Status(quest)
			if status and status ~= "done" and status ~= "passed" and status ~= "closed" then
				local rewards = ns.Rewards(quest)
				local best
				for _, list in ipairs({ rewards.choice, rewards.given }) do
					for _, item in ipairs(list) do
						local gain = item.link and W.UpgradeGain and W.UpgradeGain(item.link)
						if gain and (not best or gain > best.gain) then best = { gain = gain, link = item.link } end
					end
				end
				local equip = best and select(4, U.ItemInstant(best.link))
				local slot = equip and SLOT_OF[U.Clean(equip)]
				if slot then
					best.slot = slot
					gear.gain[id] = best
					if not gear.ids[slot] then
						gear.ids[slot] = {}
						gear.places[#gear.places + 1] = { id = slot }
					end
					table.insert(gear.ids[slot], id)
				end
			end
		end
	end
	for _, ids in pairs(gear.ids) do
		table.sort(ids, function(a, b) return gear.gain[a].gain > gear.gain[b].gain end)
	end
	return gear
end

-- How much better a quest's best reward is for you (and its link), when it is.
function ns.GearGain(id) return Gear().gain[id] end
-- A slot's quests, the best gain first.
function ns.GearQuestIds(slot) return Gear().ids[slot] or EMPTY end

function ns.Places(kind)
	if kind == "gear" then return Gear().places end
	if kind == "class" then return ClassBands() end
	return kind == "zones" and ns.Zones() or ns.Dungeons()
end

-- Forever's own quests ----------------------------------------------------------------------------------
-- A quest the data does not know, seen in the game: offered to you (kept with its giver as the game showed
-- it), or one Wanderer saw an NPC of the data offer (W.QuestOffers) that you have taken. Shown in its giver's
-- place as "seen at" its giver, with only what the game showed.

local seenQuests, index

-- Where its giver stands: { kind, id, name (the game's first), x, y, zone }, nil when nowhere known.
local function SeenGiver(npc, kind, record)
	local all = kind == "Object" and ns.OBJECTS or ns.UNITS
	local who = all and all[npc] and Someone(kind or "Npc", npc) or nil
	if record then
		who = who or { kind = kind or "Npc", id = npc }
		who.name = record.name or who.name or "?"
		-- (a giver the data does not know: where you stood talking to it)
		if not who.zone and record.map then
			for _, zone in ipairs(ns.Zones()) do
				if MapOfArea(zone.id) == record.map then
					who.zone, who.x, who.y = zone.id, record.x, record.y
					break
				end
			end
		end
	end
	return who and who.zone and who or nil
end

local function SeenQuests()
	if seenQuests then return seenQuests end
	seenQuests = {}
	local function Add(id, npc, kind, record)
		if type(id) ~= "number" or seenQuests[id] or (ns.QUESTS and ns.QUESTS[id]) then return end
		local who = SeenGiver(npc, kind, record)
		if not who then return end
		seenQuests[id] = { id = id, name = record and record.title, questLevel = record and record.lvl, requiredLevel = 0,
			requiredRaces = 0, requiredClasses = 0, zone = who.zone, before = EMPTY, any = false, exclusiveTo = EMPTY,
			row = { zone = who.zone }, seen = who }
	end
	for id, record in pairs(Offers()) do
		if type(record) == "table" then Add(id, record.npc, record.kind, record) end
	end
	local book = W.QuestOffers and W.QuestOffers()
	for npc, entry in pairs(type(book) == "table" and book or EMPTY) do
		local offers = type(entry) == "table" and entry.offers
		-- (an object's id may be an NPC's too: a giver of unknown kind placed only when the data knows it as an NPC
		-- alone)
		local kind = type(entry) == "table" and (entry.kind == "Npc" or entry.kind == "Object") and entry.kind or nil
		if not kind and ns.UNITS and ns.UNITS[npc] and not (ns.OBJECTS and ns.OBJECTS[npc]) then kind = "Npc" end
		if kind then
			for id in pairs(type(offers) == "table" and offers or EMPTY) do Add(id, npc, kind) end
		end
	end
	return seenQuests
end

-- A giver seen offering one more: the lists made again when next asked (the map's givers too).
local giverIndex
function ns.ForgetSeen() seenQuests, index, giverIndex = nil, nil, nil end

-- Forever's own quests seen (id -> quest), for the map's givers.
function ns.SeenQuestList() return ns.QUESTS and SeenQuests() or EMPTY end

function ns.SeenQuest(id)
	if not ns.QUESTS then return nil end
	-- (kept since the lists were made: made again)
	if not SeenQuests()[id] and ns.OfferRecord(id) then ns.ForgetSeen() end
	return SeenQuests()[id]
end

-- The quests of each place (its area -> quest ids, in order), read once: dungeons and zones alike.
function ns.Index()
	if index then return index end
	index = {}
	for id, row in pairs(ns.QUESTS or EMPTY) do
		if (ns.DUNGEONS and ns.DUNGEONS[row.zone]) or (ns.ZONES and ns.ZONES[row.zone]) then
			index[row.zone] = index[row.zone] or {}
			table.insert(index[row.zone], id)
		end
	end
	for id, quest in pairs(ns.QUESTS and SeenQuests() or EMPTY) do
		if (ns.DUNGEONS and ns.DUNGEONS[quest.zone]) or (ns.ZONES and ns.ZONES[quest.zone]) then
			index[quest.zone] = index[quest.zone] or {}
			table.insert(index[quest.zone], id)
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
	if kind == "gear" then return Gear().ids[place] or EMPTY end
	if kind == "class" then
		local band = ClassBands()[place]
		return band and band.ids or EMPTY
	end
	return ns.Index()[place] or EMPTY
end

-- The quests for you whose name holds the words (folded by Fold), each once, with its place's name (your class's
-- bands, the dungeons, the zones, in that order; each place's own quests only), at most "most": { quest, depth,
-- dungeon, status, place } as the tree's nodes.
function ns.Search(needle, Fold, most)
	local found, list = {}, {}
	for _, tab in ipairs({ "class", "dungeons", "zones" }) do
		for _, place in ipairs(ns.Places(tab)) do
			for _, id in ipairs(QuestIds(place.id, tab)) do
				if #list >= most then return list end
				local quest = ns.Quest(id)
				if quest and not found[id] and ns.ForYou(quest) and Fold(ns.QuestName(quest)):find(needle, 1, true) then
					found[id] = true
					list[#list + 1] = { quest = quest, depth = 0, dungeon = true, status = ns.Status(quest), place = place.name }
				end
			end
		end
	end
	return list
end

-- A place's summary, without its tree: its levels, its quests for you and those done (or passed).
function ns.Summary(place, kind)
	local low, high, finished, total, take, log = nil, nil, 0, 0, 0, 0
	for _, id in ipairs(QuestIds(place, kind)) do
		local quest = ns.Quest(id)
		if ns.ForYou(quest) then
			total = total + 1
			local status = ns.Status(quest)
			if status == "done" or status == "passed" then finished = finished + 1 end
			if status == "available" then take = take + 1 elseif status == "active" then log = log + 1 end
			-- (a quest of no set level, like an ale given inside, says nothing of the place's levels)
			local level = quest.questLevel or 0
			if level > 1 then low, high = math.min(low or level, level), math.max(high or level, level) end
		end
	end
	return { low = low, high = high, done = finished, total = total, take = take, log = log }
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
-- { quest, depth, dungeon (one of the place's own), status }, the first ones first.
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
	return list
end

-- Who drops it, who gives near you, the way there -------------------------------------------------------

-- Where someone of the data stands in the world: x, y, continent (the game's order); nil when unknown.
local function WorldOf(who)
	local map = who and who.zone and who.x and MapOfArea(who.zone)
	if not map then return nil end
	return U.MapToWorld(map, who.x / 100, who.y / 100)
end

-- The creatures that drop an item a quest asks: { Someone, ... } (one by name), those with a place first, the
-- nearest first when you stand on their continent, else by name.
-- The merchants that sell what the quests ask, the objects of the world that hold it (item -> NPCs, objects), read
-- the first time they are asked for.
local soldFrom, heldFrom
local function Sold()
	if not soldFrom then
		soldFrom = Read(ns.SOLD_SOURCE) or {}
		ns.SOLD_SOURCE = nil
	end
	return soldFrom
end
local function Held()
	if not heldFrom then
		heldFrom = Read(ns.HELD_SOURCE) or {}
		ns.HELD_SOURCE = nil
	end
	return heldFrom
end

-- Those of a list, one of each name (the nearest), the placed and nearest first.
local function Nearest(ids, kind)
	if type(ids) ~= "table" then return EMPTY end
	local hx, hy, here = U.Here()
	local byName, list = {}, {}
	for _, id in ipairs(ids) do
		local who = Someone(kind, id)
		local wx, wy, instance = WorldOf(who)
		who.far = math.huge
		if wx and hx and instance == here then who.far = math.sqrt((wx - hx) ^ 2 + (wy - hy) ^ 2) end
		who.placed = who.x ~= nil
		local same = byName[who.name]
		if not same or (who.placed and not same.placed) or who.far < same.far then byName[who.name] = who end
	end
	for _, who in pairs(byName) do list[#list + 1] = who end
	table.sort(list, function(a, b)
		if a.placed ~= b.placed then return a.placed end
		if a.far ~= b.far then return a.far < b.far end
		return a.name < b.name
	end)
	return list
end

function ns.SoldSources(item) return ns.HasData() and Nearest(Sold()[item], "Npc") or EMPTY end
function ns.HeldSources(item) return ns.HasData() and Nearest(Held()[item], "Object") or EMPTY end

-- Everywhere an item a quest asks comes from, the nearest first: { { how = "drop" | "sold" | "held", who }, ... }.
function ns.ItemSources(item)
	local out = {}
	for _, pair in ipairs({ { "drop", ns.DropSources(item) }, { "sold", ns.SoldSources(item) }, { "held", ns.HeldSources(item) } }) do
		for _, who in ipairs(pair[2]) do out[#out + 1] = { how = pair[1], who = who } end
	end
	table.sort(out, function(a, b)
		if a.who.placed ~= b.who.placed then return a.who.placed end
		return a.who.far < b.who.far
	end)
	return out
end

function ns.DropSources(item)
	local units = ns.HasData() and Drops()[item]
	if type(units) ~= "table" then return EMPTY end
	local hx, hy, here = U.Here()
	local byName, list = {}, {}
	for _, id in ipairs(units) do
		local who = Someone("Npc", id)
		local wx, wy, instance = WorldOf(who)
		who.far = math.huge
		if wx and hx and instance == here then who.far = math.sqrt((wx - hx) ^ 2 + (wy - hy) ^ 2) end
		who.placed = who.x ~= nil
		local same = byName[who.name]
		if not same or (who.placed and not same.placed) or who.far < same.far then byName[who.name] = who end
	end
	for _, who in pairs(byName) do list[#list + 1] = who end
	table.sort(list, function(a, b)
		if a.placed ~= b.placed then return a.placed end
		if a.far ~= b.far then return a.far < b.far end
		return a.name < b.name
	end)
	return list
end

-- The givers of the data and of Forever's own quests seen, by the area they stand in: area -> { key -> { who,
-- ids } }. Made once (and for your side: a giver of both sides is the one of yours).
local function GiverIndex()
	if giverIndex and giverIndex.who == you.who then return giverIndex.areas end
	local areas = {}
	local function Add(id, who)
		if not (type(who) == "table" and who.zone and who.x and who.y and who.kind ~= "Item") then return end
		local givers = areas[who.zone] or {}
		areas[who.zone] = givers
		local key = who.kind .. ":" .. tostring(who.id)
		local entry = givers[key] or { who = who, ids = {} }
		givers[key] = entry
		entry.ids[#entry.ids + 1] = id
	end
	for id in pairs(ns.QUESTS or EMPTY) do
		local quest = ns.Quest(id)
		if quest then Add(id, ns.Giver(quest)) end
	end
	for id, quest in pairs(ns.SeenQuestList()) do Add(id, quest.seen) end
	giverIndex = { who = you.who, areas = areas }
	return areas
end

-- On a zone's map: the givers of quests you could take now, from your level -3 to +3 (lowToo: the lower ones
-- too, marked low). { { who, x, y (0 to 1), quests (by level), low } }.
local NEAR_BELOW, NEAR_ABOVE = 3, 3
function ns.GiversOn(map, lowToo)
	if not (map and ns.HasData()) then return EMPTY end
	local level = you.level or 1
	local found = {}
	for area, givers in pairs(GiverIndex()) do
		if MapOfArea(area) == map then
			for _, entry in pairs(givers) do
				local list, low = {}, true
				for _, id in ipairs(entry.ids) do
					local quest = ns.Quest(id)
					local questLevel = quest and (quest.questLevel or level)
					if quest and questLevel <= level + NEAR_ABOVE and (lowToo or questLevel >= level - NEAR_BELOW)
						and ns.ForYou(quest) and ns.Status(quest) == "available" then
						list[#list + 1] = quest
						if questLevel >= level - NEAR_BELOW then low = false end
					end
				end
				if list[1] then
					table.sort(list, function(a, b) return (a.questLevel or 0) < (b.questLevel or 0) end)
					found[#found + 1] = { who = entry.who, x = entry.who.x / 100, y = entry.who.y / 100, quests = list, low = low }
				end
			end
		end
	end
	return found
end

-- Tooltips ---------------------------------------------------------------------------------------------------
-- A tooltip in the kit's lines ({ title (gold), { words, r, g, b } or words, ... }) for a frame not ours to hook
-- (a map pin, a row whose side changes): the kit's own.
function ns.ShowTip(owner, lines, anchor) return W.Skin.ShowTip(owner, lines, anchor) end
-- A tooltip line in one of the kit's colors (text, soft, blue: a hint).
function ns.TipLine(words, role)
	local c = W.Skin.COLORS[role] or W.Skin.COLORS.text
	return { words, c[1], c[2], c[3] }
end

-- The way to someone (see ns.GoOrSay), said when it cannot.
function ns.Follow(who, info)
	return ns.GoOrSay(who and who.zone and ns.MapOf(who.zone), who and who.x, who and who.y, who and who.name, info)
end

-- A place (a map id, x and y from 0 to 100) as one step more of Wanderer Maps' route (false without it, or
-- nowhere known; false, "full", "here" or "off": the route is full, you already stand there, Wanderer Maps is off; said).
function ns.StepAt(map, x, y, name, info)
	local found = ns.Maps()
	if not (found and found.AddStep and map and x and y) then return false end
	local added, why = found.AddStep(map, x / 100, y / 100, name, info)
	return added and true or false, why
end

-- Someone (an area and its place) as one step more of the route; who.map: a map id's place already.
function ns.AddToRoute(who, info)
	if not who then return false end
	return ns.StepAt(who.map or (who.zone and ns.MapOf(who.zone)), who.x, who.y, who.name, info)
end

-- Someone's place as a map link in the chat's box (never sent), through Wanderer Maps.
function ns.LinkInChat(who)
	local found = ns.Maps()
	local map = who and who.zone and ns.MapOf(who.zone)
	if not (found and found.ChatLink and map and who.x and who.y) then return false end
	return found.ChatLink(map, who.x / 100, who.y / 100) and true or false
end

-- The two above, said in the chat: added to the route (or why not; a full route is said by Wanderer Maps), a
-- link that could not be made.
function ns.SayToRoute(who, info)
	local added, why = ns.AddToRoute(who, info)
	if added then W.Print(ns.L.ROUTE_ADDED:format(who.name or "?")) elseif why ~= "full" and why ~= "here" and why ~= "off" then W.Print(ns.L.PIN_FAILED) end
end
function ns.SayLinkInChat(who)
	if not ns.LinkInChat(who) then W.Print(ns.L.PIN_FAILED) end
end
