local _, ns = ...
local L = ns.L

-- The quests you follow, on the screen, in Wanderer's hand (in the game's list's place; off: the game's comes back).
-- * One quest "in front", at the top: bigger, a golden line beside it, a star, its objectives always shown. Only
--   you choose it (a click; a click again lets it go), nothing else ever changes it. The game's own focus follows.
-- * The others below, by zone (the one you are in first, the dungeons apart, each folded as you left it), in your
--   own order: dragged by the handle that shows under the mouse, or Up / Down / Top / Bottom in the right click.
--   "Arrange now" (the heading's menu) orders them once, by level, by distance or ready first; nothing moves by
--   itself after. A quest taken comes at the bottom, marked "New" a few minutes.
-- * Objectives: their count at the right, a check once done; a quest done says to whom it goes (a click: the way).
-- * A quest's item on its line. A highest height (the wheel moves the list), a compact mode (only the one in front
--   detailed). Calm: faded at rest, the others faded in a fight, back under the mouse.
-- Which quests are followed stays the game's (its watch list: Shift click in the log, its own option to follow the
-- quests taken). The order, the quest in front and what is folded are this character's.
-- In a fight nothing moves (the quests' item buttons are the game's protected kind): the counts change in place,
-- the rest is drawn again once the fight is over.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin
-- (the family's gold: its accents)
local GOLD = Skin and (rawget(Skin, "SCREEN_COLORS") or Skin.COLORS).gold
local Safe, Clean = U.Safe, U.Clean
local ItemClick = ns.ItemClick
local function LinkOf(item) local _, link = U.ItemInfo(item) return link end

local WIDTH = 250
local INDENT = 14 -- objectives under the title
local GAP = 6 -- between two quests
local ITEM = 22 -- a quest item's button
local NEW_TIME = 300 -- seconds a quest taken is "new"
local REST = 0.7 -- the list at rest (calm)
local IN_FIGHT = 0.7 -- the others during a fight (their opacity on the screen, never below the rest's)
local FADE_IN, FADE_OUT = 0.2, 0.6
local FALLBACK = { "TOPRIGHT", "TOPRIGHT", -70, -250 }
local TITLE_ROLE = (rawget(Skin, "SCREEN_COLORS") or Skin.COLORS).title
-- (the kit's roles for this list: still to do as bright as the titles, done a quiet green; an older core: its own)
local OBJECTIVE_ROLE = rawget((rawget(Skin, "SCREEN_COLORS") or Skin.COLORS), "objective") or (rawget(Skin, "SCREEN_COLORS") or Skin.COLORS).title
local DONE_ROLE = rawget((rawget(Skin, "SCREEN_COLORS") or Skin.COLORS), "done") or { 0.45, 0.74, 0.5 }
local COUNT_ROOM = 40 -- the count's room at the right of a row

local root, heading, featuredFrame, listFrame, ground, insertLine
local rows = {} -- the rows drawn, in order
local pool = {}
local items = {} -- quest id -> its item button (made out of a fight)
local itemPool = {}
local itemsMade = 0
local offset = 0 -- rows of the list scrolled away
local dirty = false -- drawn again once the fight is over
local dragging -- the quest id held by its handle
local gameSpot -- where the game's list stood
local tween = U and U.Tween(1)
local settled = false -- the game's list read and put away only once the world is shown (its place set by then)

-- Settings and what is kept --------------------------------------------------------------------------------------

local function Settings() return W.Settings and W.Settings("quests") or nil end

-- Another addon draws the quests followed (Questie's tracker, Kaliel's Tracker...): left to it.
local function Other() return W.Yields and W.Yields("questTracker") or nil end

-- Wanderer Maps there, its atlas on: a click on a title shows the quest there, the pin on hover puts it in front.
-- (a Maps that says whether its atlas is on is asked; an older one is taken at its word)
function ns.OnAtlas()
	local maps = _G.WandererMaps
	if not (type(maps) == "table" and maps.ShowQuest ~= nil) then return false end
	if maps.AtlasOn then return maps.AtlasOn() and true or false end
	return true
end

-- The quest you pinned in front of the list (nil: none, or the list is off).
function ns.InFront()
	if not ns.TrackerOn() then return nil end
	return ns.TrackerStore().featured
end

function ns.TrackerOn()
	local settings = Settings()
	return settings ~= nil and settings.tracker ~= false and not Other()
end
local On = ns.TrackerOn

local function Setting(key) local settings = Settings() return settings and settings[key] end

-- A setting changed from the list itself (its heading's menu): in every profile of this character, as the
-- settings page writes it.
local function ChangeSetting(key, value)
	W.ChangeEverywhere(function()
		local settings = Settings()
		if settings then settings[key] = value end
	end)
end

-- This character's: the order, the quest in front, the folded zones, the quests taken lately, the list's place.
function ns.TrackerStore()
	WandererQuestsDB = type(WandererQuestsDB) == "table" and WandererQuestsDB or {}
	local all = type(WandererQuestsDB.tracker) == "table" and WandererQuestsDB.tracker or {}
	WandererQuestsDB.tracker = all
	local key = W.CharacterKey and W.CharacterKey() or "?"
	local mine = type(all[key]) == "table" and all[key] or {}
	all[key] = mine
	for _, part in ipairs({ "order", "folded", "new" }) do
		if type(mine[part]) ~= "table" then mine[part] = {} end
	end
	return mine
end
local Store = ns.TrackerStore

-- The quest log -------------------------------------------------------------------------------------------------

local function Log() return C_QuestLog end

local function Watched(id)
	local log = Log()
	if not (log and log.GetQuestWatchType) then return false end
	return Clean(Safe(log.GetQuestWatchType, id)) ~= nil
end

-- Followed in the game's watch list (true: it is now). The game refuses past its limit: said in the chat then.
local function WatchLimit()
	local consts = _G.Constants and _G.Constants.QuestWatchConsts
	return tonumber(consts and consts.MAX_QUEST_WATCHES) or tonumber(_G.MAX_WATCHABLE_QUESTS)
end
function ns.WatchQuest(id)
	local log = Log()
	if Watched(id) then return true end
	if not (id and log and log.AddQuestWatch) then return false end
	Safe(log.AddQuestWatch, id)
	if Watched(id) then return true end
	local most = WatchLimit()
	local count = log.GetNumQuestWatches and Clean(Safe(log.GetNumQuestWatches))
	-- (refused for another reason (the quest gone): nothing said)
	if most and type(count) == "number" and count < most then return false end
	local words = _G.QUEST_WATCH_TOO_MANY
	W.Print((most and type(words) == "string" and words:find("%d", 1, true)) and words:format(most) or L.TRACKER_WATCH_FULL)
	return false
end

-- The quest's kind as the game's log tells it, short after its level, as Classic writes it: "+" elite or for a
-- group ("[30+]"), "d" a dungeon ("[30d]"), "r" a raid ("[60r]"); "" for none. group: the players advised.
function ns.TagMark(id, group)
	local log = Log()
	if not (id and log) then return "" end
	local tagID, elite
	local info = log.GetQuestTagInfo and Safe(log.GetQuestTagInfo, id)
	if type(info) == "table" then
		tagID, elite = Clean(info.tagID), Clean(info.isElite)
	elseif not log.GetQuestTagInfo and _G.GetQuestTagInfo then
		tagID = Clean((Safe(_G.GetQuestTagInfo, id)))
	end
	local consts = _G.Constants and _G.Constants.QuestConsts or {}
	local tags = _G.Enum and _G.Enum.QuestTag or {}
	if tagID and tagID == (consts.QUEST_INFO_RAID_ID or tags.Raid or 62) then return "r" end
	if tagID and tagID == (consts.QUEST_INFO_DUNGEON_ID or tags.Dungeon or 81) then return "d" end
	if Clean(Safe(log.IsEliteQuest, id)) then elite = true end
	group = tonumber(group) or Clean(Safe(log.GetSuggestedGroupSize, id))
	if elite or (tagID and tagID == (consts.QUEST_INFO_ELITE_ID or tags.Group or 1)) or (type(group) == "number" and group > 1) then
		return "+"
	end
	return ""
end

-- Failed (its time ran out, the one to escort fell...).
local function Failed(id, info)
	local log = Log()
	if log and log.IsFailed and Clean(Safe(log.IsFailed, id)) then return true end
	return type(info) == "table" and Clean(info.isFailed) and true or false
end

-- The seconds a timed quest has left (nil: not timed). index: its line in the log (the game's older way).
local function TimeLeft(id, index)
	local log = Log()
	if log and log.GetTimeAllowed then
		local total, elapsed = Safe(log.GetTimeAllowed, id)
		total, elapsed = Clean(total), Clean(elapsed)
		if type(total) == "number" and total > 0 and type(elapsed) == "number" then return math.max(0, total - elapsed) end
		return nil
	end
	local timers, indexOf = _G.GetQuestTimers, _G.GetQuestIndexForTimer
	if timers and indexOf then
		timers = { Safe(timers) }
		for at, left in ipairs(timers) do
			if Clean(Safe(indexOf, at)) == index then return tonumber(Clean(left)) end
		end
	end
	return nil
end

-- A quest as Wanderer Quests' own data knows it (nil when it does not).
local function DataOf(id)
	if not (ns.HasData and ns.HasData()) then return nil end
	local ok, quest = pcall(ns.Quest, id)
	return ok and type(quest) == "table" and quest or nil
end

-- A quest of a dungeon.
local function InDungeon(id)
	local quest = DataOf(id)
	return quest ~= nil and quest.zone ~= nil and ns.DUNGEONS ~= nil and ns.DUNGEONS[quest.zone] ~= nil
end

-- An objective's words without its count ("Linen Cloth: 3/10", "3/10 Linen Cloth" -> "Linen Cloth").
local function ObjectiveWords(text)
	text = tostring(text or ""):gsub("\194\160", " "):gsub("^%s*%-%s*", "")
	text = text:gsub("^%d+%s*/%s*%d+%s+", ""):gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", "")
	return text
end

-- The item an objective asks for (its name in the objective's words), from the quest's data: nil when it is not an
-- item, or the data does not know the quest.
local function AskedItemOf(quest, words)
	local data = type(words) == "string" and ns.HasData() and ns.Quest(quest.id)
	if not (data and data.row) then return nil end
	local lower = words:lower()
	for _, ask in ipairs(ns.Asks(data)) do
		local name = ask.kind == "Item" and ask.name
		if name and lower:find(name:lower(), 1, true) then return ask.id end
	end
	return nil
end

local function Objectives(id)
	local log, list = Log(), {}
	local found = log and log.GetQuestObjectives and Safe(log.GetQuestObjectives, id)
	for _, objective in ipairs(type(found) == "table" and found or {}) do
		local text = Clean(objective.text)
		if type(text) == "string" and text ~= "" then
			local have, need = Clean(objective.numFulfilled) or 0, Clean(objective.numRequired) or 0
			local count
			if Clean(objective.type) == "progressbar" then
				count = ("%d%%"):format(math.floor(have + 0.5))
			elseif need > 1 then
				count = ("%d/%d"):format(have, need)
			end
			list[#list + 1] = { words = ObjectiveWords(text), count = count, done = Clean(objective.finished) and true or false }
		end
	end
	return list
end

-- The quests followed: { id, index, title, level, tag, header, complete, failed, timeLeft, readAt, objectives,
-- dungeon } in the log's order.
function ns.TrackedQuests()
	local log, list, header = Log(), {}, nil
	if not (log and log.GetNumQuestLogEntries and log.GetInfo) then return list end
	for index = 1, Clean(Safe(log.GetNumQuestLogEntries)) or 0 do
		local info = Safe(log.GetInfo, index)
		if type(info) == "table" then
			if Clean(info.isHeader) then
				-- (a heading without words: its quests with the others, never a group without a name)
				local title = Clean(info.title)
				header = type(title) == "string" and title:find("%S") and title or nil
			else
				local id = Clean(info.questID)
				if id and not Clean(info.isHidden) and Watched(id) then
					local failed = Failed(id, info)
					list[#list + 1] = { id = id, index = index, title = Clean(info.title) or ("#" .. id), level = Clean(info.level),
						tag = ns.TagMark(id, Clean(info.suggestedGroup)), header = header, failed = failed,
						complete = not failed and Clean(Safe(log.IsComplete, id)) and true or false, objectives = Objectives(id),
						autoComplete = Clean(info.isAutoComplete) and true or false,
						timeLeft = not failed and TimeLeft(id, index) or nil, readAt = GetTime(), dungeon = InDungeon(id) }
				end
			end
		end
	end
	return list
end

-- Whether a quest is still in the log at all.
local function InLog(id)
	local log = Log()
	if log and log.GetLogIndexForQuestID then return Clean(Safe(log.GetLogIndexForQuestID, id)) ~= nil end
	if log and log.IsOnQuest then return Clean(Safe(log.IsOnQuest, id)) and true or false end
	return true
end

-- The order kept: every quest followed in it (a new one at the bottom), those gone from the log let go.
local logRead = false -- the game said its log is read (an empty log then means no quest, not "not read yet")
local function KeepOrder(quests)
	local mine = Store()
	local placed = {}
	-- (the log not read yet at login, empty: nothing kept is let go, what comes next is not "new")
	local log = Log()
	local ready = logRead or (log and log.GetNumQuestLogEntries and (Clean(Safe(log.GetNumQuestLogEntries)) or 0) > 0)
	for index = #mine.order, 1, -1 do
		local id = mine.order[index]
		if placed[id] or (ready and not InLog(id)) then table.remove(mine.order, index) else placed[id] = true end
	end
	for _, quest in ipairs(quests) do
		if not placed[quest.id] then
			mine.order[#mine.order + 1] = quest.id
			placed[quest.id] = true
			-- (the first time, the quests already followed are not new)
			if mine.seeded and not mine.new[quest.id] then mine.new[quest.id] = time() end
		end
	end
	if ready then mine.seeded = true end
	local now = time()
	for id, at in pairs(mine.new) do
		if now - at > NEW_TIME or not placed[id] then mine.new[id] = nil end
	end
	if ready and mine.featured and not (placed[mine.featured] and Watched(mine.featured)) then
		ns.frontGone, mine.featured = mine.featured, nil
	end
	local position = {}
	for index, id in ipairs(mine.order) do position[id] = index end
	return position
end

-- The zone you are in (a dungeon: the dungeons).
local function HereKey()
	if Clean(Safe(IsInInstance)) then return "dungeons" end
	return Clean(Safe(GetRealZoneText))
end

-- The groups to draw: { key, title, quests } (one without a title when they are not grouped), the quest in front apart.
function ns.TrackerModel()
	local quests = ns.TrackedQuests()
	local position = KeepOrder(quests)
	local mine = Store()
	local featured
	local rest = {}
	for _, quest in ipairs(quests) do
		quest.new = mine.new[quest.id] ~= nil
		if quest.id == mine.featured then featured = quest else rest[#rest + 1] = quest end
	end
	table.sort(rest, function(a, b) return (position[a.id] or 0) < (position[b.id] or 0) end)
	if Setting("trackerGroup") == false then
		for _, quest in ipairs(rest) do quest.group = "all" end
		return featured, { { key = "all", quests = rest } }, #quests
	end
	local groups, byKey = {}, {}
	for _, quest in ipairs(rest) do
		local key = quest.dungeon and "dungeons" or quest.header or "other"
		quest.group = key
		local group = byKey[key]
		if not group then
			group = { key = key, title = key == "dungeons" and L.TRACKER_DUNGEONS or (key == "other" and L.TRACKER_OTHER or key),
				quests = {}, first = position[quest.id] or 0 }
			byKey[key] = group
			groups[#groups + 1] = group
		end
		group.quests[#group.quests + 1] = quest
	end
	local here = HereKey()
	table.sort(groups, function(a, b)
		if (a.key == here) ~= (b.key == here) then return a.key == here end
		if (a.key == "dungeons") ~= (b.key == "dungeons") then return b.key == "dungeons" end
		return a.first < b.first
	end)
	return featured, groups, #quests
end

-- Changes ------------------------------------------------------------------------------------------------------------

local Refresh, Scroll

-- The game's own focus (its map's arrow) kept on the quest in front: given again when the game lets it go, drawn
-- again when one of its objectives changes. A pin you follow on the map is left alone; a quest chosen on the
-- game's map is the one in front from then on.
local steered = 0 -- when Wanderer last set the game's focus (its own changes are not your choices)
local focusState -- the quest in front's objectives as last seen
local refocus = false -- back in the world (a reload, a loading screen): the quest in front given to the game again

local function Steer(id)
	local super = _G.C_SuperTrack
	if not (super and super.SetSuperTrackedQuestID) then return end
	steered = GetTime()
	Safe(super.SetSuperTrackedQuestID, id or 0)
end

local function StateOf(id)
	local words = { Clean(Safe(Log().IsComplete, id)) and "done" or "" }
	for _, objective in ipairs(Objectives(id)) do
		words[#words + 1] = (objective.done and "+" or "-") .. (objective.count or "")
	end
	return table.concat(words, ";")
end

local function KeepFocus()
	local super = _G.C_SuperTrack
	local id = Store().featured
	if not (id and super and super.GetSuperTrackedQuestID and Log() and Watched(id)) then
		focusState = nil
		return
	end
	if super.IsSuperTrackingUserWaypoint and Clean(Safe(super.IsSuperTrackingUserWaypoint)) then return end
	local state = StateOf(id)
	local before = focusState
	focusState = state
	-- (the game may still name it after a reload without following it any more: given again, once)
	if refocus then
		refocus = false
		Steer(0)
		return Steer(id)
	end
	if Clean(Safe(super.GetSuperTrackedQuestID)) ~= id then return Steer(id) end
	-- (the same quest given again: the game draws its arrow where its next objective is)
	if before and before ~= state then
		Steer(0)
		Steer(id)
	end
end

-- The game's focus changed by you on its map: that quest in front (followed), or none.
local function FocusChosen()
	if GetTime() - steered < 0.5 then return end
	local map = _G.WorldMapFrame
	if not (map and map.IsShown and map:IsShown()) then return end
	local super = _G.C_SuperTrack
	-- (a pin followed on the map, Wanderer Maps' arrow: not a quest let go)
	if super and super.IsSuperTrackingUserWaypoint and Clean(Safe(super.IsSuperTrackingUserWaypoint)) then return end
	local id = super and super.GetSuperTrackedQuestID and Clean(Safe(super.GetSuperTrackedQuestID)) or 0
	-- (none: a choice only when nothing else is followed either)
	if id == 0 and super and super.IsSuperTrackingAnything and Clean(Safe(super.IsSuperTrackingAnything)) then return end
	local mine = Store()
	if id == mine.featured then return end
	if id ~= 0 and not Watched(id) then return end
	mine.featured = id ~= 0 and id or nil
	focusState = nil
	Refresh()
end

-- The quest in front, or none (the game's own focus follows).
function ns.Feature(id)
	local mine = Store()
	if mine.featured == id then id = nil end
	mine.featured = id
	focusState, refocus = nil, false
	Steer(id)
	Skin.Play("click")
	Refresh()
end

-- In front, whatever was there (a quest chosen on Wanderer Maps' atlas); followed first if it was not.
function ns.PutInFront(id)
	local log = Log()
	if not (id and log) then return end
	-- (the game's limit reached: said, and nothing put in front)
	if not ns.WatchQuest(id) then return end
	if Store().featured ~= id then ns.Feature(id) end
end

-- The quest in front handed in, its sequel taken: the sequel in front. A sequel is what the quest data says
-- comes next; when the data names none, a quest taken just after that the game follows.
local INHERIT_WAIT = 60 -- seconds after handing in, for a quest the data does not know
local handedIn -- { id, time } the quest in front, just handed in

-- (the list may already have let it go: the game says the quest is gone before it says it was handed in)
local function NoteHandedIn(id)
	if id and (id == Store().featured or id == ns.frontGone) then handedIn = { id = id, time = GetTime() } end
end

local function IsSequel(id, before)
	local earlier = ns.Quest(before)
	local following = earlier and ns.Next(earlier) or {}
	for _, other in ipairs(following) do
		if other.id == id then return true end
	end
	if following[1] then return false end -- (the data knows what comes next, and it is another)
	local super = _G.C_SuperTrack
	return handedIn and handedIn.id == before and GetTime() - handedIn.time <= INHERIT_WAIT
		and super and super.GetSuperTrackedQuestID and Clean(Safe(super.GetSuperTrackedQuestID)) == id or false
end

local INHERIT_TRIES = 4
local function Inherit(id, tries)
	local mine = Store()
	local before = handedIn and handedIn.id
	-- (another quest put in front since: yours stays)
	if not (id and before) or id == before or (mine.featured and mine.featured ~= before) then return end
	if not IsSequel(id, before) then return end
	-- (the game adds it to its list a moment after)
	if not Watched(id) then
		tries = tries or INHERIT_TRIES
		if tries > 0 then C_Timer.After(0.5, function() Inherit(id, tries - 1) end) end
		return
	end
	mine.featured, handedIn = id, nil
	focusState, refocus = nil, false
	Steer(id)
	Refresh()
end

-- A quest moved in the order, just before another (after: just after it; nil: at the bottom).
local function Put(id, target, after)
	if id == target then return end
	local order = Store().order
	for index, each in ipairs(order) do
		if each == id then
			table.remove(order, index)
			break
		end
	end
	local at = #order + 1
	for index, each in ipairs(order) do
		if each == target then
			at = after and index + 1 or index
			break
		end
	end
	table.insert(order, at, id)
	Refresh()
end
function ns.MoveQuest(id, before) Put(id, before, false) end

-- The quests of the same group as this one, as drawn (to move it among them).
local function Neighbours(id)
	local _, groups = ns.TrackerModel()
	for _, group in ipairs(groups) do
		for index, quest in ipairs(group.quests) do
			if quest.id == id then return group.quests, index end
		end
	end
	return {}, nil
end

-- Up, down, to the top, to the bottom of its group.
function ns.Step(id, how)
	local list, index = Neighbours(id)
	if not index then return end
	if how == "up" and index > 1 then
		ns.MoveQuest(id, list[index - 1].id)
	elseif how == "down" and index < #list then
		Put(id, list[index + 1].id, true)
	elseif how == "top" and index > 1 then
		ns.MoveQuest(id, list[1].id)
	elseif how == "bottom" and index < #list then
		Put(id, list[#list].id, true)
	end
end

-- Arranged once (by level, by distance, ready first): the order takes it, nothing moves by itself after.
local function Distance(id)
	local log = Log()
	local value = log and log.GetDistanceSqToQuest and Clean(Safe(log.GetDistanceSqToQuest, id))
	return type(value) == "number" and value or math.huge
end
local function CanArrangeByDistance()
	local log = Log()
	return log ~= nil and log.GetDistanceSqToQuest ~= nil
end
function ns.Arrange(how)
	local quests = ns.TrackedQuests()
	local key = {}
	-- (alike: they keep the order they had)
	local position = KeepOrder(quests)
	for _, quest in ipairs(quests) do
		local index = position[quest.id] or 0
		if how == "level" then
			key[quest.id] = { quest.level or 0, index }
		elseif how == "distance" then
			key[quest.id] = { Distance(quest.id), index }
		else
			key[quest.id] = { quest.complete and 0 or 1, index }
		end
	end
	table.sort(quests, function(a, b)
		local ka, kb = key[a.id], key[b.id]
		if ka[1] ~= kb[1] then return ka[1] < kb[1] end
		return ka[2] < kb[2]
	end)
	local mine = Store()
	local followed = {}
	local order = {}
	for _, quest in ipairs(quests) do
		order[#order + 1] = quest.id
		followed[quest.id] = true
	end
	-- (the quests not followed now keep their place after, for when they are followed again)
	for _, id in ipairs(mine.order) do
		if not followed[id] then order[#order + 1] = id end
	end
	mine.order = order
	Refresh()
end

-- No longer followed (the game's watch list).
function ns.Unfollow(id)
	local log = Log()
	if log and log.RemoveQuestWatch then Safe(log.RemoveQuestWatch, id) end
	Refresh()
end

-- A quest of your log followed, or no longer (Shift and a click in the Quests list, as in the game's log); false
-- when it is not in your log.
function ns.ToggleWatch(id)
	if not (id and Log() and InLog(id)) then return false end
	if Watched(id) then
		ns.Unfollow(id)
	elseif ns.WatchQuest(id) then
		Refresh()
	end
	Skin.Play("click")
	return true
end

function ns.Fold(key)
	local folded = Store().folded
	folded[key] = not folded[key] or nil
	Skin.Play("click")
	Refresh()
end

-- Who takes a quest done (Wanderer Quests' data): { name, zone, x, y } or nil.
local function Ender(id)
	local quest = DataOf(id)
	if not quest then return nil end
	local ok, who = pcall(ns.Ender, quest)
	return ok and who or nil
end

-- The way to who takes it, as one of Wanderer Maps' steps to hand in (its sign, its words, ticked once handed in).
local function GoHandIn(who, quest)
	return ns.Follow(who, { kind = "handin", quest = quest.id, label = quest.title })
end

-- The game acts on the quest selected in its log: this one selected for a moment, the one you had put back after.
local function WithSelected(id, act)
	local log = Log()
	if not (log and log.SetSelectedQuest) then return end
	local before = log.GetSelectedQuest and Clean(Safe(log.GetSelectedQuest))
	if before ~= id then Safe(log.SetSelectedQuest, id) end
	local ok = act(log)
	if before ~= id and log.GetSelectedQuest then Safe(log.SetSelectedQuest, before or 0) end
	return ok
end

-- The items that go with a quest abandoned (the game's own question names them): their names, or nil.
local function AbandonItems(log)
	local list = log.GetAbandonQuestItems and Safe(log.GetAbandonQuestItems)
	if type(list) ~= "table" then return nil end
	local names = {}
	for _, item in ipairs(list) do
		item = Clean(item)
		if item then names[#names + 1] = U.ItemName(item) or ("#" .. tostring(item)) end
	end
	return names[1] and table.concat(names, ", ") or nil
end

local function Abandon(quest)
	local lost
	WithSelected(quest.id, function(log)
		Safe(log.SetAbandonQuest)
		lost = AbandonItems(log)
	end)
	local question = L.TRACKER_ABANDON_ASK:format(quest.title)
	if lost then question = question .. "\n" .. L.ABANDON_ITEMS:format(lost) end
	Skin.Ask(question, function()
		local ok = WithSelected(quest.id, function(log)
			return pcall(function()
				log.SetAbandonQuest()
				log.AbandonQuest()
			end)
		end)
		if not ok then W.Print(L.QUEST_REFUSED) end
	end)
end

local function Share(quest)
	local ok = QuestLogPushQuest and WithSelected(quest.id, function() return pcall(QuestLogPushQuest) end)
	if not ok then W.Print(L.QUEST_REFUSED) end
end

local function Shareable(id)
	local log = Log()
	return IsInGroup and Clean(Safe(IsInGroup)) and log and log.IsPushableQuest and Clean(Safe(log.IsPushableQuest, id)) and true or false
end

-- A quest's actions, one set wherever a quest is offered (this list's right click, the Quests window's list, Wanderer
-- Maps' atlas): { text, glyph, onClick, front }. quest: { id, title, level }; where: "tracker", "window" or "atlas"
-- (what that place's own click already does is left out).
function ns.QuestActions(quest, where)
	local list = {}
	if not (quest and quest.id) then return list end
	local known = ns.HasData() and ns.Quest(quest.id)
	quest.title = quest.title or (known and ns.QuestName(known)) or ("#" .. quest.id)
	local function Add(text, glyph, run, front) list[#list + 1] = { text = text, glyph = glyph, onClick = run, front = front } end
	local log = Log()
	local inLog = log ~= nil and InLog(quest.id)
	local watched = inLog and Watched(quest.id)
	if watched and On() then
		Add(Store().featured == quest.id and L.TRACKER_UNFEATURE or L.TRACKER_FEATURE, "star", function() ns.Feature(quest.id) end, true)
	end
	if where ~= "window" and ns.Reveal and known then Add(L.TRACKER_SHEET, "chevron", function() ns.Reveal(quest.id) end) end
	-- (the game's own details of the quest, as its list's menu offers them, in its words)
	local open = _G.QuestUtil and _G.QuestUtil.OpenQuestDetails or _G.QuestMapFrame_OpenToQuestDetails
	if inLog and open and type(_G.OBJECTIVES_VIEW_IN_QUESTLOG) == "string" then
		Add(_G.OBJECTIVES_VIEW_IN_QUESTLOG, "chevron", function() Safe(open, quest.id) end)
	end
	-- (Wanderer Maps: the quest on its map in the atlas)
	if where ~= "atlas" and inLog and ns.OnAtlas() then
		Add(L.TRACKER_ATLAS, "chevron", function() _G.WandererMaps.ShowQuest(quest.id, quest.title) end)
	end
	local who = inLog and Clean(Safe(log.IsComplete, quest.id)) and Ender(quest.id)
	if who then Add(L.TRACKER_GO:format(who.name or "?"), "chevron", function() GoHandIn(who, quest) end) end
	-- (a link in the chat: the mouse's, the pad writes no line)
	if not (U.UsingPad and U.UsingPad()) then Add(L.TRACKER_LINK, "chevron", function() ns.LinkQuest(quest) end) end
	if inLog and Shareable(quest.id) then Add(L.TRACKER_SHARE, "plus", function() Share(quest) end) end
	if inLog then
		if watched then
			Add(L.TRACKER_UNFOLLOW, "minus", function() ns.Unfollow(quest.id) end)
		else
			Add(L.TRACKER_FOLLOW, "plus", function() if ns.WatchQuest(quest.id) then Refresh() end end)
		end
		Add(L.TRACKER_ABANDON, "close", function() Abandon(quest) end)
	end
	return list
end

-- The right click on a quest: in front, its place, then the quest's own actions (its sheet, the atlas, the way to
-- who takes it, the chat, share, stop following, abandon).
local function QuestMenu(owner, quest)
	local actions = ns.QuestActions(quest, "tracker")
	U.Menu(owner, function(_, menu)
		menu:CreateTitle(quest.title)
		local rest = 1
		if actions[1] and actions[1].front then
			menu:CreateButton(actions[1].text, actions[1].onClick)
			rest = 2
		end
		if not InCombatLockdown() then
			menu:CreateButton(L.MOVE_UP, function() ns.Step(quest.id, "up") end)
			menu:CreateButton(L.MOVE_DOWN, function() ns.Step(quest.id, "down") end)
			menu:CreateButton(L.TRACKER_TOP, function() ns.Step(quest.id, "top") end)
			menu:CreateButton(L.TRACKER_BOTTOM, function() ns.Step(quest.id, "bottom") end)
		end
		menu:CreateDivider()
		for index = rest, #actions do menu:CreateButton(actions[index].text, actions[index].onClick) end
	end)
end

-- The heading's menu: arrange now, the way it shows, its place, its settings.
local function HeadingMenu(owner)
	U.Menu(owner, function(_, menu)
		menu:CreateTitle(L.TRACKER_ARRANGE)
		menu:CreateButton(L.TRACKER_BY_LEVEL, function() ns.Arrange("level") end)
		if CanArrangeByDistance() then menu:CreateButton(L.TRACKER_BY_DISTANCE, function() ns.Arrange("distance") end) end
		menu:CreateButton(L.TRACKER_READY_FIRST, function() ns.Arrange("ready") end)
		menu:CreateDivider()
		menu:CreateCheckbox(L.TRACKER_GROUP, function() return Setting("trackerGroup") ~= false end, function()
			ChangeSetting("trackerGroup", Setting("trackerGroup") == false)
			Refresh()
		end)
		menu:CreateCheckbox(L.TRACKER_COMPACT, function() return Setting("trackerCompact") == true end, function()
			ChangeSetting("trackerCompact", Setting("trackerCompact") ~= true)
			Refresh()
		end)
		menu:CreateDivider()
		-- (placing is a mouse's: not offered under the pad)
		if W.PlaceMode and not (U.UsingPad and U.UsingPad()) then menu:CreateButton(L.TRACKER_PLACE, function() W.PlaceMode() end) end
		if W.OpenOptions then menu:CreateButton(L.TRACKER_SETTINGS, function() W.OpenOptions("ext:quests") end) end
	end)
end

-- Drawing ------------------------------------------------------------------------------------------------------------

local function Hint(lines)
	-- (a controller: its own buttons; no Shift and no handle to drag, the menu holds both)
	if U.UsingPad and U.UsingPad() then
		lines[#lines + 1] = ns.TipLine(ns.OnAtlas() and L.TRACKER_HINT_ATLAS_PAD or L.TRACKER_HINT_CLICK_PAD, "blue")
		lines[#lines + 1] = ns.TipLine(L.TRACKER_HINT_RIGHT_PAD, "blue")
		return
	end
	lines[#lines + 1] = ns.TipLine(ns.OnAtlas() and L.TRACKER_HINT_ATLAS or L.TRACKER_HINT_CLICK, "blue")
	lines[#lines + 1] = ns.TipLine(L.TRACKER_HINT_SHIFT, "blue")
	lines[#lines + 1] = ns.TipLine(L.TRACKER_HINT_RIGHT, "blue")
	if not InCombatLockdown() then lines[#lines + 1] = ns.TipLine(L.TRACKER_HINT_DRAG, "blue") end
end

local function QuestTip(row)
	local quest = row.quest
	if not quest then return end
	local lines = { { quest.title, GOLD[1], GOLD[2], GOLD[3] } }
	if quest.header then lines[#lines + 1] = ns.TipLine(quest.level and L.TRACKER_LEVEL_IN:format(quest.level, quest.header) or quest.header, "soft") end
	for _, objective in ipairs(quest.objectives) do
		lines[#lines + 1] = ns.TipLine((objective.done and "+ " or "- ") .. objective.words .. (objective.count and ("  " .. objective.count) or ""),
			objective.done and "muted" or "text")
	end
	Hint(lines)
	ns.ShowTip(row, lines, "ANCHOR_LEFT")
end

local function Row()
	local row = table.remove(pool)
	if row then return row end
	row = CreateFrame("Button", nil, root)
	row:SetHeight(16)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.text = (rawget(Skin, "ScreenText") or Skin.Text)(row, "GameFontNormal", "text")
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row.count = (rawget(Skin, "ScreenText") or Skin.Text)(row, "GameFontHighlightSmall", "text")
	row.count:SetPoint("RIGHT", row, "RIGHT", -2, 0)
	row.count:SetJustifyH("RIGHT")
	row.mark = row:CreateTexture(nil, "ARTWORK")
	row.mark:SetSize(10, 10)
	row.line = Skin.Rule(row, true, 0.85)
	row.rule = Skin.Rule(row, false, 0.22)
	row.handle = CreateFrame("Button", nil, row)
	row.handle:SetSize(12, 14)
	row.handle:SetPoint("RIGHT", row, "LEFT", -1, 0)
	row.handle.glyph = Skin.Glyph(row.handle, "move", 12)
	row.handle.glyph:SetPoint("CENTER")
	row.handle:SetAlpha(0)
	row.handle:SetScript("OnEnter", function(self) if not InCombatLockdown() then self:SetAlpha(1) end end)
	row.handle:SetScript("OnLeave", function(self)
		if not (dragging and self.row.quest and dragging == self.row.quest.id) then self:SetAlpha(0) end
	end)
	row.handle:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" or InCombatLockdown() or not self.row.quest then return end
		dragging = self.row.quest.id
	end)
	row.handle:SetScript("OnMouseUp", function() ns.EndDrag() end)
	row.handle.row = row
	-- The pin, shown on hover of a title while a click shows the quest on the atlas (Wanderer Maps): it puts the quest
	-- in front, or takes it back.
	row.atlas = CreateFrame("Button", nil, row)
	row.atlas:SetSize(14, 14)
	row.atlas:SetPoint("RIGHT", row, "RIGHT", -1, 0)
	row.atlas:SetFrameLevel(row:GetFrameLevel() + 3)
	row.atlas.icon = row.atlas:CreateTexture(nil, "ARTWORK")
	row.atlas.icon:SetAllPoints()
	Skin.GlyphOn(row.atlas.icon, "star")
	row.atlas.padIgnored = true
	row.atlas.row = row
	row.atlas:Hide()
	row.atlas:SetScript("OnClick", function(self)
		local quest = self.row.quest
		if quest then ns.Feature(quest.id) end
	end)
	row.atlas:SetScript("OnEnter", function(self)
		ns.ShowTip(self, { self.row.featured and L.TRACKER_UNFEATURE or L.TRACKER_FEATURE }, "ANCHOR_LEFT")
	end)
	row.atlas:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
		if not self.row:IsMouseOver() then self:Hide() end
	end)
	row.handle.padIgnored = true -- (dragged: a mouse's)
	row:SetScript("OnEnter", function(self)
		if self.kind == "quest" then
			if not InCombatLockdown() and not self.featured then self.handle:SetAlpha(1) end
			-- (the pin: gold on the quest in front)
			local c = (rawget(Skin, "SCREEN_COLORS") or Skin.COLORS)[self.featured and "gold" or "label"]
			self.atlas.icon:SetVertexColor(c[1], c[2], c[3])
			self.atlas:SetShown(ns.OnAtlas() and self.quest ~= nil)
			QuestTip(self)
		elseif self.item then
			return -- (an item asked: the kit's item tooltip below, where it comes from under it)
		elseif self.tip then
			ns.ShowTip(self, self.tip, "ANCHOR_LEFT")
		end
	end)
	row:SetScript("OnLeave", function(self)
		if not (self.handle:IsMouseOver() or dragging) then self.handle:SetAlpha(0) end
		if not self.atlas:IsMouseOver() then self.atlas:Hide() end
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self, button)
		if self.onClick then return self.onClick(self, button) end
	end)
	row:SetScript("OnMouseWheel", function(_, delta) Scroll(delta) end)
	Skin.ItemTooltip(row, function(self) return self.kind == "objective" and self.item or nil end, "ANCHOR_LEFT")
	return row
end

local function Free(row)
	row:Hide()
	row:ClearAllPoints()
	row.quest, row.kind, row.onClick, row.tip, row.featured, row.objective, row.compact = nil, nil, nil, nil, nil, nil, nil
	row.item, row.questsSources, row.timer = nil, nil, nil
	pool[#pool + 1] = row
end

local function Release()
	-- (from the last: the next drawing takes the same rows in the same order, the controller's choice stays on its line)
	for index = #rows, 1, -1 do Free(rows[index]) end
	wipe(rows)
end

-- A row of a kind, its words set: "heading", "group", "quest", "objective", "failed", "timer", "turnin", "more".
local function Line(parent, kind, words, role, template)
	local row = Row()
	row:SetParent(parent)
	row.kind = kind
	-- (a controller goes from title to title, as on the game's list: what is written under a title is not stopped on,
	-- but for the line to hand it in and an item asked, where it comes from)
	row.padIgnored = (kind == "objective" or kind == "failed" or kind == "timer") or nil
	row.padAlt, row.padAltWord = nil, nil
	-- (the top button: a right click's menu, on a quest's lines and the heading; a zone's name and "n more" have none)
	row.padRight = (kind == "quest" or kind == "turnin" or kind == "objective" or kind == "heading") or nil
	row.text:SetFontObject(Skin.FontFor(template or "GameFontNormal"))
	local c = type(role) == "table" and role or (rawget(Skin, "SCREEN_COLORS") or Skin.COLORS)[role or "text"] or (rawget(Skin, "SCREEN_COLORS") or Skin.COLORS).text
	row.text:SetTextColor(c[1], c[2], c[3])
	row.text:SetShadowColor(0, 0, 0, 0.95)
	row.text:SetShadowOffset(1, -1)
	row.text:SetText(words or "")
	row.count:SetText("")
	row.count:SetTextColor((rawget(Skin, "SCREEN_COLORS") or Skin.COLORS).text[1], (rawget(Skin, "SCREEN_COLORS") or Skin.COLORS).text[2], (rawget(Skin, "SCREEN_COLORS") or Skin.COLORS).text[3])
	row.count:SetShadowColor(0, 0, 0, 0.95)
	row.count:SetShadowOffset(1, -1)
	row.mark:Hide()
	row.line:Hide()
	row.rule:Hide()
	row.handle:Hide()
	row.handle:SetAlpha(0)
	row.text:ClearAllPoints()
	row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.text:SetWordWrap(false)
	row.room = 0
	row:EnableMouse(kind ~= "objective" and kind ~= "more" and kind ~= "failed" and kind ~= "timer")
	row:EnableMouseWheel(true)
	row:Show()
	rows[#rows + 1] = row
	return row
end

-- A small mark before the words (a glyph), the words moved after it.
local function Mark(row, glyph, role, size)
	row.mark:SetSize(size or 10, size or 10)
	Skin.SetGlyph(row.mark, glyph)
	local c = type(role) == "table" and role or (rawget(Skin, "SCREEN_COLORS") or Skin.COLORS)[role or "gold"]
	row.mark:SetVertexColor(c[1], c[2], c[3])
	row.mark:ClearAllPoints()
	row.mark:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.mark:Show()
	row.text:ClearAllPoints()
	row.text:SetPoint("LEFT", row.mark, "RIGHT", 3, 0)
	row.room = (size or 10) + 3
end

-- The words' width on a row starting this far from the list's left (the count keeps its room at the right).
local function Width(row, left)
	row.text:SetWidth(math.max(40, WIDTH - (left or 0) - (row.room or 0) - COUNT_ROOM))
end

local function Height(row, least, left)
	Width(row, left)
	local height = math.max(least or 14, math.ceil(U.Measure(row.text, "GetStringHeight", least or 14)) + 2)
	row:SetHeight(height)
	return height
end

local function TitleWords(quest)
	local words = quest.level and ("[%d%s] %s"):format(quest.level, quest.tag or "", quest.title) or quest.title
	if quest.new then words = words .. "  " .. (rawget(Skin, "ScreenColorize") or Skin.Colorize)(L.TRACKER_NEW, "gold") end
	return words
end

local function TitleColor(quest)
	if quest.level and W.QuestLevelColor then
		local r, g, b = W.QuestLevelColor(quest.level)
		if r then return { r, g, b } end
	end
	return TITLE_ROLE
end

-- Failed, in the game's word, in red.
local function FailedWords() return (rawget(Skin, "ScreenColorize") or Skin.Colorize)(_G.FAILED or "", "bad") end

-- The time a timed quest has left, as a clock ("4:05", "1:02:00"), red in its last minute.
local function Clock(row)
	local left = math.max(0, math.floor(row.timer.left - (GetTime() - row.timer.at)))
	local clock = left >= 3600 and ("%d:%02d:%02d"):format(math.floor(left / 3600), math.floor(left % 3600 / 60), left % 60)
		or ("%d:%02d"):format(math.floor(left / 60), left % 60)
	return (rawget(Skin, "ScreenColorize") or Skin.Colorize)(clock, left < 60 and "bad" or "text")
end

-- A timed quest's words: the line under its title, or its count on one line (compact).
local function WriteTimer(row)
	if row.kind == "timer" then
		row.text:SetText((_G.TIME_REMAINING and (_G.TIME_REMAINING .. " ") or "") .. Clock(row))
	else
		row.count:SetText(Clock(row))
	end
end

-- How far a quest is on one line (compact): its objectives done of all, or a check once it is done (failed: said;
-- timed: its time left).
local function HowFar(quest)
	if quest.failed then return FailedWords() end
	if quest.complete then return Skin.GlyphText("check", "good", 11) end
	local done, total = 0, #quest.objectives
	for _, objective in ipairs(quest.objectives) do if objective.done then done = done + 1 end end
	return total > 0 and ("%d/%d"):format(done, total) or ""
end

-- The lines of one quest (its title, then its objectives or who takes it), from y down; the new y.
local function DrawQuest(parent, quest, y, featured, compact)
	local title = Line(parent, "quest", TitleWords(quest), TitleColor(quest), featured and (_G.GameFontNormalMed3 and "GameFontNormalMed3" or "GameFontNormalLarge") or "GameFontNormal")
	title.quest, title.featured = quest, featured
	-- (with Wanderer Maps the click shows the quest on the atlas: pinning it in front is the pin on hover, or the
	-- controller's left button)
	if ns.OnAtlas() then
		title.padAlt, title.padAltWord = function() ns.Feature(quest.id) end, "PIN"
	end
	title:SetPoint("TOPLEFT", parent, "TOPLEFT", featured and 10 or 0, -y)
	title:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
	if featured then Mark(title, "star", "gold", 12) end
	title.handle:SetShown(not featured)
	title.onClick = function(self, button)
		if button == "RightButton" then return QuestMenu(self, quest) end
		-- (Shift, as the game's list: its link while you write in the chat, else no longer followed)
		if IsShiftKeyDown() then
			if ns.Writing() then return ns.LinkQuest(quest) end
			return ns.Unfollow(quest.id)
		end
		if ns.OnAtlas() and _G.WandererMaps.ShowQuest(quest.id, quest.title) then return end
		ns.Feature(quest.id)
	end
	local top = y
	y = y + Height(title, featured and 18 or 15, featured and 10 or 0)
	local left = (featured and 10 or 0) + INDENT
	local oneLine = compact and not featured
	if quest.timeLeft and not (oneLine or quest.failed or quest.complete) then
		-- (a timed quest: the time it has left under its title, counted down each second)
		local timer = Line(parent, "timer", "", "soft", "GameFontHighlight")
		timer.quest = quest
		timer.timer = { left = quest.timeLeft, at = quest.readAt or GetTime() }
		WriteTimer(timer)
		timer:SetPoint("TOPLEFT", parent, "TOPLEFT", left, -y)
		timer:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
		y = y + Height(timer, 13, left)
	end
	if oneLine then
		-- (one line: how far, or done, or the time left; written again in place in a fight)
		title.compact = true
		title.count:SetText(HowFar(quest))
		if quest.timeLeft and not quest.complete then
			title.timer = { left = quest.timeLeft, at = quest.readAt or GetTime() }
			WriteTimer(title)
		end
	elseif quest.failed then
		-- (failed: said in place of its objectives, in red, as the game's log says it)
		local failed = Line(parent, "failed", FailedWords(), "bad", "GameFontHighlight")
		failed.quest = quest
		Mark(failed, "close", "bad", 9)
		failed:SetPoint("TOPLEFT", parent, "TOPLEFT", left, -y)
		failed:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
		y = y + Height(failed, 14, left)
	elseif quest.complete and not InCombatLockdown() then
		-- (a quest completed from afar, as the game's list does it: a click completes it, no one to go to)
		local here = quest.autoComplete and _G.ShowQuestComplete and _G.QUEST_WATCH_CLICK_TO_COMPLETE
		local who = not here and Ender(quest.id)
		local turnin = Line(parent, "turnin", here or (who and L.TRACKER_TURN_IN_TO:format(who.name or "?")) or L.TRACKER_TURN_IN, "good", "GameFontHighlight")
		turnin.quest = quest
		Mark(turnin, "check", "good")
		turnin:SetPoint("TOPLEFT", parent, "TOPLEFT", (featured and 10 or 0) + INDENT, -y)
		turnin:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
		turnin.tip = { ns.TipLine(here or (who and L.TRACKER_GO:format(who.name or "?")) or L.TRACKER_TURN_IN, "blue") }
		turnin.onClick = function(self, button)
			if button == "RightButton" then return QuestMenu(self, quest) end
			if here then
				if _G.RemoveAutoQuestPopUp then Safe(_G.RemoveAutoQuestPopUp, quest.id) end
				return Safe(_G.ShowQuestComplete, quest.id)
			end
			if who then GoHandIn(who, quest) end
		end
		y = y + Height(turnin, 14, (featured and 10 or 0) + INDENT)
	else
		for index, objective in ipairs(quest.objectives) do
			local line = Line(parent, "objective", objective.words, objective.done and DONE_ROLE or OBJECTIVE_ROLE, "GameFontHighlight")
			line.quest, line.objective = quest, index
			if objective.done then Mark(line, "check", "good", 12) else Mark(line, "dot", "kicker", 6) end
			line.count:SetText(objective.count or "")
			local c = objective.done and DONE_ROLE or OBJECTIVE_ROLE
			line.count:SetTextColor(c[1], c[2], c[3])
			line.text:SetWordWrap(true)
			-- (an item asked, still to gather: under the mouse where it comes from, a click the way to the nearest)
			local item = not objective.done and AskedItemOf(quest, objective.words)
			if item then
				line.item, line.questsSources = item, true
				line:EnableMouse(true)
				-- (a controller stops on it: the bottom and the left buttons open where it comes from)
				line.padIgnored = nil
				-- (the left button too, but only with the atlas: without it, it is the game's map, PadEnter)
				if ns.OnAtlas() then line.padAlt, line.padAltWord = function(self) ns.SourceCard(item, self) end, "SOURCES" end
				line.onClick = function(self, button)
					if button == "RightButton" then return QuestMenu(self, quest) end
					if ItemClick(LinkOf(item)) then return end
					ns.SourceCard(item, self)
				end
			end
			line:SetPoint("TOPLEFT", parent, "TOPLEFT", (featured and 10 or 0) + INDENT, -y)
			line:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
			y = y + Height(line, 13, (featured and 10 or 0) + INDENT)
		end
	end
	if featured then
		title.line:ClearAllPoints()
		title.line:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -top)
		title.line:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", 2, -y)
		title.line:Show()
	end
	return y
end

-- The quest's item: a button of the game's protected kind, beside its title (made and placed out of a fight).
local function ItemOf(quest)
	if not GetQuestLogSpecialItemInfo then return nil end
	local link, icon, _, whenDone = Safe(GetQuestLogSpecialItemInfo, quest.index)
	link, icon, whenDone = Clean(link), Clean(icon), Clean(whenDone)
	if not link or (quest.complete and not whenDone) then return nil end
	return link, icon
end

local function ItemButton()
	local button = table.remove(itemPool)
	if button then return button end
	-- (a name of its own: the controller's key clicks it by that name, the game only lets an item be used that way)
	itemsMade = itemsMade + 1
	button = CreateFrame("Button", "WandererQuestsTrackerItem" .. itemsMade, root, "SecureActionButtonTemplate")
	button.padPrimary, button.padOutside = "LeftButton", true -- (it stands left of its row, outside the list)
	button:SetSize(ITEM, ITEM)
	button:RegisterForClicks("AnyUp", "AnyDown")
	-- (the game's way: Shift links the item, Ctrl tries it on; a modified click never uses it)
	button:SetAttribute("shift-type1", "")
	button:SetAttribute("ctrl-type1", "")
	button:SetScript("PreClick", function(self, _, down)
		if not down then ItemClick(self.link) end
	end)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.edges = Skin.Edges(button, GOLD[1], GOLD[2], GOLD[3], 0.35)
	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.cooldown:SetAllPoints()
	Skin.ItemTooltip(button, function(self) return self.link end)
	return button
end

local function Cooldown(button)
	if not (button.index and GetQuestLogSpecialItemCooldown) then return end
	local start, duration, enable = Safe(GetQuestLogSpecialItemCooldown, button.index)
	start, duration, enable = Clean(start), Clean(duration), Clean(enable)
	if start and duration and duration > 0 and enable ~= 0 then button.cooldown:SetCooldown(start, duration) else button.cooldown:Clear() end
end

-- The item buttons for the quests drawn (out of a fight only: the game's rule for its protected buttons).
local function PlaceItems()
	if InCombatLockdown() then return end
	local wanted = {}
	for _, row in ipairs(rows) do
		if row.kind == "quest" and row:IsShown() then
			local link, icon = ItemOf(row.quest)
			if link then wanted[row.quest.id] = { row = row, link = link, icon = icon, index = row.quest.index } end
		end
	end
	for id, button in pairs(items) do
		if not wanted[id] then
			button:Hide()
			button:ClearAllPoints()
			button.link, button.index = nil, nil
			itemPool[#itemPool + 1] = button
			items[id] = nil
		end
	end
	for id, want in pairs(wanted) do
		local button = items[id] or ItemButton()
		items[id] = button
		button.link, button.index = want.link, want.index
		button:SetAttribute("type", "item")
		button:SetAttribute("item", want.link)
		button.icon:SetTexture(want.icon or 134400)
		button:ClearAllPoints()
		button:SetPoint("TOPRIGHT", want.row, "TOPLEFT", -16, 2)
		button:Show()
		Cooldown(button)
	end
end

-- The counts changed in a fight: written in place, nothing moved (the rest once the fight is over).
local function InPlace()
	local fresh = {}
	for _, quest in ipairs(ns.TrackedQuests()) do fresh[quest.id] = quest end
	for _, row in ipairs(rows) do
		local quest = row.quest and fresh[row.quest.id]
		if quest and row.kind == "objective" then
			local objective = quest.objectives[row.objective]
			if objective then
				row.text:SetText(objective.words)
				row.count:SetText(objective.count or "")
				local c = objective.done and DONE_ROLE or OBJECTIVE_ROLE
				row.text:SetTextColor(c[1], c[2], c[3])
				-- (some objectives can be undone: an item asked dropped or sold)
				if objective.done then Mark(row, "check", "good", 12) else Mark(row, "dot", "kicker", 6) end
				row.count:SetTextColor(c[1], c[2], c[3])
			end
		elseif quest and row.kind == "quest" and row.compact then
			row.count:SetText(HowFar(quest))
		end
		-- (a timer read again from the game: its clock follows it)
		if quest and row.timer and quest.timeLeft then
			row.timer.left, row.timer.at = quest.timeLeft, quest.readAt or GetTime()
			WriteTimer(row)
		end
	end
	for _, button in pairs(items) do Cooldown(button) end
end

-- The clocks of the timed quests shown, written again each second (nothing done while none is shown).
local ticking = 0
local function TickTimers(elapsed)
	ticking = ticking + elapsed
	if ticking < 1 then return end
	ticking = 0
	for _, row in ipairs(rows) do
		if row.timer and row:IsShown() then WriteTimer(row) end
	end
end

local function Fit()
	local scale = tonumber(Setting("trackerScale")) or 1
	local height = tonumber(Setting("trackerHeight")) or 420
	root:SetScale(scale)
	root:SetSize(WIDTH, height)
end

-- Everything drawn again (in a fight: the counts in place only, the rest after).
local function Draw()
	if not root then return end
	if InCombatLockdown() and not On() then
		-- (put away once the fight is over: it may hold protected buttons)
		dirty = true
		return
	end
	if not On() then
		Release()
		PlaceItems()
		root:Hide()
		return
	end
	if settled then KeepFocus() end
	if InCombatLockdown() then
		dirty = true
		return InPlace()
	end
	dirty = false
	Fit()
	Release()
	local featured, groups, count = ns.TrackerModel()
	-- (nothing followed: nothing on the screen, as the game's own list)
	if count == 0 then
		offset, root.more = 0, false
		PlaceItems()
		return root:Hide()
	end
	root:Show()
	local mine = Store()
	local compact = Setting("trackerCompact") == true
	local maxHeight = tonumber(Setting("trackerHeight")) or 420
	-- The heading: the word, how many, the menu.
	local head = Line(heading, "heading", U.Upper(L.QUESTS) .. "  " .. (rawget(Skin, "ScreenColorize") or Skin.Colorize)(tostring(count), "muted"), "kicker", "GameFontNormalSmall")
	head:SetPoint("TOPLEFT", heading, "TOPLEFT", 0, 0)
	head:SetPoint("RIGHT", heading, "RIGHT", 0, 0)
	Mark(head, mine.closed and "chevron" or "down", "kicker", 9)
	head.rule:ClearAllPoints()
	head.rule:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -1)
	head.rule:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, -1)
	head.rule:Show()
	head.count:SetText(Skin.GlyphText("grid", "label", 11))
	local pad = U.UsingPad and U.UsingPad()
	head.tip = { { L.QUESTS, GOLD[1], GOLD[2], GOLD[3] }, ns.TipLine(pad and L.TRACKER_HEAD_CLICK_PAD or L.TRACKER_HEAD_CLICK, "blue"),
		ns.TipLine(pad and L.TRACKER_HEAD_RIGHT_PAD or L.TRACKER_HEAD_RIGHT, "blue") }
	head.onClick = function(self, button)
		if button == "RightButton" then return HeadingMenu(self) end
		mine.closed = not mine.closed or nil
		Skin.Play("click")
		Refresh()
	end
	local headHeight = Height(head, 14) + 4
	heading:SetHeight(headHeight)
	-- The quest in front.
	local y = 0
	featuredFrame:ClearAllPoints()
	featuredFrame:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -4)
	featuredFrame:SetPoint("RIGHT", root, "RIGHT", 0, 0)
	if featured and not mine.closed then
		y = DrawQuest(featuredFrame, featured, 2, true, false) + GAP + 2
	end
	featuredFrame:SetHeight(math.max(1, y))
	listFrame:ClearAllPoints()
	listFrame:SetPoint("TOPLEFT", featuredFrame, "BOTTOMLEFT", 0, 0)
	listFrame:SetPoint("RIGHT", root, "RIGHT", 0, 0)
	-- The others, by group, the wheel's offset skipped, as many as the height allows.
	local room = maxHeight - headHeight - 4 - y
	local drawn, skipped, hidden = 0, 0, 0
	local ly = 0
	local placed = {} -- each entry drawn: { rows before it, ly before it, its kind } (to let the last go)
	local function Fits(height) return ly + height <= room end
	if not mine.closed then
		for _, group in ipairs(groups) do
			local folded = group.title and mine.folded[group.key]
			local entries = { group.title and { kind = "group", group = group } or nil }
			if not folded then
				for _, quest in ipairs(group.quests) do entries[#entries + 1] = { kind = "quest", quest = quest } end
			end
			for _, item in ipairs(entries) do
				if skipped < offset then
					skipped = skipped + 1
				elseif hidden > 0 or not Fits(18) then
					hidden = hidden + (item.kind == "quest" and 1 or 0)
				elseif item.kind == "group" then
					placed[#placed + 1] = { rows = #rows, ly = ly, kind = "group", open = not folded }
					local g = item.group
					local line = Line(listFrame, "group", U.Upper(g.title) .. "  " .. (rawget(Skin, "ScreenColorize") or Skin.Colorize)(tostring(#g.quests), "muted"), "kicker", "GameFontNormalSmall")
					Mark(line, folded and "plus" or "chevron", "kicker", 8)
					line:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, -ly)
					line:SetPoint("RIGHT", listFrame, "RIGHT", 0, 0)
					line.tip = { ns.TipLine(folded and L.TRACKER_UNFOLD or L.TRACKER_FOLD, "blue") }
					line.onClick = function() ns.Fold(g.key) end
					ly = ly + Height(line, 13) + 3
					drawn = drawn + 1
				else
					local before = #rows
					local after = DrawQuest(listFrame, item.quest, ly, false, compact)
					if after > room and drawn > 0 then
						-- (it does not fit: let it go, the rest below)
						for index = #rows, before + 1, -1 do Free(table.remove(rows, index)) end
						hidden = hidden + 1
					else
						placed[#placed + 1] = { rows = before, ly = ly, kind = "quest" }
						ly = after + GAP
						drawn = drawn + 1
					end
				end
			end
		end
	end
	-- (scrolled past the end: back up)
	if drawn == 0 and offset > 0 then
		offset = math.max(0, offset - 1)
		return Draw()
	end
	if hidden > 0 then
		-- (the line "n more" within the height chosen: the last entries drawn let go to make its room, the first kept)
		-- (no wheel under a controller: said without it)
		local moreText = (U.UsingPad and U.UsingPad()) and L.TRACKER_MORE_PAD or L.TRACKER_MORE
		local more = Line(listFrame, "more", moreText:format(hidden), "muted", "GameFontNormalSmall")
		table.remove(rows)
		local moreHeight = Height(more, 12, INDENT)
		while #placed > 0 do
			local last = placed[#placed]
			local tooHigh = ly + moreHeight > room and #placed > 1
			-- (a zone's heading left alone at the bottom, its quests all below)
			local alone = last.kind == "group" and last.open and #placed > 1
			if not (tooHigh or alone) then break end
			for index = #rows, last.rows + 1, -1 do Free(table.remove(rows, index)) end
			if last.kind == "quest" then hidden = hidden + 1 end
			ly = last.ly
			table.remove(placed)
		end
		rows[#rows + 1] = more
		more.text:SetText(moreText:format(hidden))
		more:SetPoint("TOPLEFT", listFrame, "TOPLEFT", INDENT, -ly)
		more:SetPoint("RIGHT", listFrame, "RIGHT", 0, 0)
		ly = ly + moreHeight
	end
	listFrame:SetHeight(math.max(1, ly))
	root.more = hidden > 0
	ground:ClearAllPoints()
	ground:SetPoint("TOPLEFT", root, "TOPLEFT", -8, 6)
	ground:SetPoint("RIGHT", root, "RIGHT", 6, 0)
	ground:SetHeight(headHeight + 4 + y + ly + 12)
	ground:SetShown(Setting("trackerBackground") == true)
	PlaceItems()
end

-- The wheel: the list (not the quest in front) moves by one line.
Scroll = function(delta)
	if InCombatLockdown() then return end
	if delta < 0 and not root.more then return end
	offset = math.max(0, offset - delta)
	Draw()
end

-- Dragging a quest by its handle: a line shows where it goes; let go, it goes there (among its group).
-- The rows of the group of the quest held, as drawn.
local function GroupRows(id)
	local group
	for _, row in ipairs(rows) do
		if row.kind == "quest" and row.quest and row.quest.id == id then group = row.quest.group end
	end
	local shown = {}
	for _, row in ipairs(rows) do
		if row.kind == "quest" and not row.featured and row.quest and row.quest.group == group and row:IsShown() then
			shown[#shown + 1] = row
		end
	end
	return shown
end

-- The row the cursor points before (nil: after the last one), and the rows of the group.
local function DropSpot(id)
	local list = GroupRows(id)
	local _, cursor = GetCursorPosition()
	for _, row in ipairs(list) do
		local top = row:GetTop()
		if top and cursor / row:GetEffectiveScale() > top - (row:GetHeight() or 14) / 2 then return row, list end
	end
	return nil, list
end

function ns.EndDrag()
	local id = dragging
	dragging = nil
	if insertLine then insertLine:Hide() end
	if not id or InCombatLockdown() then return end
	local spot, list = DropSpot(id)
	if spot then return Put(id, spot.quest.id, false) end
	local last = list[#list]
	if last and last.quest.id ~= id then Put(id, last.quest.id, true) end
end

local function ShowInsert()
	local spot, list = DropSpot(dragging)
	local last = list[#list]
	insertLine:ClearAllPoints()
	if spot then
		insertLine:SetPoint("BOTTOMLEFT", spot, "TOPLEFT", 0, 1)
		insertLine:SetPoint("BOTTOMRIGHT", spot, "TOPRIGHT", 0, 1)
	elseif last then
		insertLine:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -GAP / 2)
		insertLine:SetPoint("TOPRIGHT", last, "BOTTOMRIGHT", 0, -GAP / 2)
	else
		return insertLine:Hide()
	end
	insertLine:Show()
end

-- The calm: faded at rest, the others faded in a fight (the quest in front stays), back under the mouse.
local function Calm(elapsed)
	if dragging then
		if not IsMouseButtonDown("LeftButton") then return ns.EndDrag() end
		ShowInsert()
	end
	-- (U.Hovered tests the mouse itself; an older Wanderer has only U.IsMouseOver)
	local over = (U.Hovered or U.IsMouseOver)(root) or dragging ~= nil
	local fight = (InCombatLockdown() or Clean(Safe(UnitAffectingCombat, "player"))) and Setting("trackerCombat") ~= false and not over
	-- (in a fight the quest in front comes up whole and the others stay as at rest: the two fades never add up)
	local target = 1
	if not (over or fight) and Setting("trackerRest") ~= false then target = REST end
	-- (written only when it changes: this runs on every frame the list is shown)
	local alpha = tween:Step(target, elapsed, FADE_IN, FADE_OUT)
	if root:GetAlpha() ~= alpha then root:SetAlpha(alpha) end
	local listAlpha = fight and math.min(1, IN_FIGHT / math.max(alpha, 0.01)) or 1
	if listFrame:GetAlpha() ~= listAlpha then listFrame:SetAlpha(listAlpha) end
	TickTimers(elapsed)
end

-- The game's list ----------------------------------------------------------------------------------------------------

-- Where the game's list stands now (its top right), before it is put away.
local function ReadGameSpot()
	local frame = _G.ObjectiveTrackerFrame
	if gameSpot or not (frame and frame.GetRight and frame:IsShown()) then return end
	local right, top = Clean(Safe(frame.GetRight, frame)), Clean(Safe(frame.GetTop, frame))
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	if type(right) ~= "number" or type(top) ~= "number" or not width or not height then return end
	local scale = (frame:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
	gameSpot = { "TOPRIGHT", "TOPRIGHT", math.floor(right * scale - width + 0.5), math.floor(top * scale - height + 0.5) }
end

function ns.TrackerDefaultPlace() return gameSpot or FALLBACK end

-- While ours is on, only the game's quest parts are put away: its other parts (a scenario, achievements, bonus
-- objectives, recipes, the Traveler's Log...) stay where they are, drawn up into the room the quests left. The game
-- keeps running its list as it does: nothing of it is called or changed, its drawing is only followed (a quest part
-- made unseen as soon as it is drawn, hidden and the rest drawn up a moment after, out of a fight: it holds protected
-- buttons). Nothing else to show: the whole list away. Ours off: everything given back.
local QUEST_PARTS = { "QuestObjectiveTracker", "CampaignQuestObjectiveTracker", "WorldQuestObjectiveTracker" }
local OTHER_PARTS = { "ScenarioObjectiveTracker", "UIWidgetObjectiveTracker", "AchievementObjectiveTracker",
	"BonusObjectiveTracker", "ProfessionsRecipeTracker", "MonthlyActivitiesObjectiveTracker", "AdventureObjectiveTracker",
	"InitiativeTasksObjectiveTracker" }
local hooked = false
local partsHooked = {}
local hiddenByUs = false -- the whole list put away (or unseen in a fight) here
local partsAway = {} -- the quest parts put away here
local GameList

local function IsQuestPart(part)
	for _, name in ipairs(QUEST_PARTS) do
		if _G[name] == part then return true end
	end
	return false
end

-- The other parts with something to show, in the game's own order.
local function OtherParts(frame)
	local list = {}
	local parts = type(frame.modules) == "table" and frame.modules or nil
	if not parts then
		parts = {}
		for _, name in ipairs(OTHER_PARTS) do parts[#parts + 1] = _G[name] end
	end
	for _, part in ipairs(parts) do
		if type(part) == "table" and not IsQuestPart(part) and part.GetContentsHeight then
			local height = Clean(Safe(part.GetContentsHeight, part))
			if type(height) == "number" and height > 0 then list[#list + 1] = part end
		end
	end
	return list
end

-- The other parts drawn up one under the other, as the game places them (its own spacing), the quests' room gone.
local function DrawUp(frame, parts)
	local top = tonumber(frame.topModulePadding)
	if not top then return end -- (not the list as it is known: left as the game drew it)
	local spacing = tonumber(frame.moduleSpacing) or 10
	local before
	for _, part in ipairs(parts) do
		part:ClearAllPoints()
		if before then part:SetPoint("TOP", before, "BOTTOM", 0, -spacing) else part:SetPoint("TOP", 0, -top) end
		part:SetPoint("LEFT", frame, "LEFT", tonumber(part.leftMargin) or 0, 0)
		before = part
	end
	local back = frame.NineSlice
	if before and back and back.SetPoint then back:SetPoint("BOTTOM", before, "BOTTOM", 0, -(tonumber(frame.bottomModulePadding) or 10)) end
end

local function QuestPartsAway(fight)
	for _, name in ipairs(QUEST_PARTS) do
		local part = _G[name]
		if type(part) == "table" and part.SetAlpha then
			partsAway[part] = true
			if part:GetAlpha() ~= 0 then part:SetAlpha(0) end
			if not fight and part:IsShown() then part:Hide() end
		end
	end
end

-- Once the game has drawn its list (a moment after, never inside its own drawing).
local followPending = false
local function FollowLater()
	if followPending then return end
	followPending = true
	C_Timer.After(0, function()
		followPending = false
		GameList()
	end)
end

local function Hook(frame)
	if not hooked and frame.HookScript then
		hooked = true
		-- (at once, as it shows: never seen a moment with only its quests' empty room)
		frame:HookScript("OnShow", function() if On() then GameList() end end)
	end
	for _, name in ipairs(QUEST_PARTS) do
		local part = _G[name]
		if type(part) == "table" and not partsHooked[part] and type(part.Update) == "function" and hooksecurefunc then
			partsHooked[part] = true
			-- (unseen at once: only its opacity; the rest a moment after)
			hooksecurefunc(part, "Update", function(self)
				if not On() then return end
				self:SetAlpha(0)
				FollowLater()
			end)
		end
	end
end

GameList = function()
	local frame = _G.ObjectiveTrackerFrame
	if not (frame and settled) then return end
	Hook(frame)
	local fight = InCombatLockdown()
	if On() then
		ReadGameSpot()
		QuestPartsAway(fight)
		local others = OtherParts(frame)
		if others[1] then
			-- (other parts to show: the list stays, without its quests)
			if hiddenByUs and frame:GetAlpha() == 0 then frame:SetAlpha(1) end
			if fight then
				hiddenByUs = hiddenByUs and not frame:IsShown()
				return U.AfterFight("questsGameList", GameList)
			end
			if hiddenByUs and not frame:IsShown() then frame:Show() end
			hiddenByUs = false
			pcall(DrawUp, frame, others)
			return
		end
		hiddenByUs = true
		if fight then
			frame:SetAlpha(0)
			return U.AfterFight("questsGameList", GameList)
		end
		frame:Hide()
	elseif hiddenByUs or next(partsAway) then
		-- (given back only what was put away here: another addon's own choice is left alone)
		if fight then return U.AfterFight("questsGameList", GameList) end
		for part in pairs(partsAway) do
			part:SetAlpha(1)
			part:Show()
		end
		wipe(partsAway)
		if hiddenByUs then
			hiddenByUs = false
			frame:SetAlpha(1)
			frame:Show()
		end
	end
end

local function Place()
	local spot = Store().place
	local place
	if type(spot) == "table" and type(spot[1]) == "string" then
		place = { spot[1], spot[1], tonumber(spot[2]) or 0, tonumber(spot[3]) or 0 }
	else
		place = ns.TrackerDefaultPlace()
	end
	if InCombatLockdown() then return U.AfterFight("questsTrackerPlace", Place) end
	root:ClearAllPoints()
	root:SetPoint(place[1], UIParent, place[2], place[3], place[4])
end

-- Start ----------------------------------------------------------------------------------------------------------------

local pending = false
function ns.RefreshTracker()
	if not root or pending then return end
	pending = true
	C_Timer.After(0.05, function()
		pending = false
		GameList()
		Draw()
	end)
end
Refresh = ns.RefreshTracker
ns.DrawTracker = function() GameList() Draw() end -- (tests: at once)

function ns.InitTracker()
	root = CreateFrame("Frame", "WandererQuestsTracker", UIParent)
	root:SetSize(WIDTH, 420)
	root:SetFrameStrata("LOW")
	root:SetClampedToScreen(true)
	root:SetMovable(true)
	root:EnableMouse(false)
	root:Hide()
	-- The controller's wheel goes to the game's list of quests, put away here: it comes to this one instead, with the
	-- game's own key for the map.
	root.padHint = (rawget(Skin, "ScreenText") or Skin.Text)(root, "GameFontHighlight", "text")
	root.padHint:SetPoint("BOTTOMLEFT", root, "TOPLEFT", 0, 4)
	root.padHint:SetText(L.TRACKER_PAD_HINT)
	root.padHint:Hide()
	local function ControllerIn()
		local map = _G.WorldMapFrame
		if not (U.UsingPad and U.UsingPad()) or not root:IsShown() or (map and map:IsShown()) then return end
		-- (with Wanderer Maps, the bottom button shows the chosen quest on the atlas and the left one pins it; else the
		-- left button is the game's map)
		local onAtlas = ns.OnAtlas()
		local taken = Skin.PadEnter(root, { actions = not onAtlas and { PAD3 = "TOGGLEWORLDMAP" } or nil,
			onLeave = function() root.padHint:Hide() end })
		if taken then
			-- (the controller's own icons when the game has them, else the words; only the keys true of every row: the
			-- chosen row's own are said by the hint under it)
			local keys = Skin.PadKeys and Skin.PadKeys((onAtlas and { { "PAD2", "BACK" } } or { { "PAD3", "MAP" }, { "PAD2", "BACK" } }))
			-- (on the atlas the fallback words would name the game's map: none then)
			root.padHint:SetText(keys or (not onAtlas and L.TRACKER_PAD_HINT) or "")
			root.padHint:Show()
		end
	end
	local micro = _G.QuestLogMicroButton
	if micro and micro.HookScript and Skin.PadEnter then micro:HookScript("OnClick", ControllerIn) end
	-- (the game's own shortcut to its list: L1 + R1 + up)
	if Skin.PadOnTrackerKey then Skin.PadOnTrackerKey(ControllerIn) end
	ground = root:CreateTexture(nil, "BACKGROUND")
	ground:SetColorTexture(0.04, 0.035, 0.03, 0.45)
	ground:Hide()
	heading = CreateFrame("Frame", nil, root)
	heading:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
	heading:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
	heading:SetHeight(16)
	featuredFrame = CreateFrame("Frame", nil, root)
	listFrame = CreateFrame("Frame", nil, root)
	insertLine = Skin.Rule(root, false, 0.9)
	insertLine:SetHeight(2)
	insertLine:Hide()
	-- (moved with Wanderer's placing mode, when it has one)
	if W.Placeable then
		W.Placeable({ key = "questsTracker", label = function() return L.TRACKER_PLACE_LABEL end, frame = root,
			load = function() return Store().place end,
			save = function(spot)
				Store().place = spot
				Place()
			end,
			enabled = function() return On() end,
			scale = function() return tonumber(Setting("trackerScale")) or 1 end,
			default = function() return ns.TrackerDefaultPlace() end })
	end
	local driver = CreateFrame("Frame", nil, root)
	driver:SetScript("OnUpdate", function(_, elapsed) Calm(elapsed) end)
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
		"ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_COOLDOWN", "UNIT_QUEST_LOG_CHANGED",
		"SUPER_TRACKING_CHANGED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event, unit, ...)
		if event == "QUEST_LOG_UPDATE" and settled then logRead = true end
		if event == "UNIT_QUEST_LOG_CHANGED" and unit ~= "player" then return end
		if event == "SUPER_TRACKING_CHANGED" then return On() and FocusChosen() end
		if event == "BAG_UPDATE_COOLDOWN" then
			for _, button in pairs(items) do Cooldown(button) end
			return
		end
		if event == "PLAYER_ENTERING_WORLD" then
			-- (a moment later: the game's list in the place you gave it, read, then put away)
			return C_Timer.After(1, function()
				settled, refocus = true, true
				ReadGameSpot()
				Place()
				Refresh()
			end)
		end
		if event == "PLAYER_REGEN_ENABLED" and not dirty then return end
		if event == "QUEST_TURNED_IN" then NoteHandedIn(unit) end
		-- (a moment later: the game has put it in its list and followed it; the quest is the last value, after the log's
		-- line on a client that sends both)
		if event == "QUEST_ACCEPTED" and On() then
			local id = Clean(select("#", ...) > 0 and select(select("#", ...), ...) or unit)
			C_Timer.After(0.3, function() Inherit(id) end)
		end
		Refresh()
	end)
	if W.OnCharacterForgotten then
		-- (its list's order and place, what givers offered it or did not (Data.lua's Offers, NotOffers), its window's
		-- state (Window.lua))
		W.OnCharacterForgotten(function(key)
			if type(WandererQuestsDB) ~= "table" then return end
			for _, part in ipairs({ "tracker", "offered", "notOffered", "view" }) do
				if type(WandererQuestsDB[part]) == "table" then WandererQuestsDB[part][key] = nil end
			end
		end)
	end
	Place()
	Refresh()
end
