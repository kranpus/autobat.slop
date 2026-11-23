class_name Progression
extends RefCounted
## Patch 0.9.7: commander levels and the quest log.
##
## Commander level: XP from battles, expeditions, upgrades, challenges, Legion
## Draft and quests. Levels unlock parts of the game and pay rewards.
## Quest log: a few daily quests (reset once a day at the time the server sets,
## Difficulty.quest_reset_minute, UTC), a few weekly quests (reset on
## Difficulty.quest_reset_weekday), and 50 story quests taken one after another.
##
## Quest objectives ("goal"):
##   counters (counted while the quest is active):
##     battle, ranked_win, kills, explore, new_unit, unit_level, tier_up,
##     gold_spend, trinket_hunt, challenge_win, draft_play, draft_win
##   milestones (checked against your progress):
##     rating, units_owned, max_tier, challenges_cleared, army_power,
##     player_level, trinkets_owned

const MAX_LEVEL := 30

## XP for each activity.
const XP := {
	"battle": 15,          # any battle you fight (ranked, duels, practice)
	"ranked_win": 15,      # ...extra for winning a ranked battle or duel
	"explore": 10,
	"unit_level": 5,
	"tier_up": 20,
	"trinket_hunt": 10,
	"challenge_win": 40,
	"challenge_first": 60, # ...extra the first time a challenge is cleared
	"draft_play": 40,
	"draft_win": 40,       # ...extra for winning a Legion Draft match
}


## XP from one level to the next.
static func xp_for_next(level: int) -> int:
	return 100 + 60 * (level - 1)


## Total XP needed to reach a level.
static func xp_for_level(level: int) -> int:
	var t := 0
	for l in range(1, mini(level, MAX_LEVEL)):
		t += xp_for_next(l)
	return t


static func level_for_xp(xp: int) -> int:
	var l := 1
	while l < MAX_LEVEL and xp >= xp_for_level(l + 1):
		l += 1
	return l


## What reaching a level unlocks (shown in the game).
const UNLOCKS := {
	2: {"key": "daily", "text": "Daily quests"},
	3: {"key": "trinkets", "text": "Trinket hunts"},
	4: {"key": "weekly", "text": "Weekly quests"},
	5: {"key": "draft", "text": "Legion Draft"},
	6: {"key": "champion", "text": "Your champion, to lead the army"},
	8: {"key": "trinket_slot2", "text": "A second trinket slot on every unit"},
	10: {"key": "maps_2", "text": "Store 2 more scouting maps"},
	15: {"key": "daily_4", "text": "A fourth daily quest"},
	20: {"key": "maps_4", "text": "Store 2 more scouting maps"},
	25: {"key": "weekly_4", "text": "A fourth weekly quest"},
}


## The level that unlocks a feature key (1 if it isn't gated).
static func unlock_level(key: String) -> int:
	for l in UNLOCKS:
		if UNLOCKS[l]["key"] == key:
			return int(l)
	return 1


static func extra_maps(level: int) -> int:
	return (2 if level >= unlock_level("maps_2") else 0) + (2 if level >= unlock_level("maps_4") else 0)


static func daily_count(level: int) -> int:
	if level < unlock_level("daily"):
		return 0
	return 4 if level >= unlock_level("daily_4") else 3


static func weekly_count(level: int) -> int:
	if level < unlock_level("weekly"):
		return 0
	return 4 if level >= unlock_level("weekly_4") else 3


static func trinket_slots(level: int) -> int:
	return Trinkets.SLOTS if level >= unlock_level("trinket_slot2") else 1


## The reward for reaching a level: gold every level, scouting maps every
## third level, a trinket every sixth (rarer as you go).
static func level_reward(level: int) -> Dictionary:
	var r := {"gold": 150 * level}
	if level >= unlock_level("champion"):
		r["sigils"] = 2
	if level % 3 == 0:
		r["maps"] = 2
	if level % 6 == 0:
		r["trinket_rarity"] = ["uncommon", "rare", "epic", "epic", "legendary"][clampi(level / 6 - 1, 0, 4)]
	return r


