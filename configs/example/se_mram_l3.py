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
    SimpleMemory,
    SrcClockDomain,
    SystemXBar,
    System,
    DDR3_1600_8x8,
    MemCtrl,
    VoltageDomain,
    TimingSimpleCPU,
)

# DerivO3CPU is an ISA-selected alias (RiscvO3CPU on this build). Imported
# separately so the script still loads on builds without an O3 CPU.
try:
    from m5.objects import DerivO3CPU
except ImportError:
    DerivO3CPU = None


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
parser.add_argument("--cwd", default="",
                    help="Working directory for the SE process (Task X9). "
                         "Set this for SPEC binaries (e.g. mcf_s) that read "
                         "auxiliary input files via relative paths. Empty = "
                         "gem5 default (unchanged for memstress/hello runs).")
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
parser.add_argument("--l3-size", default="16MB",
                    help="L3 cache size (e.g. 4MB, 8MB, 16MB, 32MB). "
                         "Used for the capacity sweep in Task B/C.")
parser.add_argument("--main-mem-type", default="dram", choices=["dram", "simple"],
                    help="dram = MemCtrl+DDR3 (default); simple = SimpleMemory "
                         "with a single fixed latency (round-3 N preliminary)")
parser.add_argument("--main-latency", default="50ns",
                    help="Main-memory latency for --main-mem-type=simple "
                         "(used as request->response delay; single value)")
parser.add_argument("--main-bandwidth", default="12.8GB/s",
                    help="Main-memory bandwidth for --main-mem-type=simple")
parser.add_argument("--max-insts", type=int, default=0,
                    help="Stop after this many instructions (0 = no limit)")
parser.add_argument("--num-cpus", type=int, default=1,
                    help="Number of cores (Task X4). 1 = original single-core "
                         "system (unchanged). >1 builds a CMP: private L1+L2 "
                         "per core, shared L3, multi-program (the same --cmd "
                         "binary runs as an independent process on each core).")
args = parser.parse_args()


# ---------------------------- System assembly ----------------------------
system = System()
system.clk_domain = SrcClockDomain(
    clock=args.cpu_clock, voltage_domain=VoltageDomain()
)
system.mem_mode = "timing"
system.mem_ranges = [AddrRange(args.mem_size)]

# CPU factory (honours --cpu-type for any core)
def make_cpu(cpu_id=0):
    if args.cpu_type == "TimingSimpleCPU":
        return TimingSimpleCPU(cpu_id=cpu_id)
    elif args.cpu_type in ("DerivO3CPU", "O3CPU"):
        # Out-of-order core. Used by Task X1 to test whether the L3 write-latency
        # "hiding" seen on TimingSimpleCPU survives on an OoO core (writebacks
        # may land on the critical path once the core has many outstanding misses).
        if DerivO3CPU is None:
            raise SystemExit("DerivO3CPU not available in this gem5 build")
        return DerivO3CPU(cpu_id=cpu_id)
    else:
        raise SystemExit(f"Unsupported cpu-type: {args.cpu_type}")


# Shared L2->L3 crossbar (present in both single- and multi-core layouts).
system.l3bus = L2XBar(width=64)

if args.num_cpus <= 1:
    # ---- Single-core layout (UNCHANGED: preserves stat names & prior data) ----
    system.cpu = make_cpu(0)

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
    system.l2.mem_side = system.l3bus.cpu_side_ports
else:
    # ---- Multi-core CMP layout (Task X4): private L1+L2 per core, shared L3 ----
    # Each core: CPU -> private L1I/L1D -> per-core L2XBar -> private L2 -> shared
    # l3bus -> shared L3. Stats are named system.cpu0.*, system.cpu1.*, ...
    system.cpu = [make_cpu(i) for i in range(args.num_cpus)]
    system.l2bus = [L2XBar() for _ in range(args.num_cpus)]
    system.l2 = [L2Cache() for _ in range(args.num_cpus)]
    for i in range(args.num_cpus):
        cpu = system.cpu[i]
        cpu.icache = L1ICache()
        cpu.dcache = L1DCache()
        cpu.dcache.tag_latency = args.l1d_read_latency
        cpu.dcache.data_latency = args.l1d_read_latency
        cpu.dcache.write_latency = args.l1d_write_latency
        cpu.icache.cpu_side = cpu.icache_port
        cpu.dcache.cpu_side = cpu.dcache_port

        l2bus = system.l2bus[i]
        cpu.icache.mem_side = l2bus.cpu_side_ports
        cpu.dcache.mem_side = l2bus.cpu_side_ports

        l2 = system.l2[i]
        l2.tag_latency = args.l2_read_latency
        l2.data_latency = args.l2_read_latency
        l2.write_latency = args.l2_write_latency
        l2.cpu_side = l2bus.mem_side_ports
        l2.mem_side = system.l3bus.cpu_side_ports

