#!/bin/bash
# Cross-build the wrstress microbench for RISC-V (static) inside the gem5-spec image.
set -e
cd /workspace/gem5/tests/test-progs/wrstress/src
mkdir -p ../bin/riscv/linux
for cc in riscv64-unknown-linux-gnu-gcc riscv64-linux-gnu-gcc; do
    if command -v "$cc" >/dev/null 2>&1; then
        echo "[build_wrstress_riscv] using $cc"
        $cc -O2 -static -o ../bin/riscv/linux/wrstress wrstress.c
        ls -la ../bin/riscv/linux/wrstress
        file ../bin/riscv/linux/wrstress 2>/dev/null || true
        exit 0
    fi
done
echo "[build_wrstress_riscv] No RISCV gcc found" >&2
exit 1
