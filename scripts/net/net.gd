class_name Net
extends Node
## Сетевая игра (кооператив): ENet, «слушающий сервер» — один из игроков (хост) играет и одновременно держит мир.
## Отдельный сервер не нужен. Порт UDP 7777 (у хоста — проброс порта или общая виртуальная сеть: Radmin VPN,
## ZeroTier, Hamachi; в одной локальной сети — просто IP хоста).
##
## Кто за что отвечает:
## - хост: время суток, зомби (ИИ, появление), их удары по игрокам и постройкам; рассылает клиентам снимки зомби;
## - каждый игрок: своё движение, инвентарь, здоровье (урон от зомби приходит с хоста);
## - правки мира (копание, удары по зданиям, двери, срубленное, срезанная трава, обысканное, выброшенные предметы) —
##   операции op(): применяются у себя и пересылаются всем (через хоста), у всех детерминированно одинаково.
## Подключение: клиент получает от хоста параметры генерации и все правки (как сохранение), сам генерирует мир.
##
## Узел живёт в /root/Net (одинаковый путь у всех — для RPC), создаётся Net.ensure().

const PORT := 7777
const VERSION := "77d-net-1"
const MAX_PEERS := 7
const STATE_HZ := 20.0
const ZSNAP_HZ := 10.0
const ZSNAP_R := 160.0        # зомби дальше этого от клиента ему не шлются
const ZSNAP_CHUNK := 10       # зомби в одном пакете снимка

signal status(text: String)
signal welcome_received(data: Dictionary)
signal failed(reason: String)

static var inst: Net
static var my_name := "Игрок"
static var applying := false  # идёт применение чужой операции — не пересылать дальше

var peer: ENetMultiplayerPeer
var hosting := false
var main: Node                # main.gd, пока идёт игра
var names := {}               # peer id -> имя
var remotes := {}             # peer id -> RemotePlayer
var my_aw := 0.0              # (клиент) заметность меня зомби — из снимков хоста
var _queue: Array = []        # (клиент) операции, пришедшие до входа в мир
var _state_t := 0.0
var _zsnap_t := 0.0
var _time_t := 0.0
var _act_seq := 0
var _act_name := ""
var _pickup_uid := 0


static func ensure(tree: SceneTree) -> Net:
	if inst != null and is_instance_valid(inst):
		return inst
	var n := Net.new()
	n.name = "Net"
	tree.root.add_child(n)
	inst = n
	return n


static func active() -> bool:
	return inst != null and is_instance_valid(inst) and inst.peer != null


static func is_host() -> bool:
	return active() and inst.hosting


static func is_client() -> bool:
	return active() and not inst.hosting


static func my_id() -> int:
	return inst.multiplayer.get_unique_id() if active() else 1


## Сообщение всем клиентам (у хоста показывается своим кодом).
static func toast_all(text: String) -> void:
	if is_host():
		inst._toast.rpc(text)


func _exit_tree() -> void:
	if inst == self:
		inst = null


# --- подключение ---------------------------------------------------------------------------

func host(port: int = PORT) -> Error:
	close()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PEERS)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	hosting = true
	names = {1: my_name}
	_connect_signals()
	return OK


func join(ip: String, port: int = PORT) -> Error:
	close()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	hosting = false
	_connect_signals()
	status.emit("Подключение к %s:%d…" % [ip, port])
	return OK


func close() -> void:
	for rp: Node in remotes.values():
		if is_instance_valid(rp):
			rp.queue_free()
	remotes.clear()
	names.clear()
	_queue.clear()
	if peer != null:
		peer.close()
	peer = null
	if is_inside_tree():
		multiplayer.multiplayer_peer = null
	hosting = false
	main = null


func _connect_signals() -> void:
	var mp := multiplayer
	if not mp.peer_connected.is_connected(_on_peer_connected):
		mp.peer_connected.connect(_on_peer_connected)
		mp.peer_disconnected.connect(_on_peer_disconnected)
		mp.connected_to_server.connect(_on_connected)
		mp.connection_failed.connect(_on_failed)
		mp.server_disconnected.connect(_on_server_gone)


