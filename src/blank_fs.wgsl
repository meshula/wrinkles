
// begin https://www.shadertoy.com/view/3sKSWc
fn DistanceToLineSegment(p0: vec2<f32>, p1: vec2<f32>, p: vec2<f32>) -> f32 {
    let distanceP0: f32 = length(p0 - p);
    let distanceP1: f32 = length(p1 - p);
    let l2: f32 = pow(length(p0 - p1), 2.0);
    let t: f32 = max(0.0, min(1.0, dot(p - p0, p1 - p0) / l2));
    let projection: vec2<f32> = p0 + t * (p1 - p0); 
    let distanceToProjection: f32 = length(projection - p);
    return min(min(distanceP0, distanceP1), distanceToProjection);
}
// end https://www.shadertoy.com/view/3sKSWc

fn Function(x: f32) -> f32
{
    let iTime = 0.0;
    var compx = x * 1.0;// 8.0;
    compx -= iTime * .1;
    compx *= 2.0 * 3.1415926359;
    return 0.5 + 0.5 * sin(compx);

//    return sin(compx * sin(iTime * 0.2)) * 
  //         sin(compx + cos(iTime * iTime * 0.01)) * 0.25 + 0.5;
}

// begin https://www.shadertoy.com/view/3sKSWc
fn DistanceToFunction(p : vec2<f32>, xDelta: f32) -> f32
{
    var result: f32 = 100.0;
    
    for (var i: f32 = -3.0; i < 3.0; i += 1.0)
    {
        var q: vec2<f32> = p;
        q.x += xDelta * i;
        
        let p0: vec2<f32> = vec2<f32>(q.x, Function(q.x));
    	let p1: vec2<f32> = vec2<f32>(q.x + xDelta, Function(q.x + xDelta));
        result = min(result, DistanceToLineSegment(p0, p1, p));
    }

    return result;
}
// end https://www.shadertoy.com/view/3sKSWc

@group(0) @binding(1) var image: texture_2d<f32>;
@group(0) @binding(2) var image_sampler: sampler;
@stage(fragment) fn main(
    @location(0) uv: vec2<f32>,
) -> @location(0) vec4<f32> {
    var output: vec4<f32>;

    output = vec4<f32>(0.1,0.1,0.1,1);

    let time = uv.x * uniforms.duration;

    let grid_width: f32 = 0.02;
    let divisions_x: f32 = uniforms.frame_rate;
    let gridx = time * divisions_x - floor(time * divisions_x);
    let modx = fract(gridx);
    if (modx > grid_width) {
        output[0] = 0.0;
    }
    else {
        output[0] = 1.0;
    }

    let divisions_y: f32 = uniforms.clip_frame_rate;
    let gridy = uv.y * divisions_y - floor(uv.y * divisions_y);
    let mody = fract(gridy);
    if (mody < grid_width) {
        output[0] = 1.0;
    }

    var intensity: f32;

    intensity = pow(intensity,1.0/2.2);

    output[0] = max(0, min(1, intensity + output[0]));
    output[1] = max(0, min(1, intensity + output[1]));
    output[2] = max(0, min(1, intensity + output[2]));
 
    output[3] = 1.0;
    return output;
}

