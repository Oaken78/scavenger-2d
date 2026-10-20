extends Node2D
## The 2D prototype: a click-to-move dusk street in classic 2D (pre-rendered sprites with normal maps, 2D lights,
## occluder shadows), built from data/layout.json and driven by Sim. Same rules, map and camera angle as the 3D
## prototype; only the rendering differs.
##
## Lighting layers: every light source is two lights. The "ground" light (mask 1: ground, fog, actors) casts
## occluder shadows; the "sprite" light (mask 2: props) has none, so a house never shadows its own walls.

signal level_started
signal canister_taken
signal drone_destroyed

const LAYOUT := "res://data/layout.json"
const MASK_SHADOWED := 1  ## ground, fog, actors: lit by shadow-casting lights
const MASK_PROPS := 2  ## props: lit without shadows (a 2D sprite cannot shadow itself correctly)

@export_group("Dusk")
@export var dusk_color := Color(0.20, 0.23, 0.38)  ## CanvasModulate: the unlit world
@export var clear_color := Color(0.03, 0.04, 0.07)
@export var moon_color := Color(0.55, 0.65, 1.0)
@export var moon_energy := 0.22
@export var moon_rotation_deg := -38.0  ## screen direction the moonlight travels (shadows fall that way)
@export var moon_height := 0.55  ## 0..1, for the normal maps
@export var shadow_color := Color(0.0, 0.0, 0.03, 0.85)
@export_group("Lamps and fire")
@export var lamp_color := Color(1.0, 0.72, 0.38)
@export var lamp_energy := 1.5
@export var lamp_radius_m := 9.0
@export var fire_color := Color(1.0, 0.48, 0.16)
@export var fire_energy := 1.7
@export var fire_radius_m := 7.0
@export var flicker_seed := 20261020
@export_group("Robot headlight")
@export var headlight_color := Color(0.92, 0.95, 1.0)
@export var headlight_energy := 1.9
@export var headlight_range_m := 11.0
@export var headlight_half_angle_deg := 26.0
@export var headlight_fade_s := 2.0  ## fade-out when the fuel runs dry
@export var robot_glow_radius_m := 2.2  ## small fill light around the robot so it never vanishes in the dark
@export_group("Drones")
@export var eye_color := Color(1.0, 0.12, 0.08)
@export var eye_energy := 1.3
@export var eye_radius_m := 2.6
@export var pick_radius_m := 1.1  ## click distance that counts as clicking a drone
@export_group("Camera and fog")
@export var camera_smoothing := 4.0
@export var fog_on := true
@export var fog_wisps := 7
@export var prop_light_scale := 0.6  ## lamps, fire and headlight on prop sprites (walls are close to the bulb)
@export var cutaway_alpha := 0.35  ## tall props in front of the robot fade to this
@export var cutaway_speed := 6.0  ## alpha change per second
@export var cutaway_assets: PackedStringArray = ["house_ruin_a", "house_ruin_b", "subway_entrance", "tree", "street_lamp"]
@export var start_delay_frames := 10  ## level_started fires after this many physics frames

var sim: Sim
var fuel: float:
	get:
		return sim.fuel if sim != null else 0.0
	set(value):
		if sim != null:
			sim.fuel = clampf(value, 0.0, sim.fuel_max)
var robot_x: float:
	get:
		return sim.robot_pos.x
var robot_z: float:
	get:
		return sim.robot_pos.y
var canisters_left: int:
	get:
		return sim.canisters.filter(func(c: Dictionary) -> bool: return not c["taken"]).size()
var drones_alive: int:
	get:
		return sim.drones.filter(func(d: Dictionary) -> bool: return d["alive"]).size()
var outcome: String:
	get:
		return sim.outcome

