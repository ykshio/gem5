"""Minimal MRAM-asymmetric-latency smoke test.

Wraps configs/deprecated/example/se.py just enough to reach the
simulation but overrides L1_DCache.write_latency so that we can
verify the new asymmetric-latency code path actually fires.

Usage:
    build/RISCV/gem5.opt configs/example/se_mram_test.py \
        --cmd=tests/test-progs/hello/bin/riscv/linux/hello \
        --caches --l2cache \
        [--l1d-write-latency=N] [--l2-write-latency=N]
"""

import argparse
import os
import sys

# gem5 only adds the script's directory to sys.path. Expose the
# top-level `configs/` so that `common`, `ruby`, etc. resolve.
sys.path.insert(
    0, os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)

# Patch sys.argv before importing se.py so se.py's argument parser
# does not see our extra options.
parser = argparse.ArgumentParser(add_help=False)
parser.add_argument("--l1d-write-latency", type=int, default=None)
parser.add_argument("--l2-write-latency", type=int, default=None)
ns, remaining = parser.parse_known_args()
sys.argv = [sys.argv[0]] + remaining

from common import Caches  # noqa: E402

if ns.l1d_write_latency is not None:
    Caches.L1_DCache.write_latency = ns.l1d_write_latency
    print(f"[mram_test] L1_DCache.write_latency = {ns.l1d_write_latency}")
if ns.l2_write_latency is not None:
    Caches.L2Cache.write_latency = ns.l2_write_latency
    print(f"[mram_test] L2Cache.write_latency = {ns.l2_write_latency}")

# Defer to the upstream se.py.
exec(
    compile(
        open("configs/deprecated/example/se.py").read(),
        "configs/deprecated/example/se.py",
        "exec",
    )
)
