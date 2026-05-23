# NVMain integration plan (Round-3 E recon, 2026-05-23 updated)

## 現状 (2026-05-23 18:51 更新)

- **NVMain ソース取得済み** (2026-05-23 本日): `/home/26kmc17/external/NVmain/`
    - origin: `https://github.com/SEAL-UCSB/NVmain.git` (Poremba lab 公式 fork、Penn State -> UCSB)
    - 最新 commit `ad28c0c` (2018-08-29 "python: Make print a function")
    - **gem5 統合コード同梱**: `SimInterface/Gem5Interface/Gem5Interface.{cpp,h}`
    - **Everspin MRAM config 同梱**: `Config/STTRAM_Everspin_4GB.config`
    - trace 例: `Tests/Traces/hello_world.nvt`
- 卒論時の senior 環境 `/home/26kmc17/cal/gem5/reference/nvmain/` (Config + run.sh のみ)
  は `Config/custom/STTRAM_Everspin_16GB.config` (16GB) を持つ。これは新 clone
  にはないので残しておく価値あり (16GB 版が必要なら移植)。
- 卒論時 senior の手法は **trace-based**:
    ```
    nvmain.fast Config trace.nvt 0
    ```
- gem5 側に NVMainMemory / NVMainBridge クラスは未追加 (これからの実装)

## NVMain 採用パスは 2 通り

### パス1: trace-based (低リスク、6/10 後 - 修論本体に間に合う)

1. NVMain 公式 (Penn State) からソース取得
2. NVMain をビルド (Docker `gem5-spec` 内で gcc が使える)
3. gem5 に `CommMonitor` を挿入 → memstress / cachewrite の memory trace を `.nvt` 形式でダンプ
4. NVMain で trace 再生 → 各アクセスの latency と energy を取得
5. (任意) フィードバックで gem5 を再走

利点: gem5 本体を変更不要、再現性高い、senior の手法と同じ
欠点: シミュレーション速度結合がない、cycle 精度は失われる

### パス2: gem5 ↔ NVMain ネイティブ統合 (高リスク、修論本体 8月以降)

1. NVMain 公式の gem5 patch を適用
2. NVMainMemory クラスを `m5.objects` に登録
3. `se_mram_l3.py` で `MemCtrl` を `NVMainMemory` に差し替え
4. gem5 ビルドを NVMain と一緒に行う SConstruct 改修

利点: 完全な cycle-accurate 連携
欠点: gem5 / NVMain どちらかの version drift で詰みやすい、build 系の調整に 1〜2 日

## 推奨ルート

1. **6/10 発表**: N の SimpleMemory preliminary のままで OK。十分強い。
2. **6/10 〜 修論初稿**: パス1 (trace-based) で main memory 評価を完成させる
3. **修論最終稿**: パス2 で integrated 検証 (必要ならば)

## パス1 の具体的手順 (NVMain 取得済、次は build → trace)

```
# 1. NVMain 取得  [DONE]
ls /home/26kmc17/external/NVmain/SConstruct  # 存在確認

# 2. NVMain build (Docker gem5-spec 内、scons 使用)
sudo docker run --rm -v /home/26kmc17/external/NVmain:/build gem5-spec \
    bash -c "cd /build && scons --build-type=fast -j$(nproc)"
   -> nvmain.fast バイナリが /home/26kmc17/external/NVmain/ に生成

# 3. NVMain 単独動作確認 (hello_world trace)
sudo docker run --rm -v /home/26kmc17/external/NVmain:/build gem5-spec \
    bash -c "cd /build && ./nvmain.fast Config/STTRAM_Everspin_4GB.config \
                                        Tests/Traces/hello_world.nvt 0"
   -> stats が出れば NVMain 単体は OK

# 4. gem5 で trace ダンプ (.nvt 形式)
   se_mram_l3.py に CommMonitor を memory bus 前段に挿入。
   gem5 の SimpleTrace dumper -> python で .nvt 形式に変換
   (.nvt フォーマット: "CYCLE OP ADDR DATA THREAD" の space-separated text)

# 5. memstress / cachewrite の trace を NVMain で再生
./nvmain.fast Config/STTRAM_Everspin_4GB.config memstress_4mb.nvt 0
./nvmain.fast Config/STTRAM_Everspin_4GB.config memstress_4mb.nvt 0  # DDR4 比較

# 6. 結果を Python で結合 (gem5 simTicks + NVMain energy + latency)
```

## パス2 の具体的手順 (gem5 ↔ NVMain native)

NVMain は `SimInterface/Gem5Interface/Gem5Interface.{cpp,h}` を持つので、
gem5 側に NVMainMemory class を追加すれば結合できる。

```
# 1. gem5 ソースに NVMainMemory class 追加
   src/mem/nvmain_memory.{cc,hh} を新規作成 (NVMain Gem5Interface を呼び出す)
   src/mem/SConscript に NVMain を追加 (NVmain build product をリンク)

# 2. NVMain を gem5 build と同時にビルド
   gem5 の SConstruct 末尾に NVmain サブビルドを追加

# 3. se_mram_l3.py で MemCtrl を NVMainMemory に差し替え可能にする
   --main-mem-type=nvmain を CLI に追加

# 4. memstress で実行
```

## ブロッカー / 確認事項

- [x] NVMain の公式 fork → SEAL-UCSB/NVmain で確定 (Poremba lab)
- [x] Gem5Interface コード存在確認 (SimInterface/Gem5Interface/)
- [x] Everspin config 同梱 (Config/STTRAM_Everspin_4GB.config)
- [ ] gem5-spec docker で NVMain SConstruct が通るか (build 試行 → 6/10 後)
- [ ] .nvt フォーマット仕様の正確な定義 (README 5節 + 既存 trace 参考)
- [ ] gem5 v24 の `CommMonitor` で memory port trace 出力カスタマイズ可能か
- [ ] STTRAM_Everspin_4GB と senior の 16GB との差分確認 (16GB のは
       `/home/26kmc17/cal/gem5/reference/nvmain/Config/custom/` 参照)

## 6/10 発表向けには「次のステップ」として 1 枚紹介
- 「N (SimpleMemory 予備調査) を NVMain で精密化する」と一言入れる
- 図 8 (`main_mem_dram_vs_mram.png`) の下に「NVMain 統合は修論本体で実施」とキャプション
