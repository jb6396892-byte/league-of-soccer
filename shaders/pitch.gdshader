shader_type spatial;
render_mode diffuse_burley;
varying vec3 field_position;
void vertex() { field_position = VERTEX; }
void fragment() {
	float stripe = step(0.5, fract((field_position.x + 48.0) / 16.0));
	float grain = fract(sin(dot(field_position.xz * 90.0, vec2(12.9898, 78.233))) * 43758.5453);
	vec3 grass = mix(vec3(0.045, 0.115, 0.042), vec3(0.060, 0.150, 0.052), stripe);
	ALBEDO = grass + (grain - 0.5) * 0.012;
	ROUGHNESS = 0.95;
}