var _layout: Dictionary = {}
var _bank: SpriteBank
var _world: Node2D
var _fog: Node2D
var _camera: Camera2D
var _hud: Hud
var _marker: Node2D
var _marker_age := 99.0
var _marker_at := Vector2.ZERO
var _robot: EntityView
var _robot_blob: Sprite2D
var _headlight: Array[PointLight2D] = []
var _robot_glow: PointLight2D
var _drones: Array[EntityView] = []
var _eyes: Array[PointLight2D] = []
var _canisters: Array[EntityView] = []
var _tall: Array[EntityView] = []  ## props that fade when they hide the robot
var _flickers: Array = []  ## {lights: Array[Light2D], base: float, kind: String}
var _wisps: Array = []  ## {node: Sprite2D, vel: Vector2 (m/s), pos: Vector2 (m)}
var _rng := RandomNumberGenerator.new()
var _anim_time := 0.0
var _fade := -1.0  ## seconds since out of fuel, -1 = not fading
var _started := false
var _frames := 0
var _flash_left := 0.0  ## robot hurt flash, 1 -> 0
var _radial: GradientTexture2D
var _pool: GradientTexture2D  ## 2:1 ellipse: a ground circle seen by the iso camera
var _headlight_tex: ImageTexture


func _ready() -> void:
	_rng.seed = flicker_seed
	_layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	sim = Sim.new(_layout)
	_bank = SpriteBank.new()
	EntityView.unlit_boost = Color(1.0 / dusk_color.r, 1.0 / dusk_color.g, 1.0 / dusk_color.b)
	RenderingServer.set_default_clear_color(clear_color)
	_radial = _make_radial(256, 256)
	_pool = _make_radial(256, 128)
	_headlight_tex = _make_cone()
	var cm := CanvasModulate.new()
	cm.color = dusk_color
	add_child(cm)
	_build_ground()
	_build_fog()
	_build_marker()
	_world = Node2D.new()
	_world.name = "World"
	_world.y_sort_enabled = true
	add_child(_world)
	_build_moon()
	_build_props()
	_build_pickups()
	_build_drones()
	_build_robot()
	_camera = Camera2D.new()
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = camera_smoothing
	_camera.position = Iso.to_screen(sim.robot_pos)
	add_child(_camera)
	_camera.make_current()
	_camera.reset_smoothing()
	_hud = Hud.new()
	add_child(_hud)
	_fog.visible = fog_on
	_sync_views(0.0)


func _physics_process(delta: float) -> void:
	_frames += 1
	if not _started and _frames >= start_delay_frames:
		_started = true
		level_started.emit()
	sim.advance(delta)
	for e: Dictionary in sim.events:
		match e["type"]:
			"pickup":
				_on_pickup(e["pos"])
			"drone_hit":
				_burst(e["pos"], 1.0, Color(1.0, 0.75, 0.4), 10)
			"drone_destroyed":
				_burst(e["pos"], 1.0, Color(1.0, 0.45, 0.2), 28)
				drone_destroyed.emit()
			"robot_hurt":
				_flash_left = 1.0
			"out_of_fuel":
				_fade = 0.0


func _process(delta: float) -> void:
	_anim_time += delta
	if _fade >= 0.0:
		_fade += delta
	_sync_views(delta)
	_update_lights()
	_update_fog(delta)
	_update_cutaway(delta)
	_update_marker(delta)
	_camera.position = Iso.to_screen(sim.robot_pos)
	_hud.set_fuel(sim.fuel, sim.fuel_max)
	match sim.outcome:
		"out_of_fuel":
			_hud.set_message("OUT OF FUEL - R to restart")
		"tank_stable":
			_hud.set_message("Tank stable")
		_:
			_hud.set_message("")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
	elif event.is_action_pressed("toggle_fog"):
		toggle_fog()
	elif event.is_action_pressed("toggle_stats"):
		_hud.toggle_stats()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		click_screen(get_global_mouse_position())


# ---- commands (input and scenario hooks) --------------------------------------------------------

## A left click at a canvas point: a drone under it is attacked, else the robot walks there.
func click_screen(canvas_point: Vector2) -> void:
	var ground := Iso.to_world(canvas_point)
	var id := sim.drone_at(ground, pick_radius_m)
	if id < 0:
		# Drones hover: also try the point the click hits at their body height.
		var hover := float(_layout["footprints"]["scrap_drone"].get("hover_height", 1.2))
		id = sim.drone_at(Iso.to_world(canvas_point + Vector2(0, (hover + 0.3) * Iso.LIFT)), pick_radius_m)
	if id >= 0:
		sim.command_attack(id)
		_place_marker(sim.drones[id]["pos"])
	else:
		sim.command_move(ground)
		_place_marker(ground)


