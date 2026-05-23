#!/bin/bash
set -e
cd /workspace/gem5/tests/test-progs/cachewrite/src
mkdir -p ../bin/riscv/linux
for cc in riscv64-linux-gnu-gcc riscv64-unknown-linux-gnu-gcc; do
    if command -v "$cc" >/dev/null 2>&1; then
        echo "[build_cachewrite_riscv] using $cc"
        $cc -O2 -static -o ../bin/riscv/linux/cachewrite cachewrite.c
        ls -la ../bin/riscv/linux/cachewrite
        exit 0
    fi
done
echo "[build_cachewrite_riscv] No RISCV gcc found" >&2
exit 1