func _on_peer_connected(_id: int) -> void:
	pass     # хост ждёт _hello с именем и версией


func _on_peer_disconnected(id: int) -> void:
	var nm := String(names.get(id, "Игрок"))
	names.erase(id)
	if remotes.has(id):
		if is_instance_valid(remotes[id]):
			remotes[id].queue_free()
		remotes.erase(id)
	_local_toast("%s вышел из игры" % nm)


func _on_connected() -> void:
	status.emit("Подключено, жду мир от хоста…")
	_hello.rpc_id(1, my_name, VERSION)


func _on_failed() -> void:
	close()
	failed.emit("Не удалось подключиться")


func _on_server_gone() -> void:
	var in_game := main != null
	close()
	failed.emit("Хост отключился")
	if in_game:
		# без автозагрузки Game (её нет в тестах --script): то же, что Game.back_to_menu()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://scenes/menu.tscn")


## Клиент -> хост: представиться. Хост отвечает миром (параметры + правки + время) или отказом.
@rpc("any_peer", "call_remote", "reliable")
func _hello(nm: String, ver: String) -> void:
	if not hosting:
		return
	var id := multiplayer.get_remote_sender_id()
	if ver != VERSION:
		_reject.rpc_id(id, "Другая версия игры (у хоста %s)" % VERSION)
		return
	if main == null or not main._spawned:
		_reject.rpc_id(id, "Хост ещё загружает мир")
		return
	names[id] = nm.substr(0, 24) if nm.strip_edges() != "" else "Игрок %d" % id
	var d := _world_snapshot()
	var raw := var_to_bytes(d)
	_welcome.rpc_id(id, raw.compress(FileAccess.COMPRESSION_ZSTD), raw.size())
	_names.rpc(names)
	_local_toast("%s подключается…" % names[id])


@rpc("authority", "call_remote", "reliable")
func _reject(reason: String) -> void:
	close()
	failed.emit(reason)


@rpc("authority", "call_remote", "reliable")
func _welcome(packed: PackedByteArray, size: int) -> void:
	var d: Variant = bytes_to_var(packed.decompress(size, FileAccess.COMPRESSION_ZSTD))
	if not (d is Dictionary):
		close()
		failed.emit("Повреждённые данные мира")
		return
	welcome_received.emit(d)


@rpc("authority", "call_remote", "reliable")
func _names(n: Dictionary) -> void:
	names = n


@rpc("authority", "call_remote", "reliable")
func _toast(text: String) -> void:
	_local_toast(text)


func _local_toast(text: String) -> void:
	if main != null and main.player != null:
		main.player.call("_toast", text, 3.5)


## Мир для подключающегося: как сохранение (SaveGame), без игрока; плюс где сейчас хост (там и появится).
func _world_snapshot() -> Dictionary:
	var terrain: Terrain = main.terrain
	var chunks := {}
	terrain._data_mutex.lock()
	for cc: Vector3i in terrain._data.keys():
		var cd: ChunkData = terrain._data[cc]
		if cd.edited:
			chunks[cc] = [cd.dens, cd.mat]
	terrain._data_mutex.unlock()
	var grids := {}
	for k: String in main.settlement.edited_grids:
		grids[k] = SaveGame._grid_to_dict(main.settlement.edited_grids[k])
	return {
		"net_client": true,
		"params": SaveGame.params_to_dict(main.world.params),
		"time": main.time_of_day, "day": main.day,
		"chunks": chunks, "buildings": grids,
		"plants": Vegetation.removed.keys(), "grass_cut": GrassField.cut.keys(),
		"looted": Loot._looted.keys(), "sleepers_killed": ZombieDirector.sleepers_killed.duplicate(),
		"spawn": main.player.global_position,
	}


# --- в игре ---------------------------------------------------------------------------------

## main.gd готов (игрок создан): клиент применяет накопленные операции.
func attach(m: Node) -> void:
	main = m
	if m.player != null:
		m.player.peer_id = my_id()
		m.player.display_name = my_name
	var q := _queue.duplicate()
	_queue.clear()
	for op: Array in q:
		_apply_op(String(op[0]), op[1])


