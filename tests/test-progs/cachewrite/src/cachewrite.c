/*
 * cachewrite: L1-resident write-heavy micro-test for validating that the
 * BaseCache write_latency parameter actually charges write hits on the
 * data array. Buffer fits well inside L1D (16 KB << 32 KB) and the
 * inner loop interleaves write+read on the same cache line so every
 * iteration after the first exercises the L1 write-hit path.
 *
 * If write_latency on L1D affects simTicks here, the asymmetric-latency
 * implementation in BaseCache is wired up correctly.
 */
#include <stdio.h>
#include <stdlib.h>

#define BUF_BYTES (16 * 1024)
#define ITERS     200

int main(void) {
    volatile unsigned char *buf = (unsigned char *)malloc(BUF_BYTES);
    if (!buf) {
        fputs("alloc failed\n", stderr);
        return 1;
    }
    for (int i = 0; i < BUF_BYTES; i += 64) {
        buf[i] = 0;
    }

    unsigned long long acc = 0;
    for (int it = 0; it < ITERS; ++it) {
        for (int i = 0; i < BUF_BYTES; i += 64) {
            buf[i] = (unsigned char)(it + i);
            acc += buf[i];
        }
    }

    printf("cachewrite done: acc=%llu\n", acc);
    free((void *)buf);
    return 0;
}
