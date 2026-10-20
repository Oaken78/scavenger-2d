class_name IsoBox
extends Node2D
## Stand-in for a missing sprite: a flat-shaded box of the asset's footprint and height, drawn in the iso
## projection. Each face carries a 1x1 normal map of its real normal, so 2D lights shade it like a 3D box.

static var _face_textures: Dictionary = {}  ## quantized normal -> CanvasTexture

@export var size := Vector2(1, 1)  ## footprint x, z in metres
@export var height := 1.0  ## metres
@export var lift := 0.0  ## metres above the ground (hovering drones)
@export var color := Color(0.5, 0.5, 0.5)
@export var rot := 0.0:  ## radians about +y (same sense as the sim heading)
	set(value):
		if not is_equal_approx(value, rot):
			rot = value
			queue_redraw()


func _draw() -> void:
	var half := size * 0.5
	var corners: Array[Vector2] = []
	for c: Vector2 in [Vector2(half.x, half.y), Vector2(-half.x, half.y), Vector2(-half.x, -half.y), Vector2(half.x, -half.y)]:
		corners.append(c.rotated(rot))
	# Side faces whose outward normal points towards the viewer (+x+z), then the top.
	for i in 4:
		var a := corners[i]
		var b := corners[(i + 1) % 4]
		var mid := (a + b) * 0.5
		if mid.x + mid.y <= 0.0:
			continue
		var n := Vector3(mid.x, 0.0, mid.y).normalized()
		var pts := PackedVector2Array([
			Iso.to_screen(a, lift), Iso.to_screen(b, lift),
			Iso.to_screen(b, lift + height), Iso.to_screen(a, lift + height),
		])
		_face(pts, n, 0.82)
	var top := PackedVector2Array()
	for c in corners:
		top.append(Iso.to_screen(c, lift + height))
	_face(top, Vector3.UP, 1.0)


func _face(pts: PackedVector2Array, normal: Vector3, shade: float) -> void:
	var c := Color(color.r * shade, color.g * shade, color.b * shade, color.a)
	var uvs := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	draw_colored_polygon(pts, c, uvs, face_texture(normal))


## A 1x1 white texture with a 1x1 normal map (Godot 2D convention: red = right, green = up on screen).
static func face_texture(world_normal: Vector3) -> CanvasTexture:
	var n := Iso.screen_normal(world_normal)
	var key := Vector3i(roundi(n.x * 32.0), roundi(n.y * 32.0), roundi(n.z * 32.0))
	if _face_textures.has(key):
		return _face_textures[key]
	var white := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	var nimg := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	nimg.fill(Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	var tex := CanvasTexture.new()
	tex.diffuse_texture = ImageTexture.create_from_image(white)
	tex.normal_texture = ImageTexture.create_from_image(nimg)
	_face_textures[key] = tex
	return tex
