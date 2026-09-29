// Car layer shading, matching the original game's paint technique:
// a paintable layer's red channel is its shading (multiplied over the paint
// colour) and its blue channel is its highlights (screen-blended on top).
shader_type canvas_item;

uniform bool painted = false;
uniform vec3 paint_color = vec3(1.0, 0.0, 0.0);
// Subtracted from rgb on unpainted layers (the original's -50 colour offset
// for far-side wheels).
uniform float darken = 0.0;
// Tints the layer towards a colour (used for selection highlights).
uniform vec4 highlight = vec4(0.0);

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	vec3 c;
	if (painted) {
		c = paint_color * t.r;
		c = c + vec3(t.b) - c * t.b;
	} else {
		c = max(t.rgb - vec3(darken), vec3(0.0));
	}
	c = mix(c, highlight.rgb, highlight.a);
	// COLOR arrives as modulate * texture, so its alpha already includes t.a.
	COLOR = vec4(c, COLOR.a);
}
