class_name LevelData
extends RefCounted

# Difficulty ramps gently: no step raises the pace by more than ~11%.
# The original LevelN.java values (2,3,3,4,4,4,4,6,6,6) jumped 50% at once.
const SPEEDS := [2.0, 2.2, 2.45, 2.7, 2.95, 3.2, 3.5, 3.8, 4.15, 4.5]
const TEA_POD_COUNTS := [2, 2, 3, 3, 4, 5, 6, 7, 8, 9]

# BEAN_COUNTS[tier][level_index]; a tier's beans are worth BEAN_VALUES[tier].
# Counts rise 6 -> 18 and the mix shifts to richer tiers, so both the number of
# beans and the score per level grow from level to level.
const BEAN_VALUES := [40, 80, 120, 160]
const BEAN_COUNTS := [
	[6, 6, 5, 4, 3, 2, 1, 0, 0, 0],
	[0, 2, 4, 4, 4, 4, 3, 3, 2, 1],
	[0, 0, 1, 3, 4, 4, 5, 5, 5, 4],
	[0, 0, 0, 1, 2, 4, 6, 8, 10, 13],
]
const FILTER_COUNT := 12

# Hand-authored levels. The run does not end there: every later level continues
# the same ramps by formula, so the game is endless and only the curve is
# designed. Each ramp caps out, or a late level would stop being playable.
const LEVEL_COUNT := 10
const MAX_SPEED := 6.0
const ENDLESS_SPEED_STEP := 0.12
const MAX_TEA_PODS := 12
# One extra bean per endless level until the board would get too crowded.
const ENDLESS_BEAN_STEPS := 20

# Tea pots enter after the first two introductory levels.
const TEAPOT_FIRST_LEVEL := 2

# The relentless chaser stays out of the tutorial levels, then enters after a
# short visible delay so it cannot be skipped by finishing the level quickly.
const ULTRA_FIRST_LEVEL := 3
const ULTRA_SPAWN_TICK := 40


# How far past the last authored level we are; 0 while inside them.
static func endless_step(level_index: int) -> int:
	return maxi(level_index - LEVEL_COUNT + 1, 0)


static func is_endless(level_index: int) -> bool:
	return level_index >= LEVEL_COUNT


static func speed(level_index: int) -> float:
	if not is_endless(level_index):
		return SPEEDS[maxi(level_index, 0)]
	return minf(SPEEDS[LEVEL_COUNT - 1] + ENDLESS_SPEED_STEP * endless_step(level_index), MAX_SPEED)


static func tea_pod_count(level_index: int) -> int:
	if not is_endless(level_index):
		return TEA_POD_COUNTS[maxi(level_index, 0)]
	var extra := (endless_step(level_index) + 1) / 2
	return mini(TEA_POD_COUNTS[LEVEL_COUNT - 1] + extra, MAX_TEA_PODS)


static func has_ultra(level_index: int) -> bool:
	return level_index >= ULTRA_FIRST_LEVEL


# Beans of one tier on a level. Endless levels keep the last authored mix and
# add one bean per level, alternating between the two richest tiers.
static func bean_count(tier: int, level_index: int) -> int:
	if not is_endless(level_index):
		return BEAN_COUNTS[tier][maxi(level_index, 0)]
	var count: int = BEAN_COUNTS[tier][LEVEL_COUNT - 1]
	var extra := mini(endless_step(level_index), ENDLESS_BEAN_STEPS)
	if tier == BEAN_COUNTS.size() - 1:
		count += (extra + 1) / 2
	elif tier == BEAN_COUNTS.size() - 2:
		count += extra / 2
	return count


static func coffee_count(level_index: int) -> int:
	var count := 0
	for tier in range(BEAN_COUNTS.size()):
		count += bean_count(tier, level_index)
	return count


static func bean_value(tier: int) -> int:
	return BEAN_VALUES[clampi(tier, 0, BEAN_VALUES.size() - 1)]


# Tier of the nth bean placed on a level, richest tiers last.
static func bean_tier(level_index: int, bean_index: int) -> int:
	var remaining := bean_index
	for tier in range(BEAN_COUNTS.size()):
		var tier_count := bean_count(tier, level_index)
		if remaining < tier_count:
			return tier
		remaining -= tier_count
	return BEAN_COUNTS.size() - 1


static func level_score(level_index: int) -> int:
	var total := 0
	for tier in range(BEAN_COUNTS.size()):
		total += bean_count(tier, level_index) * BEAN_VALUES[tier]
	return total
