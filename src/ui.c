// SPDX-License-Identifier: MIT
/*
 * The F1 menu (see ui.h).  Immediate mode: the app and the scenes declare
 * the menu's rows every frame; input that arrived since the last frame is
 * matched to rows by index, using the last frame's layout for the mouse.
 *
 * Drawing: one stream of GFX_VTX_UI vertices.  A vertex either samples the
 * font atlas (params.z < 0) or describes a rounded rectangle by its signed
 * distance (uv = offset from the centre, params = half size, radius), so
 * panels, switches and slider knobs stay crisp at any scale.
 */
#include "ui.h"

#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "app.h"

#if defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-function"
#pragma GCC diagnostic ignored "-Wsign-compare"
#pragma GCC diagnostic ignored "-Wunused-parameter"
#endif
#define STB_TRUETYPE_IMPLEMENTATION
#define STBTT_STATIC
#include "stb_truetype.h"
#if defined(__GNUC__)
#pragma GCC diagnostic pop
#endif

/* ---------------------------------------------------------------- fonts */

enum { F_BODY, F_SMALL, F_HEAD, F_TITLE, NFONTS };
static const int FONT_FILE[NFONTS] = {0, 0, 1, 1};          /* 0 regular, 1 bold */
static const float FONT_PX[NFONTS] = {17.0f, 14.0f, 13.0f, 22.0f};

/* Beyond ASCII: arrows, guillemets, dots, dash, ellipsis, arrow keys. */
static const int EXTRA_CP[] = {0x2039, 0x203A, 0x2190, 0x2191, 0x2192, 0x2193, 0x00B7, 0x2022,
                               0x2014, 0x2013, 0x2026, 0x00D7, 0x00B0, 0x00B2, 0x00B3};
#define NEXTRA ((int)(sizeof EXTRA_CP / sizeof *EXTRA_CP))

typedef struct {
    stbtt_packedchar ascii[95];
    stbtt_packedchar extra[NEXTRA];
    int extra_cp[NEXTRA], nextra;
    float px, ascent, descent;
} Font;

/* ---------------------------------------------------------------- state */

enum { IT_SECTION, IT_CHOICE, IT_TOGGLE, IT_SLIDER, IT_BUTTON, IT_TEXT };
enum { OP_DELTA, OP_ACTIVATE, OP_SET };

typedef struct {
    int type;
    char label[160], value[200];
    float frac; /* slider position / switch state */
    float y, h; /* layout, list coordinates */
} Item;

typedef struct { int item, kind; float v; } Op;

#define MAX_ITEMS 128
#define MAX_OPS 64

static struct {
    int ok, open;
    unsigned char *ttf[2];
    stbtt_fontinfo info[2];
    Font font[NFONTS];
    GfxTex *atlas;
    int aw, ah;
    float built_scale;
    GfxProg *prog;

    /* this frame's rows and the last laid-out ones (for the mouse) */
    Item items[MAX_ITEMS], prev[MAX_ITEMS];
    int nitems, nprev;
    int sel, sel_by_key;
    Op ops[MAX_OPS];
    int nops;
    char title[64], subtitle[300];

    int fb_w, fb_h;
    float s;                             /* UI scale */
    float px, py, pw, ph;                /* panel */
    float list_y0, list_y1, content_h;
    float scroll, scroll_target, sel_anim;
    float anim;                          /* 0 closed .. 1 open */
    float hint_t;                        /* seconds since start, for the F1 hint */

    double mx, my;
    int drag;                            /* slider row being dragged, -1 */

    GfxUiVtx *v;
    int nv, cap, nv_fixed;
} U = {.drag = -1};

/* ---------------------------------------------------------------- setup */

static unsigned char *load_file(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    unsigned char *d = n > 0 ? malloc((size_t)n) : NULL;
    if (d && fread(d, 1, (size_t)n, f) != (size_t)n) { free(d); d = NULL; }
    fclose(f);
    return d;
}

static const char *UI_UBO = "GFX_UBO(0) st_Uniforms { vec4 uScreen; vec4 uClip; };\n";

static const char *UI_VS =
    "layout(location=0) in vec2 aPos; layout(location=1) in vec2 aUV;\n"
    "layout(location=2) in vec4 aCol; layout(location=3) in vec3 aPar;\n"
    "out vec2 vUV; out vec4 vCol; out vec3 vPar; out vec2 vPx;\n"
    "void main(){\n"
    "  vUV = aUV; vCol = aCol; vPar = aPar; vPx = aPos;\n"
    "  vec2 ndc = vec2(aPos.x / uScreen.x * 2.0 - 1.0, 1.0 - aPos.y / uScreen.y * 2.0);\n"
    "  if (uScreen.z > 0.5) ndc.y = -ndc.y;\n" /* the Vulkan swapchain stores rows top-down */
    "  gl_Position = GFX_CLIP(vec4(ndc, 0.0, 1.0));\n"
    "}\n";

