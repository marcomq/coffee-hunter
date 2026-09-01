class_name NetLink
extends Node

# Two halves, deliberately separated:
#   * discovery  - how peers FIND each other (UDP broadcast on the local net)
#   * transport  - how peers TALK once found (ENet + RPCs below)
# Only the discovery half is LAN-bound. Swapping it for a relay or a matchmaking
# service later leaves everything below `--- transport ---` untouched, which is
# why joining by typed address is a first-class path rather than a debug hatch:
# it already carries Tailscale/ZeroTier addresses and 127.0.0.1 today.

const SaveDataClass = preload("res://scripts/save_data.gd")

signal lobby_changed
signal roster_changed
signal link_ready(player_index: int)
signal link_lost(reason: String)
signal player_left(player_index: int)
signal input_received(player_index: int, direction: Vector2i, throw_pressed: bool)
signal snapshot_received(payload: PackedByteArray)
signal event_received(kind: StringName, cell: Vector2i, world_index: int, player_index: int)
signal match_started(seed_value: int, player_count: int)
signal rematch_requested(player_index: int)
signal rematch_changed(flags: PackedByteArray)

enum Role { OFFLINE, HOST, CLIENT }

const MAX_PLAYERS := 4
const GAME_PORT := 44567
const DISCOVERY_PORT := 44568
const BEACON_INTERVAL := 1.0
# A second instance on this machine cannot take the discovery port while the
# first one is browsing, so a failed bind is retried at this interval.
const BIND_RETRY_INTERVAL := 1.0
# A host that has gone quiet for this long drops off the browser.
const BEACON_TIMEOUT := 4.0
const BEACON_TAG := "coffee-hunter-v1"
# Bumped whenever a snapshot or an RPC changes shape. The beacon tag only gates
# what the browser lists; a join by typed address skips discovery entirely, so
# the handshake below is the only place a mismatched build is actually caught.
const PROTOCOL_VERSION := 1
# A guest posts one input per physics tick. Twice that leaves plenty of room for
# a jittery sender while still cutting off a peer that floods the host.
const INPUT_BUDGET := 140.0

var role := Role.OFFLINE
var found_games: Array[Dictionary] = []
var status_text := ""
# Who is in this match: [{peer_id, index, name}, ...]. The host keeps the list and
# hands out the slots; everyone else mirrors whatever the host last sent.
var roster: Array[Dictionary] = []
# Shut while a race is on: a latecomer would sit in the waiting room holding up
# the rematch, since that waits for every seat in the roster.
var accepting := true

var _beacon := PacketPeerUDP.new()
var _browser := PacketPeerUDP.new()
var _beacon_countdown := 0.0
var _browsing := false
var _browse_wanted := false
var _bind_retry := 0.0
var _host_name := "Plantation"
var _local_name := "PAOLO"
# The slot this peer last knew as its own; a rematch can renumber it.
var _seated_index := -1
var _closing := false
# peer_id -> inputs still allowed this second, refilled in _process.
var _input_budget: Dictionary[int, float] = {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --- discovery ---------------------------------------------------------------


func host(player_name := "PAOLO") -> bool:
	_ensure_peer_closed()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(GAME_PORT, MAX_PLAYERS - 1)
	if error != OK:
		status_text = "Port %d is taken" % GAME_PORT
		return false
	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	_seated_index = 0
	_local_name = player_name
	_host_name = player_name
	roster = [{"peer_id": 1, "index": 0, "name": SaveDataClass.clean_name(player_name)}]
	accepting = true
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_beacon_countdown = 0.0
	status_text = "Waiting for players..."
	stop_browsing()
	link_ready.emit(0)
	roster_changed.emit()
	return true


func join(address: String, player_name := "PAOLO") -> bool:
	_ensure_peer_closed()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(), GAME_PORT)
	if error != OK:
		status_text = "Cannot reach %s" % address
		return false
	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	_seated_index = -1
	_local_name = player_name
	roster.clear()
	status_text = "Connecting to %s..." % address
	stop_browsing()
	return true


