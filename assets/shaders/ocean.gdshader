shader_type spatial;
render_mode specular_schlick_ggx, cull_back, shadows_disabled;

// The sea does not take shadows. A ship's shadow across open water is a faint
// thing in life, and on a mesh this large and this flat the shadow map cannot
// hold it: it broke into dark blotches that read as oil slicks, and they were
// invisible from the cutscene's distance but obvious from the ship's own deck.

// Open ocean.
//
// The surface is four Gerstner waves stacked on top of each other. A Gerstner
// wave moves each point of the surface in a small circle rather than just up
// and down, which is what real deep water does and what gives a swell its
// sharp crests and wide flat troughs. Four of them at different sizes and
// angles stop the pattern from reading as a repeating grid.
//
// The normal is worked out from the same maths rather than from a texture, so
// the lighting always agrees with the shape - important here, because the
// camera drops close to the surface during a hit and any disagreement shows.

uniform vec3 deep_color : source_color = vec3(0.035, 0.095, 0.135);
uniform vec3 shallow_color : source_color = vec3(0.085, 0.235, 0.29);
uniform vec3 foam_color : source_color = vec3(0.85, 0.92, 0.95);
uniform float wave_scale = 1.0;
uniform float wave_speed = 1.0;
uniform float roughness_value = 0.06;
uniform float foam_amount = 0.6;
uniform float fade_start = 1600.0;
uniform float fade_end = 3000.0;
uniform sampler2D detail_normal : hint_normal;
uniform float detail_strength = 0.13;
uniform float detail_scale = 0.022;

// The waves themselves live here, because the wake lying on this water has to
// be displaced by exactly the same sum. See gerstner.gdshaderinc.
#include "res://assets/shaders/gerstner.gdshaderinc"

varying vec3 world_pos;
varying float crest;

void vertex() {
	vec3 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;

	float fade = sea_fade(p, CAMERA_POSITION_WORLD, fade_start, fade_end);

	vec3 normal_sum = vec3(0.0);
	vec3 offset = sea_displacement(p, t, wave_scale, wave_speed, fade, normal_sum);

	VERTEX += (inverse(MODEL_MATRIX) * vec4(offset, 0.0)).xyz;
	world_pos = p + offset;
	// Measured against every wave stacked at once, so "1.0" means the rare
	// moment all four crests line up - not merely the top of the big swell.
	// Normalising against one wave instead made most of the sea count as a
	// breaking crest, and the whitecaps came out as continents.
	crest = clamp(offset.y / max(TOTAL_AMPLITUDE * wave_scale, 0.001), -1.0, 1.0);

	NORMAL = normalize(vec3(normal_sum.x, 1.0 + normal_sum.y, normal_sum.z));
}

void fragment() {
	// Ripple far too small to model in the mesh, added to the normal only.
	// Without it the swell is a sheet of moulded glass; real water is never
	// smooth between the waves.
	//
	// It has to be faded out hard with distance. Six-metre ripple seen from a
	// kilometre away is a fraction of a pixel, and what comes back is not
	// ripple but moire - broad warm and dark patches drifting over the sea
	// where the minified normal happens to catch the sun. Beyond half a
	// kilometre the water is left smooth and the swell carries it.
	vec2 drift = vec2(TIME * 0.012, TIME * -0.008);
	vec3 ripple = texture(detail_normal, world_pos.xz * detail_scale + drift).xyz * 2.0 - 1.0;
	vec3 ripple2 = texture(detail_normal, world_pos.xz * detail_scale * 2.7 - drift * 1.6).xyz * 2.0 - 1.0;
	float close = 1.0 - smoothstep(40.0, 380.0, length(world_pos - CAMERA_POSITION_WORLD));
	NORMAL = normalize(NORMAL + vec3(ripple.x + ripple2.x * 0.5, 0.0, ripple.y + ripple2.y * 0.5)
		* detail_strength * close);

	vec3 view = normalize(world_pos - CAMERA_POSITION_WORLD);
	float facing = clamp(dot(-view, normalize(NORMAL * mat3(VIEW_MATRIX))), 0.0, 1.0);

	// Water seen edge-on reflects the sky; water seen from above shows its
	// own colour. That is the whole reason a calm sea is bright at the
	// horizon and dark underfoot.
	float fresnel = pow(1.0 - facing, 4.0);
	// Only the deepest troughs go dark. Reaching the deep colour as early as
	// crest -0.4 turned every trough near-black, and from a bridge twenty-four
	// metres up - where you are looking down at troughs rather than across at
	// crests - the sea came out as drifting black blotches.
	vec3 body = mix(deep_color, shallow_color, smoothstep(-0.95, 0.85, crest));

	// Whitecaps only where the water is genuinely breaking, and broken up by
	// the ripple noise so they scatter instead of lying in smooth bands.
	// The whitecap speckle samples the same noise, so it aliases the same way;
	// far off, the foam is left to the crest alone.
	float speckle = texture(detail_normal, world_pos.xz * detail_scale * 1.3).z;
	float scatter = mix(1.0, smoothstep(0.35, 0.8, speckle), close);
	float foam = smoothstep(0.72, 0.99, crest) * foam_amount * scatter;

	ALBEDO = mix(body, foam_color, foam);
	ROUGHNESS = mix(roughness_value, 0.55, foam);
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 0.2, foam);
	RIM = fresnel * 0.5;
}