static const char *UI_FS =
    "GFX_TEX(1) sampler2D uFont;\n"
    "in vec2 vUV; in vec4 vCol; in vec3 vPar; in vec2 vPx;\n"
    "layout(location=0) out vec4 o;\n"
    "void main(){\n"
    "  float inside = step(uClip.x, vPx.x) * step(uClip.y, vPx.y) * step(vPx.x, uClip.z) * step(vPx.y, uClip.w);\n"
    "  float a;\n"
    "  if (vPar.z < 0.0) a = texture(uFont, vUV).r;\n"
    "  else {\n"                                         /* rounded rectangle, uv = offset from its centre */
    "    vec2 q = abs(vUV) - vPar.xy + vPar.z;\n"
    "    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - vPar.z;\n"
    "    a = clamp(0.5 - d, 0.0, 1.0);\n"
    "  }\n"
    "  o = vec4(vCol.rgb, 1.0) * (vCol.a * a * uScreen.w * inside);\n" /* premultiplied */
    "}\n";

int ui_init(const char *font_dir) {
    static const char *const files[2] = {"AtkinsonHyperlegible-Regular.ttf", "AtkinsonHyperlegible-Bold.ttf"};
    for (int i = 0; i < 2; i++) {
        char path[1200];
        snprintf(path, sizeof path, "%s/%s", font_dir, files[i]);
        U.ttf[i] = load_file(path);
        if (!U.ttf[i] || !stbtt_InitFont(&U.info[i], U.ttf[i], stbtt_GetFontOffsetForIndex(U.ttf[i], 0))) {
            fprintf(stderr, "menu unavailable: cannot load %s\n", path);
            ui_shutdown();
            return 0;
        }
    }
    GfxProgDesc d = {.label = "ui", .vs = {UI_UBO, UI_VS}, .nvs = 2, .fs = {UI_UBO, UI_FS}, .nfs = 2,
                     .tex = {"uFont"}, .ntex = 1, .vtx = GFX_VTX_UI};
    U.prog = gfx->program(&d);
    if (!U.prog) {
        ui_shutdown();
        return 0;
    }
    U.ok = 1;
    U.drag = -1;
    return 1;
}

void ui_shutdown(void) {
    if (U.atlas) gfx->tex_free(U.atlas);
    if (U.prog) gfx->prog_free(U.prog);
    free(U.ttf[0]);
    free(U.ttf[1]);
    free(U.v);
    memset(&U, 0, sizeof U);
    U.drag = -1;
}

int ui_available(void) { return U.ok; }
int ui_is_open(void) { return U.ok && U.open; }

void ui_set_open(int open) {
    if (!U.ok) return;
    U.open = open;
    U.drag = -1;
    U.hint_t = 1e9f; /* the hint has done its job */
}

/* Rasterises the fonts for UI scale s into the atlas texture. */
static void build_atlas(float s) {
    for (int size = 512; size <= 4096; size *= 2) {
        unsigned char *bmp = calloc((size_t)size * (size_t)size, 1);
        stbtt_pack_context pc;
        if (!stbtt_PackBegin(&pc, bmp, size, size, 0, 1, NULL)) { free(bmp); return; }
        stbtt_PackSetOversampling(&pc, 1, 1);
        int ok = 1;
        for (int f = 0; f < NFONTS && ok; f++) {
            Font *ft = &U.font[f];
            const stbtt_fontinfo *info = &U.info[FONT_FILE[f]];
            ft->px = roundf(FONT_PX[f] * s);
            ft->nextra = 0;
            for (int k = 0; k < NEXTRA; k++)
                if (stbtt_FindGlyphIndex(info, EXTRA_CP[k])) ft->extra_cp[ft->nextra++] = EXTRA_CP[k];
            stbtt_pack_range r[2] = {
                {.font_size = ft->px, .first_unicode_codepoint_in_range = 32, .num_chars = 95,
                 .chardata_for_range = ft->ascii},
                {.font_size = ft->px, .array_of_unicode_codepoints = ft->extra_cp, .num_chars = ft->nextra,
                 .chardata_for_range = ft->extra},
            };
            ok = stbtt_PackFontRanges(&pc, U.ttf[FONT_FILE[f]], 0, r, ft->nextra ? 2 : 1);
            int asc, desc, gap;
            stbtt_GetFontVMetrics(info, &asc, &desc, &gap);
            float sc = stbtt_ScaleForPixelHeight(info, ft->px);
            ft->ascent = (float)asc * sc;
            ft->descent = (float)desc * sc;
        }
        stbtt_PackEnd(&pc);
        if (ok) {
            if (U.atlas) gfx->tex_free(U.atlas);
            U.atlas = gfx->texture(GFX_R8, size, size, 1, 0, 1);
            gfx->upload(U.atlas, bmp);
            U.aw = U.ah = size;
            U.built_scale = s;
            free(bmp);
            return;
        }
        free(bmp);
    }
}

