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
const LEVEL_COUNT := 10

# The relentless chaser stays out of the tutorial levels and joins late.
const ULTRA_FIRST_LEVEL := 3
const ULTRA_SPAWN_TICK := 40


static func speed(level_index: int) -> float:
	return SPEEDS[clampi(level_index, 0, LEVEL_COUNT - 1)]


static func tea_pod_count(level_index: int) -> int:
	return TEA_POD_COUNTS[clampi(level_index, 0, LEVEL_COUNT - 1)]


static func has_ultra(level_index: int) -> bool:
	return level_index >= ULTRA_FIRST_LEVEL


static func coffee_count(level_index: int) -> int:
	var count := 0
	for tier_counts in BEAN_COUNTS:
		count += tier_counts[clampi(level_index, 0, LEVEL_COUNT - 1)]
	return count


static func bean_value(tier: int) -> int:
	return BEAN_VALUES[clampi(tier, 0, BEAN_VALUES.size() - 1)]


# Tier of the nth bean placed on a level, richest tiers last.
static func bean_tier(level_index: int, bean_index: int) -> int:
	var level := clampi(level_index, 0, LEVEL_COUNT - 1)
	var remaining := bean_index
	for tier in range(BEAN_COUNTS.size()):
		var tier_count: int = BEAN_COUNTS[tier][level]
		if remaining < tier_count:
			return tier
		remaining -= tier_count
	return BEAN_COUNTS.size() - 1


static func level_score(level_index: int) -> int:
	var total := 0
	for tier in range(BEAN_COUNTS.size()):
		total += BEAN_COUNTS[tier][clampi(level_index, 0, LEVEL_COUNT - 1)] * BEAN_VALUES[tier]
	return total
