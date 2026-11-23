// SPDX-License-Identifier: MIT
#include "imgout.h"

#include <png.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

typedef struct {
    char *path;
    unsigned char *rgba;
    int w, h, fmt;
} Job;

struct ImgWriter {
    pthread_mutex_t mu;
    pthread_cond_t can_push, can_pop;
    Job *q;
    int cap, head, count, done, failed;
    pthread_t *threads;
    int nthreads;
};

static int write_ppm(const Job *j) {
    FILE *f = fopen(j->path, "wb");
    if (!f) return 0;
    fprintf(f, "P6\n%d %d\n255\n", j->w, j->h);
    unsigned char *row = malloc((size_t)j->w * 3);
    for (int y = j->h - 1; y >= 0; y--) {
        const unsigned char *s = j->rgba + (size_t)y * (size_t)j->w * 4;
        for (int x = 0; x < j->w; x++) memcpy(row + x * 3, s + x * 4, 3);
        fwrite(row, 3, (size_t)j->w, f);
    }
    free(row);
    return fclose(f) == 0;
}

static int write_png(const Job *j) {
    FILE *f = fopen(j->path, "wb");
    if (!f) return 0;
    png_structp png = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    png_infop info = png ? png_create_info_struct(png) : NULL;
    if (!info || setjmp(png_jmpbuf(png))) {
        png_destroy_write_struct(&png, &info);
        fclose(f);
        return 0;
    }
    png_init_io(png, f);
    png_set_compression_level(png, 3); /* fast; frames are usually re-encoded anyway */
    png_set_IHDR(png, info, (png_uint_32)j->w, (png_uint_32)j->h, 8, PNG_COLOR_TYPE_RGB, PNG_INTERLACE_NONE,
                 PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);
    png_write_info(png, info);
    png_set_filler(png, 0, PNG_FILLER_AFTER); /* drop the alpha byte */
    for (int y = j->h - 1; y >= 0; y--) png_write_row(png, j->rgba + (size_t)y * (size_t)j->w * 4);
    png_write_end(png, NULL);
    png_destroy_write_struct(&png, &info);
    return fclose(f) == 0;
}

static void *worker(void *arg) {
    ImgWriter *w = arg;
    for (;;) {
        pthread_mutex_lock(&w->mu);
        while (!w->count && !w->done) pthread_cond_wait(&w->can_pop, &w->mu);
        if (!w->count && w->done) {
            pthread_mutex_unlock(&w->mu);
            return NULL;
        }
        Job j = w->q[w->head];
        w->head = (w->head + 1) % w->cap;
        w->count--;
        pthread_cond_signal(&w->can_push);
        pthread_mutex_unlock(&w->mu);

        int ok = j.fmt == IMG_PPM ? write_ppm(&j) : write_png(&j);
        if (!ok) {
            fprintf(stderr, "could not write %s\n", j.path);
            pthread_mutex_lock(&w->mu);
            w->failed++;
            pthread_mutex_unlock(&w->mu);
        }
        free(j.path);
        free(j.rgba);
    }
}

ImgWriter *imgw_create(int threads, int max_queued) {
    ImgWriter *w = calloc(1, sizeof *w);
    pthread_mutex_init(&w->mu, NULL);
    pthread_cond_init(&w->can_push, NULL);
    pthread_cond_init(&w->can_pop, NULL);
    w->cap = max_queued > 0 ? max_queued : 1;
    w->q = calloc((size_t)w->cap, sizeof *w->q);
    w->nthreads = threads > 0 ? threads : 1;
    w->threads = calloc((size_t)w->nthreads, sizeof *w->threads);
    for (int i = 0; i < w->nthreads; i++) pthread_create(&w->threads[i], NULL, worker, w);
    return w;
}

void imgw_push(ImgWriter *w, char *path, unsigned char *rgba, int width, int height, int fmt) {
    pthread_mutex_lock(&w->mu);
    while (w->count == w->cap) pthread_cond_wait(&w->can_push, &w->mu);
    w->q[(w->head + w->count) % w->cap] = (Job){path, rgba, width, height, fmt};
    w->count++;
    pthread_cond_signal(&w->can_pop);
    pthread_mutex_unlock(&w->mu);
}

int imgw_finish(ImgWriter *w) {
    pthread_mutex_lock(&w->mu);
    w->done = 1;
    pthread_cond_broadcast(&w->can_pop);
    pthread_mutex_unlock(&w->mu);
    for (int i = 0; i < w->nthreads; i++) pthread_join(w->threads[i], NULL);
    int failed = w->failed;
    pthread_mutex_destroy(&w->mu);
    pthread_cond_destroy(&w->can_push);
    pthread_cond_destroy(&w->can_pop);
    free(w->q);
    free(w->threads);
    free(w);
    return failed;
}

int img_format_from_name(const char *name) {
    const char *dot = strrchr(name, '.');
    return dot && !strcasecmp(dot, ".ppm") ? IMG_PPM : IMG_PNG;
}