/* ---------------------------------------------------------------- drawing primitives */

typedef struct { unsigned char r, g, b, a; } Col;
static Col C(int r, int g, int b, int a) { Col c = {(unsigned char)r, (unsigned char)g, (unsigned char)b, (unsigned char)a}; return c; }

static const Col COL_PANEL = {14, 16, 22, 236}, COL_EDGE = {255, 255, 255, 20};
static const Col COL_TEXT = {226, 229, 236, 255}, COL_DIM = {140, 148, 166, 255};
static const Col COL_ACCENT = {104, 146, 255, 255}, COL_TRACK = {64, 69, 84, 255};
static const Col COL_SEL = {255, 255, 255, 16}, COL_KNOB = {244, 246, 250, 255};

static GfxUiVtx *push(int n) {
    if (U.nv + n > U.cap) {
        U.cap = (U.nv + n) * 2 + 1024;
        U.v = realloc(U.v, sizeof *U.v * (size_t)U.cap);
    }
    GfxUiVtx *v = U.v + U.nv;
    U.nv += n;
    return v;
}

static void quad(float x0, float y0, float x1, float y1, float u0, float v0, float u1, float v1, Col c,
                 float p0, float p1, float p2) {
    GfxUiVtx *v = push(6);
    float xs[6] = {x0, x1, x1, x0, x1, x0}, ys[6] = {y0, y0, y1, y0, y1, y1};
    float us[6] = {u0, u1, u1, u0, u1, u0}, vs[6] = {v0, v0, v1, v0, v1, v1};
    for (int i = 0; i < 6; i++) {
        v[i].pos[0] = xs[i]; v[i].pos[1] = ys[i];
        v[i].uv[0] = us[i]; v[i].uv[1] = vs[i];
        v[i].col[0] = c.r; v[i].col[1] = c.g; v[i].col[2] = c.b; v[i].col[3] = c.a;
        v[i].p[0] = p0; v[i].p[1] = p1; v[i].p[2] = p2;
    }
}

/* Rounded rectangle; one pixel of margin for the anti-aliased edge. */
static void rect(float x, float y, float w, float h, float r, Col c) {
    float hw = w * 0.5f, hh = h * 0.5f;
    if (r > hw) r = hw;
    if (r > hh) r = hh;
    quad(x - 1, y - 1, x + w + 1, y + h + 1, -hw - 1, -hh - 1, hw + 1, hh + 1, c, hw, hh, r);
}

static void circle(float cx, float cy, float r, Col c) { rect(cx - r, cy - r, 2 * r, 2 * r, r, c); }

static const stbtt_packedchar *glyph(const Font *f, int cp) {
    if (cp >= 32 && cp < 127) return &f->ascii[cp - 32];
    for (int i = 0; i < f->nextra; i++)
        if (f->extra_cp[i] == cp) return &f->extra[i];
    return &f->ascii['?' - 32];
}

static int has_glyph(int font, int cp) {
    const Font *f = &U.font[font];
    if (cp >= 32 && cp < 127) return 1;
    for (int i = 0; i < f->nextra; i++)
        if (f->extra_cp[i] == cp) return 1;
    return 0;
}

static int utf8_next(const char **ps) {
    const unsigned char *s = (const unsigned char *)*ps;
    int cp = *s++, extra = 0;
    if (cp >= 0xF0) { cp &= 0x07; extra = 3; }
    else if (cp >= 0xE0) { cp &= 0x0F; extra = 2; }
    else if (cp >= 0xC0) { cp &= 0x1F; extra = 1; }
    for (; extra && (*s & 0xC0) == 0x80; extra--) cp = (cp << 6) | (*s++ & 0x3F);
    *ps = (const char *)s;
    return cp;
}

static float text_w(int font, const char *s) {
    const Font *f = &U.font[font];
    float w = 0;
    while (*s) w += glyph(f, utf8_next(&s))->xadvance;
    return w;
}

