// SPDX-License-Identifier: MIT
/* Background image writer for offline rendering: PNG (libpng) or PPM. */
#ifndef IMGOUT_H
#define IMGOUT_H

enum { IMG_PNG, IMG_PPM };

typedef struct ImgWriter ImgWriter;

ImgWriter *imgw_create(int threads, int max_queued);
/* Takes ownership of `path` and `rgba` (both malloc'd).  rgba is w*h RGBA8
 * with the bottom row first (as read back from the GPU).  Blocks while the
 * queue is full. */
void imgw_push(ImgWriter *w, char *path, unsigned char *rgba, int width, int height, int fmt);
/* Waits for every queued image, then frees the writer.  Returns the number
 * of images that failed to write. */
int imgw_finish(ImgWriter *w);

int img_format_from_name(const char *name); /* by extension; PNG unless .ppm */

#endif
