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
local Safe, Clean = U.Safe, U.Clean

local WIDTH = 250
local INDENT = 14 -- objectives under the title
local GAP = 6 -- between two quests
local ITEM = 22 -- a quest item's button
local NEW_TIME = 300 -- seconds a quest taken is "new"
local REST = 0.7 -- the list at rest (calm)
local IN_FIGHT = 0.25 -- the others during a fight
local FADE_IN, FADE_OUT = 0.2, 0.6
local FALLBACK = { "TOPRIGHT", "TOPRIGHT", -70, -250 }
local TITLE_ROLE = { 0.88, 0.85, 0.77 }
local OBJECTIVE_ROLE = { 0.66, 0.62, 0.55 }
local DONE_ROLE = { 0.42, 0.4, 0.36 }
local COUNT_ROOM = 40 -- the count's room at the right of a row

local root, heading, featuredFrame, listFrame, ground, insertLine
local rows = {} -- the rows drawn, in order
local pool = {}
local items = {} -- quest id -> its item button (made out of a fight)
local itemPool = {}
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

-- The quests followed: { id, index, title, level, header, complete, objectives, dungeon } in the log's order.
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
					list[#list + 1] = { id = id, index = index, title = Clean(info.title) or ("#" .. id), level = Clean(info.level),
						header = header, complete = Clean(Safe(log.IsComplete, id)) and true or false, objectives = Objectives(id),
						dungeon = InDungeon(id) }
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
local function KeepOrder(quests)
	local mine = Store()
	local placed = {}
	for index = #mine.order, 1, -1 do
		local id = mine.order[index]
		if placed[id] or not InLog(id) then table.remove(mine.order, index) else placed[id] = true end
	end
	for _, quest in ipairs(quests) do
		if not placed[quest.id] then
			mine.order[#mine.order + 1] = quest.id
			placed[quest.id] = true
			-- (the first time, the quests already followed are not new)
			if mine.seeded and not mine.new[quest.id] then mine.new[quest.id] = time() end
		end
	end
	mine.seeded = true
	local now = time()
	for id, at in pairs(mine.new) do
		if now - at > NEW_TIME or not placed[id] then mine.new[id] = nil end
	end
	if mine.featured and not (placed[mine.featured] and Watched(mine.featured)) then mine.featured = nil end
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
	local id = super and super.GetSuperTrackedQuestID and Clean(Safe(super.GetSuperTrackedQuestID)) or 0
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
	focusState = nil
	Steer(id)
	Skin.Play("click")
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

local function Abandon(quest)
	Skin.Ask(L.TRACKER_ABANDON_ASK:format(quest.title), function()
		local log = Log()
		if not log then return end
		Safe(log.SetSelectedQuest, quest.id)
		Safe(log.SetAbandonQuest)
		Safe(log.AbandonQuest)
	end)
end

local function Share(quest)
	local log = Log()
	if not log then return end
	Safe(log.SetSelectedQuest, quest.id)
	if QuestLogPushQuest then Safe(QuestLogPushQuest) end
end

-- The right click on a quest: in front, its place, its sheet, the way to who takes it, the chat, share, abandon.
local function QuestMenu(owner, quest)
	U.Menu(owner, function(_, menu)
		menu:CreateTitle(quest.title)
		menu:CreateButton(Store().featured == quest.id and L.TRACKER_UNFEATURE or L.TRACKER_FEATURE, function() ns.Feature(quest.id) end)
		if not InCombatLockdown() then
			menu:CreateButton(L.MOVE_UP, function() ns.Step(quest.id, "up") end)
			menu:CreateButton(L.MOVE_DOWN, function() ns.Step(quest.id, "down") end)
			menu:CreateButton(L.TRACKER_TOP, function() ns.Step(quest.id, "top") end)
			menu:CreateButton(L.TRACKER_BOTTOM, function() ns.Step(quest.id, "bottom") end)
		end
		menu:CreateDivider()
		if ns.Reveal then menu:CreateButton(L.TRACKER_SHEET, function() ns.Reveal(quest.id) end) end
		local who = quest.complete and Ender(quest.id)
		if who then menu:CreateButton(L.TRACKER_GO:format(who.name or "?"), function() GoHandIn(who, quest) end) end
		menu:CreateButton(L.TRACKER_LINK, function() U.ChatInsert(Clean(Safe(GetQuestLink, quest.id))) end)
		local log = Log()
		if IsInGroup and IsInGroup() and log and log.IsPushableQuest and Clean(Safe(log.IsPushableQuest, quest.id)) then
			menu:CreateButton(L.TRACKER_SHARE, function() Share(quest) end)
		end
		menu:CreateButton(L.TRACKER_UNFOLLOW, function() ns.Unfollow(quest.id) end)
		menu:CreateButton(L.TRACKER_ABANDON, function() Abandon(quest) end)
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
		if W.PlaceMode then menu:CreateButton(L.TRACKER_PLACE, function() W.PlaceMode() end) end
		if W.OpenOptions then menu:CreateButton(L.TRACKER_SETTINGS, function() W.OpenOptions("ext:quests") end) end
	end)
end

-- Drawing ------------------------------------------------------------------------------------------------------------

local function Hint(lines)
	lines[#lines + 1] = ns.TipLine(L.TRACKER_HINT_CLICK, "blue")
	lines[#lines + 1] = ns.TipLine(L.TRACKER_HINT_SHIFT, "blue")
	lines[#lines + 1] = ns.TipLine(L.TRACKER_HINT_RIGHT, "blue")
	if not InCombatLockdown() then lines[#lines + 1] = ns.TipLine(L.TRACKER_HINT_DRAG, "blue") end
end

local function QuestTip(row)
	local quest = row.quest
	if not quest then return end
	local lines = { { quest.title, 1, 0.82, 0 } }
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
	row.text = Skin.Text(row, "GameFontNormal", "text")
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row.count = Skin.Text(row, "GameFontHighlightSmall", "text")
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
	row:SetScript("OnEnter", function(self)
		if self.kind == "quest" then
			if not InCombatLockdown() and not self.featured then self.handle:SetAlpha(1) end
			QuestTip(self)
		elseif self.tip then
			ns.ShowTip(self, self.tip, "ANCHOR_LEFT")
		end
	end)
	row:SetScript("OnLeave", function(self)
		if not (self.handle:IsMouseOver() or dragging) then self.handle:SetAlpha(0) end
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self, button)
		if self.onClick then return self.onClick(self, button) end
	end)
	row:SetScript("OnMouseWheel", function(_, delta) Scroll(delta) end)
	return row
end

local function Free(row)
	row:Hide()
	row:ClearAllPoints()
	row.quest, row.kind, row.onClick, row.tip, row.featured, row.objective, row.compact = nil, nil, nil, nil, nil, nil, nil
	pool[#pool + 1] = row
end

local function Release()
	for _, row in ipairs(rows) do Free(row) end
	wipe(rows)
end

-- A row of a kind, its words set: "heading", "group", "quest", "objective", "turnin", "more".
local function Line(parent, kind, words, role, template)
	local row = Row()
	row:SetParent(parent)
	row.kind = kind
	row.text:SetFontObject(Skin.FontFor(template or "GameFontNormal"))
	local c = type(role) == "table" and role or Skin.COLORS[role or "text"] or Skin.COLORS.text
	row.text:SetTextColor(c[1], c[2], c[3])
	row.text:SetShadowColor(0, 0, 0, 0.95)
	row.text:SetShadowOffset(1, -1)
	row.text:SetText(words or "")
	row.count:SetText("")
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
	row:EnableMouse(kind ~= "objective" and kind ~= "more")
	row:EnableMouseWheel(true)
	row:Show()
	rows[#rows + 1] = row
	return row
end

-- A small mark before the words (a glyph), the words moved after it.
local function Mark(row, glyph, role, size)
	row.mark:SetSize(size or 10, size or 10)
	Skin.SetGlyph(row.mark, glyph)
	local c = type(role) == "table" and role or Skin.COLORS[role or "gold"]
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
	local words = quest.level and ("[%d] %s"):format(quest.level, quest.title) or quest.title
	if quest.new then words = words .. "  " .. Skin.Colorize(L.TRACKER_NEW, "gold") end
	return words
end

local function TitleColor(quest)
	if quest.level and W.QuestLevelColor then
		local r, g, b = W.QuestLevelColor(quest.level)
		if r then return { r, g, b } end
	end
	return TITLE_ROLE
end

-- How far a quest is on one line (compact): its objectives done of all, or a check once it is done.
local function HowFar(quest)
	if quest.complete then return Skin.GlyphText("check", "good", 11) end
	local done, total = 0, #quest.objectives
	for _, objective in ipairs(quest.objectives) do if objective.done then done = done + 1 end end
	return total > 0 and ("%d/%d"):format(done, total) or ""
end

-- The lines of one quest (its title, then its objectives or who takes it), from y down; the new y.
local function DrawQuest(parent, quest, y, featured, compact)
	local title = Line(parent, "quest", TitleWords(quest), TitleColor(quest), featured and (_G.GameFontNormalMed3 and "GameFontNormalMed3" or "GameFontNormalLarge") or "GameFontNormal")
	title.quest, title.featured = quest, featured
	title:SetPoint("TOPLEFT", parent, "TOPLEFT", featured and 10 or 0, -y)
	title:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
	if featured then Mark(title, "star", "gold", 12) end
	title.handle:SetShown(not featured)
	title.onClick = function(self, button)
		if button == "RightButton" then return QuestMenu(self, quest) end
		if IsShiftKeyDown() then return ns.Unfollow(quest.id) end
		ns.Feature(quest.id)
	end
	local top = y
	y = y + Height(title, featured and 18 or 15, featured and 10 or 0)
	if compact and not featured then
		-- (one line: how far, or done; written again in place in a fight)
		title.compact = true
		title.count:SetText(HowFar(quest))
	elseif quest.complete and not InCombatLockdown() then
		local who = Ender(quest.id)
		local turnin = Line(parent, "turnin", who and L.TRACKER_TURN_IN_TO:format(who.name or "?") or L.TRACKER_TURN_IN, "good", "GameFontHighlight")
		turnin.quest = quest
		Mark(turnin, "check", "good")
		turnin:SetPoint("TOPLEFT", parent, "TOPLEFT", (featured and 10 or 0) + INDENT, -y)
		turnin:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
		turnin.tip = { ns.TipLine(who and L.TRACKER_GO:format(who.name or "?") or L.TRACKER_TURN_IN, "blue") }
		turnin.onClick = function(self, button)
			if button == "RightButton" then return QuestMenu(self, quest) end
			if who then GoHandIn(who, quest) end
		end
		y = y + Height(turnin, 14, (featured and 10 or 0) + INDENT)
	else
		for index, objective in ipairs(quest.objectives) do
			local line = Line(parent, "objective", objective.words, objective.done and DONE_ROLE or OBJECTIVE_ROLE, "GameFontHighlight")
			line.quest, line.objective = quest, index
			if objective.done then Mark(line, "check", "good", 9) else Mark(line, "dot", { 0.85, 0.75, 0.5 }, 6) end
			line.count:SetText(objective.count or "")
			local c = objective.done and DONE_ROLE or { 0.88, 0.84, 0.74 }
			line.count:SetTextColor(c[1], c[2], c[3])
			line.text:SetWordWrap(true)
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
	button = CreateFrame("Button", nil, root, "SecureActionButtonTemplate")
	button:SetSize(ITEM, ITEM)
	button:RegisterForClicks("AnyUp", "AnyDown")
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.edges = Skin.Edges(button, 1, 0.82, 0, 0.35)
	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.cooldown:SetAllPoints()
	button:SetScript("OnEnter", function(self)
		if not self.link then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetHyperlink(self.link)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
				if objective.done then Mark(row, "check", "good", 9) end
			end
		elseif quest and row.kind == "quest" and row.compact then
			row.count:SetText(HowFar(quest))
		end
	end
	for _, button in pairs(items) do Cooldown(button) end
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
	local head = Line(heading, "heading", U.Upper(L.QUESTS) .. "  " .. Skin.Colorize(tostring(count), "muted"), "kicker", "GameFontNormalSmall")
	head:SetPoint("TOPLEFT", heading, "TOPLEFT", 0, 0)
	head:SetPoint("RIGHT", heading, "RIGHT", 0, 0)
	Mark(head, mine.closed and "plus" or "chevron", "kicker", 9)
	head.rule:ClearAllPoints()
	head.rule:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -1)
	head.rule:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, -1)
	head.rule:Show()
	head.count:SetText(Skin.GlyphText("grid", "label", 11))
	head.tip = { { L.QUESTS, 1, 0.82, 0 }, ns.TipLine(L.TRACKER_HEAD_CLICK, "blue"), ns.TipLine(L.TRACKER_HEAD_RIGHT, "blue") }
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
					local line = Line(listFrame, "group", U.Upper(g.title) .. "  " .. Skin.Colorize(tostring(#g.quests), "muted"), "kicker", "GameFontNormalSmall")
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
		local more = Line(listFrame, "more", L.TRACKER_MORE:format(hidden), "muted", "GameFontNormalSmall")
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
		more.text:SetText(L.TRACKER_MORE:format(hidden))
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
	if not root:IsShown() then return end
	if dragging then
		if not IsMouseButtonDown("LeftButton") then return ns.EndDrag() end
		ShowInsert()
	end
	local over = U.IsMouseOver(root) or dragging ~= nil
	local target = 1
	if not over and Setting("trackerRest") ~= false then target = REST end
	root:SetAlpha(tween:Step(target, elapsed, FADE_IN, FADE_OUT))
	local fight = (InCombatLockdown() or Clean(Safe(UnitAffectingCombat, "player"))) and Setting("trackerCombat") ~= false and not over
	listFrame:SetAlpha(fight and IN_FIGHT or 1)
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

-- The game's list away while ours is on (out of a fight: it holds protected buttons), back when ours is off.
local hooked = false
local hiddenByUs = false
local function GameList()
	local frame = _G.ObjectiveTrackerFrame
	if not (frame and settled) then return end
	if not hooked and frame.HookScript then
		hooked = true
		frame:HookScript("OnShow", function(self)
			if not On() then return end
			hiddenByUs = true
			if InCombatLockdown() then
				self:SetAlpha(0)
				U.AfterFight("questsGameList", GameList)
			else
				self:Hide()
			end
		end)
	end
	if On() then
		ReadGameSpot()
		if InCombatLockdown() then
			frame:SetAlpha(0)
			hiddenByUs = true
			return U.AfterFight("questsGameList", GameList)
		end
		frame:Hide()
		hiddenByUs = true
	elseif hiddenByUs then
		-- (given back only when it was put away here: another addon's own choice is left alone)
		if InCombatLockdown() then return U.AfterFight("questsGameList", GameList) end
		hiddenByUs = false
		frame:SetAlpha(1)
		frame:Show()
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
	W.Placeable({ key = "questsTracker", label = function() return L.TRACKER_PLACE_LABEL end, frame = root,
		load = function() return Store().place end,
		save = function(spot)
			Store().place = spot
			Place()
		end,
		enabled = function() return On() end,
		scale = function() return tonumber(Setting("trackerScale")) or 1 end,
		default = function() return ns.TrackerDefaultPlace() end })
	local driver = CreateFrame("Frame", nil, root)
	driver:SetScript("OnUpdate", function(_, elapsed) Calm(elapsed) end)
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
		"ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_COOLDOWN", "UNIT_QUEST_LOG_CHANGED",
		"SUPER_TRACKING_CHANGED" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event, unit)
		if event == "UNIT_QUEST_LOG_CHANGED" and unit ~= "player" then return end
		if event == "SUPER_TRACKING_CHANGED" then return On() and FocusChosen() end
		if event == "BAG_UPDATE_COOLDOWN" then
			for _, button in pairs(items) do Cooldown(button) end
			return
		end
		if event == "PLAYER_ENTERING_WORLD" then
			-- (a moment later: the game's list in the place you gave it, read, then put away)
			return C_Timer.After(1, function()
				settled = true
				ReadGameSpot()
				Place()
				Refresh()
			end)
		end
		if event == "PLAYER_REGEN_ENABLED" and not dirty then return end
		Refresh()
	end)
	if W.OnCharacterForgotten then
		-- (its list's order and place, what givers offered it (Data.lua's Offers), its window's state (Window.lua))
		W.OnCharacterForgotten(function(key)
			if type(WandererQuestsDB) ~= "table" then return end
			for _, part in ipairs({ "tracker", "offered", "view" }) do
				if type(WandererQuestsDB[part]) == "table" then WandererQuestsDB[part][key] = nil end
			end
		end)
	end
	Place()
	Refresh()
end