/* Text with its baseline at y; returns the x after it. */
static float text(int font, float x, float y, const char *s, Col c) {
    const Font *f = &U.font[font];
    float fx = roundf(x), fy = roundf(y);
    while (*s) {
        const stbtt_packedchar *g = glyph(f, utf8_next(&s));
        if (g->x1 > g->x0) {
            float x0 = fx + g->xoff, y0 = fy + g->yoff;
            quad(x0, y0, x0 + (float)(g->x1 - g->x0), y0 + (float)(g->y1 - g->y0), (float)g->x0 / (float)U.aw,
                 (float)g->y0 / (float)U.ah, (float)g->x1 / (float)U.aw, (float)g->y1 / (float)U.ah, c, 0, 0, -1);
        }
        fx += g->xadvance;
    }
    return fx;
}

/* Vertically centred in [y, y + h]. */
static float text_mid(int font, float x, float y, float h, const char *s, Col c) {
    const Font *f = &U.font[font];
    return text(font, x, y + h * 0.5f + (f->ascent + f->descent) * 0.5f, s, c);
}

/* Shortens s with an ellipsis to fit in max_w. */
static void fit(int font, const char *s, float max_w, char *out, size_t n) {
    snprintf(out, n, "%s", s);
    if (text_w(font, out) <= max_w) return;
    size_t len = strlen(out);
    while (len > 0) {
        do len--; while (len > 0 && ((unsigned char)out[len] & 0xC0) == 0x80);
        snprintf(out + len, n - len, "…");
        if (text_w(font, out) <= max_w) return;
    }
}

/* ---------------------------------------------------------------- building the menu */

static int selectable(const Item *it) { return it->type != IT_SECTION && it->type != IT_TEXT; }

void ui_begin(int fb_w, int fb_h, float dt, const char *title, const char *subtitle) {
    (void)dt;
    U.fb_w = fb_w;
    U.fb_h = fb_h;
    U.nitems = 0;
    snprintf(U.title, sizeof U.title, "%s", title);
    snprintf(U.subtitle, sizeof U.subtitle, "%s", subtitle);
}

static Item *add(int type, const char *label) {
    if (U.nitems >= MAX_ITEMS) return NULL;
    Item *it = &U.items[U.nitems++];
    memset(it, 0, sizeof *it);
    it->type = type;
    snprintf(it->label, sizeof it->label, "%s", label);
    return it;
}

void ui_section(const char *title) {
    Item *it = add(IT_SECTION, title);
    if (!it) return;
    for (char *c = it->label; *c; c++)
        if (*c >= 'a' && *c <= 'z') *c = (char)(*c - 'a' + 'A');
}

void ui_text(const char *label, const char *value) {
    Item *it = add(IT_TEXT, label);
    if (it) snprintf(it->value, sizeof it->value, "%s", value);
}

int ui_choice(const char *label, int *v, const char *const *options, int n) {
    Item *it = add(IT_CHOICE, label);
    if (!it || n <= 0) return 0;
    int idx = (int)(it - U.items), old = *v;
    for (int i = 0; i < U.nops; i++) {
        if (U.ops[i].item != idx) continue;
        int d = U.ops[i].kind == OP_ACTIVATE ? 1 : (int)U.ops[i].v;
        if (U.ops[i].kind == OP_SET) d = 0;
        *v = ((*v + d) % n + n) % n;
    }
    if (*v < 0 || *v >= n) *v = 0;
    snprintf(it->value, sizeof it->value, "%s", options[*v]);
    return *v != old;
}

int ui_toggle(const char *label, int *v) {
    Item *it = add(IT_TOGGLE, label);
    if (!it) return 0;
    int idx = (int)(it - U.items), old = !!*v;
    for (int i = 0; i < U.nops; i++) {
        if (U.ops[i].item != idx) continue;
        if (U.ops[i].kind == OP_ACTIVATE) *v = !*v;
        else if (U.ops[i].kind == OP_DELTA) *v = U.ops[i].v > 0;
    }
    it->frac = *v ? 1.0f : 0.0f;
    snprintf(it->value, sizeof it->value, "%s", *v ? "On" : "Off");
    return !!*v != old;
}

static float quantize(float v, float lo, float hi, float step) {
    if (step > 0) v = lo + roundf((v - lo) / step) * step;
    return v < lo ? lo : v > hi ? hi : v;
}

