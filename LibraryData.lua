local _, ns = ...

-- The books of the libraries of WoW Forever (see CREDITS.md): each lies somewhere in the world and is handed in to
-- your side's librarian as a quest of its own; the 10th, 20th and 25th open a reward there.
-- { quest (handing it in), item (the book), level (of where it lies), at = { { map, x, y (0 to 100) } } (two places:
-- the same book in either), side (only that side can take it), soon (not in the game yet), unsure (its place not
-- confirmed yet), to (who takes it: "mage", your side's mage trainer; else the librarian) }
-- (the level 60 books: to the mage trainer as players report it; not confirmed in game yet)
ns.LIBRARY_BOOKS = {
	{ quest = 79092, item = 203755, level = 1, at = { { 1429, 65.4, 70.1 } } }, -- Archmage Theocritus' Research Journal
	{ quest = 79091, item = 203754, level = 1, at = { { 1455, 75.7, 10.5 } } }, -- Archmage Antonidas: The Unabridged Autobiography
	{ quest = 79093, item = 208860, level = 1, at = { { 1436, 52.7, 53.8 }, { 1432, 35.6, 48.9 } } }, -- Rumi of Gnomeregan: The Collected Works
	{ quest = 79094, item = 207972, level = 1, at = { { 1454, 38.7, 78.4 } }, side = "Horde" }, -- The Lessons of Ta'zo
	{ quest = 79095, item = 208185, level = 1, at = { { 1420, 59.4, 52.3 } } }, -- The Apothecary's Metaphysical Primer
	{ quest = 79097, item = 208800, level = 1, at = { { 1413, 62.7, 36.3 } } }, -- Baxtan: On Destructive Magics
	{ quest = 79096, item = 210177, level = 1, at = { { 1421, 43.4, 41.2 } }, soon = true }, -- Ataeric: On Arcane Curiosities
	{ quest = 78124, item = 209843, level = 1, at = { { 1439, 59.8, 22.3 } } }, -- Nar'thalas Almanac, Vol. 74
	{ quest = 78127, item = 209844, level = 1, at = { { 1421, 63.5, 63.1 } } }, -- The Dalaran Digest, Vol. 23
	{ quest = 78142, item = 209845, level = 1, at = { { 1436, 45.4, 70.4 } } }, -- Bewitchments and Glamours
	{ quest = 78143, item = 209846, level = 1, at = { { 1413, 46, 36.5 } } }, -- Secrets of the Dreamers
	{ quest = 78145, item = 209847, level = 1, at = { { 1413, 56.3, 8.8 } } }, -- Arcanic Systems Manual
	{ quest = 78146, item = 209848, level = 1, at = { { 1437, 33.6, 47.9 } } }, -- Goaz Scrolls
	{ quest = 78147, item = 209849, level = 1, at = { { 1431, 16.6, 28.5 } } }, -- Crimes Against Anatomy
	{ quest = 78148, item = 209850, level = 1, at = { { 1432, 77.4, 14 } } }, -- Runes of the Sorcerer-Kings
	{ quest = 78149, item = 209851, level = 1, at = { { 1442, 74.4, 85.7 } } }, -- Fury of the Land
	{ quest = 79947, item = 215683, level = 35, at = { { 1441, 34.4, 40.1 } } }, -- Geomancy: The Stone-Cold Truth
	{ quest = 79948, item = 215815, level = 35, at = { { 1416, 48.4, 57.6 } } }, -- Defensive Magics 101
	{ quest = 79949, item = 215816, level = 35, at = { { 1417, 73.6, 65.2 } } }, -- A Web of Lies: Debunking Myths and Legends
	{ quest = 79950, item = 215817, level = 35, at = { { 1443, 55.1, 26.2 } } }, -- Demons and You
	{ quest = 79951, item = 215820, level = 35, at = { { 1418, 56.7, 39.9 } } }, -- Mummies: A Guide to the Unsavory Undead
	{ quest = 79952, item = 215822, level = 35, at = { { 1445, 57.2, 20.8 } } }, -- RwlRwlRwlRwl!
	{ quest = 79953, item = 215824, level = 35, at = { { 1435, 61.4, 22.4 } }, unsure = true }, -- A Luddite's Guide to Caring for Your Demonic Pet
	{ quest = 79535, item = 213165, level = 35, at = { { 1434, 41.4, 50.9 } } }, -- Basilisks: Should Petrification be Feared?
	{ quest = 81947, item = 220345, level = 45, at = { { 1435, 70, 51 } } }, -- Sanguine Sorcery
	{ quest = 81949, item = 220346, level = 45, at = { { 1446, 72.7, 47.8 } } }, -- Legends of the Tidesages
	{ quest = 81951, item = 220347, level = 45, at = { { 1444, 50.6, 15.7 } }, soon = true }, -- The Liminal and the Arcane
	{ quest = 81952, item = 220348, level = 45, at = { { 1447, 20.7, 62 } } }, -- Everyday Etiquette
	{ quest = 81953, item = 220349, level = 45, at = { { 1428, 29, 28.9 } } }, -- Stonewrought Design
	{ quest = 81954, item = 220350, level = 45, at = { { 1425, 36, 72.8 } } }, -- Venomous Journeys
	{ quest = 81955, item = 220352, level = 45, at = { { 1427, 37.8, 49.3 } } }, -- A Mind of Metal
	{ quest = 81956, item = 220353, level = 45, at = { { 1419, 55.4, 32.2 } }, unsure = true }, -- Conjurer's Codex
	{ quest = 84395, item = 228132, level = 60, at = { { 1422, 38.2, 54.6 } }, to = "mage" }, -- Undead Potatoes
	{ quest = 84396, item = 228133, level = 60, at = { { 1428, 29, 28.9 } }, unsure = true, to = "mage" }, -- Magma or Lava?
	{ quest = 84397, item = 228134, level = 60, at = { { 1448, 65.2, 3.3 } }, to = "mage" }, -- Northern Kalimdor - A Comprehensive Guide
	{ quest = 84398, item = 228135, level = 60, at = { { 1423, 71.8, 48.2 } }, to = "mage" }, -- A Study of the Light
	{ quest = 84399, item = 228136, level = 60, at = { { 1452, 60.7, 37.7 } }, to = "mage" }, -- Ka-Boom!
	{ quest = 84400, item = 228138, level = 60, at = { { 1423, 47.2, 42.3 } }, to = "mage" }, -- The Knight and the Lady
	{ quest = 84401, item = 228140, level = 60, at = { { 1423, 26.5, 15 } }, unsure = true, to = "mage" }, -- Scourge: Undead Menace or Misunderstood?
	{ quest = 84402, item = 228141, level = 60, at = { { 1422, 69.4, 72.8 } }, to = "mage" }, -- Necromancy 101
}

-- The rewards: how many books handed in open them, their quest, from which level.
ns.LIBRARY_REWARDS = {
	{ books = 10, quest = 78150, level = 1 },
	{ books = 20, quest = 79536, level = 20 },
	{ books = 25, quest = 82208, level = 30 },
}

-- Each side's librarian, where the books are handed in: { map, x, y }.
ns.LIBRARIANS = {
	Alliance = { 1453, 49.0, 86.3 }, -- the Mage Tower, Stormwind
	Horde = { 1458, 73.4, 33.0 }, -- Undercity
}

-- Each side's mage trainer who takes the books marked "mage": an NPC of the quest data (its name and place there).
ns.LIBRARY_MAGES = {
	Alliance = 5497, -- Jennea Cannon, the Wizard's Sanctum, Stormwind
	Horde = 7825, -- Oran Snakewrithe, the Magic Quarter, Undercity
}