func start_browsing() -> void:
	_browse_wanted = true
	found_games.clear()
	_bind_browser()
	lobby_changed.emit()


# The port is only ever held by another local instance sitting in its own lobby;
# it frees the moment that instance hosts or leaves, so browsing is not given up
# on a busy port - it is picked up on the next retry.
func _bind_browser() -> bool:
	if _browsing:
		return true
	_bind_retry = BIND_RETRY_INTERVAL
	if _browser.bind(DISCOVERY_PORT) != OK:
		status_text = "Port %d is busy - still looking for games" % DISCOVERY_PORT
		return false
	_browsing = true
	return true


func stop_browsing() -> void:
	_browse_wanted = false
	if not _browsing:
		return
	_browser.close()
	_browsing = false


# Every caller but the lobby reaches this from inside a multiplayer signal, i.e.
# from within ENet's own poll. Closing the peer there tears down the object that
# is currently dispatching, which segfaults the engine - so the actual teardown
# is deferred to the end of the frame, and re-entry is refused meanwhile.
func disconnect_link(reason := "") -> void:
	if _closing:
		return
	_closing = true
	role = Role.OFFLINE
	_seated_index = -1
	roster.clear()
	stop_browsing()
	_beacon.close()
	_close_peer.call_deferred()
	if reason != "":
		status_text = reason
		link_lost.emit(reason)


# Opening a link is always user-driven from the lobby, never from inside a
# multiplayer signal, so the old peer can be closed right here. It has to be:
# a peer left dangling by the deferred path still owns the UDP port, and the
# next host() would fail with "Couldn't create an ENet host".
func _ensure_peer_closed() -> void:
	_closing = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null


func _close_peer() -> void:
	_closing = false
	# A fresh host()/join() may have run between the request and this deferred
	# call; tearing that new peer down would kill a healthy link.
	if role != Role.OFFLINE:
		return
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null


func _process(delta: float) -> void:
	if role == Role.HOST:
		_beacon_countdown -= delta
		if _beacon_countdown <= 0.0:
			_beacon_countdown = BEACON_INTERVAL
			_beacon.put_packet(var_to_bytes({
				"tag": BEACON_TAG,
				"name": _host_name,
				"port": GAME_PORT,
				"players": roster.size(),
			}))
	if role == Role.HOST:
		for peer_id in _input_budget:
			_input_budget[peer_id] = minf(_input_budget[peer_id] + INPUT_BUDGET * delta, INPUT_BUDGET)
	if _browse_wanted and not _browsing:
		_bind_retry -= delta
		if _bind_retry <= 0.0 and _bind_browser():
			lobby_changed.emit()
	if _browsing:
		_poll_browser()


func _poll_browser() -> void:
	while _browser.get_available_packet_count() > 0:
		var payload := _browser.get_packet()
		var sender := _browser.get_packet_ip()
		var beacon: Variant = bytes_to_var(payload)
		if not (beacon is Dictionary) or beacon.get("tag", "") != BEACON_TAG:
			continue
		_remember_host(sender, String(beacon.get("name", "Plantation")), int(beacon.get("players", 1)))
	_forget_stale_hosts()


func _remember_host(address: String, host_name: String, player_count: int) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for entry in found_games:
		if entry["address"] == address:
			entry["last_seen"] = now
			entry["name"] = host_name
			entry["players"] = player_count
			return
	found_games.append({"address": address, "name": host_name, "players": player_count, "last_seen": now})
	lobby_changed.emit()


func _forget_stale_hosts() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var kept: Array[Dictionary] = []
	for entry in found_games:
		if now - float(entry["last_seen"]) < BEACON_TIMEOUT:
			kept.append(entry)
	if kept.size() != found_games.size():
		found_games = kept
		lobby_changed.emit()


# --- transport ---------------------------------------------------------------
# The host is the only authority. Clients never simulate: they post their intent
# and draw whatever comes back.


func is_host() -> bool:
	return role == Role.HOST


