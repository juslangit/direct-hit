shader_type spatial;
render_mode blend_mix, cull_back, unshaded, depth_draw_never, shadows_disabled;

// Foam lying on the sea.
//
// The geometry is a flat strip built in wake.gd; all this does is put it on the
// water and give it a pattern. Putting it on the water is the whole job: the
// strip arrives flat, and it is displaced here by the same four Gerstner waves
// the sea itself is displaced by, from the same include, so the foam rides the
// swell instead of being sliced by it.
//
// Unshaded, because a horizontal white sheet lit as a solid takes the afternoon
// sun full on and comes out brighter than anything else in the picture. It
// writes no depth - it never has to occlude anything, and not writing keeps it
// from fighting the water for the same pixels - but it still tests, so a crest
// passing in front of the foam hides it, which is where foam collects anyway.

#include "res://assets/shaders/gerstner.gdshaderinc"

uniform vec4 tint : source_color = vec4(0.90, 0.94, 0.96, 0.85);
uniform sampler2D foam : filter_linear_mipmap, repeat_enable;
uniform float wave_scale = 1.0;
uniform float wave_speed = 1.0;
uniform float fade_start = 1600.0;
uniform float fade_end = 3000.0;
// Where the pattern has scrolled to. Driven from wake.gd at the ship's own
// speed, so the foam stands still in the water while the strip carrying it
// moves with the ship.
uniform vec2 scroll = vec2(0.0, 0.0);
// A hand's breadth clear of the surface. Enough that the two never interleave
// at a glancing angle, small enough not to read as floating.
uniform float lift = 0.22;

void vertex() {
	vec3 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float fade = sea_fade(p, CAMERA_POSITION_WORLD, fade_start, fade_end);
	vec3 normal_sum = vec3(0.0);
	vec3 offset = sea_displacement(p, TIME, wave_scale, wave_speed, fade, normal_sum);
	offset.y += lift;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(offset, 0.0)).xyz;
	NORMAL = normalize(vec3(normal_sum.x, 1.0 + normal_sum.y, normal_sum.z));
}

void fragment() {
	ALBEDO = tint.rgb;
	// Three things multiplied: how bright this foam is meant to be, where along
	// and across the track this fragment sits (baked into the strip's vertex
	// colours), and the torn pattern of the foam itself.
	ALPHA = tint.a * COLOR.a * texture(foam, UV + scroll).a;
}
