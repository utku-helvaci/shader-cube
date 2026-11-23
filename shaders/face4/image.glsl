// Letters for the buttons
int cafeLetter(int letter, int row) {
    int rows[5];

    if (letter == 65) rows = int[5](14,17,31,17,17);
    else if (letter == 67) rows = int[5](15,16,16,16,15);
    else if (letter == 68) rows = int[5](30,17,17,17,30);
    else if (letter == 69) rows = int[5](31,16,30,16,31);
    else if (letter == 70) rows = int[5](31,16,30,16,16);
    else if (letter == 71) rows = int[5](15,16,19,17,15);
    else if (letter == 72) rows = int[5](17,17,31,17,17);
    else if (letter == 73) rows = int[5](31,4,4,4,31);
    else if (letter == 76) rows = int[5](16,16,16,16,31);
    else if (letter == 77) rows = int[5](17,27,21,17,17);
    else if (letter == 79) rows = int[5](14,17,17,17,14);
    else if (letter == 80) rows = int[5](30,17,30,16,16);
    else if (letter == 82) rows = int[5](30,17,30,18,17);
    else if (letter == 83) rows = int[5](15,16,14,1,30);
    else if (letter == 84) rows = int[5](31,4,4,4,4);
    else if (letter == 85) rows = int[5](17,17,17,17,14);
    else rows = int[5](0,0,0,0,0);

    return rows[row];
}

float cafeText(vec2 p, vec2 center, float pixel, int label) {
    int letters[13];
    int count = 6;

    if (label == 0) {
        letters = int[13](77,65,84,67,72,65,0,0,0,0,0,0,0);
    } else if (label == 1) {
        letters = int[13](67,79,70,70,69,69,0,0,0,0,0,0,0);
    } else if (label == 2) {
        letters = int[13](80,79,85,82,0,0,0,0,0,0,0,0,0);
        count = 4;
    } else if (label == 3) {
        letters = int[13](83,72,65,80,69,0,0,0,0,0,0,0,0);
        count = 5;
    } else if (label == 4) {
        letters = int[13](82,69,83,69,84,0,0,0,0,0,0,0,0);
        count = 5;
    } else if (label == 5) {
        letters = int[13](72,79,76,68,0,84,79,0,80,79,85,82,0);
        count = 12;
    } else {
        letters = int[13](68,82,65,71,0,84,79,0,83,72,65,80,69);
        count = 13;
    }

    vec2 grid = (p - center) / pixel;
    grid.x += (float(count) * 6.0 - 1.0) * 0.5;
    grid.y = 2.5 - grid.y;

    if (grid.x < 0.0 || grid.y < 0.0 || grid.y >= 5.0) {
        return 0.0;
    }

    int index = int(floor(grid.x / 6.0));
    int column = int(mod(floor(grid.x), 6.0));
    int row = int(floor(grid.y));

    if (index >= count || column >= 5) return 0.0;

    int bits = cafeLetter(letters[index], row);
    return float((bits >> (4 - column)) & 1);
}

float cafeDisk(vec2 p, float radius, float edge) {
    return 1.0 - smoothstep(
        radius - edge, radius + edge, length(p)
    );
}