# --- quests ----------------------------------------------------------------------------

const COUNTER_GOALS := ["battle", "ranked_win", "kills", "explore", "new_unit", "unit_level", "tier_up",
	"gold_spend", "trinket_hunt", "challenge_win", "draft_play", "draft_win", "champion_roll"]

## Daily quest pool: three (four from level 15) are picked each day.
## "min_level": only offered once that part of the game is unlocked.
const DAILY := [
	{"id": "d_battles", "goal": "battle", "n": 5, "text": "Fight 5 battles", "gold": 300},
	{"id": "d_ranked", "goal": "ranked_win", "n": 3, "text": "Win 3 ranked battles", "gold": 400},
	{"id": "d_kills", "goal": "kills", "n": 600, "text": "Defeat 600 enemy units", "gold": 300},
	{"id": "d_explore", "goal": "explore", "n": 3, "text": "Send scouts out 3 times", "gold": 250, "maps": 1},
	{"id": "d_levels", "goal": "unit_level", "n": 3, "text": "Level up units 3 times", "gold": 300},
	{"id": "d_spend", "goal": "gold_spend", "n": 1500, "text": "Spend 1,500 gold on upgrades", "gold": 400},
	{"id": "d_tier", "goal": "tier_up", "n": 1, "text": "Upgrade a squad's tier", "gold": 350},
	{"id": "d_challenge", "goal": "challenge_win", "n": 1, "text": "Win a challenge (replays count)", "gold": 300},
	{"id": "d_trinket", "goal": "trinket_hunt", "n": 1, "text": "Go on a trinket hunt", "gold": 250, "min_level": 3},
	{"id": "d_draft", "goal": "draft_play", "n": 1, "text": "Play a Legion Draft match", "gold": 400, "min_level": 5},
	{"id": "d_altar", "goal": "champion_roll", "n": 2, "text": "Roll twice at the champion's Altar", "gold": 350, "min_level": 6},
]
const DAILY_XP := 60
const DAILY_SIGILS := 1

## Weekly quest pool: three (four from level 25) are picked each week.
const WEEKLY := [
	{"id": "w_battles", "goal": "battle", "n": 30, "text": "Fight 30 battles", "gold": 2000, "maps": 3},
	{"id": "w_ranked", "goal": "ranked_win", "n": 15, "text": "Win 15 ranked battles", "gold": 2500, "maps": 3},
	{"id": "w_kills", "goal": "kills", "n": 5000, "text": "Defeat 5,000 enemy units", "gold": 2000, "maps": 2},
	{"id": "w_explore", "goal": "explore", "n": 15, "text": "Send scouts out 15 times", "gold": 1500, "maps": 4},
	{"id": "w_levels", "goal": "unit_level", "n": 20, "text": "Level up units 20 times", "gold": 2000, "maps": 2},
	{"id": "w_tiers", "goal": "tier_up", "n": 5, "text": "Upgrade squad tiers 5 times", "gold": 2500, "maps": 2},
	{"id": "w_recruits", "goal": "new_unit", "n": 2, "text": "Recruit 2 new units", "gold": 2000, "maps": 3},
	{"id": "w_spend", "goal": "gold_spend", "n": 12000, "text": "Spend 12,000 gold on upgrades", "gold": 3000, "maps": 2},
	{"id": "w_trinkets", "goal": "trinket_hunt", "n": 5, "text": "Go on 5 trinket hunts", "gold": 1500, "maps": 3, "min_level": 3},
	{"id": "w_draft", "goal": "draft_play", "n": 3, "text": "Play 3 Legion Draft matches", "gold": 2500, "maps": 3, "min_level": 5},
	{"id": "w_altar", "goal": "champion_roll", "n": 10, "text": "Roll 10 times at the champion's Altar", "gold": 2500, "maps": 2, "min_level": 6},
]
const WEEKLY_XP := 300
const WEEKLY_SIGILS := 3

