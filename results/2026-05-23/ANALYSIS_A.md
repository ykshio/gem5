# Round-4 A: L2 MRAM sweep (memstress WS=4MB)

L1 SRAM (4/4) と L3 SRAM (40/40) を固定し、L2 を 4 構成で sweep。

| config | rlat | wlat | simTicks [s] | CPI | L2 hits | L2 misses | L2 wb_in |
|---|---:|---:|---:|---:|---:|---:|---:|
| sram_14_14 | 14 | 14 | **64.53** | **23.51** | 41 | 525,641 | 262,318 |
| stt_7_25   |  7 | 25 | 60.80 | 22.15 | 41 | 525,641 | 262,318 |
| stt_7_35   |  7 | 35 | 60.80 | 22.15 | 41 | 525,641 | 262,318 |
| sot_7_18   |  7 | 18 | 60.80 | 22.15 | 41 | 525,641 | 262,318 |

## 観測事項

1. **L2 MRAM (rlat=7) は SRAM (rlat=14) より 5.8% 高速** (64.53 → 60.80 s)
2. **L2 でも writeback 隠蔽が再現**: wlat 18 / 25 / 35 で simTicks 完全一致 (60.80 s)
   → L3 と同じ構造的帰結 (writeback fire-and-forget)
3. L2 hits = 41 のみ → 4MB workload では L2 はほぼ完全に miss し、L3 行きが大半。
   それでも rlat 短縮の効果は L2 を経由する全パケットに作用する

## 修論への含意

§5 考察の構成提案表が完成:

| level | 推奨 | 根拠 |
|---|---|---|
| L1   | SRAM | H (1.08× 遅い + 1166× エネルギー) |
| L2   | MRAM | **A (5.8% 速い + writeback 隠蔽再現)** ← NEW |
| L3   | MRAM | R1 + F + J (1.32× 速い + leakage 込み 4-6× 削減) |
| Main | 要検証 | N 予備調査、NVMain 統合は別途 |

L2/L3 で writeback 隠蔽が **両方とも再現** したため、「キャッシュ階層の write-allocate
+ writeback fire-and-forget」がメカニズム的に同質であることが裏付けられた。
