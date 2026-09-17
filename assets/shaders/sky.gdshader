shader_type sky;

// Weather over the battle.
//
// An empty gradient sky reads as a test scene no matter how good the water is,
// because there is nothing up there for the eye to measure distance against.
// These are cheap layered-noise clouds - two sheets at different heights and
// speeds, lit from the sun's side so the camera tilting up during a sinking
// finds something worth looking at.

uniform vec3 top_color : source_color = vec3(0.13, 0.26, 0.45);
uniform vec3 horizon_color : source_color = vec3(0.66, 0.72, 0.78);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.97, 0.92);
uniform vec3 cloud_shadow : source_color = vec3(0.42, 0.45, 0.52);
uniform float coverage = 0.46;
uniform float wind = 0.004;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
		f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 6; i++) {
		value += amplitude * noise(p);
		p *= 2.03;
		amplitude *= 0.5;
	}
	return value;
}

// One sheet of cloud, flattened onto the sky dome. Dividing by the height of
// the ray is what makes a flat layer look like it runs away to the horizon.
float layer(vec3 dir, float height, float scale, float speed, float thickness) {
	if (dir.y <= 0.002) {
		return 0.0;
	}
	vec2 p = dir.xz / dir.y * height * scale + vec2(TIME * speed, TIME * speed * 0.35);
	float d = fbm(p);
	float mass = smoothstep(coverage, coverage + thickness, d);
	// Fade them out near the horizon so the layer does not end in a hard line.
	return mass * smoothstep(0.0, 0.16, dir.y);
}

void sky() {
	vec3 dir = EYEDIR;
	float up = clamp(dir.y, 0.0, 1.0);
	vec3 sky_color = mix(horizon_color, top_color, pow(up, 0.55));

	float high = layer(dir, 1.0, 0.85, wind * 0.6, 0.30);
	float low = layer(dir, 0.55, 1.9, wind, 0.38);
	float mass = clamp(high * 0.55 + low, 0.0, 1.0);

	// Light the cloud from whichever side the sun is on, so the shading in the
	// sky agrees with the shading on the ship.
	float toward_sun = clamp(dot(dir, LIGHT0_DIRECTION * -1.0), 0.0, 1.0);
	vec3 cloud = mix(cloud_shadow, cloud_lit, pow(toward_sun, 1.6) * 0.75 + 0.25);
	cloud += LIGHT0_COLOR * pow(toward_sun, 18.0) * 0.5;

	COLOR = mix(sky_color, cloud, mass * 0.92);
}
