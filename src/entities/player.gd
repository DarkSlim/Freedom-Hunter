extends "entity.gd"


onready var camera_node = get_node("../yaw/pitch/camera")
onready var yaw_node = get_node("../yaw")
onready var audio_node = get_node("audio")
onready var interact_node = get_node("interact")
onready var offset = yaw_node.get_translation().y
onready var hud = get_node("/root/game/hud")
onready var onscreen = hud.get_node("onscreen")
var inventory = preload("res://scene/inventory.tscn").instance()

const SPRINT_USE = 5
const SPRINT_REGENERATION = 4
const SPEED = 5
const JUMP = 5
const SPRINT_SPEED = 7.5

#multiplayer
var local = true
var start_walk = false

signal got_item
signal used_item

func init(local, hp, stamina):
	assert(get_node("model/AnimationPlayer") != null)
	.init(hp, stamina, get_node("model/AnimationPlayer"))
	self.local = local
	resume_player()

	get_node("weapon/sword").init(self)

	# TEST CODE
	var Item = preload("res://src/items/item.gd")
	var null_item = Item.new()
	null_item.init(self, preload("res://media/items/null.png"), "None", 0, 0, true, 0, true)
	var Potion = preload("res://src/items/potion.gd")
	var potion = Potion.new()
	potion.init(self, preload("res://media/items/potion.png"), "Potion", 10, 25)
	var Firework = preload("res://src/items/firework.gd")
	var firework = Firework.new()
	firework.init(self, preload("res://media/items/firework.png"), "Firework", 10)
	var Barrel = preload("res://src/items/barrel.gd")
	var barrel = Barrel.new()
	barrel.init(self, preload("res://media/items/barrel.png"), "Barrel", 5)
	inventory.init([null_item, potion, firework, barrel], 30)
	inventory.set_pos(Vector2(1370, 200))
	inventory.set_name("player_inventory")

func sort_by_distance(a, b):
	var dist_a = (get_global_transform().origin - a.get_global_transform().origin).length()
	var dist_b = (get_global_transform().origin - b.get_global_transform().origin).length()
	return dist_a < dist_b

func get_nearest_interact():
	var interacts = interact_node.get_overlapping_areas()
	for i in interacts:
		if not i.is_in_group("interact"):
			interacts.erase(i)
	if interacts.size() > 0:
		interacts.sort_custom(self, "sort_by_distance")
		return interacts[0]
	return null

func interact_with(interact):
	if interact != null and not hud.get_node("notification/animation").is_playing():
		interact.get_parent().interact(self)

func interact_with_nearest():
	interact_with(get_nearest_interact())

func _input(event):
	if event.is_action_pressed("player_scroll_next") and not Input.is_action_pressed("camera_rotation_lock"):
		inventory.activate_next()
		hud.update_items()
	elif event.is_action_pressed("player_scroll_back") and not Input.is_action_pressed("camera_rotation_lock"):
		inventory.activate_prev()
		hud.update_items()
	elif event.is_action_pressed("player_use"):
		inventory.use_active_item()
		hud.update_items()
	elif event.is_action_pressed("player_interact"):
		interact_with_nearest()

func add_item(item):
	var remainder = inventory.add_item(item)
	if local:
		hud.update_items()
		if remainder > 0:
			hud.notify("You got %d out of %d %s" % [remainder - item.quantity, item.quantity, item.name])
		else:
			hud.notify("You got %d %s" % [item.quantity, item.name])
	return remainder

func heal(amount):
	hp += amount
	if hp > max_hp:
		hp = max_hp

sync func die():
	.die()
	get_node("audio").play("hit")
	rotate_x(PI/2)
	set_translation(get_translation() + Vector3(0, 0.5, 0))
	set_fixed_process(false)
	set_process_input(false)

func get_name():  # this script is attached to a node always called body
	return get_parent().get_name()  # parent's name is more meaningful

func pause_player():
	set_process_input(false)
	set_fixed_process(false)
	camera_node.set_process_input(false)

func resume_player():
	if local:
		set_process_input(true)
		set_fixed_process(true)
		camera_node.set_process_input(true)

func _process(delta):
	var anim = animation_node.get_current_animation()
	if direction.length() != 0:
		if dodging:
			if anim != "dodge":
				animation_node.play("dodge")
			return
		if running:
			if anim != "run":
				animation_node.play("run")
			return
		else:
			if anim != "walk":
				animation_node.play("walk")
	else:
		if anim != "idle":
			animation_node.play("idle")


func _fixed_process(delta):
	assert(local)
	# This fails on the client! See https://github.com/godotengine/godot/issues/6475
	get_parent().set_network_mode(NETWORK_MODE_MASTER)
	assert(get_parent().is_network_master())
	assert(get_network_mode() == NETWORK_MODE_INHERIT)
	direction = Vector3(0, 0, 0)
	var jump = 0
	var camera = camera_node.get_global_transform()
	# Player movements
	running = Input.is_action_pressed("player_run")
	var speed = SPEED
	if Input.is_action_pressed("player_forward"):
		direction -= Vector3(camera.basis.z.x, 0, camera.basis.z.z)
	if Input.is_action_pressed("player_backward"):
		direction += Vector3(camera.basis.z.x, 0, camera.basis.z.z)
	if Input.is_action_pressed("player_left"):
		direction -= Vector3(camera.basis.x.x, 0, camera.basis.x.z)
	if Input.is_action_pressed("player_right"):
		direction += Vector3(camera.basis.x.x, 0, camera.basis.x.z)
	if onscreen.is_visible():
		var d = onscreen.direction
		if onscreen.intensity > 0.75:
			speed = onscreen.intensity * SPRINT_SPEED
			stamina -= SPRINT_USE * delta
			running = true
		else:
			speed = onscreen.intensity * SPEED
			running = false
		direction = d.y * camera.basis.z + d.x * camera.basis.x
	if running and stamina > 0 and direction != Vector3():
		speed = SPRINT_SPEED
		stamina -= SPRINT_USE * delta
	elif stamina < max_stamina:
		stamina += SPRINT_REGENERATION * delta
		if stamina > max_stamina:
			stamina = max_stamina
	if Input.is_action_pressed("player_dodge"):
		if running:
			if on_floor:
				jumping = true
				jump = SPRINT_SPEED
				stamina -= 3
		elif not dodging:
			dodging = true
			speed *= 3
			stamina -= 15

	direction = direction.normalized()
	direction.x = direction.x * speed
	direction.y = jump
	direction.z = direction.z * speed

	# Player collision and physics
	move_entity(delta)

	if Input.is_action_pressed("player_attack_left"):
		if not animation_node.is_playing():
			rpc("attack", "left_attack_0")
	if Input.is_action_pressed("player_attack_right"):
		if not animation_node.is_playing():
			rpc("attack", "right_attack_0")

	# Camera follows the player
	yaw_node.set_translation(get_translation() + Vector3(0, offset, 0))
