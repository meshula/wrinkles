struct Uniforms {
    aspect_ratio: f32,
    mip_level: f32,
    duration: f32,
    frame_rate: f32,
}
@group(0) @binding(0) var<uniform> uniforms: Uniforms;

