# Round-3 N: main memory DRAM vs MRAM preliminary sketch

⚠ **予備調査**: gem5 `SimpleMemory` を使った flat-latency 近似。Read/Write
非対称や DRAM チャネル/ランク/バンク構造は反映されない。本格評価は
NVMain 統合後 (6/10 発表後 〜 修論本体) に再実施。

## Setup

| param | value |
|---|---|
| Main memory model | `SimpleMemory` |
| latency configs | 100 ns (DRAM-proxy), 200 ns (MRAM avg of 100/300), 300 ns (MRAM slow) |
| L1/L2/L3 | SRAM defaults from `se_mram_l3.py` |
| workloads | cachewrite (L1-resident), memstress 4MB (mixed L3 hit/miss) |

## cachewrite (L1-resident, main memory rarely touched)

| config           | main_lat | simTicks [s] | CPI    | L3 miss lat [ps] |
|------------------|---------:|-------------:|-------:|-----------------:|
| dram_proxy       |    100ns | 3.484        | 8.11   | 171,000          |
| mram_main_200    |    200ns | 3.636        | 8.47   | 271,000          |
| mram_main_300    |    300ns | 3.787        | 8.82   | 371,000          |

→ main_lat 100→300 ns で simTicks +8.7%、CPI +8.7%。
   L3 miss lat は main_lat の差 (+100/+200 ns) をそのまま反映。
   L1-resident workload でも cold-miss と initial fill が main memory に届く
   ため、わずかにペナルティが出る。

## memstress WS=4MB (混在 L3 hit/miss、main memory への traffic 多め)

| config           | main_lat | simTicks [s] | CPI    | L3 miss lat [ps] |
|------------------|---------:|-------------:|-------:|-----------------:|
| dram_proxy       |    100ns | 68.231       | 24.86  | 171,000          |
| mram_main_200    |    200ns | 74.913       | 27.29  | 271,000          |
| mram_main_300    |    300ns | 81.594       | 29.73  | 371,000          |

→ main_lat 100→300 ns で simTicks +19.6%、CPI +19.6%。
   約 13% (87.3%→ 12.7% miss) の L3 miss が main memory に届くため、
   cachewrite より影響が大きい。

## 解釈

- MRAM main memory (avg 200 ns 想定) のペナルティ:
    - L1-resident workload: +4.4% simTicks
    - 混在 workload (memstress 4MB): +9.8% simTicks
- 修論的含意:
    - dynamic 観点では DRAM の 100 ns → MRAM の 200 ns で 10〜20% 遅い
    - leakage 観点では MRAM main は SRAM L3 と同様の優位性 (非揮発で
      idle power 削減) が期待できる → total energy では逆転する可能性
    - SimpleMemory モデルの限界: チャネル並列性なし、バースト/プリチャージなし、
      Read/Write 非対称なし → 実 MRAM main の評価には NVMain が必要

## 6/10 発表での扱い

- 「予備調査として」明記し、speed -10〜20% / leakage 期待大の方向性のみ示す
- 詳細評価は「NVMain 統合後 (修論本体)」と注釈
- 図: `figures/main_mem_dram_vs_mram.png` (2 サブプロット: cachewrite / memstress)

## NVMain 統合 TODO (発表後)

1. NVMain ビルド (横山先輩のパッチ → `reference/nvmain/`)
2. gem5 ↔ NVMain ブリッジ (NVMainPort / MemCtrl の置換)
3. STT-MRAM main memory config (read=100ns, write=300ns, asymmetric)
4. memstress + SPEC mcf_s で実評価
5. leakage 込み total energy を main memory レベルで再計算
