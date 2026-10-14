shader_type canvas_item;
uniform vec2 top_left = vec2(0,0);
uniform vec2 top_right = vec2(1,0);
uniform vec2 bottom_left = vec2(0,1);
uniform vec2 bottom_right = vec2(1,1);
uniform bool use_yuv = false;
uniform sampler2D y_plane : filter_linear, repeat_disable;
uniform sampler2D u_plane : filter_linear, repeat_disable;
uniform sampler2D v_plane : filter_linear, repeat_disable;
void fragment() {
    vec2 image_uv = mix(mix(top_left, top_right, UV.x), mix(bottom_left, bottom_right, UV.x), UV.y);
    if (use_yuv) {
        float y = 1.164383 * (texture(y_plane, image_uv).r - 16.0 / 255.0);
        float u = texture(u_plane, image_uv).r - 128.0 / 255.0;
        float v = texture(v_plane, image_uv).r - 128.0 / 255.0;
        COLOR = vec4(clamp(vec3(y + 1.596027*v, y - 0.391762*u - 0.812968*v, y + 2.017232*u), vec3(0.0), vec3(1.0)), 1.0);
    } else {
        COLOR = texture(TEXTURE, image_uv);
    }
}
