# 修論ストーリー骨子 (2026-05-23 時点)

ブランチ `feature/mram-cache` で実装した gem5 v24 拡張と、Round 1 〜 3
の実験結果を「MRAM L3 がデータセンタ電力課題に対する設計解になる」
というストーリーに沿って整理する。

---

## 1. 序論

- データセンタの消費電力増加と SRAM L3 のリーク電力支配
- 卒論到達点: L3 MRAM で 32MB workload 上の dynamic energy を 93% 削減、
  しかし 12% の性能低下を観測した
- 卒論の制限事項 → 修論の出発点:
    - gem5 は Read/Write 対称 latency しか持たない → MRAM の非対称性を
      モデル化していなかった
    - leakage を含めた total energy 評価ができていなかった
    - main memory レイヤは未検証

## 2. 関連研究

- Sun 2011 (STT-MRAM L1/L2, MICRO)
- Smullen 2011 (relaxed retention STT-MRAM, HPCA)
- Oboril 2015 (hybrid SOT/STT-MRAM L1, DATE)
- Mittal 2014 (MRAM cache survey)
- NVMain (Poremba 2015), DESTINY (Poremba 2015), CACTI 7 (Balasubramonian 2017)
- CXL / メモリプール構想 (Intel 2022, IBM 2023)

## 3. 実装: gem5 v24 への Read/Write 非対称 latency

- `BaseCache` に `writeLatency` メンバ追加 (`Cache.py` で
  `write_latency = Param.Cycles(Self.data_latency, ...)`)
- `calculateAccessLatency()` に `is_write` フラグを追加し、書き込み時は
  `writeLatency` を採用 (`src/mem/cache/base.cc`)
- demand WriteReq hit path + writeback path 両方に組み込み
- 関連 commit:
    - `dac0836` (5/11) 実装本体
    - `57a4d1a` (5/23) writeback path 拡張
- 検証ハーネス: `tests/test-progs/cachewrite/`, `tests/test-progs/memstress/`,
  `configs/example/se_mram_l3.py`

## 4. 評価結果 (4 + 1 定量結果)

### 4.1 L1 を MRAM にしてはいけない

- 図: `figures/l1_sram_vs_mram.png` (Round-2 H)
- 数値: L1 MRAM(3/10) は SRAM(4/4) より 1.08× 遅く、1166× エネルギー
- 解釈: 32KB L1 のリーク savings は小さく、書き込みエネルギーが圧倒

### 4.2 L3 write penalty は構造的に隠蔽される

- 図: `figures/writeback_hiding.png` (Round 1, WS=32MB)
   + `figures/ws4mb_sweep.png` (Round-2 F, WS=4MB)
- 主張: writeback は fire-and-forget (`pkt->needsResponse()==false`) のため、
  L1→L2→L3 の write 系パケットは CPU stall に寄与しない
- エビデンス:
    - WS=32MB (100% L3 miss): 6 構成 simTicks 完全一致 (617.32 G)
    - WS=4MB (87.3% L3 hit): 6 構成 simTicks 完全一致 (48.82 G)
    - 両極端で一致 → 条件依存ではなく構造的帰結

### 4.3 L3 read benefit は CPU に露出する

- 図: `figures/rlat_effect.png` (Round-2 F-rlat)
- 数値: MRAM L3 (10/35) は SRAM L3 (40/40) より **1.32× 高速**
  (同一 hit rate での rlat 単独効果)
- 解釈: 隠蔽されるのは write 側だけ。read latency 短縮は素直に効く

### 4.4 leakage 込み total energy で MRAM が圧勝

- 図: `figures/total_energy_dyn_vs_leak.png` (Round-3 J)
- 数値 (WS=4MB, 22nm 16MB L3, 文献 leakage 値):

  | tech | E_dyn | E_leak | E_total | vs SRAM |
  | --- | ---:|---:|---:|---:|
  | SRAM      | 0.049 mJ | 322.6 mJ | 322.7 mJ | 1.00×  |
  | STT-MRAM  | 62.4 mJ  | 9.8 mJ   | 72.1 mJ  | **0.224×** |
  | SOT-MRAM  | 43.1 mJ  | 7.3 mJ   | 50.4 mJ  | **0.156×** |