# L3 (parameters from CLI)
system.l3 = L3Cache()
system.l3.tag_latency = args.l3_read_latency
system.l3.data_latency = args.l3_read_latency
system.l3.write_latency = args.l3_write_latency
system.l3.write_buffers = args.l3_write_buffers
system.l3.size = args.l3_size
system.l3.cpu_side = system.l3bus.mem_side_ports

# L3 -> mem bus -> DRAM
system.membus = SystemXBar()
system.l3.mem_side = system.membus.cpu_side_ports

# Interrupt wiring (RISC-V CPU still needs this)
if args.num_cpus <= 1:
    system.cpu.createInterruptController()
else:
    for cpu in system.cpu:
        cpu.createInterruptController()

# Memory controller / main memory
if args.main_mem_type == "dram":
    system.mem_ctrl = MemCtrl()
    system.mem_ctrl.dram = DDR3_1600_8x8()
    system.mem_ctrl.dram.range = system.mem_ranges[0]
    system.mem_ctrl.port = system.membus.mem_side_ports
else:
    # SimpleMemory mode: round-3 N preliminary swap. Models main memory
    # as a flat-latency device with no DRAM channel/rank/bank structure
    # nor read/write asymmetry. Sufficient for a sensitivity-style
    # comparison of DRAM-class vs MRAM-class latencies; NVMain is needed
    # for accurate MRAM main-memory modelling.
    system.mem_ctrl = SimpleMemory(latency=args.main_latency,
                                   bandwidth=args.main_bandwidth)
    system.mem_ctrl.range = system.mem_ranges[0]
    system.mem_ctrl.port = system.membus.mem_side_ports
system.system_port = system.membus.cpu_side_ports

# Workload (SE multi-program: each core runs an independent copy of --cmd)
system.workload = SEWorkload.init_compatible(args.cmd)
cmd_line = [args.cmd] + (args.options.split() if args.options else [])
if args.num_cpus <= 1:
    process = Process()
    process.cmd = cmd_line
    if args.cwd:
        process.cwd = args.cwd
    system.cpu.workload = process
    system.cpu.createThreads()
    if args.max_insts > 0:
        system.cpu.max_insts_any_thread = args.max_insts
else:
    for i, cpu in enumerate(system.cpu):
        # Distinct pid per core so the independent processes don't collide.
        process = Process(pid=100 + i)
        process.cmd = cmd_line
        if args.cwd:
            # Per-core cwd (Task X9-2 rate): each core's SPEC process gets its
            # own working dir <cwd>/core<i> so that fixed-name output files
            # (e.g. mcf's result file) written by independent copies don't
            # collide/corrupt. The launching script must pre-create these dirs.
            process.cwd = f"{args.cwd}/core{i}"
        cpu.workload = process
        cpu.createThreads()
        if args.max_insts > 0:
            cpu.max_insts_any_thread = args.max_insts


print(
    f"[se_mram_l3] cpu={args.cpu_type}x{args.num_cpus} | "
    f"L1D read/data_lat={args.l1d_read_latency} "
    f"write_lat={args.l1d_write_latency} | "
    f"L2 read/data_lat={args.l2_read_latency} "
    f"write_lat={args.l2_write_latency} | "
    f"L3 size={args.l3_size} read/data_lat={args.l3_read_latency} "
    f"write_lat={args.l3_write_latency} "
    f"write_buffers={args.l3_write_buffers} cycles | "
    f"main_mem={args.main_mem_type}"
    + (f"({args.main_latency})" if args.main_mem_type == "simple" else "")
    + f" @ {args.cpu_clock}",
    flush=True,
)


# ---------------------------- Run ----------------------------
root = Root(full_system=False, system=system)
m5.instantiate()
exit_event = m5.simulate()
print(f"Exiting @ tick {m5.curTick()} because {exit_event.getCause()}")