int ui_slider(const char *label, float *v, float lo, float hi, float step, const char *fmt) {
    Item *it = add(IT_SLIDER, label);
    if (!it) return 0;
    int idx = (int)(it - U.items);
    float old = *v;
    for (int i = 0; i < U.nops; i++) {
        if (U.ops[i].item != idx) continue;
        if (U.ops[i].kind == OP_DELTA) *v = quantize(*v + U.ops[i].v * step, lo, hi, step);
        else if (U.ops[i].kind == OP_SET) *v = quantize(lo + U.ops[i].v * (hi - lo), lo, hi, step);
    }
    it->frac = hi > lo ? (*v - lo) / (hi - lo) : 0;
    snprintf(it->value, sizeof it->value, fmt, *v);
    return *v != old;
}

int ui_islider(const char *label, int *v, int lo, int hi, int step) {
    float f = (float)*v;
    int changed = ui_slider(label, &f, (float)lo, (float)hi, (float)step, "%.0f");
    *v = (int)lroundf(f);
    return changed;
}

int ui_button(const char *label) {
    Item *it = add(IT_BUTTON, label);
    if (!it) return 0;
    int idx = (int)(it - U.items), pressed = 0;
    for (int i = 0; i < U.nops; i++)
        if (U.ops[i].item == idx && U.ops[i].kind == OP_ACTIVATE) pressed = 1;
    return pressed;
}

/* Rows in list coordinates, the panel around them, scrolling. */
void ui_end(void) {
    float s = U.s = fmaxf(1.0f, fminf(3.0f, (float)U.fb_h / 1080.0f));
    float y = 0;
    for (int i = 0; i < U.nitems; i++) {
        Item *it = &U.items[i];
        it->h = (it->type == IT_SECTION ? (i ? 42.0f : 30.0f) : it->type == IT_BUTTON ? 44.0f : 38.0f) * s;
        it->y = y;
        y += it->h;
    }
    U.content_h = y + 8 * s;
    U.pw = 470 * s;
    U.px = 20 * s;
    U.py = 20 * s;
    float header = 84 * s, footer = 46 * s;
    U.ph = fminf((float)U.fb_h - 40 * s, header + U.content_h + footer);
    U.list_y0 = U.py + header;
    U.list_y1 = U.py + U.ph - footer;

    if (U.nitems && (U.sel >= U.nitems || !selectable(&U.items[U.sel]))) { /* keep the selection on a row */
        int k = U.sel < U.nitems ? U.sel : U.nitems - 1;
        while (k < U.nitems && !selectable(&U.items[k])) k++;
        if (k >= U.nitems)
            for (k = U.nitems - 1; k > 0 && !selectable(&U.items[k]); k--) {}
        U.sel = k;
    }
    float view = U.list_y1 - U.list_y0, max_scroll = fmaxf(0, U.content_h - view);
    if (U.sel_by_key && U.sel < U.nitems) { /* keep the keyboard selection in view */
        const Item *it = &U.items[U.sel];
        float top = it->y, bottom = it->y + it->h;
        if (U.sel > 0 && U.items[U.sel - 1].type == IT_SECTION) top = U.items[U.sel - 1].y;
        if (top < U.scroll_target) U.scroll_target = top;
        if (bottom > U.scroll_target + view) U.scroll_target = bottom - view;
        U.sel_by_key = 0;
    }
    U.scroll_target = fminf(fmaxf(U.scroll_target, 0), max_scroll);
    memcpy(U.prev, U.items, sizeof *U.items * (size_t)U.nitems);
    U.nprev = U.nitems;
    U.nops = 0;
}

/* ---------------------------------------------------------------- input */

static void op(int item, int kind, float v) {
    if (item < 0 || item >= U.nprev || U.nops >= MAX_OPS) return;
    U.ops[U.nops++] = (Op){item, kind, v};
}

static void move_sel(int dir, int count) {
    int k = U.sel;
    for (int moved = 0; moved < count;) {
        int n = k + dir;
        while (n >= 0 && n < U.nprev && !selectable(&U.prev[n])) n += dir;
        if (n < 0 || n >= U.nprev) break;
        k = n;
        moved++;
    }
    U.sel = k;
    U.sel_by_key = 1;
}

