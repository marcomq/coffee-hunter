class_name PlayerSlot
extends RefCounted

# One competitor. The slot travels with its player through the portal, so board
# position and match stats sit together here instead of on the world: a player
# who raids the neighbouring plantation takes their score along.
var cell: Vector2i
var facing := Vector2i.DOWN
var prev: Vector2i
var moved_at := -1.0
var arrives_at := 0.0
var invulnerable_until := 0.0
var contact_since := -1.0
var score := 0
# Only beans and squashes feed this. The extra-life ladder reads it instead of
# `score` so that points taken off a rival can never buy lives.
var earned_score := 0
var lives := 3
# Out of lives, or gone from the link. An eliminated slot is taken off its board
# entirely, so the rules below never have to ask.
var is_out := false
# Seconds of standing still banked toward the next coffee throw. Travels with the
# slot, so a portal hop can top it up.
var coffee_charge := 0.0
var next_extra_life_score := 0
