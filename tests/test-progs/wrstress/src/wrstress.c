/*
 * wrstress: write-RATIO-parametrized memory stress micro-workload.
 *
 * Purpose (Task: write-intensive L3 study): sweep the store fraction to find the
 * point where L3 write latency (e.g. SOT wl=22 vs STT wl=35) stops being hidden.
 *
 * Usage:
 *   wrstress <size_mb> <iters> <write_pct>
 *     size_mb   buffer size in MB (default 16). Pick >> per-core L3 share so the
 *               buffer thrashes L3 and dirty L2->L3 writebacks dominate.
 *     iters     passes over the buffer (default 100000). In gem5 we bound the run
 *               with -I/--max-insts, so iters is set large and the cap is the limiter
 *               (=> identical instruction count across every write_pct point).
 *     write_pct 0..100: fraction of cache-line accesses that are STORES (default 50).
 *
 * Each pass strides the buffer at 64 B (one cache line). For each line an even
 * (Bresenham) schedule chooses store-vs-load so exactly write_pct% are stores,
 * uniformly interleaved (not clustered). `buf` is volatile so stores are real side
 * effects (never dead-code-eliminated); loads accumulate into a printed sum.
 *
 * Static, libc-only, no threads/syscalls beyond malloc/printf -> clean under gem5 SE.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    size_t mb   = (argc > 1 && atoi(argv[1]) > 0) ? (size_t)atoi(argv[1]) : 16;
    long   iters = (argc > 2 && atol(argv[2]) > 0) ? atol(argv[2]) : 100000;
    int    wpct = 50;
    if (argc > 3) { int v = atoi(argv[3]); if (v < 0) v = 0; if (v > 100) v = 100; wpct = v; }

    size_t bytes = mb * (size_t)1024 * 1024;
    volatile unsigned char *buf = (unsigned char *)malloc(bytes);
    if (!buf) { fputs("alloc failed\n", stderr); return 1; }
    memset((void *)buf, 0, bytes);              /* make buffer resident */

    unsigned long long sum = 0, stores = 0, loads = 0;
    for (long it = 0; it < iters; ++it) {
        int acc = 0;                            /* Bresenham accumulator */
        for (size_t i = 0; i < bytes; i += 64) {
            acc += wpct;
            if (acc >= 100) {                   /* STORE this line */
                acc -= 100;
                buf[i] = (unsigned char)(it + i);
                stores++;
            } else {                            /* LOAD this line */
                sum += buf[i];
                loads++;
            }
        }
    }
    printf("wrstress done: size=%zuMB iters=%ld write_pct=%d stores=%llu loads=%llu sum=%llu\n",
           mb, iters, wpct, stores, loads, sum);
    free((void *)buf);
    return 0;
}
