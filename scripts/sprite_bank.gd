class_name SpriteBank
extends RefCounted
## Loads the pre-rendered sprites of A01 from res://assets/sprites/manifest.json:
## assets/sprites/<name>/<anim>_<dir>_<frame>.png (+ _n.png normal map, optional _e.png emissive).
## An asset missing from the manifest, or whose first frame is missing, means "no sprites": the caller uses a
## stand-in. The reader accepts a few spellings of each key so small format details do not need code changes.

const MANIFEST := "res://assets/sprites/manifest.json"
const ROOT := "res://assets/sprites"

var px_per_m := 64.0
## name -> {origin: Vector2, dirs: int, anims: {anim: {frames, fps, loop}}, lift_m: float, lights: {name: Vector3}}
var _assets: Dictionary = {}
var _cache: Dictionary = {}  ## "name/anim_dir_frame" -> {tex: CanvasTexture, emissive: Texture2D or null}
var _root := ROOT


func _init(path := MANIFEST) -> void:
	_root = path.get_base_dir()
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_warning("sprite manifest is not a JSON object: " + path)
		return
	var root: Dictionary = data
	px_per_m = float(root.get("px_per_m", 64.0))
	var list: Variant = root.get("assets", root)
	if list is Array:
		for entry: Variant in list:
			if entry is Dictionary and entry.has("name"):
				_add(str(entry["name"]), entry)
	elif list is Dictionary:
		for key: Variant in list:
			if list[key] is Dictionary and (list[key].has("anims") or list[key].has("animations")):
				_add(str(key), list[key])


func has(asset: String) -> bool:
	return _assets.has(asset)


func names() -> Array:
	return _assets.keys()


## Ground-origin pixel inside the image.
func origin(asset: String) -> Vector2:
	return _assets[asset]["origin"]


func dirs(asset: String) -> int:
	return _assets[asset]["dirs"]


func fps(asset: String, anim: String) -> float:
	return float(_assets[asset]["anims"].get(anim, {}).get("fps", 12.0))


func loops(asset: String, anim: String) -> bool:
	return bool(_assets[asset]["anims"].get(anim, {}).get("loop", true))


## Extra lift in metres the presentation adds; A01 renders actors at their height, so callers pass 0.
func lift_m(asset: String, fallback: float) -> float:
	var v: float = _assets[asset]["lift_m"]
	return fallback if v < 0.0 else v


## A light anchor in metres at dir 0 (x, y up, z; glTF axes), or fallback when the manifest has none.
func light_anchor(asset: String, fallback: Vector3) -> Vector3:
	if not has(asset):
		return fallback
	var lights: Dictionary = _assets[asset]["lights"]
	if lights.is_empty():
		return fallback
	return lights.values()[0]


## The anim to play: the wanted one if rendered, else a close substitute, else the first one.
func pick_anim(asset: String, wanted: String) -> String:
	var anims: Dictionary = _assets[asset]["anims"]
	for name: String in [wanted, "hover", "idle", "static"]:
		if anims.has(name):
			return name
	return str(anims.keys()[0])


func frame_count(asset: String, anim: String) -> int:
	return int(_assets[asset]["anims"].get(anim, {}).get("frames", 1))


## {tex: CanvasTexture (colour + normal), emissive: Texture2D or null}, or {} when the file is missing.
func frame(asset: String, anim: String, dir: int, index: int) -> Dictionary:
	var key := "%s/%s_%d_%d" % [asset, anim, dir, index]
	if _cache.has(key):
		return _cache[key]
	var base := "%s/%s/%s_%d_%d" % [_root, asset, anim, dir, index]
	var out := {}
	if ResourceLoader.exists(base + ".png"):
		var tex := CanvasTexture.new()
		tex.diffuse_texture = load(base + ".png")
		if ResourceLoader.exists(base + "_n.png"):
			tex.normal_texture = load(base + "_n.png")
		out["tex"] = tex
		out["emissive"] = load(base + "_e.png") if ResourceLoader.exists(base + "_e.png") else null
	_cache[key] = out
	return out


func _add(asset: String, entry: Dictionary) -> void:
	var anims := {}
	var raw: Variant = entry.get("anims", entry.get("animations", {}))
	if raw is Dictionary:
		for a: Variant in raw:
			anims[str(a)] = _anim_info(raw[a])
	elif raw is Array:
		for v: Variant in raw:
			if v is Dictionary and v.has("name"):
				anims[str(v["name"])] = _anim_info(v)
			else:
				anims[str(v)] = {"frames": 1, "fps": 12.0, "loop": true}
	if anims.is_empty():
		anims["static"] = {"frames": 1, "fps": 1.0, "loop": false}
	var o: Variant = entry.get("origin", entry.get("ground_origin", entry.get("origin_px", null)))
	var origin_px := Vector2.ZERO
	if o is Array and o.size() >= 2:
		origin_px = Vector2(float(o[0]), float(o[1]))
	elif o is Dictionary:
		origin_px = Vector2(float(o.get("x", 0)), float(o.get("y", 0)))
	else:
		push_warning("sprite manifest: %s has no origin; drawing it from its top-left corner" % asset)
	var lights := {}
	var raw_lights: Variant = entry.get("lights", {})
	if raw_lights is Dictionary:
		for k: Variant in raw_lights:
			var v: Variant = raw_lights[k]
			if v is Array and v.size() >= 3:
				lights[str(k)] = Vector3(float(v[0]), float(v[1]), float(v[2]))
	var dirs := int(entry.get("dirs", entry.get("dir_count", entry.get("directions", 1))))
	var first: String = anims.keys()[0]
	var first_png := "%s/%s/%s_0_0.png" % [_root, asset, first]
	if not ResourceLoader.exists(first_png):
		push_warning("sprite manifest: %s lists %s but %s is missing; using the stand-in box" % [asset, first, first_png])
		return
	_assets[asset] = {
		"origin": origin_px,
		"dirs": maxi(dirs, 1),
		"anims": anims,
		"lift_m": float(entry.get("lift_m", -1.0)),
		"lights": lights,
	}


static func _anim_info(v: Variant) -> Dictionary:
	if v is Dictionary:
		return {
			"frames": maxi(int(v.get("frames", v.get("frame_count", 1))), 1),
			"fps": float(v.get("fps", 12.0)),
			"loop": bool(v.get("loop", true)),
		}
	return {"frames": maxi(int(v), 1), "fps": 12.0, "loop": true}