func debug_move_to(x: float, z: float) -> void:
	sim.command_move(Vector2(x, z))
	_place_marker(Vector2(x, z))


func debug_attack(index: int) -> void:
	sim.command_attack(index)


func toggle_fog() -> void:
	fog_on = not fog_on
	_fog.visible = fog_on


# ---- building the scene -------------------------------------------------------------------------

func _build_ground() -> void:
	var b: Array = _layout["bounds"]
	var pad := 18.0
	var corners := [Vector2(b[0] - pad, b[1] - pad), Vector2(b[2] + pad, b[1] - pad),
		Vector2(b[2] + pad, b[3] + pad), Vector2(b[0] - pad, b[3] + pad)]
	var poly := Polygon2D.new()
	poly.name = "Ground"
	var pts := PackedVector2Array()
	for c: Vector2 in corners:
		pts.append(Iso.to_screen(c))
	poly.polygon = pts
	poly.z_index = -10
	poly.light_mask = MASK_SHADOWED
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ground.gdshader")
	var road: Dictionary = _layout["road"]
	mat.set_shader_parameter("road_z", float(road["from"][1]))
	mat.set_shader_parameter("road_half_width", float(road["width"]) * 0.5)
	mat.set_shader_parameter("sx", Iso.SX)
	mat.set_shader_parameter("sy", Iso.SY)
	poly.material = mat
	add_child(poly)


func _build_fog() -> void:
	_fog = Node2D.new()
	_fog.name = "Fog"
	_fog.z_index = -5
	add_child(_fog)
	var rect := ColorRect.new()
	rect.name = "FogLayer"
	rect.size = Vector2(1800, 1100)
	rect.light_mask = MASK_SHADOWED
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/fog.gdshader")
	mat.set_shader_parameter("sx", Iso.SX)
	mat.set_shader_parameter("sy", Iso.SY)
	rect.material = mat
	_fog.add_child(rect)
	var b: Array = _layout["bounds"]
	for i in fog_wisps:
		var s := Sprite2D.new()
		s.texture = _radial
		s.self_modulate = Color(0.6, 0.66, 0.78, 0.22)
		s.light_mask = MASK_SHADOWED
		var size_m := _rng.randf_range(5.0, 9.0)
		s.transform = Iso.ground_basis(size_m / _radial.width)
		var pos := Vector2(_rng.randf_range(b[0], b[2]), _rng.randf_range(b[1], b[3]))
		_wisps.append({"node": s, "pos": pos, "vel": Vector2(_rng.randf_range(0.2, 0.45), _rng.randf_range(-0.1, 0.15))})
		_fog.add_child(s)


func _build_marker() -> void:
	_marker = Node2D.new()
	_marker.name = "ClickMarker"
	_marker.z_index = -4
	_marker.material = EntityView._unlit_material()
	_marker.draw.connect(_draw_marker)
	add_child(_marker)


func _build_moon() -> void:
	for mask: int in [MASK_SHADOWED, MASK_PROPS]:
		var moon := DirectionalLight2D.new()
		moon.color = moon_color
		moon.energy = moon_energy
		moon.height = moon_height
		moon.rotation_degrees = moon_rotation_deg
		moon.range_item_cull_mask = mask
		# No moon shadows: 2D directional shadows never end, so every tree threw a stripe across the map.
		add_child(moon)


