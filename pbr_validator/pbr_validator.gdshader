shader_type spatial;

render_mode unshaded, fog_disabled;

// --- Validation Mode Control ---
uniform int validation_mode = 0;

// --- Material Data Uniforms ---
uniform vec4 albedo_solid_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
uniform float roughness_value = 1.0;
uniform float metallic_value = 0.0;
uniform sampler2D roughness_texture : hint_default_transparent, filter_linear_mipmap_anisotropic;
uniform sampler2D metallic_texture : hint_default_transparent, filter_linear_mipmap_anisotropic;

// --- Triplanar-specific uniforms ---
uniform bool use_triplanar = false;
uniform vec3 triplanar_scale = vec3(1.0);
uniform float triplanar_sharpness = 0.5;

// v Albedo Validation Uniforms ---
uniform float min_albedo_linear = 0.010;
uniform float max_albedo_linear = 0.946;
uniform float falloff = 0.02;
uniform bool use_hard_edges = false;
uniform vec3 under_color : source_color = vec3(1.0, 0.0, 0.0);
uniform vec3 over_color : source_color = vec3(0.0, 0.0, 1.0);
uniform int in_range_mode = 1;
uniform vec3 in_range_color : source_color = vec3(0.0, 1.0, 0.0);

// --- Roughness Validation Uniforms ---
uniform bool highlight_roughness_extremes = false;
uniform vec3 roughness_extreme_color : source_color = vec3(1.0, 0.0, 1.0);


varying vec3 world_vertex;
varying vec3 world_normal;
varying vec2 uv_varying;

vec4 get_albedo_color() {
	vec4 texture_color;
	if (use_triplanar) {
		vec3 scaled_vertex = world_vertex * triplanar_scale;
		vec3 blend_weights = abs(world_normal);
		blend_weights = pow(blend_weights, vec3(triplanar_sharpness));
		blend_weights = blend_weights / (blend_weights.x + blend_weights.y + blend_weights.z);
		vec4 x_tex = texture(albedo_texture, scaled_vertex.yz);
		vec4 y_tex = texture(albedo_texture, scaled_vertex.xz);
		vec4 z_tex = texture(albedo_texture, scaled_vertex.xy);
		texture_color = x_tex * blend_weights.x + y_tex * blend_weights.y + z_tex * blend_weights.z;
	} else {
		texture_color = texture(albedo_texture, uv_varying);
	}
	return albedo_solid_color * texture_color;
}

void vertex() {
	world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	uv_varying = UV;
}

void fragment() {
	if (validation_mode == 1) { // Albedo Validation
		vec4 final_albedo = get_albedo_color();
		float luminance = dot(final_albedo.rgb, vec3(0.2126, 0.7152, 0.0722));
		vec3 greyscale = vec3(luminance);

		float under_blend;
		float over_blend;

		if (use_hard_edges) {
			under_blend = 1.0 - step(min_albedo_linear, luminance);
			over_blend = step(max_albedo_linear, luminance);
		} else {
			float under_t = max(0.0, min_albedo_linear - falloff);
			under_blend = 1.0 - smoothstep(under_t, min_albedo_linear, luminance);

			float over_t = min(1.0, max_albedo_linear + falloff);
			over_blend = smoothstep(max_albedo_linear, over_t, luminance);
		}

		vec3 base_color = (in_range_mode == 1) ? in_range_color : greyscale;

		vec3 final_color = base_color;
		final_color = mix(final_color, under_color, under_blend);
		final_color = mix(final_color, over_color, over_blend);
		ALBEDO = final_color;

	} else if (validation_mode == 2) { // Roughness
		float final_roughness;
		vec4 rough_tex_val = texture(roughness_texture, uv_varying);
		if (rough_tex_val.a > 0.1) { final_roughness = rough_tex_val.g; }
		else { final_roughness = roughness_value; }

		// --- Roughness Highlighting Logic ---
		if (highlight_roughness_extremes && (final_roughness < 0.01 || final_roughness > 0.99)) {
			ALBEDO = roughness_extreme_color;
		} else {
			ALBEDO = vec3(final_roughness);
		}

	} else if (validation_mode == 3) { // Metallic
		float final_metallic;
		vec4 metal_tex_val = texture(metallic_texture, uv_varying);
		if (metal_tex_val.a > 0.1) { final_metallic = metal_tex_val.b; }
		else { final_metallic = metallic_value; }
		ALBEDO = vec3(final_metallic);

	} else { // Mode 0: Default Unlit Albedo View
		ALBEDO = get_albedo_color().rgb;
	}
}