int ui_on_key(int key, int action, int mods) {
    if (!ui_is_open() || action == GLFW_RELEASE) return 0;
    int big = (mods & GLFW_MOD_SHIFT) ? 10 : 1;
    switch (key) {
    case GLFW_KEY_UP: case GLFW_KEY_W: move_sel(-1, 1); return 1;
    case GLFW_KEY_DOWN: case GLFW_KEY_S: move_sel(1, 1); return 1;
    case GLFW_KEY_PAGE_UP: move_sel(-1, 6); return 1;
    case GLFW_KEY_PAGE_DOWN: move_sel(1, 6); return 1;
    case GLFW_KEY_HOME: move_sel(-1, 1000); return 1;
    case GLFW_KEY_END: move_sel(1, 1000); return 1;
    case GLFW_KEY_LEFT: case GLFW_KEY_A: op(U.sel, OP_DELTA, (float)-big); return 1;
    case GLFW_KEY_RIGHT: case GLFW_KEY_D: op(U.sel, OP_DELTA, (float)big); return 1;
    case GLFW_KEY_ENTER: case GLFW_KEY_KP_ENTER: case GLFW_KEY_SPACE:
        if (action == GLFW_PRESS) op(U.sel, OP_ACTIVATE, 0);
        return 1;
    case GLFW_KEY_ESCAPE:
        if (action == GLFW_PRESS) ui_set_open(0);
        return 1;
    }
    return 0;
}

static int in_panel(double x, double y) { return x >= U.px && x <= U.px + U.pw && y >= U.py && y <= U.py + U.ph; }

static int row_at(double y) {
    if (y < U.list_y0 || y > U.list_y1) return -1;
    float ly = (float)y - U.list_y0 + U.scroll;
    for (int i = 0; i < U.nprev; i++)
        if (ly >= U.prev[i].y && ly < U.prev[i].y + U.prev[i].h) return i;
    return -1;
}

/* Horizontal geometry of a row's value area (also used to draw). */
static float inner_l(void) { return U.px + 22 * U.s; }
static float inner_r(void) { return U.px + U.pw - 22 * U.s; }
static float track_x0(void) { return inner_r() - 64 * U.s - 150 * U.s; }
static float track_x1(void) { return inner_r() - 64 * U.s; }

static float track_frac(double x) {
    float f = ((float)x - track_x0()) / (track_x1() - track_x0());
    return f < 0 ? 0 : f > 1 ? 1 : f;
}

int ui_on_cursor(double x, double y) {
    if (!ui_is_open()) return 0;
    U.mx = x;
    U.my = y;
    if (U.drag >= 0) {
        op(U.drag, OP_SET, track_frac(x));
        return 1;
    }
    if (!in_panel(x, y)) return 0;
    int r = row_at(y);
    if (r >= 0 && selectable(&U.prev[r])) U.sel = r;
    return 1;
}

int ui_on_button(int button, int action) {
    if (!ui_is_open()) return 0;
    if (action == GLFW_RELEASE) {
        int was = U.drag >= 0;
        U.drag = -1;
        return was || in_panel(U.mx, U.my);
    }
    if (!in_panel(U.mx, U.my)) return 0;
    if (button != GLFW_MOUSE_BUTTON_LEFT) return 1;
    int r = row_at(U.my);
    if (r < 0 || !selectable(&U.prev[r])) return 1;
    U.sel = r;
    switch (U.prev[r].type) {
    case IT_TOGGLE: case IT_BUTTON: op(r, OP_ACTIVATE, 0); break;
    case IT_CHOICE: { /* left half of the value: previous, otherwise next */
        float mid = inner_r() - text_w(F_BODY, U.prev[r].value) * 0.5f - 14 * U.s;
        op(r, OP_DELTA, U.mx < mid && U.mx > inner_r() - 200 * U.s ? -1.0f : 1.0f);
        break;
    }
    case IT_SLIDER:
        if (U.mx >= track_x0() - 10 * U.s) {
            U.drag = r;
            op(r, OP_SET, track_frac(U.mx));
        }
        break;
    }
    return 1;
}

int ui_on_scroll(double dy) {
    if (!ui_is_open() || !in_panel(U.mx, U.my)) return 0;
    U.scroll_target -= (float)dy * 80 * U.s;
    return 1;
}

/* ---------------------------------------------------------------- drawing */

typedef struct { float screen[4], clip[4]; } UiUniforms;