func _build_props() -> void:
	var fps: Dictionary = _layout["footprints"]
	for p: Dictionary in _layout["props"]:
		var asset: String = p["asset"]
		var fp: Dictionary = fps[asset]
		var pos := Vector2(p["pos"][0], p["pos"][1])
		var rot := deg_to_rad(float(p["rot"]))
		var size := _stand_in_size(asset, fp)
		var view := EntityView.new()
		view.name = "%s_%d" % [asset, _world.get_child_count()]
		view.position = Iso.to_screen(pos)
		view.setup(_bank, asset, size, float(fp["height"]), _stand_in_color(asset), rot, 0.0, MASK_PROPS)
		_world.add_child(view)
		if asset in cutaway_assets:
			_tall.append(view)
		var real: Array = fp["size"]
		if real[0] > 0 and real[1] > 0:
			_add_occluder(view, Vector2(real[0], real[1]), rot)
		match str(p.get("light", "")):
			"lamp", "lamp_flicker":
				var h := float(fp.get("light_height", 4.2))
				view.add_spot(Vector3(0, h, 0), 4.0, Color(1.0, 0.85, 0.6))
				_add_glow(view, h, lamp_color, 1.4)
				var lights := _add_light_pair(pos, lamp_color, lamp_energy, lamp_radius_m, h, _pool, Vector2.ZERO)
				_flickers.append({"lights": lights, "base": lamp_energy, "kind": str(p["light"])})
			"fire":
				var h := float(fp.get("light_height", 0.6))
				for k in 6:
					var a := TAU * k / 6.0
					view.add_spot(Vector3(cos(a) * 0.3, 0.15 + 0.1 * (k % 2), sin(a) * 0.3), 3.0, Color(1.0, 0.55, 0.15))
				_add_glow(view, h, fire_color, 1.5)
				_add_embers(view)
				var lights := _add_light_pair(pos, fire_color, fire_energy, fire_radius_m, h, _pool, Vector2.ZERO)
				_flickers.append({"lights": lights, "base": fire_energy, "kind": "fire"})


func _build_pickups() -> void:
	var fp: Dictionary = _layout["footprints"]["fuel_canister"]
	for c: Dictionary in sim.canisters:
		var view := EntityView.new()
		view.name = "Canister%d" % c["id"]
		view.position = Iso.to_screen(c["pos"])
		view.setup(_bank, "fuel_canister", _stand_in_size("fuel_canister", fp), float(fp["height"]),
			_stand_in_color("fuel_canister"), 0.0, 0.0, MASK_SHADOWED | MASK_PROPS)
		view.add_spot(Vector3(0, float(fp["height"]) + 0.05, 0), 2.0, Color(1.0, 0.85, 0.3))
		_world.add_child(view)
		_canisters.append(view)


func _build_drones() -> void:
	var fp: Dictionary = _layout["footprints"]["scrap_drone"]
	var hover := float(fp.get("hover_height", 1.2))
	for d: Dictionary in sim.drones:
		var view := EntityView.new()
		view.name = "Drone%d" % d["id"]
		view.setup(_bank, "scrap_drone", _stand_in_size("scrap_drone", fp), 0.45,
			_stand_in_color("scrap_drone"), d["heading"], hover, MASK_SHADOWED)
		view.add_spot(Vector3(0.42, 0.22, 0), 3.0, eye_color)
		_add_blob(view, 0.5, 0.45)
		_world.add_child(view)
		_drones.append(view)
		var eye := _make_light(eye_color, eye_energy, eye_radius_m, (hover + 0.2) * Iso.LIFT, _pool)
		eye.range_item_cull_mask = MASK_SHADOWED | MASK_PROPS
		add_child(eye)
		_eyes.append(eye)


func _build_robot() -> void:
	var fp: Dictionary = _layout["footprints"]["robot"]
	_robot = EntityView.new()
	_robot.name = "Robot"
	_robot.setup(_bank, "robot", _stand_in_size("robot", fp), float(fp["height"]), _stand_in_color("robot"),
		sim.robot_heading, 0.0, MASK_SHADOWED)
	var hh := float(fp.get("headlight_height", 1.1))
	_robot.add_spot(Vector3(0.47, hh, 0), 3.5, Color(1.0, 0.97, 0.85))
	_robot_blob = _add_blob(_robot, 0.75, 0.55)
	_world.add_child(_robot)
	_headlight = _add_light_pair(sim.robot_pos, headlight_color, headlight_energy, headlight_range_m, hh,
		_headlight_tex, Vector2(_headlight_tex.get_width() * 0.5, 0))
	_robot_glow = _make_light(Color(0.9, 0.85, 0.7), 0.6, robot_glow_radius_m, hh * Iso.LIFT, _pool)
	_robot_glow.range_item_cull_mask = MASK_SHADOWED | MASK_PROPS
	add_child(_robot_glow)