func is_online() -> bool:
	return role != Role.OFFLINE


# The host always owns slot 0; every guest is told its slot with the roster.
func local_player_index() -> int:
	if role == Role.HOST:
		return 0
	# No peer, no seat: a guest has no slot until the host's roster hands it one.
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return -1
	return index_of_peer(multiplayer.get_unique_id())


func index_of_peer(peer_id: int) -> int:
	for entry in roster:
		if int(entry["peer_id"]) == peer_id:
			return int(entry["index"])
	return -1


func name_of(player_index: int) -> String:
	for entry in roster:
		if int(entry["index"]) == player_index:
			return String(entry["name"])
	return "PLAYER %d" % (player_index + 1)


# Everyone but the host, for the per-peer snapshot loop.
func guests() -> Array[Dictionary]:
	var others: Array[Dictionary] = []
	for entry in roster:
		if int(entry["peer_id"]) != 1:
			others.append(entry)
	return others


# The lowest free slot, so a seat left by a quitter is filled again.
func _claim_slot(peer_id: int, player_name: String) -> int:
	for entry in roster:
		if int(entry["peer_id"]) == peer_id:
			return int(entry["index"])
	var taken: Array[int] = []
	for entry in roster:
		taken.append(int(entry["index"]))
	for candidate in range(MAX_PLAYERS):
		if not taken.has(candidate):
			roster.append({"peer_id": peer_id, "index": candidate, "name": SaveDataClass.clean_name(player_name)})
			roster.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["index"]) < int(b["index"]))
			return candidate
	return -1


# Seats left empty by a quitter are closed up before the next race, so the match
# above can keep counting its players 0..n-1.
func compact_slots() -> void:
	if role != Role.HOST:
		return
	roster.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["index"]) < int(b["index"]))
	for position in range(roster.size()):
		roster[position]["index"] = position
	push_roster.rpc(_packed_roster())
	roster_changed.emit()


func _packed_roster() -> Array:
	var packed: Array = []
	for entry in roster:
		packed.append([int(entry["peer_id"]), int(entry["index"]), String(entry["name"])])
	return packed


# Deliberately quiet: a peer that has just connected is not yet able to receive
# RPCs reliably. The host waits for the guest to announce itself instead, which
# is the first moment a broadcast is guaranteed to land.
func _on_peer_connected(_peer_id: int) -> void:
	if role == Role.HOST:
		status_text = "A player is connecting..."


# With server relay on, a client also hears about every other client leaving, so
# only the host acts on this: a guest learns who is gone from the next roster.
# The one departure that ends a guest's match is the host's, and that arrives as
# `server_disconnected`.
func _on_peer_disconnected(peer_id: int) -> void:
	if role != Role.HOST:
		return
	var index := index_of_peer(peer_id)
	if index < 0:
		return
	_input_budget.erase(peer_id)
	for entry_index in range(roster.size()):
		if int(roster[entry_index]["peer_id"]) == peer_id:
			roster.remove_at(entry_index)
			break
	status_text = "%s left the plantation" % name_of(index)
	push_roster.rpc(_packed_roster())
	player_left.emit(index)
	roster_changed.emit()


func _on_connected_to_server() -> void:
	status_text = "Connected - waiting for a slot"
	announce_ready.rpc_id(1, _local_name, PROTOCOL_VERSION)


func _on_connection_failed() -> void:
	disconnect_link("Connection failed")


func _on_server_disconnected() -> void:
	disconnect_link("The host closed the game")


# A build that disagrees about a snapshot's shape draws a different board from
# the same bytes, so it is turned away at the handshake rather than let in.
func accepts_protocol(protocol: int) -> bool:
	return protocol == PROTOCOL_VERSION


# One input per physics tick is the honest rate; a peer that exceeds its bucket
# is simply not heard until the bucket refills.
func _spend_input_budget(peer_id: int) -> bool:
	var budget: float = _input_budget.get(peer_id, INPUT_BUDGET)
	if budget < 1.0:
		return false
	_input_budget[peer_id] = budget - 1.0
	return true


