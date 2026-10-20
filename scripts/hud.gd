class_name Hud
extends CanvasLayer
## Fuel bar, outcome message, control hint and the F3 stats line (frame time, FPS, draw calls).

@export var bar_size := Vector2(260, 18)
@export var fuel_color := Color(0.95, 0.68, 0.22)
@export var low_fuel_color := Color(0.95, 0.25, 0.18)
@export var low_fuel_ratio := 0.25

var _bar: ProgressBar
var _fill: StyleBoxFlat
var _fuel_label: Label
var _message: Label
var _hint: Label
var _stats: Label
var _frame_ms := 16.7


func _ready() -> void:
	layer = 10
	var label := Label.new()
	label.text = "FUEL"
	label.position = Vector2(24, 18)
	_style_label(label, 16)
	add_child(label)
	_bar = ProgressBar.new()
	_bar.position = Vector2(76, 20)
	_bar.size = bar_size
	_bar.show_percentage = false
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.06, 0.09, 0.75)
	bg.border_color = Color(0.6, 0.6, 0.65, 0.6)
	bg.set_border_width_all(1)
	_fill = StyleBoxFlat.new()
	_fill.bg_color = fuel_color
	_bar.add_theme_stylebox_override("background", bg)
	_bar.add_theme_stylebox_override("fill", _fill)
	add_child(_bar)
	_fuel_label = Label.new()
	_fuel_label.position = Vector2(76 + bar_size.x + 10, 18)
	_style_label(_fuel_label, 16)
	add_child(_fuel_label)
	_message = Label.new()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.anchor_left = 0.0
	_message.anchor_right = 1.0
	_message.offset_left = 0
	_message.offset_right = 0
	_message.offset_top = 120
	_style_label(_message, 34)
	add_child(_message)
	_hint = Label.new()
	_hint.text = "Left click: walk / attack a drone    F: fog    F3: stats    R: restart"
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = 24
	_hint.offset_top = -40
	_style_label(_hint, 15)
	_hint.modulate = Color(1, 1, 1, 0.75)
	add_child(_hint)
	_stats = Label.new()
	_stats.anchor_left = 1.0
	_stats.anchor_right = 1.0
	_stats.offset_left = -330
	_stats.offset_top = 18
	_stats.visible = false
	_style_label(_stats, 15)
	add_child(_stats)


func _process(delta: float) -> void:
	_frame_ms = lerpf(_frame_ms, delta * 1000.0, 0.1)
	if _stats.visible:
		_stats.text = "frame %.2f ms   FPS %d   draw calls %d" % [
			_frame_ms,
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		]


func set_fuel(fuel: float, fuel_max: float) -> void:
	_bar.max_value = fuel_max
	_bar.value = fuel
	_fill.bg_color = low_fuel_color if fuel < fuel_max * low_fuel_ratio else fuel_color
	_fuel_label.text = "%d" % int(ceil(fuel))


func set_message(text: String) -> void:
	_message.text = text


func toggle_stats() -> void:
	_stats.visible = not _stats.visible


func stats_visible() -> bool:
	return _stats.visible


func _style_label(l: Label, font_size: int) -> void:
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