## Two lights at one source: shadowed for the ground layer, unshadowed for props. height in metres.
func _add_light_pair(ground: Vector2, color: Color, energy: float, radius_m: float, height_m: float,
		tex: Texture2D, offset_px: Vector2) -> Array[PointLight2D]:
	var out: Array[PointLight2D] = []
	for mask: int in [MASK_SHADOWED, MASK_PROPS]:
		var l := _make_light(color, energy if mask == MASK_SHADOWED else energy * prop_light_scale, radius_m, height_m * Iso.LIFT, tex)
		l.offset = offset_px
		l.position = Iso.to_screen(ground)
		l.range_item_cull_mask = mask
		if mask == MASK_SHADOWED:
			l.shadow_enabled = true
			l.shadow_color = shadow_color
			l.shadow_filter = Light2D.SHADOW_FILTER_PCF5
			l.shadow_filter_smooth = 1.5
			l.shadow_item_cull_mask = 1
		add_child(l)
		out.append(l)
	return out


## A point light whose texture lies on the ground: a circle of radius_m metres becomes the iso ellipse.
func _make_light(color: Color, energy: float, radius_m: float, height_px: float, tex: Texture2D) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = tex
	l.color = color
	l.energy = energy
	l.height = height_px
	# Light2D textures follow only position, rotation and scale (a skewed transform turned the cone), so the
	# iso foreshortening is baked into the textures (_pool is a 2:1 ellipse) and the scale stays uniform.
	l.scale = Vector2.ONE * (2.0 * radius_m * Iso.PX_PER_M / tex.get_width())
	l.set_meta("radius_m", radius_m)
	return l


func _add_occluder(view: EntityView, size: Vector2, rot: float) -> void:
	# Only the two far edges (away from the camera): the near walls stay lit, the ground behind gets the shadow.
	var half := size * 0.5
	if absf(sin(rot)) > 0.5:
		half = Vector2(half.y, half.x)
	var occ := LightOccluder2D.new()
	var poly := OccluderPolygon2D.new()
	poly.closed = false
	poly.polygon = PackedVector2Array([
		Iso.to_screen(Vector2(-half.x, half.y)), Iso.to_screen(Vector2(-half.x, -half.y)),
		Iso.to_screen(Vector2(half.x, -half.y)),
	])
	occ.occluder = poly
	occ.occluder_light_mask = 1
	view.add_child(occ)


