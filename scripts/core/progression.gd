class_name Progression
## Player experience (XP) and levels.
##
## Every finished match gives XP; winning gives much more. XP is saved in
## Config.xp and never goes down. Levels get a little longer each time:
##
##   XP to go from level n to n + 1 = LEVEL_BASE + LEVEL_STEP * (n - 1)
##   (level 1 -> 2: 400 XP, 2 -> 3: 500 XP, 3 -> 4: 600 XP, ...)

## XP for playing a match to the end.
const XP_MATCH := 50
## XP for each elimination in the match.
const XP_KILL := 10
## Extra XP for winning the match.
const XP_WIN := 250

const LEVEL_BASE := 400
const LEVEL_STEP := 100
const MAX_LEVEL := 100


## XP needed to go from `level` to the next one.
static func xp_to_next(level: int) -> int:
	return LEVEL_BASE + LEVEL_STEP * (level - 1)


## Level reached with `total_xp`, plus the progress inside that level:
## {"level": int, "into": XP earned in this level, "needed": XP this level needs}.
static func level_info(total_xp: int) -> Dictionary:
	var level := 1
	var left := maxi(total_xp, 0)
	while level < MAX_LEVEL and left >= xp_to_next(level):
		left -= xp_to_next(level)
		level += 1
	return {"level": level, "into": left, "needed": xp_to_next(level)}


## XP for one finished match, with the lines that explain it:
## {"total": int, "lines": [[label, amount], ...]}.
static func match_reward(kills: int, won: bool) -> Dictionary:
	var lines := [["Match played", XP_MATCH]]
	if kills > 0:
		lines.append(["%d elimination%s" % [kills, "" if kills == 1 else "s"], kills * XP_KILL])
	if won:
		lines.append(["Victory", XP_WIN])
	var total := 0
	for line in lines:
		total += int(line[1])
	return {"total": total, "lines": lines}


## XP a player would have earned with these statistics. Used once, to give
## players from older versions (no saved XP yet) the levels they already
## played for.
static func xp_from_stats(stats: Dictionary) -> int:
	return int(stats.get("matches", 0)) * XP_MATCH \
		+ int(stats.get("kills", 0)) * XP_KILL \
		+ int(stats.get("wins", 0)) * XP_WIN
