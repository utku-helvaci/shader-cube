// SPDX-License-Identifier: MIT
/* The few operating-system services shader-cube needs beyond C and GLFW:
 * Linux (POSIX) and Windows. */
#ifndef PLAT_H
#define PLAT_H

#include <stddef.h>

void plat_init(void);                  /* once, at start-up */
double plat_time(void);                /* seconds on a monotonic clock */
void plat_sleep_until(double t);       /* returns at plat_time() >= t, sleeping most of the way */
int plat_cpu_count(void);
int plat_mkdir_p(const char *path);    /* 1 on success, also if it already exists */
int plat_is_file(const char *path);
int plat_exe_dir(char *out, size_t n); /* directory of the executable, '/'-separated; 0 on failure */

#endif
