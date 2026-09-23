// The shape of the open sea, in one place.
//
// Two things have to be displaced by exactly the same sum: the water, and the
// wake of foam lying on it. If they are computed separately they drift, and a
// wake that drifts does not look slightly wrong - it is cut in half by every
// crest that rises above it, or it floats a clear two metres over the troughs.
// Keeping the waves here, included by both shaders, is what makes them the
// same sea as a fact rather than as something to remember.
//
// The surface is four Gerstner waves stacked on top of each other. A Gerstner
// wave moves each point of the surface in a small circle rather than just up
// and down, which is what real deep water does and what gives a swell its
// sharp crests and wide flat troughs. Four of them at different sizes and
// angles stop the pattern from reading as a repeating grid.

// direction.xy, amplitude, wavelength.
//
// One unit is one metre. Open ocean swell runs roughly sixty times longer than
// it is tall, so these keep that ratio; the earlier set was three times too
// steep and the sea read as a gale in every shot.
//
// The shortest wave also has to stay several mesh quads wide. Below about
// three quads per wavelength the surface cannot hold the shape, and instead of
// small waves you get a crumpled-foil pattern that crawls as the camera moves.
// That is what sets the floor on WAVE_D.
const vec4 WAVE_A = vec4(1.0, 0.25, 0.95, 92.0);
const vec4 WAVE_B = vec4(0.72, -0.68, 0.52, 57.0);
const vec4 WAVE_C = vec4(-0.45, 0.89, 0.26, 34.0);
const vec4 WAVE_D = vec4(0.94, 0.33, 0.11, 20.0);
const vec4 STEEP = vec4(0.85, 0.75, 0.65, 0.55);
const float TOTAL_AMPLITUDE = 1.84;

// One wave. Returns the offset it applies to this point and accumulates its
// contribution to the surface normal.
//
// The horizontal part of a Gerstner wave must stay tied to its own amplitude:
// steepness * amplitude, never steepness / wavenumber. Divide by the
// wavenumber and a short wave gets a sideways push far larger than its own
// height, the surface folds through itself, and a calm sea renders as broken
// glass. Ask for shorter waves and it gets worse, which is exactly how this
// was found.
vec3 gerstner(
		vec4 wave, float steepness, float fade, vec3 p, float t,
		float scale, float speed_scale, inout vec3 normal_sum) {
	vec2 dir = normalize(wave.xy);
	float amplitude = wave.z * scale * fade;
	float wavelength = wave.w * scale;
	float k = 6.28318 / wavelength;
	float speed = sqrt(9.81 / k) * speed_scale;
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

// The whole sea at one point: how far the surface moves there, with the normal
// accumulated into `normal_sum`.
vec3 sea_displacement(
		vec3 p, float t, float scale, float speed_scale, float fade,
		inout vec3 normal_sum) {
	vec3 offset = vec3(0.0);
	offset += gerstner(WAVE_A, STEEP.x, fade, p, t, scale, speed_scale, normal_sum);
	offset += gerstner(WAVE_B, STEEP.y, fade, p, t, scale, speed_scale, normal_sum);
	offset += gerstner(WAVE_C, STEEP.z, fade, p, t, scale, speed_scale, normal_sum);
	offset += gerstner(WAVE_D, STEEP.w, fade, p, t, scale, speed_scale, normal_sum);
	return offset;
}

// How much of the swell is drawn at this point. Far out the mesh is too coarse
// to hold a wave and it turns to noise, so the waves themselves are flattened
// by distance rather than the finished offset being scaled down - flatten one
// and not the other and the lighting comes apart.
// The parameters are deliberately not called fade_start and fade_end: both
// shaders that include this have uniforms by those names, and a parameter is
// not allowed to shadow a uniform - it fails to compile with "redefinition of
// 'fade_start'", pointing here rather than at the uniform it collided with.
float sea_fade(vec3 p, vec3 camera, float begins, float ends) {
	return 1.0 - smoothstep(begins, ends, length(p.xz - camera.xz));
}
