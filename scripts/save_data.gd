class_name SaveData
extends RefCounted

# Small enough that a ConfigFile beats any format with a schema. The path is a
# static var, not a const, so tests can redirect it away from the real save.
static var path := "user://coffee-hunter.cfg"
const SECTION := "progress"
const SCORE_SLOTS := 5
const NAME_LENGTH := 12
const DEFAULT_NAME := "PAOLO"


static func _config() -> ConfigFile:
	var config := ConfigFile.new()
	# A missing file is the normal first-run case, not an error.
	config.load(path)
	return config


static func high_score() -> int:
	return int(_config().get_value(SECTION, "high_score", 0))


static func best_level() -> int:
	return int(_config().get_value(SECTION, "best_level", 0))


static func player_name() -> String:
	return String(_config().get_value(SECTION, "player_name", DEFAULT_NAME))


static func set_player_name(value: String) -> void:
	var config := _config()
	config.set_value(SECTION, "player_name", clean_name(value))
	config.save(path)


# Upper case and clipped, so a long name cannot push the score out of the panel.
# Square brackets go too: the roster panel draws these names as bbcode, and a
# name is the one string in it that someone else's machine gets to choose.
# Public because the host has to run every name a guest announces through it.
static func clean_name(value: String) -> String:
	var cleaned := value.strip_edges().to_upper().replace("[", "").replace("]", "")
	if cleaned == "":
		return DEFAULT_NAME
	return cleaned.substr(0, NAME_LENGTH)


# Best runs first, at most SCORE_SLOTS of them: [{name, score, level}, ...].
static func scores() -> Array:
	var stored: Variant = _config().get_value(SECTION, "scores", [])
	if not (stored is Array):
		return []
	var entries: Array = []
	for entry in stored:
		if entry is Dictionary and entry.has("score"):
			entries.append(entry)
	return entries


static func is_muted() -> bool:
	return bool(_config().get_value(SECTION, "muted", false))


static func set_muted(value: bool) -> void:
	var config := _config()
	config.set_value(SECTION, "muted", value)
	config.save(path)


# Best score and furthest level only, so a run still in progress counts toward
# both. Deliberately no table entry: a run that is not over has no place there.
# Returns true when this beat the stored high score.
static func record_progress(score: int, level_index: int) -> bool:
	var config := _config()
	var previous_score := int(config.get_value(SECTION, "high_score", 0))
	var previous_level := int(config.get_value(SECTION, "best_level", 0))
	var is_record := score > previous_score
	config.set_value(SECTION, "high_score", maxi(score, previous_score))
	config.set_value(SECTION, "best_level", maxi(level_index, previous_level))
	config.save(path)
	return is_record


# A finished run: the progress above, plus its one line in the table.
static func record_run(score: int, level_index: int, name := "") -> bool:
	var is_record := record_progress(score, level_index)
	# A run worth no points says nothing about who played well; it only pushes a
	# real entry out of a five-slot table.
	if score > 0:
		var config := _config()
		var entries := scores()
		entries.append({
			"name": clean_name(name if name != "" else player_name()),
			"score": score,
			"level": level_index,
		})
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["score"]) > int(b["score"]))
		entries.resize(mini(entries.size(), SCORE_SLOTS))
		config.set_value(SECTION, "scores", entries)
		config.save(path)
	return is_record
