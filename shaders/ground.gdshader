shader_type canvas_item;
// Ground of the street, drawn as one big polygon in screen space under everything. Each pixel is mapped back to
// world metres (inverse iso projection) so the cracked asphalt road, grass and moss stay fixed to the world.
// Writes a normal map (2D convention: r = right, g = up on screen, b = towards viewer) so lights rake the cracks.

uniform float sx = 45.254834;          // screen px per metre of (x - z); Iso.SX
uniform float sy = 22.627417;          // screen px per metre of (x + z); Iso.SY
uniform float road_z = 0.0;            // world z of the road's centre line (metres)
uniform float road_half_width = 4.0;   // half the road width (metres)
uniform vec3 asphalt_color : source_color = vec3(0.30, 0.30, 0.32);   // dry asphalt
uniform vec3 crack_color : source_color = vec3(0.10, 0.11, 0.10);     // dark cracks and wet patches
uniform vec3 grass_color : source_color = vec3(0.24, 0.34, 0.16);     // overgrown grass
uniform vec3 moss_color : source_color = vec3(0.16, 0.28, 0.14);      // moss patches
uniform vec3 dirt_color : source_color = vec3(0.31, 0.26, 0.19);      // trodden earth at the road edge
uniform vec3 line_color : source_color = vec3(0.62, 0.58, 0.42);      // faded centre line paint
uniform float bump_strength = 0.6;     // how hard the noise tilts the normal (0 = flat ground)

varying vec2 world;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// Thin dark lines where a warped noise crosses 0.5: cheap crack network.
float cracks(vec2 p) {
	float n = fbm(p * 0.45 + fbm(p * 0.9) * 1.5);
	return 1.0 - smoothstep(0.0, 0.035, abs(n - 0.5));
}

float height_at(vec2 w) {
	float on_road = 1.0 - smoothstep(road_half_width - 0.4, road_half_width + 0.6, abs(w.y - road_z));
	float grass_h = fbm(w * 3.0) * 0.6 + fbm(w * 0.7) * 0.4;
	float road_h = 0.5 - cracks(w) * 0.5 + noise(w * 6.0) * 0.08;
	return mix(grass_h, road_h, on_road);
}

void vertex() {
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	float d = p.x / sx;
	float s = p.y / sy;
	world = vec2((s + d) * 0.5, (s - d) * 0.5);
}

void fragment() {
	vec2 w = world;
	float dist_road = abs(w.y - road_z);
	float edge = fbm(w * 0.8) * 0.9;
	float on_road = 1.0 - smoothstep(road_half_width - 0.3 - edge, road_half_width + 0.2 - edge, dist_road);
	// Road: asphalt with patches, cracks and a broken centre line.
	float patch = fbm(w * 0.35);
	vec3 road = mix(asphalt_color * 0.8, asphalt_color * 1.1, patch);
	road = mix(road, crack_color, smoothstep(0.62, 0.8, fbm(w * 0.5 + 7.0)) * 0.6);  // wet dark patches
	float dash = step(0.5, fract(w.x * 0.25)) * (1.0 - smoothstep(0.06, 0.1, abs(w.y - road_z)));
	road = mix(road, line_color, dash * smoothstep(0.35, 0.6, fbm(w * 2.0)) * 0.8);
	float cr = cracks(w);
	road = mix(road, moss_color * 0.8, cr * smoothstep(0.4, 0.7, fbm(w * 1.3 + 3.0)));  // moss in the cracks
	road = mix(road, crack_color, cr * 0.85);
	// Off road: grass, moss and dirt near the road edge.
	float g = fbm(w * 0.6 + 11.0);
	vec3 grass = mix(grass_color, moss_color, smoothstep(0.4, 0.65, g));
	grass *= 0.8 + 0.35 * noise(w * 9.0);
	grass = mix(grass, dirt_color, (1.0 - smoothstep(0.0, 1.6, dist_road - road_half_width)) * 0.7);
	COLOR = vec4(mix(grass, road, on_road), 1.0);
	// Normal from the height field, tilted onto the ground plane as seen by the camera.
	float e = 0.06;
	float h0 = height_at(w);
	float hx = height_at(w + vec2(e, 0.0)) - h0;
	float hz = height_at(w + vec2(0.0, e)) - h0;
	vec3 n_world = normalize(vec3(-hx * bump_strength / e * 0.1, 1.0, -hz * bump_strength / e * 0.1));
	// world -> screen normal (right, up, towards viewer) for the 30 degree pitch, 45 degree yaw camera
	vec3 right = vec3(0.70710678, 0.0, -0.70710678);
	vec3 up = vec3(-0.35355339, 0.8660254, -0.35355339);
	vec3 toward = vec3(0.61237244, 0.5, 0.61237244);
	vec3 n = normalize(vec3(dot(n_world, right), dot(n_world, up), dot(n_world, toward)));
	NORMAL_MAP = n * 0.5 + 0.5;
}
