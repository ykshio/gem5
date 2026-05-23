# Round-2 F: WS=4MB analysis

## Stats summary (memstress 4MB, 12.7% miss = 87.3% L3 hit)

L3 demand miss rate = 0.127 (87.3% hit rate) → **mixed regime**, exactly the
condition we wanted to refute the "writeback hiding requires 100% miss" theory.

## F-1/F-2: wlat × write_buffers grid

| config        | rlat | wlat | bufs | simTicks [s] | CPI   |
|---------------|-----:|-----:|-----:|-------------:|------:|
| sram_buf16    |   40 |   40 |   16 | 64.529       | 23.51 |
| mram35_buf16  |   10 |   35 |   16 | 48.824       | 17.79 |
| mram50_buf16  |   10 |   50 |   16 | 48.824       | 17.79 |
| sram_buf4     |   40 |   40 |    4 | 64.529       | 23.51 |
| mram35_buf4   |   10 |   35 |    4 | 48.824       | 17.79 |
| mram50_buf4   |   10 |   50 |    4 | 48.824       | 17.79 |

**2×2 refutation grid (wlat × write_buffers, MRAM read rlat=10 fixed):**

|              | wlat=35    | wlat=50    | Δ wlat 35→50 |
|--------------|-----------:|-----------:|-------------:|
| buffers=16   | 48.824 G   | 48.824 G   | **0 (none)** |
| buffers=4    | 48.824 G   | 48.824 G   | **0 (none)** |
| Δ bufs 16→4  | 0          | 0          |              |

→ **writeback hiding hypothesis CONFIRMED also under mixed hit/miss (WS=4MB)**:
   - wlat 35 vs 50: identical simTicks
   - buffers 16 vs 4: identical simTicks
   - Robust across two regimes (32MB all-miss + 4MB mixed-hit): MRAM L3
     write penalty is structurally hidden.

## F-rlat: L3 read latency isolation (wlat=40 fixed)

| config         | rlat | wlat | simTicks [s] | CPI   |
|----------------|-----:|-----:|-------------:|------:|
| rlat10_wlat40  |   10 |   40 | 48.824       | 17.79 |
| rlat40_wlat40  |   40 |   40 | 64.529       | 23.51 |

→ **L3 read latency is FULLY EXPOSED**:
   - rlat 10→40: simTicks +32.2% / CPI +32.2%
   - This is the read-benefit story for MRAM L3.

**Headline**: MRAM L3 (10/35) vs SRAM L3 (40/40) → **1.32× faster** with
identical hit rate.

## Energy (Everspin: Erd=25.872 nJ, Ewr=97.020 nJ; SRAM 0.05 nJ illustrative)

L3 array reads  = `system.l3.overallHits::total`              = 458,804
L3 array writes = `system.l3.WritebackDirty.hits::total`     = 520,613
(WS=4MB fits in L3 so `system.l3.writebacks::total` is absent — no eviction)

| tech | E_L3 [mJ] |
|------|----------:|
| SRAM | 0.049     |
| MRAM | **62.4**  |

→ MRAM L3 burns ~62 mJ on this workload vs ~0.05 mJ for SRAM — **1273×
more energy** even though it runs 1.32× FASTER. "Writeback hiding"
collapses the time cost; the per-write energy cost is fully counted.

## Three-line thesis takeaway

1. MRAM L3 write penalty is structurally hidden (writeback fire-and-forget),
   robust across WS regimes and write-buffer depth.
2. MRAM L3 read benefit (Read 10 vs SRAM 40) is fully exposed → **1.32× speedup**.
3. Cost: ~1273× more dynamic write energy. Net evaluation requires adding
   MRAM leakage savings (static power) to be fair.