- 解釈: dynamic-only で 1000× 負けていても、SRAM の 5 W leakage が
  64 ms 燃え続ける時間スケールで MRAM の非揮発性が逆転

### 4.5 (予備) main memory を MRAM に置き換えた場合 [Round-3 N]

- 図: `figures/main_mem_dram_vs_mram.png` (作成予定)
- SimpleMemory の単一 latency 近似による予備調査
- 本格評価は NVMain 統合後 (6/10 以降)

## 5. 考察

提案構成 = **「L1 = SRAM, L2-L3 = MRAM, Main = 要検討」**

| level | 推奨 | 根拠 |
|-------|------|------|
| L1    | SRAM | §4.1 (MRAM はエネルギー 1166×)  |
| L2    | MRAM | §4.2 と同論理が L2 にも適用 (capacity 比は L3 より小だが trend は同方向) |
| L3    | MRAM | §4.2-§4.4 (write 隠蔽 + read 短縮 + leakage savings) |
| Main  | 要検証 | §4.5 (予備調査のみ、NVMain で要再評価) |

- writeback 非同期性が「MRAM 採用の追い風」 — 卒論時点では悲観材料だった
  write 遅延が、現代のキャッシュ階層では構造的に隠蔽される

## 6. 今後の課題

- NVMain 統合による main memory MRAM の精密評価
- SPEC CPU 2017 / MLPerf inference での再評価 (現状はマイクロベンチのみ)
- マルチコア対応 (現状は TimingSimpleCPU 1 コア)
- 書き込みポリシー (FlipNWrite, encoding) を組み合わせた dynamic energy
  削減
- DESTINY で leakage 値を 22nm 統一に再計算 (現状文献値ベース)

## 7. 結論

gem5 v24 に Read/Write 非対称 latency を実装し、4 つの定量実験を通して
「MRAM は L2-L3 で使うべき」を構造的に示した。書き込み penalty は
キャッシュ階層の writeback 非同期性により隠蔽される一方、リーク削減と
read 短縮は素直に CPU 性能に反映される。

---

## 図一覧と引用関係

| # | ファイル                                | 章節 | 出典実験 (commit) |
|--|------------------------------------------|------|-------------------|
| 1 | `figures/l1_wlat_cpi.png`                | §3   | Round 0 検証      |
| 2 | `figures/l1_wlat_energy_full.png`        | §3   | Round-2 G-2 (`cf17989d`) |
| 3 | `figures/l1_sram_vs_mram.png`            | §4.1 | Round-2 H (`88c96b32`) |
| 4 | `figures/writeback_hiding.png`           | §4.2 | Round 1 (`4b719d66`) |
| 5 | `figures/ws4mb_sweep.png`                | §4.2 | Round-2 F (`88c96b32`) |
| 6 | `figures/rlat_effect.png`                | §4.3 | Round-2 F-rlat (`88c96b32`) |
| 7 | `figures/total_energy_dyn_vs_leak.png`   | §4.4 | Round-3 J         |
| 8 | `figures/main_mem_dram_vs_mram.png`      | §4.5 | Round-3 N         |
| 9 | `figures/l1_speed_energy.png`            | §4.1 補助 | Round-2 G |

## 各章への一行要約 (slide 用)

- §4.1 「L1 MRAM は速度・エネルギー両軸で不利。L1 は SRAM に残せ。」
- §4.2 「MRAM L3 write penalty は writeback 非同期性により隠蔽される。」
- §4.3 「一方 MRAM L3 read 短縮は 1.32× speedup として CPU に現れる。」
- §4.4 「dynamic で 1000× 負けても、leakage 込み total で 4-6× 勝つ。」
- §4.5 「main memory MRAM 化はペナルティ X%、本格評価は NVMain 後。」
