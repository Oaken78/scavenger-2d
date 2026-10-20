class_name Iso
extends RefCounted
## World (metres: x east, z south, y up) <-> screen (pixels) for the shared camera: orthographic, 30 degrees
## down, yaw 45 degrees, looking from +x+z towards -x-z, 64 px per metre. Same angle as the 3D prototype.

const PX_PER_M := 64.0
const PITCH := deg_to_rad(30.0)
const YAW := deg_to_rad(45.0)
## Screen pixels per world metre along x - z (horizontal) and x + z (vertical); world height lifts by LIFT.
const SX := cos(YAW) * PX_PER_M
const SY := sin(YAW) * sin(PITCH) * PX_PER_M
const LIFT := cos(PITCH) * PX_PER_M


## Ground point (x, z) at height y to screen.
static func to_screen(ground: Vector2, height := 0.0) -> Vector2:
	return Vector2((ground.x - ground.y) * SX, (ground.x + ground.y) * SY - height * LIFT)


## Screen point back to the ground plane (y = 0).
static func to_world(screen: Vector2) -> Vector2:
	var d := screen.x / SX  # x - z
	var s := screen.y / SY  # x + z
	return Vector2((s + d) * 0.5, (s - d) * 0.5)


## Screen direction (unit) of a world heading (radians, 0 = +x, increasing towards +z).
static func heading_to_screen_angle(heading: float) -> float:
	return (to_screen(Vector2.from_angle(heading)) - to_screen(Vector2.ZERO)).angle()


## Linear part of the ground projection: maps a top-down texture (x = world x, y = world z) to the screen.
static func ground_basis(metres_per_px: float) -> Transform2D:
	var bx := to_screen(Vector2(1, 0)) * metres_per_px
	var bz := to_screen(Vector2(0, 1)) * metres_per_px
	return Transform2D(bx, bz, Vector2.ZERO)


## Sprite direction index for a heading, k = heading / (360 / dirs) rounded, wrapped to 0..dirs-1.
static func dir_index(heading: float, dirs: int) -> int:
	if dirs <= 1:
		return 0
	var k := int(round(heading / (TAU / dirs)))
	return posmod(k, dirs)


## World normal (x, y up, z) to the 2D normal-map space: (right, up on screen, towards the viewer).
static func screen_normal(n: Vector3) -> Vector3:
	var right := Vector3(cos(YAW), 0.0, -sin(YAW))
	var up := Vector3(-sin(PITCH) * cos(YAW), cos(PITCH), -sin(PITCH) * sin(YAW))
	var toward := Vector3(cos(PITCH) * cos(YAW), sin(PITCH), cos(PITCH) * sin(YAW))
	return Vector3(n.dot(right), n.dot(up), n.dot(toward)).normalized()
