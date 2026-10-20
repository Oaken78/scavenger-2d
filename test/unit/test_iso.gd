extends GutTest
## Unit tests for scripts/iso.gd and the sprite manifest reader: one behaviour per test, the name states the rule.


func test_projection_and_inverse_agree() -> void:
	for p: Vector2 in [Vector2.ZERO, Vector2(3, 2), Vector2(-17.5, 12.25), Vector2(20, -20)]:
		var back := Iso.to_world(Iso.to_screen(p))
		assert_almost_eq(back.x, p.x, 0.0001)
		assert_almost_eq(back.y, p.y, 0.0001)


func test_further_from_the_camera_is_higher_on_screen() -> void:
	# The camera looks from +x+z, so -x-z is further away, which is up on screen (smaller y).
	assert_lt(Iso.to_screen(Vector2(-1, -1)).y, Iso.to_screen(Vector2(1, 1)).y)


func test_height_lifts_up_on_screen() -> void:
	assert_lt(Iso.to_screen(Vector2(2, 3), 1.0).y, Iso.to_screen(Vector2(2, 3)).y)
	assert_eq(Iso.to_screen(Vector2(2, 3), 1.0).x, Iso.to_screen(Vector2(2, 3)).x)


func test_dir_index_wraps_headings_to_eight_directions() -> void:
	assert_eq(Iso.dir_index(0.0, 8), 0)
	assert_eq(Iso.dir_index(PI * 0.5, 8), 2)
	assert_eq(Iso.dir_index(-PI * 0.25, 8), 7)
	assert_eq(Iso.dir_index(TAU, 8), 0)


func test_missing_manifest_means_no_sprites() -> void:
	var bank := SpriteBank.new("res://does/not/exist.json")
	assert_false(bank.has("robot"))
