void MAIN()
{
    float rim = pow(clamp(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW_VECTOR))), 0.0, 1.0), 2.4);
    BASE_COLOR = vec4(atmosphereColor.rgb, rim * atmosphereStrength);
    EMISSIVE_COLOR = atmosphereColor.rgb * rim * 0.55;
    ROUGHNESS = 1.0;
}
