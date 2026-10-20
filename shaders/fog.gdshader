shader_type canvas_item;
// Drifting ground fog: a screen-sized rect over the ground (under the props) whose noise is pinned to world metres
// and drifts with the wind. Lights brighten it (custom light(): no normals, fog scatters light in every direction).

uniform float sx = 45.254834;          // screen px per metre of (x - z); Iso.SX
uniform float sy = 22.627417;          // screen px per metre of (x + z); Iso.SY
uniform vec3 fog_color : source_color = vec3(0.55, 0.62, 0.75);  // fog albedo before light (dusk grey-blue)
uniform float density = 0.6;           // peak opacity of the thickest patches, 0..1
uniform float scale = 0.12;            // noise frequency per metre (smaller = bigger banks)
uniform vec2 wind = vec2(0.35, 0.12);  // drift in metres per second (x, z)
uniform float light_gain = 2.0;        // how strongly lights glow in the fog, 0..4

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
	for (int k = 0; k < 5; k++) {
		v += a * noise(p);
		p = p * 2.02 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	float d = p.x / sx;
	float s = p.y / sy;
	world = vec2((s + d) * 0.5, (s - d) * 0.5);
}

void fragment() {
	vec2 w = world * scale;
	float n = fbm(w - wind * scale * TIME);
	n = mix(n, fbm(w * 1.7 + wind * scale * TIME * 0.6 + 5.0), 0.4);
	float a = smoothstep(0.32, 0.78, n) * density;
	COLOR = vec4(fog_color, a);
}

void light() {
	LIGHT = vec4(LIGHT_COLOR.rgb * LIGHT_ENERGY * COLOR.rgb * light_gain, LIGHT_COLOR.a);
}
