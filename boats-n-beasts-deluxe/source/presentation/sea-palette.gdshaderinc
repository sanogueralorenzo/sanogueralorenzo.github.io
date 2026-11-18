vec3 linear_color(vec3 color) {
    return mix(color / 12.92, pow((color + vec3(.055)) / 1.055, vec3(2.4)), step(vec3(.04045), color));
}

vec3 sea_weather(vec3 daylight, vec2 weather) {
    vec3 evening = daylight * vec3(.86, .90, 1.015) + vec3(.034, .014, .038);
    vec3 storm = daylight * vec3(.60, .72, .88) + vec3(.032, .005, .046);
    return mix(mix(daylight, evening, weather.x), storm, weather.y);
}
