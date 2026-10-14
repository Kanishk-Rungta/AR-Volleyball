@tool
extends CompositorEffect
class_name IslandCompositor

# Two raster passes work with Mobile attachments without storage/copy flags.
var device: RenderingDevice
var shader := RID()
var pipeline := RID()
var sampler := RID()
var work_image := RID()
var work_framebuffer := RID()
var work_size := Vector2i.ZERO

const VERTEX := """
#version 450
layout(location=0) out vec2 uv;
void main() {
    uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
    gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
}
"""
const FRAGMENT := """
#version 450
layout(location=0) in vec2 uv;
layout(location=0) out vec4 result;
layout(set=0,binding=0) uniform sampler2D color_image;
layout(push_constant, std430) uniform Params { vec4 options; } params;
void main() {
    vec4 c = texture(color_image, uv);
    float vignette = 1.0 - .45 * dot(uv - .5, uv - .5);
    float luminance = dot(c.rgb, vec3(.2126,.7152,.0722));
    vec3 graded = mix(vec3(luminance),c.rgb,1.25) * vec3(1.07,1.02,.94) * vignette;
    result = vec4(mix(c.rgb,max(graded,vec3(0)),params.options.x),c.a);
}
"""

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	device = RenderingServer.get_rendering_device()

func _render_callback(callback_type: int, data: RenderData) -> void:
	if device == null or callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return
	var buffers: RenderSceneBuffersRD = data.get_render_scene_buffers()
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return
	if not shader.is_valid():
		var source := RDShaderSource.new()
		source.source_vertex = VERTEX
		source.source_fragment = FRAGMENT
		var spirv := device.shader_compile_spirv_from_source(source)
		if not spirv.compile_error_vertex.is_empty() or not spirv.compile_error_fragment.is_empty():
			push_error(spirv.compile_error_vertex + spirv.compile_error_fragment)
			return
		shader = device.shader_create_from_spirv(spirv)
		sampler = device.sampler_create(RDSamplerState.new())
	for view in range(buffers.get_view_count()):
		var color := buffers.get_color_layer(view)
		if work_size != size or not work_image.is_valid():
			if work_image.is_valid():
				device.free_rid(work_image)
			var format := device.texture_get_format(color)
			format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
			format.array_layers = 1
			format.usage_bits = RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
			work_image = device.texture_create(format, RDTextureView.new())
			work_framebuffer = device.framebuffer_create([work_image])
			work_size = size
		if not pipeline.is_valid():
			var blend := RDPipelineColorBlendState.new()
			blend.attachments = [RDPipelineColorBlendStateAttachment.new()]
			pipeline = device.render_pipeline_create(shader, device.framebuffer_get_format(work_framebuffer), -1, RenderingDevice.RENDER_PRIMITIVE_TRIANGLES, RDPipelineRasterizationState.new(), RDPipelineMultisampleState.new(), RDPipelineDepthStencilState.new(), blend)
		_draw_pass(color, work_framebuffer, 0.0)
		var destination := device.framebuffer_create([color])
		_draw_pass(work_image, destination, 1.0)
		device.free_rid(destination)

func _draw_pass(input: RID, output: RID, strength: float) -> void:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform.binding = 0
	uniform.add_id(sampler)
	uniform.add_id(input)
	var uniform_set := UniformSetCacheRD.get_cache(shader, 0, [uniform])
	var commands := device.draw_list_begin(output)
	device.draw_list_bind_render_pipeline(commands, pipeline)
	device.draw_list_bind_uniform_set(commands, uniform_set, 0)
	var constants := PackedFloat32Array([strength, 0, 0, 0]).to_byte_array()
	device.draw_list_set_push_constant(commands, constants, constants.size())
	device.draw_list_draw(commands, false, 1, 3)
	device.draw_list_end()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and device != null:
		for resource in [shader, sampler, work_image]:
			if resource.is_valid():
				device.free_rid(resource)