func detach() -> void:
	main = null


func _process(delta: float) -> void:
	if not active() or main == null or main.player == null:
		return
	_state_t -= delta
	if _state_t <= 0.0:
		_state_t = 1.0 / STATE_HZ
		_send_state()
	if hosting:
		_zsnap_t -= delta
		if _zsnap_t <= 0.0:
			_zsnap_t = 1.0 / ZSNAP_HZ
			_send_zombies()
		_time_t -= delta
		if _time_t <= 0.0:
			_time_t = 1.0
			_time.rpc(main.time_of_day, main.day)


@rpc("authority", "call_remote", "unreliable_ordered")
func _time(tod: float, day: int) -> void:
	if main != null:
		main.time_of_day = tod
		main.day = day


# --- игроки ---------------------------------------------------------------------------------

## Действие руки своего игрока (удар, выстрел, питьё…) — показать у других на модели.
func local_action(action: String) -> void:
	_act_seq = (_act_seq + 1) % 1000
	_act_name = action


func _send_state() -> void:
	var pl: Player = main.player
	var s: Variant = pl.inventory.selected_item()
	var flags := (1 if pl.crouching else 0) | (2 if pl._sprinting else 0) | (4 if pl._dead_t > 0.0 else 0) \
		| (8 if pl.flying else 0) | (16 if pl.inventory.has_backpack else 0)
	_pstate.rpc(pl.global_position, pl.rotation.y, pl._pitch, flags, "" if s == null else String(s["id"]), _act_seq, _act_name)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _pstate(pos: Vector3, yaw: float, pitch: float, flags: int, item: String, act_seq: int, act: String) -> void:
	if main == null:
		return
	var id := multiplayer.get_remote_sender_id()
	var rp: RemotePlayer = remotes.get(id)
	if rp == null or not is_instance_valid(rp):
		rp = RemotePlayer.new()
		rp.peer_id = id
		rp.display_name = String(names.get(id, "Игрок %d" % id))
		rp.position = pos
		main.add_child(rp)
		remotes[id] = rp
		_local_toast("%s в игре" % rp.display_name)
	rp.apply_state(pos, yaw, pitch, flags, item, act_seq, act)


## Хост: зомби ударил игрока по сети.
func damage_remote(id: int, amount: float) -> void:
	_damage.rpc_id(id, amount)


@rpc("authority", "call_remote", "reliable")
func _damage(amount: float) -> void:
	if main != null and main.player != null:
		main.player.take_damage(amount)


# --- шум и звуки ---------------------------------------------------------------------------

func send_noise(pos: Vector3, radius: float) -> void:
	_noise.rpc_id(1, pos, radius)


@rpc("any_peer", "call_remote", "unreliable")
func _noise(pos: Vector3, radius: float) -> void:
	if hosting:
		ZombieDirector.noise(pos, radius, remotes.get(multiplayer.get_remote_sender_id()))


## Звук, который должны услышать и остальные (шаги, удары, выстрелы игрока; голоса и удары зомби у хоста).
static func echo_sfx(ctx: Node, nm: String, pos: Vector3, vol: float, dist: float, pv: float) -> void:
	if not active() or applying or inst.main == null:
		return
	var ok := ctx is Player or (ctx is Zombie and not (ctx as Zombie).puppet and inst.hosting)
	if ok:
		inst._sfx.rpc(nm, pos, vol, dist, pv)


@rpc("any_peer", "call_remote", "unreliable")
func _sfx(nm: String, pos: Vector3, vol: float, dist: float, pv: float) -> void:
	if main == null or main.player == null:
		return
	if main.player.global_position.distance_to(pos) > dist + 5.0:
		return
	applying = true
	Sfx.play_at(main, nm, pos, vol, dist, pv)
	applying = false


## Визуальный эффект для остальных: кровь от попадания.
func fx_blood(pos: Vector3, dir: Vector3, k: float) -> void:
	_fx_blood.rpc(pos, dir, k)


