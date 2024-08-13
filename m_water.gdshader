shader_type spatial;
render_mode cull_disabled;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_nearest;

group_uniforms surface;
uniform vec4 surface_color: source_color = vec4(0.0, 0.378625, 0.71875, 1.0); // #0061B7
uniform vec4 fresnel_color: source_color = vec4(0.71875, 0.159227, 0.274512, 1.0); // #B72946
uniform sampler2D surface_noise_01; // FastNoiseLite { normalize: inactive, seamless: active, type: cellular, frequency: 0.05, fractal: none, cellular: euclidian squared }
uniform sampler2D surface_noise_02; // FastNoiseLite { normalize: inactive, seamless: active, type: cellular, frequency: 0.05, fractal: none, cellular: euclidian squared }

group_uniforms wave;
uniform sampler2D wave_noise; // FastNoiseLite { seamless: active, type: cellular, fractal: none, cellular: euclidian squared }
uniform vec2 wave_direction_01 = vec2(1.0, 1.0);
uniform vec2 wave_direction_02 = vec2(-1.0, -1.0);
uniform float time_scale : hint_range(0.0, 0.2, 0.005) = 0.025; // Rate of movement multiplied by TIME
uniform float wave_noise_scale: hint_range(1.0, 20.0) = 10.0;
uniform float wave_height_scale: hint_range(0.0, 1.0) = 0.15;

group_uniforms edge;
uniform vec3 edge_color : source_color = vec3(1,1,1);
uniform float proximity_fade_distance: hint_range(0.0, .5) = 0.2;
uniform float edge_intensity: hint_range(1.0, 10.0) = 8.0;
uniform float edge_count: hint_range(1.0, 4.0, 1.0) = 4.0;

group_uniforms depth;
uniform float depth_fade_distance : hint_range(0.0, 10.0) = 1.0;
uniform float absorbance : hint_range(1.0, 10.0) = 2.0;
uniform float shallow_color_intensity : hint_range(0.0, 3.0, 0.01) = .3;
uniform float deep_color_intensity : hint_range(0.0, 3.0, 0.01) = 1.033;


// Varying variables
varying float wave_height;
varying vec3 wave_world_position;

float fresnel(float amount, vec3 normal, vec3 view) {
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0 )), amount);
}

void vertex() {
	wave_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wave_height = texture(wave_noise, wave_world_position.xz / wave_noise_scale + TIME * time_scale).r;
	VERTEX.y += wave_height * wave_height_scale;
}

void fragment() {

	// Wave
	vec2 time_01 = (TIME * wave_direction_01) * time_scale; // Movement rate of first wave
	vec2 time_02 = (TIME * wave_direction_02) * time_scale; // Movement rate of second wave
	vec3 normal_blend = mix(texture(surface_noise_01, UV + time_01).rgb, texture(surface_noise_02, UV + time_02).rgb, 0.5).rgb;

	// fresnel
	float fresnel = fresnel(5.0, NORMAL, VIEW);
	vec4 albedo = mix(surface_color, fresnel_color, fresnel);

	// noise
	vec4 noise = texture(surface_noise_01, UV + time_01) * texture(surface_noise_02, UV + time_02);
	noise = pow(noise, vec4(1.25));
	albedo += noise;

	// Depth texture magic
	float depth = texture(DEPTH_TEXTURE, SCREEN_UV, 0.0).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float depth_texture_y = world.y / world.w;
	float vertex_y = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
	float vertical_depth = vertex_y - depth_texture_y;

	// Changes the color of geometry behind it as the water gets deeper
	float depth_fade_blend = exp(-vertical_depth / depth_fade_distance);
	depth_fade_blend = clamp(depth_fade_blend, 0.0, 1.0);

	// Makes the water more transparent as it gets more shallow
	float alpha_blend = -vertical_depth * absorbance;
	alpha_blend = clamp(1.0 - exp(alpha_blend), 0.0, 1.0);
	vec3 deep_color = (surface_color * deep_color_intensity).rgb;
	vec3 shallow_color = (surface_color * shallow_color_intensity).rgb;
	vec3 water_volume_color = mix(deep_color, shallow_color, depth_fade_blend);

	// Detect edge magic with depth texture magic
	float proximity_fade;
	float depth_edges = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec4 edges_depth_world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_edges, 1.0);
	edges_depth_world.xyz /= edges_depth_world.w;
	proximity_fade = clamp(1.0 - smoothstep(edges_depth_world.z + proximity_fade_distance, edges_depth_world.z, VERTEX.z), 0.0, 1.0);
	float oneMinus_proximity_fade = 1.0 - proximity_fade;

	float edges_wave = fma(TIME, time_scale, oneMinus_proximity_fade);
	float edges_weight = edges_wave + oneMinus_proximity_fade;

	float edges_proximity_intensity = pow(oneMinus_proximity_fade, edge_intensity);
	edges_weight = (abs(sin(edges_weight * edge_count)) * oneMinus_proximity_fade) + edges_proximity_intensity;

	vec3 depth_albedo = mix(albedo.rgb, water_volume_color.rbg, .5);
	vec3 proximity_fade_albedo = mix(depth_albedo.rbg, edge_color, vec3(edges_weight));
	ALBEDO = proximity_fade_albedo;
	ALPHA = alpha_blend;
	NORMAL_MAP = normal_blend;
}
