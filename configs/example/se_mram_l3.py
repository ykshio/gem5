"""SE-mode 3-level cache hierarchy with configurable L3 read/write latency.

The default `configs/deprecated/example/se.py` does not wire up an L3
cache in this gem5 v24 tree, so this script builds a minimal system
explicitly. Use it for SRAM-vs-MRAM L3 sweeps.

Latencies are in *cycles* and are interpreted by the gem5 cache model
against the CPU clock domain (1 GHz here -> 1 ns per cycle).

Usage:
    build/RISCV/gem5.opt --outdir=<dir> configs/example/se_mram_l3.py \\
        --cmd=<workload> \\
        --l3-read-latency=10 --l3-write-latency=35 \\
        [--max-insts=N] [--cpu-type=TimingSimpleCPU]
"""

import argparse

import m5
from m5.objects import (
    AddrRange,
    Cache,
    L2XBar,
    Process,
    Root,
    SEWorkload,
    SrcClockDomain,
    SystemXBar,
    System,
    DDR3_1600_8x8,
    MemCtrl,
    VoltageDomain,
    TimingSimpleCPU,
)


# ---------------------------- Cache classes ----------------------------
class L1Cache(Cache):
    assoc = 2
    tag_latency = 4
    data_latency = 4
    write_latency = 4
    response_latency = 4
    mshrs = 4
    tgts_per_mshr = 20
    size = "32kB"


class L1ICache(L1Cache):
    is_read_only = True
    writeback_clean = True


class L1DCache(L1Cache):
    # L1D timings overridable from CLI (defaults match an SRAM L1).
    pass


class L2Cache(Cache):
    assoc = 8
    # L2 timings overridable from CLI (defaults match an SRAM L2).
    tag_latency = 14
    data_latency = 14
    write_latency = 14
    response_latency = 14
    mshrs = 20
    tgts_per_mshr = 12
    size = "256kB"


class L3Cache(Cache):
    assoc = 16
    # L3 timings are set per-run from CLI args.
    tag_latency = 40
    data_latency = 40
    write_latency = 40
    response_latency = 20
    mshrs = 32
    tgts_per_mshr = 12
    size = "16MB"
    write_buffers = 16


# ---------------------------- Argument parsing ----------------------------
parser = argparse.ArgumentParser()
parser.add_argument("--cmd", required=True, help="Workload binary path")
parser.add_argument("--options", default="", help="Workload arguments")
parser.add_argument("--cpu-type", default="TimingSimpleCPU")
parser.add_argument("--cpu-clock", default="1GHz")
parser.add_argument("--mem-size", default="512MB")
parser.add_argument("--l1d-read-latency", type=int, default=4,
                    help="L1D read (data + tag) latency in cycles")
parser.add_argument("--l1d-write-latency", type=int, default=4,
                    help="L1D write latency in cycles")
parser.add_argument("--l2-read-latency", type=int, default=14,
                    help="L2 read (data + tag) latency in cycles")
parser.add_argument("--l2-write-latency", type=int, default=14,
                    help="L2 write latency in cycles")
parser.add_argument("--l3-read-latency", type=int, default=40,
                    help="L3 read (data + tag) latency in cycles")
parser.add_argument("--l3-write-latency", type=int, default=40,
                    help="L3 write latency in cycles")
parser.add_argument("--l3-write-buffers", type=int, default=16,
                    help="L3 write buffer entries (back-pressure depth)")
parser.add_argument("--max-insts", type=int, default=0,
                    help="Stop after this many instructions (0 = no limit)")
args = parser.parse_args()


# ---------------------------- System assembly ----------------------------
system = System()
system.clk_domain = SrcClockDomain(
    clock=args.cpu_clock, voltage_domain=VoltageDomain()
)
system.mem_mode = "timing"
system.mem_ranges = [AddrRange(args.mem_size)]

# CPU
if args.cpu_type == "TimingSimpleCPU":
    system.cpu = TimingSimpleCPU()
else:
    raise SystemExit(f"Unsupported cpu-type: {args.cpu_type}")

# L1 caches (L1D parameters from CLI)
system.cpu.icache = L1ICache()
system.cpu.dcache = L1DCache()
system.cpu.dcache.tag_latency = args.l1d_read_latency
system.cpu.dcache.data_latency = args.l1d_read_latency
system.cpu.dcache.write_latency = args.l1d_write_latency
system.cpu.icache.cpu_side = system.cpu.icache_port
system.cpu.dcache.cpu_side = system.cpu.dcache_port

# L1 -> L2 bus
system.l2bus = L2XBar()
system.cpu.icache.mem_side = system.l2bus.cpu_side_ports
system.cpu.dcache.mem_side = system.l2bus.cpu_side_ports

# L2 (parameters from CLI)
system.l2 = L2Cache()
system.l2.tag_latency = args.l2_read_latency
system.l2.data_latency = args.l2_read_latency
system.l2.write_latency = args.l2_write_latency
system.l2.cpu_side = system.l2bus.mem_side_ports

# L2 -> L3 bus
system.l3bus = L2XBar(width=64)
system.l2.mem_side = system.l3bus.cpu_side_ports

# L3 (parameters from CLI)
system.l3 = L3Cache()
system.l3.tag_latency = args.l3_read_latency
system.l3.data_latency = args.l3_read_latency
system.l3.write_latency = args.l3_write_latency
system.l3.write_buffers = args.l3_write_buffers
system.l3.cpu_side = system.l3bus.mem_side_ports

# L3 -> mem bus -> DRAM
system.membus = SystemXBar()
system.l3.mem_side = system.membus.cpu_side_ports

# Interrupt wiring (RISC-V CPU still needs this)
system.cpu.createInterruptController()

# Memory controller
system.mem_ctrl = MemCtrl()
system.mem_ctrl.dram = DDR3_1600_8x8()
system.mem_ctrl.dram.range = system.mem_ranges[0]
system.mem_ctrl.port = system.membus.mem_side_ports
system.system_port = system.membus.cpu_side_ports

# Workload
process = Process()
process.cmd = [args.cmd] + (args.options.split() if args.options else [])
system.workload = SEWorkload.init_compatible(args.cmd)
system.cpu.workload = process
system.cpu.createThreads()

# Optional max-insts
if args.max_insts > 0:
    system.cpu.max_insts_any_thread = args.max_insts


print(
    f"[se_mram_l3] L1D read/data_lat={args.l1d_read_latency} "
    f"write_lat={args.l1d_write_latency} | "
    f"L2 read/data_lat={args.l2_read_latency} "
    f"write_lat={args.l2_write_latency} | "
    f"L3 read/data_lat={args.l3_read_latency} "
    f"write_lat={args.l3_write_latency} "
    f"write_buffers={args.l3_write_buffers} cycles "
    f"@ {args.cpu_clock}",
    flush=True,
)


# ---------------------------- Run ----------------------------
root = Root(full_system=False, system=system)
m5.instantiate()
exit_event = m5.simulate()
print(f"Exiting @ tick {m5.curTick()} because {exit_event.getCause()}")