## The 50 story quests, in order. Rewards grow along the way; every fifth
## brings scouting maps, every tenth a trinket.
const STORY := [
	{"goal": "battle", "n": 1, "text": "Fight your first battle"},
	{"goal": "unit_level", "n": 1, "text": "Level up a unit"},
	{"goal": "explore", "n": 1, "text": "Send scouts into a region"},
	{"goal": "ranked_win", "n": 1, "text": "Win a ranked battle"},
	{"goal": "challenge_win", "n": 1, "text": "Win a challenge"},
	{"goal": "units_owned", "n": 6, "text": "Own 6 units"},
	{"goal": "tier_up", "n": 1, "text": "Upgrade a squad's tier"},
	{"goal": "rating", "n": 100, "text": "Reach 100 rating"},
	{"goal": "kills", "n": 300, "text": "Defeat 300 enemy units"},
	{"goal": "player_level", "n": 3, "text": "Reach commander level 3"},
	{"goal": "trinket_hunt", "n": 1, "text": "Go on a trinket hunt"},
	{"goal": "trinkets_owned", "n": 3, "text": "Own 3 trinkets"},
	{"goal": "ranked_win", "n": 5, "text": "Win 5 ranked battles"},
	{"goal": "rating", "n": 250, "text": "Reach 250 rating (Goblin Warrens)"},
	{"goal": "challenges_cleared", "n": 3, "text": "Clear 3 challenges"},
	{"goal": "unit_level", "n": 10, "text": "Level up units 10 times"},
	{"goal": "units_owned", "n": 10, "text": "Own 10 units"},
	{"goal": "draft_play", "n": 1, "text": "Play a Legion Draft match"},
	{"goal": "rating", "n": 500, "text": "Reach 500 rating (Haunted Crypt)"},
	{"goal": "army_power", "n": 500, "text": "Field an army of 500 Strength"},
	{"goal": "new_unit", "n": 3, "text": "Recruit 3 new units"},
	{"goal": "max_tier", "n": 3, "text": "Raise a squad to tier 3"},
	{"goal": "kills", "n": 2000, "text": "Defeat 2,000 enemy units"},
	{"goal": "player_level", "n": 8, "text": "Reach commander level 8"},
	{"goal": "ranked_win", "n": 15, "text": "Win 15 ranked battles"},
	{"goal": "rating", "n": 800, "text": "Reach 800 rating (Fungal Hollows)"},
	{"goal": "challenges_cleared", "n": 5, "text": "Clear 5 challenges"},
	{"goal": "units_owned", "n": 15, "text": "Own 15 units"},
	{"goal": "army_power", "n": 1000, "text": "Field an army of 1,000 Strength"},
	{"goal": "explore", "n": 25, "text": "Send scouts out 25 times"},
	{"goal": "rating", "n": 1000, "text": "Reach 1,000 rating"},
	{"goal": "trinkets_owned", "n": 8, "text": "Own 8 trinkets"},
	{"goal": "max_tier", "n": 5, "text": "Raise a squad to tier 5"},
	{"goal": "draft_win", "n": 1, "text": "Win a Legion Draft match"},
	{"goal": "challenges_cleared", "n": 7, "text": "Clear 7 challenges"},
	{"goal": "army_power", "n": 2000, "text": "Field an army of 2,000 Strength"},
	{"goal": "player_level", "n": 15, "text": "Reach commander level 15"},
	{"goal": "rating", "n": 1500, "text": "Reach 1,500 rating"},
	{"goal": "units_owned", "n": 25, "text": "Own 25 units"},
	{"goal": "kills", "n": 10000, "text": "Defeat 10,000 enemy units"},
	{"goal": "max_tier", "n": 8, "text": "Raise a squad to tier 8"},
	{"goal": "challenges_cleared", "n": 10, "text": "Clear 10 challenges"},
	{"goal": "rating", "n": 2000, "text": "Reach 2,000 rating"},
	{"goal": "army_power", "n": 4000, "text": "Field an army of 4,000 Strength"},
	{"goal": "trinkets_owned", "n": 20, "text": "Own 20 trinkets"},
	{"goal": "player_level", "n": 20, "text": "Reach commander level 20"},
	{"goal": "challenges_cleared", "n": 12, "text": "Clear every challenge"},
	{"goal": "rating", "n": 2500, "text": "Reach 2,500 rating"},
	{"goal": "max_tier", "n": 10, "text": "Raise a squad to tier 10"},
	{"goal": "rating", "n": 3000, "text": "Reach 3,000 rating"},
]


