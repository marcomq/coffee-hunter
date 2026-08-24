class_name NetLink
extends Node

# Two halves, deliberately separated:
#   * discovery  - how peers FIND each other (UDP broadcast on the local net)
#   * transport  - how peers TALK once found (ENet + RPCs below)
# Only the discovery half is LAN-bound. Swapping it for a relay or a matchmaking
# service later leaves everything below `--- transport ---` untouched, which is
# why joining by typed address is a first-class path rather than a debug hatch:
# it already carries Tailscale/ZeroTier addresses and 127.0.0.1 today.

signal lobby_changed
signal link_ready(player_index: int)
signal link_lost(reason: String)
signal input_received(player_index: int, direction: Vector2i, throw_pressed: bool)
signal snapshot_received(payload: PackedByteArray)
signal event_received(kind: StringName, cell: Vector2i, world_index: int, player_index: int)
signal match_started(seed_value: int)
signal rematch_requested

enum Role { OFFLINE, HOST, CLIENT }

const GAME_PORT := 44567
const DISCOVERY_PORT := 44568
const BEACON_INTERVAL := 1.0
# A host that has gone quiet for this long drops off the browser.
const BEACON_TIMEOUT := 4.0
const BEACON_TAG := "coffee-hunter-v1"

var role := Role.OFFLINE
var found_games: Array[Dictionary] = []
var status_text := ""

var _beacon := PacketPeerUDP.new()
var _browser := PacketPeerUDP.new()
var _beacon_countdown := 0.0
var _browsing := false
var _host_name := "Plantage"
var _closing := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --- discovery ---------------------------------------------------------------


func host(host_name := "Plantage") -> bool:
	_ensure_peer_closed()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(GAME_PORT, 1)
	if error != OK:
		status_text = "Port %d ist belegt" % GAME_PORT
		return false
	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	_host_name = host_name
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_beacon_countdown = 0.0
	status_text = "Warte auf einen Gegenspieler..."
	stop_browsing()
	return true


func join(address: String) -> bool:
	_ensure_peer_closed()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(), GAME_PORT)
	if error != OK:
		status_text = "Kann %s nicht erreichen" % address
		return false
	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	status_text = "Verbinde mit %s..." % address
	stop_browsing()
	return true


func start_browsing() -> void:
	if _browsing:
		return
	if _browser.bind(DISCOVERY_PORT) != OK:
		status_text = "Kann im LAN nicht suchen (Port %d belegt)" % DISCOVERY_PORT
		return
	_browsing = true
	found_games.clear()
	lobby_changed.emit()


func stop_browsing() -> void:
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
			}))
	if _browsing:
		_poll_browser()


func _poll_browser() -> void:
	while _browser.get_available_packet_count() > 0:
		var payload := _browser.get_packet()
		var sender := _browser.get_packet_ip()
		var beacon: Variant = bytes_to_var(payload)
		if not (beacon is Dictionary) or beacon.get("tag", "") != BEACON_TAG:
			continue
		_remember_host(sender, String(beacon.get("name", "Plantage")))
	_forget_stale_hosts()


func _remember_host(address: String, host_name: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for entry in found_games:
		if entry["address"] == address:
			entry["last_seen"] = now
			entry["name"] = host_name
			return
	found_games.append({"address": address, "name": host_name, "last_seen": now})
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


# Host owns player 0, the single guest owns player 1.
func local_player_index() -> int:
	return 0 if role == Role.HOST else 1


# Deliberately quiet: a peer that has just connected is not yet able to receive
# RPCs reliably. The host waits for the guest to announce itself instead, which
# is the first moment a broadcast is guaranteed to land.
func _on_peer_connected(_peer_id: int) -> void:
	if role == Role.HOST:
		status_text = "Gegenspieler verbindet sich..."


# Fires on both sides, so the wording has to follow the role: for the host a
# guest walked out, for the guest the host closed the plantation.
func _on_peer_disconnected(_peer_id: int) -> void:
	if role == Role.CLIENT:
		disconnect_link("Der Host hat das Spiel beendet")
	else:
		disconnect_link("Der Gegenspieler hat die Verbindung verlassen")


func _on_connected_to_server() -> void:
	status_text = "Verbunden"
	announce_ready.rpc_id(1)
	link_ready.emit(1)


func _on_connection_failed() -> void:
	disconnect_link("Verbindung fehlgeschlagen")


func _on_server_disconnected() -> void:
	disconnect_link("Der Host hat das Spiel beendet")


func send_input(direction: Vector2i, throw_pressed: bool) -> void:
	if role != Role.CLIENT:
		return
	submit_input.rpc_id(1, direction, throw_pressed)


func broadcast_snapshot(payload: PackedByteArray) -> void:
	if role != Role.HOST:
		return
	push_snapshot.rpc(payload)


func broadcast_event(kind: StringName, cell: Vector2i, world_index: int, player_index: int) -> void:
	if role != Role.HOST:
		return
	push_event.rpc(kind, cell, world_index, player_index)


func broadcast_match_start(seed_value: int) -> void:
	if role != Role.HOST:
		return
	push_match_start.rpc(seed_value)


# A rematch takes both sides, so this only announces intent - it travels either
# way and the receiver decides what it is worth. Only the host owns the seed and
# can actually start the next race.
func send_rematch() -> void:
	if role == Role.OFFLINE:
		return
	request_rematch.rpc()


@rpc("any_peer", "call_remote", "reliable")
func request_rematch() -> void:
	rematch_requested.emit()


@rpc("any_peer", "call_remote", "reliable")
func announce_ready() -> void:
	if role != Role.HOST:
		return
	status_text = "Gegenspieler verbunden"
	link_ready.emit(0)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_input(direction: Vector2i, throw_pressed: bool) -> void:
	if role != Role.HOST:
		return
	input_received.emit(1, direction, throw_pressed)


@rpc("authority", "call_remote", "unreliable")
func push_snapshot(payload: PackedByteArray) -> void:
	snapshot_received.emit(payload)


@rpc("authority", "call_remote", "reliable")
func push_event(kind: StringName, cell: Vector2i, world_index: int, player_index: int) -> void:
	event_received.emit(kind, cell, world_index, player_index)


@rpc("authority", "call_remote", "reliable")
func push_match_start(seed_value: int) -> void:
	match_started.emit(seed_value)