@rpc("any_peer", "call_remote", "unreliable")
func _fx_blood(pos: Vector3, dir: Vector3, k: float) -> void:
	if main != null:
		Blood.spray(main, pos, dir, k)


# --- зомби ----------------------------------------------------------------------------------

## Клиент ударил марионетку: удар — хосту (там настоящий зомби).
func zombie_hit(z: Zombie, dmg: float, dir: Vector3, pos: Vector3, kind: String, bonus: float) -> void:
	_zhit.rpc_id(1, z.net_id, dmg, dir, pos, kind, bonus)


@rpc("any_peer", "call_remote", "reliable")
func _zhit(id: int, dmg: float, dir: Vector3, pos: Vector3, kind: String, bonus: float) -> void:
	if not hosting:
		return
	var z: Zombie = Zombie.by_id.get(id)
	if z == null or not is_instance_valid(z) or z.dead:
		return
	var sender := multiplayer.get_remote_sender_id()
	z.take_hit(dmg, dir, pos, kind, bonus, remotes.get(sender), sender)


## Хост: событие зомби для марионеток (сбит с ног, убит).
func zevent(id: int, ev: String, dir: Vector3, extra: int) -> void:
	_zev.rpc(id, ev, dir, extra)


@rpc("authority", "call_remote", "reliable")
func _zev(id: int, ev: String, dir: Vector3, extra: int) -> void:
	var z: Zombie = Zombie.by_id.get(id)
	if z == null or not is_instance_valid(z) or not z.puppet:
		return
	match ev:
		"knock":
			z.net_knock(dir)
		"die":
			z.net_die(dir)
			if extra == my_id():
				Gear.kills += 1


## Хост: снимки зомби каждому клиенту (только те, что рядом с ним).
func _send_zombies() -> void:
	var zs: Array = []
	if main.zombies != null:
		for z: Zombie in main.zombies.get_children():
			if not z.is_queued_for_deletion():
				zs.append(z)
	for id: int in remotes:
		var rp: Node3D = remotes[id]
		if not is_instance_valid(rp):
			continue
		var list: Array = []
		for z: Zombie in zs:
			if z.global_position.distance_to(rp.global_position) < ZSNAP_R:
				list.append(z.net_state())
				if list.size() >= ZSNAP_CHUNK:     # пакет меньше MTU (иначе потери выше)
					_zsnap.rpc_id(id, list)
					list = []
		if not list.is_empty():
			_zsnap.rpc_id(id, list)


@rpc("authority", "call_remote", "unreliable_ordered")
func _zsnap(list: Array) -> void:
	if main == null or main.zombies == null:
		return
	var me := my_id()
	var seen := {}
	for e: Array in list:
		var id := int(e[0])
		seen[id] = true
		var z: Zombie = Zombie.by_id.get(id)
		if z == null or not is_instance_valid(z):
			if bool(e[9]):
				continue     # уже мёртвый — не создавать
			z = Zombie.new()
			z.net_id = id
			z.puppet = true
			z.ztype = "mudworn" if int(e[1]) == 1 else "friend"
			z.player = main.player
			z.gen = main.terrain.gen
			z.terrain = main.terrain
			z.position = e[2]
			z.rotation.y = float(e[3])
			main.zombies.add_child(z)
		elif bool(e[9]) and not z.dead:
			z.net_die(z._last_hit_dir)
		z.net_apply(e[2], float(e[3]), String(e[4]), float(e[5]), int(e[6]), float(e[7]))
		z.aw_mine = float(e[7]) if int(e[8]) == me else 0.0
	# заметность меня — по всем марионеткам (снимок приходит несколькими пакетами)
	var aw := 0.0
	for z: Zombie in main.zombies.get_children():
		if z.puppet and not z.dead:
			aw = maxf(aw, z.aw_mine)
	my_aw = aw
	# пропавшие из снимков (ушли далеко, удалены хостом) — убрать; мёртвые доживают сами (ragdoll, гниение)
	var now := Time.get_ticks_msec()
	for z: Zombie in main.zombies.get_children():
		if z.puppet and not z.dead and not seen.has(z.net_id) and now - z.net_seen_ms > 1500:
			z.queue_free()


