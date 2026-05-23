/*
 * memstress: write-heavy single-threaded micro-workload for cache experiments.
 *
 * Allocates a buffer larger than L2 so that writes hit L3 (or miss to DRAM
 * after warmup). Performs ITERS passes of strided writes followed by a
 * read-reduce so the writes are not dead code.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BUF_BYTES (32 * 1024 * 1024)   /* 32 MB > L3 (16 MB): forces L3 misses
                                          and frequent DRAM writebacks, stressing
                                          the writeBuffer / write-latency path. */
#define ITERS     4

int main(void) {
    volatile unsigned char *buf = (unsigned char *)malloc(BUF_BYTES);
    if (!buf) {
        fputs("alloc failed\n", stderr);
        return 1;
    }

    /* Initialize so that the buffer is resident. */
    memset((void *)buf, 0, BUF_BYTES);

    unsigned long long acc = 0;
    for (int it = 0; it < ITERS; ++it) {
        /* Write pass: stride 64 (cache-line) writes, ~16 K writes per pass. */
        for (int i = 0; i < BUF_BYTES; i += 64) {
            buf[i] = (unsigned char)(it + i);
        }
        /* Read-reduce pass to defeat DCE. */
        for (int i = 0; i < BUF_BYTES; i += 64) {
            acc += buf[i];
        }
    }

    printf("memstress done: acc=%llu\n", acc);
    free((void *)buf);
    return 0;
}
