#!/bin/bash
# gem5 MRAM Read/Write 非対称レイテンシ操作ラッパー
#
# 環境前提:
#   - snap docker が動作中（停止中なら `sudo snap start docker`）
#   - イメージ `gem5-spec` が存在
#   - このリポジトリは /home/26kmc17/gem5 配下に配置（snap docker 制約）
#
# Usage:
#   ./gem5_mram.sh <subcommand> [args]
#
# Subcommands:
#   build              gem5.opt を RISCV ターゲットでビルド
#   build clean        ビルドディレクトリを削除してから再ビルド
#   run [opts]         hello を se_mram_test.py で実行
#                      例: ./gem5_mram.sh run --l1d-write-latency=50
#   ab [wlat]          L1D write_latency の A/B 比較（デフォルト B 側 = 100）
#                      例: ./gem5_mram.sh ab 200
#   ab-l2 [wlat]       L2 write_latency の A/B 比較（デフォルト B 側 = 100）
#   stats <dir>        指定 m5out から主要統計を抽出
#   shell              gem5-spec コンテナ内で対話シェル
#   help               このヘルプ
#
# 補足:
#   - 全ての docker 実行に sudo を使う。パスワード入力が要る。
#   - workload は tests/test-progs/hello/bin/riscv/linux/hello で固定（hello）。
#     別 workload を使うときは ./gem5_mram.sh run --cmd=<path> ... と渡せばよい
#     （se_mram_test.py が --cmd を se.py 側に通す）。

set -e

# --- 定数 -----------------------------------------------------------
HOST_REPO="/home/26kmc17/gem5"
CONT_REPO="/workspace/gem5"
IMAGE="gem5-spec"
GEM5="build/RISCV/gem5.opt"
SCRIPT="configs/example/se_mram_test.py"
WORKLOAD="tests/test-progs/hello/bin/riscv/linux/hello"

# Host 側に正しい場所で実行されているかチェック
if [[ "$(realpath "$(pwd)")" != "$HOST_REPO" && ! "$1" == "help" && ! "$1" == "" ]]; then
    echo "[warn] このスクリプトは $HOST_REPO 内で実行することを想定しています" >&2
fi

# --- docker run 共通ラッパー ----------------------------------------
docker_run() {
    sudo docker run --rm -v "$HOST_REPO":"$CONT_REPO" "$IMAGE" \
        bash -c "cd $CONT_REPO && $*"
}

docker_run_it() {
    sudo docker run --rm -it -v "$HOST_REPO":"$CONT_REPO" "$IMAGE" \
        bash -c "cd $CONT_REPO && $*"
}

# --- subcommand: build ---------------------------------------------
cmd_build() {
    local clean=""
    if [[ "$1" == "clean" ]]; then
        clean="rm -rf build && "
        shift
    fi
    echo "[build] scons build/RISCV/gem5.opt -j$(nproc)"
    docker_run "${clean}scons build/RISCV/gem5.opt -j\$(nproc)"
    echo "[build] done"
}

# --- subcommand: run -----------------------------------------------
cmd_run() {
    local extra_args="$*"
    echo "[run] hello (extra: $extra_args)"
    docker_run "rm -rf m5out && $GEM5 $SCRIPT $extra_args --cmd=$WORKLOAD --caches --l2cache --cpu-type=TimingSimpleCPU"
    cmd_stats m5out
}

# --- subcommand: ab / ab-l2 ----------------------------------------
cmd_ab_internal() {
    local target="$1"   # l1d or l2
    local wlat="${2:-100}"
    local flag
    if [[ "$target" == "l1d" ]]; then
        flag="--l1d-write-latency=$wlat"
    else
        flag="--l2-write-latency=$wlat"
    fi
    echo "[ab] target=$target write_latency: A=default vs B=$wlat"
    docker_run "
        rm -rf m5out_A m5out_B
        echo '=== Run A: default ==='
        $GEM5 --outdir=m5out_A $SCRIPT --cmd=$WORKLOAD --caches --l2cache --cpu-type=TimingSimpleCPU 2>&1 | tail -2
        echo '=== Run B: $flag ==='
        $GEM5 --outdir=m5out_B $SCRIPT $flag --cmd=$WORKLOAD --caches --l2cache --cpu-type=TimingSimpleCPU 2>&1 | tail -2
    "
    echo
    echo "===== A vs B 比較 ====="
    cmd_stats_compare m5out_A m5out_B
}

cmd_ab() {
    cmd_ab_internal l1d "$1"
}

cmd_abl2() {
    cmd_ab_internal l2 "$1"
}

# --- subcommand: stats ---------------------------------------------
cmd_stats() {
    local dir="${1:-m5out}"
    if [[ ! -f "$dir/stats.txt" ]]; then
        echo "[stats] $dir/stats.txt not found" >&2
        return 1
    fi
    echo "--- $dir/stats.txt ---"
    grep -E "simSeconds|simTicks|hostSeconds" "$dir/stats.txt"
    echo "--- L1D ---"
    grep -E "system\.cpu\.dcache\.(overallHits|overallMisses|WriteReq|ReadReq)" "$dir/stats.txt" | head -8 || true
    echo "--- L2 ---"
    grep -E "system\.l2\.(overallHits|overallMisses|demandHits|demandMisses)" "$dir/stats.txt" | head -8 || true
}

cmd_stats_compare() {
    local a="$1" b="$2"
    printf "%-40s %15s %15s %15s\n" "metric" "A" "B" "diff(B-A)"
    for stat in simTicks simSeconds; do
        local va vb
        va=$(grep -E "^$stat" "$a/stats.txt" | awk '{print $2}')
        vb=$(grep -E "^$stat" "$b/stats.txt" | awk '{print $2}')
        local diff
        diff=$(python3 -c "print(f'{float($vb) - float($va):.6g}')" 2>/dev/null || echo "n/a")
        printf "%-40s %15s %15s %15s\n" "$stat" "$va" "$vb" "$diff"
    done
}

# --- subcommand: shell ---------------------------------------------
cmd_shell() {
    echo "[shell] entering $IMAGE container at $CONT_REPO ..."
    docker_run_it "exec bash"
}

# --- subcommand: help ----------------------------------------------
cmd_help() {
    # 先頭のコメントブロック（連続する `#` 行）だけを表示
    awk 'NR==1{next} /^#/{sub(/^# ?/, ""); print; next} {exit}' "$0"
}

# --- dispatch ------------------------------------------------------
case "${1:-help}" in
    build)    shift; cmd_build "$@" ;;
    run)      shift; cmd_run "$@" ;;
    ab)       shift; cmd_ab "$@" ;;
    ab-l2)    shift; cmd_abl2 "$@" ;;
    stats)    shift; cmd_stats "$@" ;;
    shell)    cmd_shell ;;
    help|-h|--help) cmd_help ;;
    *)
        echo "unknown subcommand: $1" >&2
        cmd_help
        exit 1
        ;;
esac