func send_input(direction: Vector2i, throw_pressed: bool) -> void:
	if role != Role.CLIENT:
		return
	submit_input.rpc_id(1, direction, throw_pressed)


# One board per guest, never the whole match: see the note above
# `MatchState.to_bytes`.
func send_snapshot(peer_id: int, payload: PackedByteArray) -> void:
	if role != Role.HOST:
		return
	push_snapshot.rpc_id(peer_id, payload)


func broadcast_event(kind: StringName, cell: Vector2i, world_index: int, player_index: int) -> void:
	if role != Role.HOST:
		return
	push_event.rpc(kind, cell, world_index, player_index)


func broadcast_match_start(seed_value: int, player_count: int) -> void:
	if role != Role.HOST:
		return
	push_match_start.rpc(seed_value, player_count)


# A rematch takes everyone, so a guest can only announce itself; the host keeps
# the tally and owns the seed for the next race.
func send_rematch() -> void:
	if role != Role.CLIENT:
		return
	request_rematch.rpc_id(1)


func broadcast_rematch(flags: PackedByteArray) -> void:
	if role != Role.HOST:
		return
	push_rematch.rpc(flags)


@rpc("any_peer", "call_remote", "reliable")
func request_rematch() -> void:
	if role != Role.HOST:
		return
	rematch_requested.emit(index_of_peer(multiplayer.get_remote_sender_id()))


@rpc("authority", "call_remote", "reliable")
func push_rematch(flags: PackedByteArray) -> void:
	rematch_changed.emit(flags)


@rpc("any_peer", "call_remote", "reliable")
func announce_ready(player_name: String, protocol := 0) -> void:
	if role != Role.HOST:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	# Two builds that disagree on a snapshot's shape connect perfectly happily and
	# then draw two different boards. Better to say so than to desync.
	if not accepts_protocol(protocol):
		push_rejected.rpc_id(peer_id, "That build is a different version of the game")
		return
	if not accepting:
		push_rejected.rpc_id(peer_id, "The race is already running - try again shortly")
		return
	var index := _claim_slot(peer_id, player_name)
	if index < 0:
		status_text = "The plantation is full"
		push_rejected.rpc_id(peer_id, "The plantation is full")
		return
	status_text = "%d players in the lobby" % roster.size()
	push_roster.rpc(_packed_roster())
	roster_changed.emit()


# The guest tears its own link down, which is what tells the host to forget the
# half-finished handshake.
@rpc("authority", "call_remote", "reliable")
func push_rejected(reason: String) -> void:
	disconnect_link(reason)


@rpc("authority", "call_remote", "reliable")
func push_roster(entries: Array) -> void:
	roster.clear()
	for entry in entries:
		roster.append({"peer_id": int(entry[0]), "index": int(entry[1]), "name": String(entry[2])})
	var own_index := local_player_index()
	# The roster that first names this peer is also the moment it learns which
	# plantation is its own - there is no earlier one. A rematch that closes up
	# empty seats moves it again, and that has to travel too.
	if own_index >= 0 and own_index != _seated_index:
		_seated_index = own_index
		status_text = "Connected as %s" % name_of(own_index)
		link_ready.emit(own_index)
	roster_changed.emit()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_input(direction: Vector2i, throw_pressed: bool) -> void:
	if role != Role.HOST:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var index := index_of_peer(peer_id)
	if index < 0 or not _spend_input_budget(peer_id):
		return
	input_received.emit(index, direction, throw_pressed)


@rpc("authority", "call_remote", "unreliable_ordered")
func push_snapshot(payload: PackedByteArray) -> void:
	snapshot_received.emit(payload)


@rpc("authority", "call_remote", "reliable")
func push_event(kind: StringName, cell: Vector2i, world_index: int, player_index: int) -> void:
	event_received.emit(kind, cell, world_index, player_index)


@rpc("authority", "call_remote", "reliable")
func push_match_start(seed_value: int, player_count: int) -> void:
	match_started.emit(seed_value, player_count)
