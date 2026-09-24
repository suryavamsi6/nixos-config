void MAIN()
{
    vec2 uv = vec2(UV0.x, 1.0 - UV0.y);
    vec3 dayColor = texture(dayMap, uv).rgb;
    BASE_COLOR = vec4(dayColor, 1.0);
    METALNESS = 0.0;
    ROUGHNESS = 0.72;
    SPECULAR_AMOUNT = 0.28;
}

void AMBIENT_LIGHT()
{
    vec2 uv = vec2(UV0.x, 1.0 - UV0.y);
    vec3 dayColor = texture(dayMap, uv).rgb;
    DIFFUSE += dayColor * TOTAL_AMBIENT_COLOR * 0.12;
}

void DIRECTIONAL_LIGHT()
{
    vec2 uv = vec2(UV0.x, 1.0 - UV0.y);
    vec3 dayColor = texture(dayMap, uv).rgb;
    vec3 nightColor = texture(nightMap, uv).rgb;
    float facing = dot(normalize(NORMAL), normalize(TO_LIGHT_DIR));
    float daylight = smoothstep(-0.14, 0.18, facing);
    vec3 sunlit = dayColor * LIGHT_COLOR * (0.10 + 0.90 * max(facing, 0.0)) * daylight * SHADOW_CONTRIB;
    vec3 cityLights = nightColor * (1.0 - daylight) * 1.45;
    DIFFUSE += sunlit + cityLights;
}
