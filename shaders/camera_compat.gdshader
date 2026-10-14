shader_type canvas_item;
uniform vec2 top_left = vec2(0,0);
uniform vec2 top_right = vec2(1,0);
uniform vec2 bottom_left = vec2(0,1);
uniform vec2 bottom_right = vec2(1,1);
void fragment() {
    vec2 image_uv = mix(mix(top_left, top_right, UV.x), mix(bottom_left, bottom_right, UV.x), UV.y);
    COLOR = vec4(texture(TEXTURE, image_uv).rgb, 1.0);
}
