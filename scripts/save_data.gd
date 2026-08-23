class_name SaveData
extends RefCounted

# Small enough that a ConfigFile beats any format with a schema. The path is a
# static var, not a const, so tests can redirect it away from the real save.
static var path := "user://coffee-hunter.cfg"
const SECTION := "progress"


static func _config() -> ConfigFile:
	var config := ConfigFile.new()
	# A missing file is the normal first-run case, not an error.
	config.load(path)
	return config


static func high_score() -> int:
	return int(_config().get_value(SECTION, "high_score", 0))


static func best_level() -> int:
	return int(_config().get_value(SECTION, "best_level", 0))


static func is_muted() -> bool:
	return bool(_config().get_value(SECTION, "muted", false))


static func set_muted(value: bool) -> void:
	var config := _config()
	config.set_value(SECTION, "muted", value)
	config.save(path)


# Returns true when this run beat the stored high score.
static func record_run(score: int, level_index: int) -> bool:
	var config := _config()
	var previous_score := int(config.get_value(SECTION, "high_score", 0))
	var previous_level := int(config.get_value(SECTION, "best_level", 0))
	var is_record := score > previous_score
	config.set_value(SECTION, "high_score", maxi(score, previous_score))
	config.set_value(SECTION, "best_level", maxi(level_index, previous_level))
	config.save(path)
	return is_record