func _add_blob(view: EntityView, radius_m: float, alpha: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _radial
	s.self_modulate = Color(0, 0, 0, alpha)
	s.material = EntityView._unlit_material()
	s.transform = Iso.ground_basis(2.0 * radius_m / _radial.width)
	s.show_behind_parent = true
	view.add_child(s)
	view.move_child(s, 0)
	return s


func _add_glow(view: EntityView, height_m: float, color: Color, radius_m: float) -> void:
	var s := Sprite2D.new()
	s.texture = _radial
	var b := EntityView.unlit_boost
	s.self_modulate = Color(color.r * b.r * 0.55, color.g * b.g * 0.55, color.b * b.b * 0.55, 1.0)
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = m
	s.scale = Vector2.ONE * (2.0 * radius_m * Iso.PX_PER_M / _radial.width)
	s.position = Iso.to_screen(Vector2.ZERO, height_m)
	view.add_child(s)


func _add_embers(view: EntityView) -> void:
	var p := CPUParticles2D.new()
	p.amount = 18
	p.lifetime = 1.6
	p.position = Iso.to_screen(Vector2.ZERO, 0.3)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 10.0
	p.direction = Vector2(0, -1)
	p.spread = 25.0
	p.gravity = Vector2(4, -30)
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 45.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	var b := EntityView.unlit_boost
	var g := Gradient.new()
	g.set_color(0, Color(1.0 * b.r, 0.7 * b.g, 0.25 * b.b, 1.0))
	g.set_color(1, Color(1.0 * b.r, 0.25 * b.g, 0.05 * b.b, 0.0))
	p.color_ramp = g
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = m
	view.add_child(p)


func _burst(ground: Vector2, height_m: float, color: Color, count: int) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = count
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.position = Iso.to_screen(ground, height_m)
	p.spread = 180.0
	p.gravity = Vector2(0, 260)
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 160.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 3.5
	var b := EntityView.unlit_boost
	p.color = Color(color.r * b.r, color.g * b.g, color.b * b.b)
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	p.material = m
	p.z_index = 5
	p.finished.connect(p.queue_free)
	add_child(p)


# ---- per frame ------------------------------------------------------------------------------------

func _sync_views(_delta: float) -> void:
	# Robot: a short lunge along the heading while swinging.
	var fwd := Vector2.from_angle(sim.robot_heading)
	var lunge := sin(sim.attack_phase * PI) * 0.3 if sim.robot_anim == "attack" else 0.0
	_robot.position = Iso.to_screen(sim.robot_pos + fwd * lunge)
	if sim.robot_anim == "attack":
		_robot.set_pose("attack", sim.robot_heading, sim.attack_phase, true)
	else:
		_robot.set_pose(sim.robot_anim, sim.robot_heading, _anim_time)
	_robot.set_flash(_flash_left)
	var hover := float(_layout["footprints"]["scrap_drone"].get("hover_height", 1.2))
	for i in _drones.size():
		var d: Dictionary = sim.drones[i]
		var view := _drones[i]
		view.visible = d["alive"]
		_eyes[i].visible = d["alive"]
		if not d["alive"]:
			continue
		view.position = Iso.to_screen(d["pos"])
		view.set_lift(view.base_lift + sin(_anim_time * 2.6 + i) * 0.08)
		view.set_pose("hover", d["heading"], _anim_time + i * 0.3)
		view.set_flash(d["hit_flash"] / Sim.HIT_FLASH)
		_eyes[i].position = Iso.to_screen(d["pos"])
		_eyes[i].energy = eye_energy * (1.0 + 1.5 * d["hit_flash"] / Sim.HIT_FLASH)
	for i in _canisters.size():
		_canisters[i].visible = not sim.canisters[i]["taken"]


func _update_lights() -> void:
	# Headlight: the cone along the heading, fading out over headlight_fade_s once the fuel is gone.
	var fade := 1.0
	if _fade >= 0.0:
		fade = clampf(1.0 - _fade / headlight_fade_s, 0.0, 1.0)
	# Turn the cone to the heading on screen and shorten it by how much the iso view foreshortens that heading.
	var fwd := Iso.to_screen(Vector2.from_angle(sim.robot_heading))
	var side := Iso.to_screen(Vector2.from_angle(sim.robot_heading + PI * 0.5))
	var px_per_tex := headlight_range_m / _headlight_tex.get_width()
	for l in _headlight:
		l.position = Iso.to_screen(sim.robot_pos)
		l.rotation = fwd.angle()
		l.scale = Vector2(fwd.length(), side.length()) * px_per_tex
		l.energy = headlight_energy * fade * (1.0 if l == _headlight[0] else prop_light_scale)
		l.visible = fade > 0.0
	_robot_glow.position = Iso.to_screen(sim.robot_pos)
	_robot_glow.energy = 0.6 * fade
	_robot.set_glow(fade)
	# Lamps and fire flicker (seeded noise, presentation only).
	for f: Dictionary in _flickers:
		var e: float = f["base"]
		match f["kind"]:
			"lamp_flicker":
				var r := _rng.randf()
				if r < 0.06:
					e *= 0.08
				elif r < 0.16:
					e *= 0.55
			"fire":
				e *= 0.82 + 0.18 * sin(_anim_time * 11.0) * sin(_anim_time * 7.3 + 1.0) + _rng.randf_range(-0.08, 0.08)
		var lights: Array = f["lights"]
		lights[0].energy = e
		lights[1].energy = e * prop_light_scale


## A tall prop drawn after the robot (lower on screen) whose image covers the robot's body fades out.
func _update_cutaway(delta: float) -> void:
	var body := Iso.to_screen(sim.robot_pos, 0.7)
	var robot_y := Iso.to_screen(sim.robot_pos).y
	for v in _tall:
		var hides := v.position.y > robot_y and v.screen_rect().has_point(body - v.position)
		var target := cutaway_alpha if hides else 1.0
		v.modulate.a = move_toward(v.modulate.a, target, cutaway_speed * delta)


func _update_fog(delta: float) -> void:
	if not _fog.visible:
		return
	var vp := get_viewport_rect().size
	var rect: ColorRect = _fog.get_node("FogLayer")
	rect.size = vp + Vector2(200, 200)
	rect.position = _camera.get_screen_center_position() - rect.size * 0.5
	var b: Array = _layout["bounds"]
	for w: Dictionary in _wisps:
		var p: Vector2 = w["pos"] + w["vel"] * delta
		if p.x > b[2] + 6.0:
			p.x = b[0] - 6.0
		if p.y > b[3] + 6.0:
			p.y = b[1] - 6.0
		elif p.y < b[1] - 6.0:
			p.y = b[3] + 6.0
		w["pos"] = p
		var s: Sprite2D = w["node"]
		s.position = Iso.to_screen(p)


func _on_pickup(at: Vector2) -> void:
	_burst(at, 0.4, Color(1.0, 0.85, 0.3), 16)
	canister_taken.emit()


func _place_marker(ground: Vector2) -> void:
	_marker_at = ground
	_marker_age = 0.0
	_marker.queue_redraw()


func _update_marker(delta: float) -> void:
	if _marker_age < 1.0:
		_marker_age += delta
		_marker.queue_redraw()
	if _flash_left > 0.0:
		_flash_left = maxf(0.0, _flash_left - delta * 4.0)


func _draw_marker() -> void:
	if _marker_age >= 0.8:
		return
	var k := _marker_age / 0.8
	var r := 0.25 + 0.35 * k
	var pts := PackedVector2Array()
	for i in 25:
		var a := TAU * i / 24.0
		pts.append(Iso.to_screen(_marker_at + Vector2(cos(a), sin(a)) * r))
	var b := EntityView.unlit_boost
	_marker.draw_polyline(pts, Color(0.75 * b.r, 0.95 * b.g, 1.0 * b.b, 1.0 - k), 2.0, true)


func _stand_in_size(asset: String, fp: Dictionary) -> Vector2:
	var s: Array = fp["size"]
	if s[0] > 0 and s[1] > 0:
		return Vector2(s[0], s[1])
	match asset:
		"robot":
			return Vector2(0.9, 0.9)
		"scrap_drone":
			return Vector2(0.8, 0.8)
		"fuel_canister":
			return Vector2(0.35, 0.25)
		"bush":
			return Vector2(1.3, 1.3)
	return Vector2(0.5, 0.5)


func _stand_in_color(asset: String) -> Color:
	match asset:
		"house_ruin_a":
			return Color(0.62, 0.6, 0.55)
		"house_ruin_b":
			return Color(0.58, 0.55, 0.5)
		"subway_entrance":
			return Color(0.45, 0.5, 0.48)
		"car_wreck":
			return Color(0.55, 0.32, 0.2)
		"street_lamp":
			return Color(0.3, 0.32, 0.34)
		"campfire":
			return Color(0.25, 0.2, 0.17)
		"tree":
			return Color(0.25, 0.38, 0.2)
		"bush":
			return Color(0.22, 0.42, 0.2)
		"fuel_canister":
			return Color(0.85, 0.2, 0.15)
		"scrap_drone":
			return Color(0.42, 0.42, 0.45)
		"robot":
			return Color(0.9, 0.7, 0.3)
	return Color(0.5, 0.5, 0.5)


func _make_radial(w: int, h: int) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.45))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = w
	t.height = h
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


## Top-down headlight cone: apex at the left middle, pointing +x (= the heading), soft edges, distance falloff.
func _make_cone() -> ImageTexture:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var half := deg_to_rad(headlight_half_angle_deg)
	for y in n:
		for x in n:
			var v := Vector2(x, y - n * 0.5)
			var d := v.length() / n
			var a := absf(v.angle())
			var edge := 1.0 - smoothstep(half * 0.6, half, a)
			var fall := (1.0 - smoothstep(0.35, 1.0, d)) * smoothstep(0.0, 0.05, d)
			var c := edge * fall
			img.set_pixel(x, y, Color(c, c, c, c))
	return ImageTexture.create_from_image(img)