# --- правки мира ----------------------------------------------------------------------------

## Операция над миром, уже выполненная у себя: разослать остальным (клиент — через хоста).
## kind: terrain [центр, радиус, насыпать, материал] | bb_hit [ключ здания, ячейка, урон, инструмент] |
## door [ключ, якорь] | removed [позиция] | grass [позиция, радиус] | looted [позиция] |
## drop [uid, позиция, предмет, скорость] | take [uid, позиция]
static func op(kind: String, args: Array) -> void:
	if not active() or applying:
		return
	if inst.hosting:
		inst._op.rpc(kind, args)
	else:
		inst._op.rpc_id(1, kind, args)


@rpc("any_peer", "call_remote", "reliable")
func _op(kind: String, args: Array) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if hosting:
		# переслать остальным клиентам
		for id in multiplayer.get_peers():
			if id != sender:
				_op.rpc_id(id, kind, args)
	if main == null:
		_queue.append([kind, args])
		return
	_apply_op(kind, args)


func _apply_op(kind: String, a: Array) -> void:
	applying = true
	match kind:
		"terrain":
			main.terrain.edit_sphere(a[0], float(a[1]), bool(a[2]), int(a[3]))
		"bb_hit":
			var bb: BlockBuilding = Settlement.live_building(String(a[0]))
			if bb != null:
				bb.hit_cell(a[1], float(a[2]), String(a[3]))
			else:
				Settlement.defer_op(String(a[0]), a)
		"door":
			var bb2: BlockBuilding = Settlement.live_building(String(a[0]))
			if bb2 != null:
				var was_open := (bb2.grid.get_meta_at(a[1].x, a[1].y, a[1].z) & (1 << 10)) != 0
				if bb2.toggle_door(a[1]):
					Sfx.play_at(main, "door_close" if was_open else "door_open", bb2._cell_world(a[1]), 0.0, 30.0)
			else:
				Settlement.defer_op(String(a[0]), a)
		"removed":
			_remove_at(a[0])
		"grass":
			GrassField.cut_around(get_tree(), a[0], float(a[1]))
		"looted":
			Loot.mark_looted(a[0])
		"drop":
			var p := ItemPickup.spawn(main, a[1], a[2], a[3])
			p.set_meta("uid", a[0])
		"take":
			for n: Node3D in get_tree().get_nodes_in_group("pickups"):
				if (n.has_meta("uid") and n.get_meta("uid") == a[0]) or \
						(String(a[0]) == "" and n.global_position.distance_to(a[1]) < 0.3):
					n.queue_free()
					break
	applying = false


## Срублено/сломано/подобрано у другого игрока: убрать узел на этом месте (дерево, камень, куст, реквизит).
func _remove_at(pos: Vector3) -> void:
	Vegetation.mark_removed(pos)
	var space: PhysicsDirectSpaceState3D = (main as Node3D).get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 1.3
	q.shape = sh
	q.transform = Transform3D(Basis(), pos + Vector3.UP * 0.7)
	q.collision_mask = 2 | 8 | 16
	for r: Dictionary in space.intersect_shape(q, 48):
		var n := r["collider"] as Node
		for i in 5:
			if n == null:
				break
			if n is Node3D and (n.has_meta("resource") or n.has_meta("breakable")) \
					and Vector2((n as Node3D).global_position.x - pos.x, (n as Node3D).global_position.z - pos.z).length() < 0.3:
				Debris.dust(main, (n as Node3D).global_position + Vector3.UP * 0.4, Color(0.45, 0.4, 0.32), 0.8)
				n.queue_free()
				return
			n = n.get_parent()


## Уникальный id выброшенного предмета.
func next_uid() -> String:
	_pickup_uid += 1
	return "%d_%d" % [my_id(), _pickup_uid]


## Локальные IPv4-адреса (подсказка хосту, какой IP сообщить друзьям).
static func local_ips() -> Array:
	var out: Array = []
	for a: String in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out
