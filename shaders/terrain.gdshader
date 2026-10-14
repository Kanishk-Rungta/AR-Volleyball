shader_type spatial;
varying vec3 local_position;
void vertex() { local_position = VERTEX; }
void fragment() {
    float contour = smoothstep(0.02, 0.045, abs(fract(local_position.y * 9.0) - 0.5));
    vec3 grass = mix(vec3(0.14, 0.32, 0.25), vec3(0.57, 0.69, 0.40), clamp(local_position.y / 1.65, 0.0, 1.0));
    ALBEDO = grass * mix(0.65, 1.0, contour);
    ROUGHNESS = 0.88;
}
