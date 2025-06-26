#version 410 core

layout(location = 0) in vec4 v_color;

layout(location = 1) in vec2 dst_pos;
layout(location = 2) in vec2 dst_center;
layout(location = 3) in vec2 dst_half_size;
layout(location = 4) in float corner_radius;
layout(location = 5) in float edge_softness;
layout(location = 6) in float border_thickness;
layout(location = 7) in vec2 texture_uv;
layout(location = 8) in float ui_element_type; // 0 = normal quad, 1 = text, 2 = waveform data, 3 = circle.
layout(location = 9) in float font_size; 

#define font_size_xs  0
#define font_size_s   1
#define font_size_m   2
#define font_size_l   3
#define font_size_xl  4

// At the moment, a fragment == a pixel.
out vec4 color;

// This indicates which texture unit holds the relevant texture data.
uniform sampler2D font_texture_xs;
uniform sampler2D font_texture_s;
uniform sampler2D font_texture_m;
uniform sampler2D font_texture_l;
uniform sampler2D font_texture_xl;
// uniform sampler2D font_texture;

uniform sampler2D circle_knob_texture;
uniform sampler2D fader_knob_texture;
uniform sampler2D background_texture;

float RoundedRectSDF(vec2 sample_pos, vec2 rect_center, vec2 rect_half_size, float r) {
	vec2 d2 = (abs(rect_center - sample_pos) -
		rect_half_size +
		vec2(r, r));
	return min(max(d2.x, d2.y), 0.0) + length(max(d2, 0.0)) - r;
}

float calculate_border_factor(vec2 softness_padding) {
	float border_factor = 1.0;
	if(border_thickness == 0) {
		return border_factor;
	} else {
		vec2 interior_half_size = dst_half_size - vec2(border_thickness, border_thickness);
		// reduction factor for the internal corner radius. not 100% sure the best way to go
		// about this, but this is the best thing I've found so far!

		// this is necessary because otherwise it looks weird
		float interior_radius_reduce_f = min(interior_half_size.x / dst_half_size.x, interior_half_size.y / dst_half_size.y);
		float interior_corner_radius = (corner_radius * interior_radius_reduce_f * interior_radius_reduce_f);

		// calculate sample distance from "interior"
		float inside_d = RoundedRectSDF(dst_pos, dst_center, interior_half_size -
			softness_padding, interior_corner_radius);

		// map distance => factor
		float inside_f = smoothstep(0, 2 * edge_softness, inside_d);
		return inside_f;

	}
}

float CircleSDF(vec2 sample_pos, vec2 center, float radius) {
	return length(sample_pos - center) - radius;
}

void main() {
	// we need to shrink the rectangle's half-size that is used for distance calculations with
	// the edge softness - otherwise the underlying primitive will cut off the falloff too early.
	vec2 softness = vec2(edge_softness, edge_softness);
	vec2 softness_padding = max(max(softness * 2.0 - 1.0, 0.0), max(softness * 2.0 - 1.0, 0.0));

	// sample distance
	float dist;
	if(ui_element_type == 3.0) { // 3.0 -> circle.
		dist = CircleSDF(dst_pos, dst_center, dst_half_size.x - softness_padding.x);
	} else {
		dist = RoundedRectSDF(dst_pos, dst_center, dst_half_size - softness_padding, corner_radius);
	}

	// map distance => a blend factor
	float sdf_factor = 1.0 - smoothstep(0.0, 2.0 * edge_softness, dist);

	// use sdf_factor in final color calculation
	if(ui_element_type == 0.0) { // normal rect
		color = v_color * sdf_factor * calculate_border_factor(softness_padding);
	} else if(ui_element_type == 2.0) { // 2 -> waveform data.
		color = v_color;
	} else if (ui_element_type == 3.0) { 
		vec4 texture_sample = texture(circle_knob_texture, texture_uv);
		color = texture_sample;
	} else if (ui_element_type == 4.0) { // i.e. fader knob
		vec4 texture_sample = texture(fader_knob_texture, texture_uv);
		color = texture_sample;
	} else if (ui_element_type == 15.0) { // i.e. background
		vec4 texture_sample = texture(background_texture, texture_uv);
		color = texture_sample;
	} else { // i.e. we're rendering text.
		float texture_sample;
		// Sample red channel due to how texture is uploaded.
		if (font_size == font_size_s) {
			texture_sample = texture(font_texture_s, texture_uv).r; 
		} else if (font_size == font_size_m) { 
			texture_sample = texture(font_texture_m, texture_uv).r; 
		} else if (font_size == font_size_l) { 
			texture_sample = texture(font_texture_l, texture_uv).r; 
		} else if (font_size == font_size_xl) { 
			texture_sample = texture(font_texture_xl, texture_uv).r; 
		// default font size will be xs.
		} else {  
			texture_sample = texture(font_texture_xs, texture_uv).r;
		}
		color = v_color * texture_sample;
	}
}
