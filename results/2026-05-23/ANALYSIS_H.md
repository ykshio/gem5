# Round-2 H: L1 SRAM vs MRAM head-to-head on cachewrite

Same workload (cachewrite, 16KB buffer × 200 passes, L1-resident).
Both L1 caches use the same size / associativity / hit rate; only the
data array timing and energy parameters differ.

| config        | rlat | wlat | simTicks [s] | CPI  | rd_hits | rd_miss | wr_hits | wr_miss |
|---------------|-----:|-----:|-------------:|-----:|--------:|--------:|--------:|--------:|
| L1 SRAM (4/4) |    4 |    4 | 3.403        | 7.93 | 67,901  | 749     | 55,661  | 421     |
| L1 MRAM (3/10)|    3 |   10 | 3.670        | 8.55 | 67,901  | 749     | 55,661  | 421     |

(Workload is timing-deterministic so access counts are identical.)

## Energy (per-access values from PARAMS.md)

L1D reads  = ReadReq.hits + ReadReq.misses = **68,650**
L1D writes = WriteReq.hits + WriteReq.misses = **56,082**

| config   | tech | Erd [nJ] | Ewr [nJ] | E_L1 [mJ] | ratio vs SRAM |
|----------|------|---------:|---------:|----------:|--------------:|
| L1 SRAM  | SRAM |     0.05 |     0.05 | 0.0062    | 1.00×         |
| L1 MRAM  | MRAM |   25.872 |   97.020 | 7.2172    | **1166×**     |

## Speed × energy verdict
- L1 MRAM is **7.8% slower** (3.670 / 3.403 ≈ 1.078)
- L1 MRAM consumes **~1166× more energy** on cache accesses
- **L1 MRAM is unviable** on both axes.

## One-liner for the slide
"L1 を MRAM にすると 1.08× 遅く、1166× エネルギーを消費する。
 L1 は SRAM のままが正しい設計判断。"

## Why this matters for the thesis
Pairs with Round-2 F to argue L3 is the right level for MRAM:
- L1 MRAM: bad on both axes (this analysis).
- L3 MRAM: invisible write penalty (F), exposed read benefit (F-rlat).
- **MRAM belongs in the last-level cache.**
