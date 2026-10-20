class_name EntityView
extends Node2D
## One prop or actor on screen. Sits at the screen point of its ground origin (the y-sort key). Shows the
## A01 sprite (colour + normal map, emissive layer unlit on top) when the bank has it, else an IsoBox stand-in.

## Multiplies unlit layers so they keep their own colour under the CanvasModulate (set by Main).
static var unlit_boost := Color.WHITE

var asset := ""
var lift_m := 0.0  ## metres the body floats above its ground point
var base_lift := 0.0  ## lift without bobbing: stand-ins hover by code, sprites are rendered hovering
var _bank: SpriteBank
var _sprite: Sprite2D
var _emissive: Sprite2D
var _box: IsoBox
var _glow: Node2D  ## stand-in emissive spots
var _spots: Array = []  ## {pos: Vector3 (metres, local x/y/z at rot 0), radius: float px, color: Color}
var _rot := 0.0
var _dir := -1
var _anim := ""
var _frame := -1


## Build the view. footprint = [size_x, size_z], height in metres, rot in radians.
func setup(bank: SpriteBank, asset_name: String, footprint: Vector2, height: float, color: Color,
		rot: float, lift: float, light_mask_bits: int) -> void:
	asset = asset_name
	_bank = bank
	_rot = rot
	if bank != null and bank.has(asset):
		lift_m = bank.lift_m(asset, 0.0)  # A01 renders hovering actors at their height already
		base_lift = lift_m
		_sprite = Sprite2D.new()
		_sprite.centered = false
		_sprite.light_mask = light_mask_bits
		add_child(_sprite)
		_emissive = Sprite2D.new()
		_emissive.centered = false
		_emissive.material = _unlit_material()
		_emissive.self_modulate = unlit_boost
		add_child(_emissive)
		set_pose("static", rot, 0.0)
	else:
		lift_m = lift
		base_lift = lift
		_box = IsoBox.new()
		_box.size = footprint
		_box.height = height
		_box.lift = lift
		_box.color = color
		_box.rot = rot
		_box.light_mask = light_mask_bits
		add_child(_box)
		_glow = Node2D.new()
		_glow.material = _unlit_material()
		_glow.self_modulate = unlit_boost
		_glow.draw.connect(_draw_spots)
		add_child(_glow)


func uses_sprites() -> bool:
	return _sprite != null


## Stand-in emissive spot (headlamp, eye, ember) at a local point in metres (rotates with the body).
func add_spot(local: Vector3, radius_px: float, color: Color) -> void:
	_spots.append({"pos": local, "radius": radius_px, "color": color})
	if _glow != null:
		_glow.queue_redraw()


## Show anim at heading (radians); t = seconds into the anim, or a 0..1 phase when phase is true.
func set_pose(anim: String, heading: float, t: float, phase := false) -> void:
	_rot = heading
	if _box != null:
		_box.rot = heading
		_glow.queue_redraw()
		return
	var a := _bank.pick_anim(asset, anim)
	var dirs := _bank.dirs(asset)
	var dir := Iso.dir_index(heading, dirs)
	var count := _bank.frame_count(asset, a)
	var f := 0
	if phase:
		f = clampi(int(t * count), 0, count - 1)
	else:
		f = int(t * _bank.fps(asset)) % maxi(count, 1)
	if a == _anim and dir == _dir and f == _frame:
		return
	_anim = a
	_dir = dir
	_frame = f
	var fr := _bank.frame(asset, a, dir, f)
	if fr.is_empty():
		return
	var off := -_bank.origin(asset) - Vector2(0, lift_m * Iso.LIFT)
	_sprite.texture = fr["tex"]
	_sprite.offset = off
	_emissive.texture = fr["emissive"]
	_emissive.offset = off


## The body's image rect in local pixels (for the cutaway test).
func screen_rect() -> Rect2:
	if _sprite != null and _sprite.texture != null:
		return Rect2(_sprite.offset, _sprite.texture.get_size())
	if _box != null:
		var half := _box.size.rotated(_box.rot).abs() * 0.5
		var r := Rect2(Iso.to_screen(Vector2(-half.x, -half.y), lift_m), Vector2.ZERO)
		for c: Vector2 in [Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y), Vector2(-half.x, -half.y)]:
			r = r.expand(Iso.to_screen(c, lift_m)).expand(Iso.to_screen(c, lift_m + _box.height))
		return r
	return Rect2()


## Height of the body above its ground point (hovering drones bob).
func set_lift(metres: float) -> void:
	if is_equal_approx(metres, lift_m):
		return
	lift_m = metres
	if _box != null:
		_box.lift = metres
		_box.queue_redraw()
		_glow.queue_redraw()
	elif _sprite != null and _sprite.texture != null:
		var off := -_bank.origin(asset) - Vector2(0, lift_m * Iso.LIFT)
		_sprite.offset = off
		_emissive.offset = off


## Brightness of the unlit layer (0 = dark, 1 = full): the headlamp fading when the fuel runs out.
func set_glow(amount: float) -> void:
	var c := Color(unlit_boost.r, unlit_boost.g, unlit_boost.b, clampf(amount, 0.0, 1.0))
	if _emissive != null:
		_emissive.self_modulate = c
	if _glow != null:
		_glow.self_modulate = c


func set_flash(amount: float) -> void:
	var m := Color(1.0 + amount * 2.0, 1.0 + amount * 2.0, 1.0 + amount * 2.0)
	if _sprite != null:
		_sprite.self_modulate = m
	if _box != null:
		_box.self_modulate = m


func _draw_spots() -> void:
	for s: Dictionary in _spots:
		var p: Vector3 = s["pos"]
		var g := Vector2(p.x, p.z).rotated(_rot)
		if g.x + g.y < -0.05:
			continue  # on the far side of the body
		var at := Iso.to_screen(g, p.y + lift_m)
		var c: Color = s["color"]
		var r: float = s["radius"]
		_glow.draw_circle(at, r * 2.2, Color(c.r, c.g, c.b, 0.18))
		_glow.draw_circle(at, r, c)


static func _unlit_material() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return m