static void draw_row(const Item *it, int idx, float y) {
    float s = U.s, l = inner_l(), r = inner_r(), h = it->h;
    int sel = idx == U.sel;
    switch (it->type) {
    case IT_SECTION:
        text(F_HEAD, l, y + h - 12 * s, it->label, COL_ACCENT);
        return;
    case IT_TEXT: {
        float lw = text_w(F_SMALL, it->label);
        text_mid(F_SMALL, l, y, h, it->label, COL_DIM);
        char v[220];
        fit(F_SMALL, it->value, r - l - lw - 18 * s, v, sizeof v);
        text_mid(F_SMALL, r - text_w(F_SMALL, v), y, h, v, COL_DIM);
        return;
    }
    case IT_BUTTON: {
        Col bg = sel ? C(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 70) : C(255, 255, 255, 12);
        rect(l, y + 5 * s, r - l, h - 10 * s, 8 * s, bg);
        if (sel) rect(l, y + 5 * s, r - l, h - 10 * s, 8 * s, C(255, 255, 255, 10));
        float w = text_w(F_BODY, it->label);
        text_mid(F_BODY, (l + r - w) * 0.5f, y + 5 * s, h - 10 * s, it->label, COL_TEXT);
        return;
    }
    default:
        break;
    }
    char label[200];
    float value_w = it->type == IT_SLIDER ? (r - track_x0()) : it->type == IT_TOGGLE ? 46 * s
                  : text_w(F_BODY, it->value) + 40 * s;
    fit(F_BODY, it->label, r - l - value_w - 14 * s, label, sizeof label);
    text_mid(F_BODY, l, y, h, label, COL_TEXT);
    if (it->type == IT_TOGGLE) {
        float tw = 40 * s, th = 22 * s, tx = r - tw, ty = y + (h - th) * 0.5f;
        rect(tx, ty, tw, th, th * 0.5f, it->frac > 0.5f ? COL_ACCENT : COL_TRACK);
        circle(tx + (it->frac > 0.5f ? tw - th * 0.5f : th * 0.5f), ty + th * 0.5f, th * 0.5f - 3 * s, COL_KNOB);
    } else if (it->type == IT_CHOICE) {
        Col arrow = sel ? COL_ACCENT : C(COL_DIM.r, COL_DIM.g, COL_DIM.b, 120);
        float vw = text_w(F_BODY, it->value);
        text_mid(F_BODY, r - text_w(F_BODY, "›"), y, h, "›", arrow);
        text_mid(F_BODY, r - 16 * s - vw, y, h, it->value, sel ? COL_TEXT : COL_DIM);
        text_mid(F_BODY, r - 16 * s - vw - 10 * s - text_w(F_BODY, "‹"), y, h, "‹", arrow);
    } else if (it->type == IT_SLIDER) {
        float x0 = track_x0(), x1 = track_x1(), cy = y + h * 0.5f, f = it->frac;
        rect(x0, cy - 2 * s, x1 - x0, 4 * s, 2 * s, COL_TRACK);
        rect(x0, cy - 2 * s, (x1 - x0) * f, 4 * s, 2 * s, COL_ACCENT);
        if (sel) circle(x0 + (x1 - x0) * f, cy, 11 * s, C(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 60));
        circle(x0 + (x1 - x0) * f, cy, 7 * s, COL_KNOB);
        text_mid(F_BODY, r - text_w(F_BODY, it->value), y, h, it->value, sel ? COL_TEXT : COL_DIM);
    }
}

static void build_panel(void) {
    float s = U.s, a = U.anim;
    float slide = (1.0f - a) * -16 * s;
    float px = U.px + slide;
    /* panel */
    rect(px - 1, U.py - 1, U.pw + 2, U.ph + 2, 15 * s, COL_EDGE);
    rect(px, U.py, U.pw, U.ph, 14 * s, COL_PANEL);
    text(F_TITLE, px + 22 * s, U.py + 36 * s, U.title, COL_TEXT);
    char sub[320];
    fit(F_SMALL, U.subtitle, U.pw - 44 * s, sub, sizeof sub);
    text(F_SMALL, px + 22 * s, U.py + 60 * s, sub, COL_DIM);
    rect(px + 22 * s, U.list_y0 - 8 * s, U.pw - 44 * s, 1, 0, C(255, 255, 255, 22));
    rect(px + 22 * s, U.list_y1 + 6 * s, U.pw - 44 * s, 1, 0, C(255, 255, 255, 22));
    int arrows = has_glyph(F_SMALL, 0x2191) && has_glyph(F_SMALL, 0x2190);
    const char *hint = arrows ? "↑↓ select   ←→ change   Enter toggle   Esc close"
                              : "Arrows: select, change   Enter: toggle   Esc: close";
    if (text_w(F_SMALL, hint) > U.pw - 44 * s) hint = arrows ? "↑↓  ←→  Enter  Esc" : "Arrows  Enter  Esc";
    text_mid(F_SMALL, px + 22 * s, U.list_y1 + 6 * s, U.py + U.ph - U.list_y1 - 6 * s, hint, COL_DIM);
    /* scroll bar */
    float view = U.list_y1 - U.list_y0;
    if (U.content_h > view + 1) {
        float th = fmaxf(view * view / U.content_h, 24 * s);
        float ty = U.list_y0 + (view - th) * (U.scroll / (U.content_h - view));
        rect(px + U.pw - 9 * s, ty, 3 * s, th, 1.5f * s, C(255, 255, 255, 40));
    }
    U.nv_fixed = U.nv;
    /* rows (clipped to the list) */
    if (U.sel < U.nitems && selectable(&U.items[U.sel])) {
        const Item *it = &U.items[U.sel];
        float target = it->y;
        if (fabsf(U.sel_anim - target) > 400 * s) U.sel_anim = target;
        float y = U.list_y0 + U.sel_anim - U.scroll;
        rect(px + 12 * s, y + 2 * s, U.pw - 24 * s, it->h - 4 * s, 9 * s, COL_SEL);
        rect(px + 12 * s, y + 9 * s, 3 * s, it->h - 18 * s, 1.5f * s, COL_ACCENT);
    }
    for (int i = 0; i < U.nitems; i++) {
        float y = U.list_y0 + U.items[i].y - U.scroll;
        if (y + U.items[i].h < U.list_y0 || y > U.list_y1) continue;
        float save = U.px;
        U.px = px;
        draw_row(&U.items[i], i, y);
        U.px = save;
    }
}

