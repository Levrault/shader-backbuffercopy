shader_type spatial;
render_mode cull_disabled, unshaded;

uniform sampler2D SCREEN_TEXTURE : source_color, hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D DEPTH_TEXTURE : source_color, hint_depth_texture;

uniform vec3 fog_color : source_color;
uniform float fog_distance : hint_range(1, 200);

vec3 color_mix(vec3 a, vec3 b, float f ) {
	f = clamp(abs(f), 0,1);
	float invf = 1.0 - f;
	return (a*f) + (b*invf);
}

void vertex() {
  POSITION = vec4(VERTEX, 1.0);
}

void fragment() {
	vec3 screen_color = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;
	float depth = texture(DEPTH_TEXTURE, SCREEN_UV).x;
	
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	
	float linear_depth = -view.z;
	float depth_mask_inv = linear_depth / fog_distance;
	
	ALBEDO = color_mix(fog_color, screen_color, depth_mask_inv);
}