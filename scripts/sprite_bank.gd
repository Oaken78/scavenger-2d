class_name SpriteBank
extends RefCounted
## Loads the pre-rendered sprites of A01 from res://assets/sprites/manifest.json:
## assets/sprites/<name>/<anim>_<dir>_<frame>.png (+ _n.png normal map, optional _e.png emissive).
## An asset missing from the manifest (or the whole manifest) means "no sprites": the caller uses a stand-in.
## The manifest reader accepts a few spellings of each key so small format details do not need code changes.

const MANIFEST := "res://assets/sprites/manifest.json"
const ROOT := "res://assets/sprites"

var px_per_m := 64.0
var _assets: Dictionary = {}  ## name -> {origin: Vector2, dirs: int, anims: {anim: frames}, fps: float, lift_m: float}
var _cache: Dictionary = {}  ## "name/anim_dir_frame" -> {tex: CanvasTexture, emissive: Texture2D or null}


func _init(path := MANIFEST) -> void:
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
			if list[key] is Dictionary:
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


func fps(asset: String) -> float:
	return _assets[asset]["fps"]


## Extra lift in metres the presentation adds; A01 renders actors at their height, so callers pass 0.
func lift_m(asset: String, fallback: float) -> float:
	var v: float = _assets[asset]["lift_m"]
	return fallback if v < 0.0 else v


## The anim to play: the wanted one if rendered, else a close substitute, else the first one.
func pick_anim(asset: String, wanted: String) -> String:
	var anims: Dictionary = _assets[asset]["anims"]
	for name: String in [wanted, "hover", "idle", "static"]:
		if anims.has(name):
			return name
	return str(anims.keys()[0])


func frame_count(asset: String, anim: String) -> int:
	return int(_assets[asset]["anims"].get(anim, 1))


## {tex: CanvasTexture (colour + normal), emissive: Texture2D or null}, or {} when the file is missing.
func frame(asset: String, anim: String, dir: int, index: int) -> Dictionary:
	var key := "%s/%s_%d_%d" % [asset, anim, dir, index]
	if _cache.has(key):
		return _cache[key]
	var base := "%s/%s/%s_%d_%d" % [ROOT, asset, anim, dir, index]
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
			var v: Variant = raw[a]
			if v is Dictionary:
				anims[str(a)] = int(v.get("frames", v.get("frame_count", 1)))
			else:
				anims[str(a)] = int(v)
	elif raw is Array:
		for v: Variant in raw:
			if v is Dictionary and v.has("name"):
				anims[str(v["name"])] = int(v.get("frames", v.get("frame_count", 1)))
			else:
				anims[str(v)] = 1
	if anims.is_empty():
		anims["static"] = 1
	var o: Variant = entry.get("origin", entry.get("ground_origin", entry.get("origin_px", [0, 0])))
	var origin_px := Vector2.ZERO
	if o is Array and o.size() >= 2:
		origin_px = Vector2(float(o[0]), float(o[1]))
	elif o is Dictionary:
		origin_px = Vector2(float(o.get("x", 0)), float(o.get("y", 0)))
	_assets[asset] = {
		"origin": origin_px,
		"dirs": int(entry.get("dirs", entry.get("dir_count", entry.get("directions", 1)))),
		"anims": anims,
		"fps": float(entry.get("fps", 12.0)),
		"lift_m": float(entry.get("lift_m", -1.0)),
	}
