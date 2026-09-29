shader_type canvas_item;
// Greys out a picture, like the original's colorMatrixFilter saturation 0
// (locked places on the GPS).

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float grey = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(grey), c.a);
}
