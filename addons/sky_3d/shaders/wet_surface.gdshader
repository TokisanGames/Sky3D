shader_type spatial;

render_mode specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color;
uniform sampler2D roughness_texture;
uniform sampler2D metallic_texture;
uniform sampler2D normal_texture;

uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float base_roughness : hint_range(0.0, 1.0) = 1.0;

void fragment() {
    // --- Albedo ---
    vec3 albedo = texture(albedo_texture, UV).rgb;
    ALBEDO = albedo;

    // --- Roughness (float + textura se existir) ---
    float r_tex = texture(roughness_texture, UV).r;
    float roughness_val = mix(base_roughness, r_tex, step(0.01, r_tex)); 
    ROUGHNESS = mix(roughness_val, 0.05, wetness);

    // --- Metallic ---
    float m_tex = texture(metallic_texture, UV).r;
    METALLIC = m_tex;

    // --- Normais ---
    vec3 n_tex = texture(normal_texture, UV).rgb * 2.0 - 1.0;
    NORMAL = normalize(n_tex);
}
