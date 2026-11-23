float milkPath(vec2 p, vec2 a, vec2 b) {
    vec2 line = b - a;

    float along = clamp(
        dot(p - a, line) / max(dot(line, line), 0.000001),
        0.0, 1.0
    );

    return length(p - a - line * along);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    float size = min(iResolution.x / 1.4, iResolution.y);
    vec2 middle = iResolution.xy * 0.5;
    vec2 cupCenter = vec2(-0.13, -0.015);

    vec2 p = (fragCoord - middle) / size;
    vec2 mouse = (iMouse.xy - middle) / size;

    vec4 oldMouse = texelFetch(iChannel0, ivec2(0, 0), 0);
    vec4 settings = texelFetch(iChannel0, ivec2(1, 0), 0);

    bool fresh = iFrame == 0 || settings.w < 0.5;
    bool down = iMouse.z > 0.0;
    bool clicked = down && (fresh || oldMouse.z < 0.5);

    float drink = fresh ? 0.0 : settings.x;
    float brush = fresh ? 0.0 : settings.y;
    bool reset = fresh;

    // Check the buttons
    if (clicked) {
        for (int i = 0; i < 5; i++) {
            vec2 button = vec2(0.48, 0.24 - float(i) * 0.12);
            vec2 offset = abs(mouse - button);

            if (offset.x < 0.12 && offset.y < 0.043) {
                if (i == 0) {
                    drink = 0.0;
                    reset = true;
                }

                if (i == 1) {
                    drink = 1.0;
                    reset = true;
                }

                if (i == 2) brush = 0.0;
                if (i == 3) brush = 1.0;
                if (i == 4) reset = true;
            }
        }
    }

    if (reset) brush = 0.0;

    // Save the controls in two corner pixels
    if (fragCoord.y < 1.0 && fragCoord.x < 1.0) {
        fragColor = vec4(mouse, down ? 1.0 : 0.0, 1.0);
        return;
    }

    if (fragCoord.y < 1.0 && fragCoord.x < 2.0) {
        fragColor = vec4(drink, brush, 0.0, 1.0);
        return;
    }

    // Start with a little milk
    if (reset) {
        float milk = 1.0 - smoothstep(
            0.025, 0.04, length(p - cupCenter)
        );

        fragColor = vec4(milk, 0.0, 0.0, 1.0);
        return;
    }

    float seconds = clamp(iTimeDelta, 0.0, 0.04);
    bool touching = down && length(mouse - cupCenter) < 0.305;

    vec2 start = mouse;

    if (oldMouse.z > 0.5 &&
        length(oldMouse.xy - cupCenter) < 0.305) {
        start = oldMouse.xy;
    }

    vec2 movement = mouse - start;
    float travel = length(movement);
    vec2 q = p;

    // Pull the milk with Mixwell
    if (touching && brush > 0.5 && travel > 0.0001) {
        vec2 brushStart = start;

        if (travel > 0.07) {
            brushStart = mouse - movement / travel * 0.07;
        }

        q += rdSegment(q, 0.014, brushStart, mouse);
    }

    // Pouring pushes nearby milk outward
    if (touching && brush < 0.5) {
        vec2 offset = q - mouse;
        float distanceSquared = dot(offset, offset);

        float spread = 0.0035 * seconds
            * exp(-distanceSquared / 0.025);

        float previousDistance = sqrt(
            max(distanceSquared - spread, 0.0)
        );

        q = mouse + offset * previousDistance
            / max(sqrt(distanceSquared), 0.00001);
    }

    // Keep the paint inside the drink
    vec2 offset = q - cupCenter;
    float distanceFromCenter = length(offset);

    if (distanceFromCenter > 0.323) {
        q = cupCenter + offset / distanceFromCenter * 0.323;
    }

    vec2 uv = (q * size + middle) / iResolution.xy;
    float milk = texture(iChannel0, uv).r;

    // Add milk along the mouse path
    if (touching && brush < 0.5) {
        float stream = 1.0 - smoothstep(
            0.008, 0.022, milkPath(p, start, mouse)
        );

        float amount = 1.0 - exp(-18.0 * seconds);
        milk = mix(milk, 1.0, stream * amount);
    }

    if (length(p - cupCenter) > 0.325) {
        milk = 0.0;
    }

    fragColor = vec4(clamp(milk, 0.0, 1.0), 0.0, 0.0, 1.0);
}