float cafeButton(vec2 p, float edge) {
    vec2 q = abs(p) - vec2(0.105, 0.028);

    float distance = length(max(q, 0.0))
        + min(max(q.x, q.y), 0.0) - 0.015;

    return 1.0 - smoothstep(-edge, edge, distance);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    float size = min(iResolution.x / 1.4, iResolution.y);
    vec2 p = (fragCoord - iResolution.xy * 0.5) / size;

    vec2 cupCenter = vec2(-0.13, -0.015);
    vec2 local = p - cupCenter;

    float edge = 1.2 / size;
    float radius = length(local);

    vec4 settings = texelFetch(iChannel0, ivec2(1, 0), 0);
    float drink = step(0.5, settings.x);
    float brush = step(0.5, settings.y);

    vec3 table = vec3(0.92, 0.89, 0.83);
    vec3 matcha = vec3(0.38, 0.48, 0.23);
    vec3 coffee = vec3(0.39, 0.22, 0.13);
    vec3 cream = vec3(0.99, 0.95, 0.86);
    vec3 ink = vec3(0.37, 0.35, 0.30);

    vec3 col = table;

    // Saucer shadow
    float shadow = 1.0 - smoothstep(
        0.38, 0.445,
        length(local - vec2(0.012, -0.022))
    );

    col *= 1.0 - shadow * 0.16;

    // Ceramic saucer
    vec3 saucerColor = vec3(0.95, 0.93, 0.88);
    saucerColor += local.y * 0.035;

    col = mix(
        col, saucerColor,
        cafeDisk(local, 0.405, edge)
    );

    float saucerRing = 1.0 - smoothstep(
        0.001, 0.004, abs(radius - 0.389)
    );

    col = mix(
        col, vec3(0.86, 0.84, 0.78),
        saucerRing * 0.4
    );

    // Cup handle
    vec2 handle = local - vec2(-0.35, 0.0);

    float handleOuter = 1.0 - smoothstep(
        0.97, 1.03,
        length(handle / vec2(0.075, 0.10))
    );

    col = mix(
        col, vec3(0.98, 0.97, 0.93),
        handleOuter
    );

    float handleHole = 1.0 - smoothstep(
        0.94, 1.06,
        length(handle / vec2(0.037, 0.058))
    );

    col = mix(col, table * 0.95, handleHole);

    // Rounded cup rim
    vec3 ceramic = vec3(0.97, 0.96, 0.91);
    ceramic += 0.025 * local.y / 0.363;

    ceramic -= 0.06 * (
        1.0 - smoothstep(0.326, 0.343, radius)
    );

    col = mix(
        col, ceramic,
        cafeDisk(local, 0.363, edge)
    );

    float highlight = 1.0 - smoothstep(
        0.001, 0.004, abs(radius - 0.355)
    );

    col = mix(
        col, vec3(1.0, 0.99, 0.96),
        highlight * 0.65
    );

    // Drink and milk
    vec3 base = mix(matcha, coffee, drink);
    base *= 1.0 - 0.17 * smoothstep(0.27, 0.325, radius);

    float milk = clamp(
        texture(iChannel0, fragCoord / iResolution.xy).r,
        0.0, 1.0
    );

    vec3 liquid = mix(base, cream, milk);

    col = mix(
        col, liquid,
        cafeDisk(local, 0.325, edge)
    );

    // Drink and brush buttons
    for (int i = 0; i < 5; i++) {
        vec2 center = vec2(0.48, 0.24 - float(i) * 0.12);
        vec2 b = p - center;

        bool selected =
            (i == 0 && drink < 0.5) ||
            (i == 1 && drink > 0.5) ||
            (i == 2 && brush < 0.5) ||
            (i == 3 && brush > 0.5);

        vec3 fill = vec3(0.97, 0.95, 0.90);
        vec3 textColor = ink;

        if (selected) {
            if (i == 0) fill = matcha;
            else if (i == 1) fill = coffee;
            else fill = vec3(0.43, 0.44, 0.37);

            textColor = cream;
        }

        col = mix(
            col, vec3(0.77, 0.74, 0.67),
            cafeButton(b, edge)
        );

        col = mix(
            col, fill,
            cafeButton(b * 1.045, edge)
        );

        col = mix(
            col, textColor,
            cafeText(p, center, 0.0046, i)
        );
    }

    // Show the instruction for the selected brush
    int instruction = brush < 0.5 ? 5 : 6;

    col = mix(
        col, ink,
        cafeText(
            p, vec2(-0.13, 0.445),
            0.0038, instruction
        )
    );

    // Brush outline while pressing
    vec2 mouse = (
        iMouse.xy - iResolution.xy * 0.5
    ) / size;

    if (iMouse.z > 0.0 &&
        length(mouse - cupCenter) < 0.305) {
        float brushRadius = brush < 0.5 ? 0.024 : 0.009;

        float ring = 1.0 - smoothstep(
            edge, edge * 2.0,
            abs(length(p - mouse) - brushRadius)
        );

        col = mix(col, cream, ring * 0.55);
    }

    fragColor = vec4(col, 1.0);
}