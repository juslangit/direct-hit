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

// direction.xy, amplitude, wavelength.
//
// One unit is one metre. Open
// ocean swell runs roughly sixty times longer than it is tall, so these keep
// that ratio; the earlier set was three times too steep and the sea read as a
// gale in every shot.
//
// The shortest wave also has to stay several mesh quads wide. Below about
// three quads per wavelength the surface cannot hold the shape, and instead
// of small waves you get a crumpled-foil pattern that crawls as the camera
// moves. That is what sets the floor on WAVE_D.
const vec4 WAVE_A = vec4(1.0, 0.25, 0.95, 92.0);
const vec4 WAVE_B = vec4(0.72, -0.68, 0.52, 57.0);
const vec4 WAVE_C = vec4(-0.45, 0.89, 0.26, 34.0);
const vec4 WAVE_D = vec4(0.94, 0.33, 0.11, 20.0);
const vec4 STEEP = vec4(0.85, 0.75, 0.65, 0.55);
const float TOTAL_AMPLITUDE = 1.84;

varying vec3 world_pos;
varying float crest;

// One wave. Returns the offset it applies to this point and accumulates its
// contribution to the surface normal.
//
// The horizontal part of a Gerstner wave must stay tied to its own amplitude:
// steepness * amplitude, never steepness / wavenumber. Divide by the
// wavenumber and a short wave gets a sideways push far larger than its own
// height, the surface folds through itself, and a calm sea renders as broken
// glass. Ask for shorter waves and it gets worse, which is exactly how this
// was found.
vec3 gerstner(vec4 wave, float steepness, float fade, vec3 p, float t, inout vec3 normal_sum) {
	vec2 dir = normalize(wave.xy);
	float amplitude = wave.z * wave_scale * fade;
	float wavelength = wave.w * wave_scale;
	float k = 6.28318 / wavelength;
	float speed = sqrt(9.81 / k) * wave_speed;
	float phase = k * (dot(dir, p.xz) - speed * t);

	float c = cos(phase);
	float s = sin(phase);
	float ka = k * amplitude;

	normal_sum += vec3(
		-dir.x * ka * c,
		-steepness * ka * s,
		-dir.y * ka * c
	);
	return vec3(
		dir.x * steepness * amplitude * c,
		amplitude * s,
		dir.y * steepness * amplitude * c
	);
}

void vertex() {
	vec3 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;

	// Far out, the mesh is too coarse to hold a wave and it turns to noise.
	// The waves are flattened by distance rather than the finished offset
	// being scaled down, so the normal always describes the shape actually
	// drawn - flatten one and not the other and the lighting comes apart.
	float fade = 1.0 - smoothstep(fade_start, fade_end, length(p.xz - CAMERA_POSITION_WORLD.xz));

	vec3 normal_sum = vec3(0.0);
	vec3 offset = vec3(0.0);
	offset += gerstner(WAVE_A, STEEP.x, fade, p, t, normal_sum);
	offset += gerstner(WAVE_B, STEEP.y, fade, p, t, normal_sum);
	offset += gerstner(WAVE_C, STEEP.z, fade, p, t, normal_sum);
	offset += gerstner(WAVE_D, STEEP.w, fade, p, t, normal_sum);

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