static void build_hint(float alpha) {
    float s = fmaxf(1.0f, fminf(3.0f, (float)U.fb_h / 1080.0f));
    const char *label = "Settings";
    float kw = text_w(F_HEAD, "F1") + 16 * s, lw = text_w(F_SMALL, label);
    float w = kw + lw + 30 * s, h = 34 * s, x = 20 * s, y = (float)U.fb_h - h - 20 * s;
    Col bg = COL_PANEL, key = C(255, 255, 255, 230), ink = COL_TEXT;
    bg.a = (unsigned char)(bg.a * alpha * 0.9f);
    key.a = (unsigned char)(key.a * alpha);
    ink.a = (unsigned char)(ink.a * alpha);
    rect(x, y, w, h, h * 0.5f, bg);
    rect(x + 8 * s, y + 6 * s, kw, h - 12 * s, 6 * s, key);
    text_mid(F_HEAD, x + 16 * s, y + 6 * s, h - 12 * s, "F1", C(14, 16, 22, (int)(255 * alpha)));
    text_mid(F_SMALL, x + kw + 18 * s, y, h, label, ink);
}

void ui_draw(GfxTex *dst, int w, int h, float dt) {
    if (!U.ok) return;
    U.fb_w = w;
    U.fb_h = h;
    U.anim = U.open ? fminf(1.0f, U.anim + dt * 9.0f) : fmaxf(0.0f, U.anim - dt * 9.0f);
    U.hint_t += dt;
    float hint = U.open ? 0.0f : fminf(1.0f, fmaxf(0.0f, (7.0f - U.hint_t) / 1.5f));
    if (U.anim <= 0 && hint <= 0) return;

    float s = U.anim > 0 ? U.s : fmaxf(1.0f, fminf(3.0f, (float)h / 1080.0f));
    if (!U.atlas || s != U.built_scale) build_atlas(s);
    if (!U.atlas) return;
    float k = fminf(1.0f, dt * 18.0f);
    U.scroll += (U.scroll_target - U.scroll) * k;
    if (U.sel < U.nitems) U.sel_anim += (U.items[U.sel].y - U.sel_anim) * fminf(1.0f, dt * 22.0f);

    U.nv = U.nv_fixed = 0;
    if (U.anim > 0) build_panel();
    else build_hint(hint);
    int fixed = U.anim > 0 ? U.nv_fixed : U.nv;

    GfxPass pass = {.color = dst};
    gfx->begin_pass(&pass);
    float flip = (!dst && gfx->flip_y()) ? 1.0f : 0.0f;
    float alpha = U.anim > 0 ? U.anim * U.anim * (3 - 2 * U.anim) : 1.0f;
    UiUniforms u = {{(float)w, (float)h, flip, alpha}, {0, 0, (float)w, (float)h}};
    GfxDraw d = {.prog = U.prog, .ubo = &u, .ubo_size = sizeof u, .tex = {U.atlas}, .filter = {GFX_LINEAR},
                 .vdata = U.v, .count = fixed, .blend = GFX_BLEND_ALPHA};
    if (fixed > 0) gfx->draw(&d);
    if (U.nv > fixed) {
        UiUniforms lu = u;
        lu.clip[0] = U.px - 20 * U.s;
        lu.clip[1] = U.list_y0;
        lu.clip[2] = U.px + U.pw + 20 * U.s;
        lu.clip[3] = U.list_y1;
        d.ubo = &lu;
        d.vdata = U.v + fixed;
        d.count = U.nv - fixed;
        gfx->draw(&d);
    }
    gfx->end_pass();
}
