// SPDX-License-Identifier: MIT
#include "plat.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <direct.h>
#include <mmsystem.h>
#ifndef CREATE_WAITABLE_TIMER_HIGH_RESOLUTION
#define CREATE_WAITABLE_TIMER_HIGH_RESOLUTION 0x00000002
#endif
#else
#include <time.h>
#include <unistd.h>
#endif

#ifdef _WIN32

static LARGE_INTEGER g_freq;
static HANDLE g_timer;

static void restore_timer_resolution(void) { timeEndPeriod(1); }

void plat_init(void) {
    /* A console program: started from Explorer it gets a console window of
     * its own, which only shows the log.  Hide that one; a console it shares
     * with a shell (cmd, PowerShell, a terminal) stays as it is. */
    DWORD procs[2];
    if (GetConsoleWindow() && GetConsoleProcessList(procs, 2) == 1) ShowWindow(GetConsoleWindow(), SW_HIDE);
    QueryPerformanceFrequency(&g_freq);
    /* High-resolution waitable timer (Windows 10 1803+); otherwise Sleep()
     * with 1 ms scheduler granularity. */
    g_timer = CreateWaitableTimerExW(NULL, NULL, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS);
    if (!g_timer) {
        timeBeginPeriod(1);
        atexit(restore_timer_resolution);
    }
}

double plat_time(void) {
    LARGE_INTEGER c;
    if (!g_freq.QuadPart) QueryPerformanceFrequency(&g_freq);
    QueryPerformanceCounter(&c);
    return (double)c.QuadPart / (double)g_freq.QuadPart;
}

void plat_sleep_until(double t) {
    double wait = t - plat_time() - 0.0015; /* sleep most of the way, spin the rest */
    if (wait > 0) {
        if (g_timer) {
            LARGE_INTEGER due;
            due.QuadPart = -(LONGLONG)(wait * 1e7); /* relative, in 100 ns units */
            if (SetWaitableTimer(g_timer, &due, 0, NULL, NULL, FALSE)) WaitForSingleObject(g_timer, INFINITE);
        } else {
            Sleep((DWORD)(wait * 1000.0));
        }
    }
    while (plat_time() < t) YieldProcessor();
}

int plat_cpu_count(void) {
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    return si.dwNumberOfProcessors > 0 ? (int)si.dwNumberOfProcessors : 1;
}

static int make_dir(const char *p) { return !_mkdir(p) || errno == EEXIST; }

int plat_exe_dir(char *out, size_t n) {
    char exe[MAX_PATH];
    DWORD len = GetModuleFileNameA(NULL, exe, sizeof exe);
    if (!len || len >= sizeof exe) return 0;
    for (char *c = exe; *c; c++)
        if (*c == '\\') *c = '/';
    char *slash = strrchr(exe, '/');
    if (slash) *slash = 0;
    snprintf(out, n, "%s", exe);
    return 1;
}

#else /* POSIX */

void plat_init(void) {}

double plat_time(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

void plat_sleep_until(double t) {
    double until = t - 0.001; /* sleep most of the way, spin the rest */
    if (until - plat_time() > 0.0005) {
        struct timespec ts = {(time_t)until, (long)((until - (double)(time_t)until) * 1e9)};
        while (clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &ts, NULL) == EINTR) {}
    }
    while (plat_time() < t) {}
}

int plat_cpu_count(void) {
    long n = sysconf(_SC_NPROCESSORS_ONLN);
    return n > 0 ? (int)n : 1;
}

static int make_dir(const char *p) { return !mkdir(p, 0755) || errno == EEXIST; }

int plat_exe_dir(char *out, size_t n) {
    char exe[1024];
    ssize_t len = readlink("/proc/self/exe", exe, sizeof exe - 1);
    if (len <= 0) return 0;
    exe[len] = 0;
    char *slash = strrchr(exe, '/');
    if (slash) *slash = 0;
    snprintf(out, n, "%s", exe);
    return 1;
}

#endif

int plat_mkdir_p(const char *path) {
    char tmp[1024];
    snprintf(tmp, sizeof tmp, "%s", path);
    for (char *p = tmp + 1; *p; p++)
        if (*p == '/' || *p == '\\') {
            char c = *p;
            *p = 0;
            if (!(p > tmp && p[-1] == ':') && !make_dir(tmp)) return 0; /* skip "C:" */
            *p = c;
        }
    return make_dir(tmp);
}

int plat_is_file(const char *path) {
    struct stat st;
    return !stat(path, &st) && (st.st_mode & S_IFMT) == S_IFREG;
}
