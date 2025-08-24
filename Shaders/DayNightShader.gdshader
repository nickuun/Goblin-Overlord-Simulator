shader_type canvas_item;
render_mode unshaded, blend_mul; // multiply onto the scene

// Hue/tint over the day: RGB = hue (alpha ignored)
uniform sampler2D gradient_tex : source_color;

// 0..1 maps 00:00..24:00 (set from script)
uniform float time_norm : hint_range(0.0, 1.0) = 0.3333333; // ~08:00

// Darkness windows (literal defaults)
uniform float dawn_start = 0.2083333; // 05:00
uniform float dawn_end   = 0.2916667; // 07:00
uniform float dusk_start = 0.7500000; // 18:00
uniform float dusk_end   = 0.8333333; // 20:00

// Night intensity
uniform float night_amount : hint_range(0.0, 1.0) = 0.6;

// Hue intensity & relight
uniform float tint_strength  : hint_range(0.0, 1.0) = 1.0; // 1 = full hue tint
uniform float min_tint_luma  : hint_range(0.0, 1.0) = 0.60; // keep tint at least this bright

// Vignette
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.35;
uniform float vignette_softness : hint_range(0.001, 1.0) = 0.35;

void fragment() {
    // 1) Hue from gradient (keeps your nice dawn/noon/dusk colors)
    vec3 hue = texture(gradient_tex, vec2(time_norm, 0.5)).rgb;

    // --- Re-light the hue so its brightness never dips below min_tint_luma ---
    // (prevents midnight hue being extra dark compared to 23:50)
    float luma = dot(hue, vec3(0.2126, 0.7152, 0.0722));
    float scale = (luma < min_tint_luma) ? (min_tint_luma / max(luma, 0.001)) : 1.0;
    vec3 hue_relit = clamp(hue * scale, 0.0, 1.0);

    // How strong the color cast is overall
    vec3 tint_rgb = mix(vec3(1.0), hue_relit, tint_strength);

    // 2) Darkness from time-of-day (smooth dusk/dawn ramps)
    float evening     = smoothstep(dusk_start, dusk_end, time_norm);       // 0→1 through dusk
    float before_dawn = 1.0 - smoothstep(dawn_start, dawn_end, time_norm); // 1→0 through dawn
    float darkness = max(evening, before_dawn); // ~0 at noon, ~1 at night
    darkness *= night_amount;

    // 3) Vignette
    float d = distance(UV, vec2(0.5));
    float vignette = smoothstep(1.0 - vignette_softness, 1.0, d) * vignette_strength;

    // 4) Apply darkness & vignette uniformly (independent of hue brightness)
    float dark_scalar = clamp(1.0 - darkness, 0.0, 1.0);
    vec3 mul_rgb = tint_rgb * dark_scalar * (1.0 - vignette);

    COLOR = vec4(mul_rgb, 1.0); // alpha unused in blend_mul
}
