# Round-4 C: long-sim leakage scaling (memstress WS=4MB, ITERS sweep)

memstress を ITERS 4 / 25 / 50 で実行し、SRAM L3 (40/40) と STT-MRAM L3 (10/35) を
比較。長時間 workload で leakage 比例優位が拡大するかを確認。

| tech | iters | simTicks [s] | CPI | L3 hits | L3 wb_in |
|------|------:|-------------:|----:|--------:|---------:|
| SRAM |     4 |   64.53      | 23.51 |   458,802 |   520,612 |
| MRAM |     4 |   48.83      | 17.79 |   458,802 |   520,612 |
| SRAM |    25 |  372.81      | 22.58 | 3,211,314 | 3,273,124 |
| MRAM |    25 |  274.53      | 16.63 | 3,211,314 | 3,273,124 |
| SRAM |    50 |  739.82      | 22.49 | 6,488,114 | 6,549,924 |
| MRAM |    50 |  543.23      | 16.52 | 6,488,114 | 6,549,924 |

## Speed: ratio は iters によらず一定

| iters | speedup (SRAM/MRAM) |
|------:|--------------------:|
|     4 |  1.32×  |
|    25 |  1.36×  |
|    50 |  1.36×  |

→ 走行時間 12.5× に延びても speed advantage は安定 (1.32〜1.36×)。

## Energy (Erd/Ewr from PARAMS.md + P_leak from PARAMS_leakage.md)

| iters | tech | E_dyn [mJ] | E_leak [mJ] | E_total [mJ] | MRAM/SRAM |
|------:|------|-----------:|------------:|-------------:|----------:|
|     4 | SRAM |       0.05 |      322.65 |       322.70 |           |
|     4 | MRAM |      62.38 |        9.77 |        72.15 |  **0.224×** |
|    25 | SRAM |       0.32 |     1864.04 |      1864.36 |           |
|    25 | MRAM |     400.27 |       54.91 |       455.18 |  0.244×   |
|    50 | SRAM |       0.65 |     3699.10 |      3699.75 |           |
|    50 | MRAM |     803.30 |      108.65 |       911.95 |  0.246×   |

(計算式: `compute_total_energy.py` 参照、SRAM E_dyn は SRAM 0.05 nJ/access で再計算)

## 観測事項

1. **MRAM 優位は workload 長によらず ~4× 安定** (24% / 24% / 25%)
2. SRAM の総エネルギーは **99.98% が leakage**: dynamic はほぼ寄与しない
3. MRAM の総エネルギーは leakage 15% / dynamic 85% → workload が長いほど dynamic 比率増
4. **「workload を伸ばすほど MRAM の絶対 mJ 差は拡大する」**:
    - iters=4:  差 = 322 - 72 = 250 mJ
    - iters=50: 差 = 3700 - 912 = 2788 mJ (**11× 拡大**)
5. SRAM:MRAM 比は一定でも、**絶対量** (data center 電力で重要) は線形に拡大

## 修論への含意

- §4.4 leakage 込み総エネルギーを **3 点** で示せる (4/25/50 iters)
- 「MRAM 優位は短時間 microbench に依存しない」が定量化
- 図 11 (`figures/long_sim_leakage.png`): iters 軸 vs total energy (両 tech)
- 発表での FAQ「microbench は短すぎないか」への即応: **長くしても MRAM が勝つ**

## キャッチコピー案

「SRAM L3 は時間ごとに 5W のリーク電力を burn し続ける。MRAM L3 は 0.2W。
1 秒の workload で 4.8 J、1 時間で 17 kJ、データセンタ規模では年間メガジュール。」
