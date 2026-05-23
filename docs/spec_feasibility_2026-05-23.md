# SPEC CPU 2017 mcf_s 動作確認メモ (Round-3 K)

日付: 2026-05-23

## 結論

**現環境では試走不可。** SPEC CPU 2017 のバイナリ・入力データセット
が `/home/26kmc17/gem5` ツリーおよび `/home/26kmc17/` 配下に
存在しない。卒論時の SPEC 環境は移行が完了していない様子。

## 確認方法

```
find /home/26kmc17/gem5 -maxdepth 6 -type f \
    \( -name "mcf_s*" -o -name "mcf_r*" -o -name "*spec*2017*" \) \
    | grep -v "\.py$"
find / -maxdepth 5 -type d -name "cpu2017*"
find /home -maxdepth 4 -type d -name "SPEC*"
```

→ いずれもヒットなし。

## ヒットしたのは設定例だけ

```
configs/example/gem5_library/x86-spec-cpu2017-benchmarks.py
configs/example/gem5_library/x86-spec-cpu2006-benchmarks.py
```

これらは「SPEC ディスクイメージ + バイナリ」を前提とするラッパで、
実行には別途 SPEC のフルインストールが必要。

## 今後の段取り (発表後でも可)

1. SPEC ライセンスのある別環境 (卒論時の環境 or 研究室の SPEC ホスト) から
   `mcf_s` 系の RISC-V バイナリ + 入力 (`inp.in`) を持ち込む
2. `tests/test-progs/spec_mcf/` に配置
3. SE モード SPEC は I/O syscall サポートが薄いため、bind-mount などで
   `cwd` を入力ディレクトリにする工夫が必要 (gem5_library の x86 用
   ラッパが参考になる)
4. RISC-V の `mcf_s` をクロスコンパイルする場合は SPEC CPU の build flow
   を docker 内で実行

## 所要時間見積もり

- 移植のみ: 半日〜1 日 (環境差で詰まる可能性高)
- 1 ベンチ動作確認: 上記 + 数時間 (シミュレーション速度に依存)
- 6/10 発表までの優先度: **低** (発表は microbench 結果で十分強い)
- 修論本体 (8 月以降): **高** (実 workload での再評価は説得力に必須)

## 6/10 発表で SPEC が必要か

不要。Round 2/3 で取得した microbench 結果 (cachewrite + memstress) が:
- L1=SRAM が必要 (H)
- L3=MRAM の write 隠蔽 + read 1.32× (F)
- leakage 込み total energy 4-6× (J)

を裏付けている。SPEC は「現実 workload でも同様の傾向」を補強する
2 次的なエビデンス。修論本体・北大発表 (6/26 候補) では必須化が望ましい。