## Story quest i (0-based) with its reward filled in.
static func story(i: int) -> Dictionary:
	if i < 0 or i >= STORY.size():
		return {}
	var q: Dictionary = STORY[i].duplicate()
	q["id"] = "s%d" % (i + 1)
	q["gold"] = 150 + 60 * i
	q["xp"] = 50 + 10 * i
	q["sigils"] = 5 if (i + 1) % 5 == 0 else 2
	if (i + 1) % 5 == 0:
		q["maps"] = 3
	if (i + 1) % 10 == 0:
		q["trinket_rarity"] = ["rare", "epic", "epic", "legendary", "legendary"][(i + 1) / 10 - 1]
	return q


static func quest_def(id: String) -> Dictionary:
	for q in DAILY:
		if q["id"] == id:
			return q.merged({"xp": DAILY_XP, "sigils": DAILY_SIGILS})
	for q in WEEKLY:
		if q["id"] == id:
			return q.merged({"xp": WEEKLY_XP, "sigils": WEEKLY_SIGILS})
	if id.begins_with("s") and id.substr(1).is_valid_int():
		return story(int(id.substr(1)) - 1)
	return {}


static func reward_text(q: Dictionary) -> String:
	var parts: Array = []
	if int(q.get("gold", 0)) > 0:
		parts.append("%d gold" % int(q["gold"]))
	if int(q.get("maps", 0)) > 0:
		parts.append("%d map%s" % [int(q["maps"]), "" if int(q["maps"]) == 1 else "s"])
	if q.has("trinket_rarity"):
		parts.append("a%s %s trinket" % ["n" if str(q["trinket_rarity"]).begins_with("e") or str(q["trinket_rarity"]).begins_with("u") else "", q["trinket_rarity"]])
	if int(q.get("sigils", 0)) > 0:
		parts.append("%d sigil%s" % [int(q["sigils"]), "" if int(q["sigils"]) == 1 else "s"])
	if int(q.get("xp", 0)) > 0:
		parts.append("%d XP" % int(q["xp"]))
	return ", ".join(PackedStringArray(parts))


# --- reset times -----------------------------------------------------------------------

const DAY := 86400
const WEEK := 604800


## Which day it is for daily quests: days counted from the reset time (UTC).
static func day_index(unix: int) -> int:
	return floori(float(unix - Difficulty.quest_reset_minute * 60) / float(DAY))


## Which week it is: weeks start on the reset weekday (0 Monday ... 6 Sunday)
## at the reset time. (1 Jan 1970 was a Thursday.)
static func week_index(unix: int) -> int:
	var monday_offset := 4 * DAY   # Thursday -> the next Monday
	return floori(float(unix - monday_offset - Difficulty.quest_reset_weekday * DAY - Difficulty.quest_reset_minute * 60) / float(WEEK))


static func seconds_to_next_day(unix: int) -> int:
	return (day_index(unix) + 1) * DAY + Difficulty.quest_reset_minute * 60 - unix


static func seconds_to_next_week(unix: int) -> int:
	return (week_index(unix) + 1) * WEEK + 4 * DAY + Difficulty.quest_reset_weekday * DAY + Difficulty.quest_reset_minute * 60 - unix


static func duration_text(sec: int) -> String:
	sec = maxi(0, sec)
	var d := sec / DAY
	var h := (sec % DAY) / 3600
	var m := (sec % 3600) / 60
	if d > 0:
		return "%dd %dh" % [d, h]
	if h > 0:
		return "%dh %dm" % [h, m]
	return "%dm" % maxi(1, m)
