// SPDX-License-Identifier: MIT
/*
 * The F1 menu: an immediate-mode list of settings that works with the
 * keyboard (arrows / WASD, Enter, Esc) and the mouse (hover, click, drag,
 * wheel), drawn over the frame through gfx.  Text is rasterised from the
 * TrueType fonts in assets/fonts with stb_truetype.
 */
#ifndef UI_H
#define UI_H

#include "gfx.h"

int ui_init(const char *font_dir); /* 0: fonts missing, the menu is unavailable */
void ui_shutdown(void);
int ui_available(void);
void ui_set_open(int open);
int ui_is_open(void);

/* Input, positions in framebuffer pixels.  1 when the menu used the event. */
int ui_on_key(int key, int action, int mods);
int ui_on_button(int button, int action);
int ui_on_cursor(double x, double y);
int ui_on_scroll(double dy);

/* Building the menu: once per frame while it is open.  The widgets return 1
 * when the user changed the value in this frame. */
void ui_begin(int fb_w, int fb_h, float dt, const char *title, const char *subtitle);
void ui_section(const char *title);
int ui_choice(const char *label, int *v, const char *const *options, int n);
int ui_toggle(const char *label, int *v);
int ui_slider(const char *label, float *v, float lo, float hi, float step, const char *fmt);
int ui_islider(const char *label, int *v, int lo, int hi, int step);
int ui_button(const char *label);
void ui_text(const char *label, const char *value);
void ui_end(void);

/* Draws the menu, or the "F1" hint when it is closed, into dst (NULL: the
 * window).  Inside a frame, outside passes. */
void ui_draw(GfxTex *dst, int w, int h, float dt);

#endif
