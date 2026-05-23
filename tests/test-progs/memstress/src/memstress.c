/*
 * memstress: write-heavy single-threaded micro-workload for cache experiments.
 *
 * Allocates a buffer of the requested size and performs ITERS passes of
 * strided writes followed by a read-reduce so the writes are not dead code.
 *
 * Usage:
 *   memstress                        -> 32 MB,  4 iters (defaults)
 *   memstress <size_mb>              -> <size_mb> MB,  4 iters
 *   memstress <size_mb> <iters>      -> <size_mb> MB, <iters> iters
 *
 * Typical sizes:
 *    4   -> fits in L3 16MB, mixed L3 hit/miss after warmup
 *   32   -> exceeds L3, 100% L3 miss + frequent writebacks toward DRAM
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DEFAULT_MB    32
#define DEFAULT_ITERS  4

int main(int argc, char **argv) {
    size_t mb = DEFAULT_MB;
    int iters = DEFAULT_ITERS;
    if (argc > 1) {
        int v = atoi(argv[1]);
        if (v > 0) mb = (size_t)v;
    }
    if (argc > 2) {
        int v = atoi(argv[2]);
        if (v > 0) iters = v;
    }
    size_t buf_bytes = mb * (size_t)1024 * 1024;

    volatile unsigned char *buf = (unsigned char *)malloc(buf_bytes);
    if (!buf) {
        fputs("alloc failed\n", stderr);
        return 1;
    }
    /* Initialize so that the buffer is resident. */
    memset((void *)buf, 0, buf_bytes);

    unsigned long long acc = 0;
    for (int it = 0; it < iters; ++it) {
        /* Write pass: stride 64 (cache-line) writes. */
        for (size_t i = 0; i < buf_bytes; i += 64) {
            buf[i] = (unsigned char)(it + i);
        }
        /* Read-reduce pass to defeat DCE. */
        for (size_t i = 0; i < buf_bytes; i += 64) {
            acc += buf[i];
        }
    }

    printf("memstress done: size=%zuMB iters=%d acc=%llu\n",
           mb, iters, acc);
    free((void *)buf);
    return 0;
}
