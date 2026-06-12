"""Modern major-CPU (AMD Ryzen 7 9800X3D-class) SE-mode cache hierarchy.

Thesis-body config (ROUND8 Task Y4). This is a SEPARATE file from
se_mram_l3.py on purpose: se_mram_l3.py is the frozen config behind the
6/17 X1-X9 results and is re-read by running experiments, so it must not
change. This file is where the Zen5-class parameters live.

Differences vs se_mram_l3.py (per research_design_modern_cpu.md s.1.3):
  * DerivO3CPU default (Zen5-class OoO), 8 cores default.
  * L1I 32 KB / 8-way, L1D 48 KB / 12-way (Zen5 widened L1D 32->48 KB).
  * L2 1 MB / 16-way (private).
  * L3 16-way, capacity sweep {32,64,96,128} MB, technology latencies via CLI.
  * DDR5 main memory (gem5 ships 4400/6400/8400; DDR5-5600 is not a stock
    model so the closest stock part, DDR5_6400_4x8, is the default. Override
    with --ddr5-model for a 4400/8400 sensitivity sweep.)

SE multi-program: each core runs an independent copy of --cmd (= SPEC rate).
FS mode (needed for stock SPEC2017 binaries) is a separate later task (Y3).

Usage:
    build/RISCV/gem5.opt --outdir=<dir> configs/example/se_mram_modern.py \\
        --cmd=<workload> --num-cpus=8 --l3-size=96MB \\
        --l3-read-latency=10 --l3-write-latency=22 [--cwd=<dir>]
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
    MemCtrl,
    VoltageDomain,
    TimingSimpleCPU,
    DDR5_4400_4x8,
    DDR5_6400_4x8,
    DDR5_8400_4x8,
)

try:
    from m5.objects import DerivO3CPU
except ImportError:
    DerivO3CPU = None

DDR5_MODELS = {
    "4400": DDR5_4400_4x8,
    "6400": DDR5_6400_4x8,
    "8400": DDR5_8400_4x8,
}


# ---------------------------- Cache classes (Zen5-class) ----------------------------
class L1ICache(Cache):
    assoc = 8                # Zen5 L1I 32 KB 8-way
    size = "32kB"
    tag_latency = 4
    data_latency = 4
    write_latency = 4
    response_latency = 4
    mshrs = 4
    tgts_per_mshr = 20
    is_read_only = True
    writeback_clean = True


class L1DCache(Cache):
    assoc = 12               # Zen5 L1D widened to 48 KB 12-way
    size = "48kB"
    tag_latency = 4
    data_latency = 4
    write_latency = 4
    response_latency = 4
    mshrs = 4
    tgts_per_mshr = 20


class L2Cache(Cache):
    assoc = 16               # 1 MB private L2 (Zen5)
    size = "1MB"
    tag_latency = 14
    data_latency = 14
    write_latency = 14
    response_latency = 14
    mshrs = 20
    tgts_per_mshr = 12


class L3Cache(Cache):
    assoc = 16
    size = "96MB"            # 9800X3D 96 MB (32 base + 64 V-Cache); overridable
    tag_latency = 40
    data_latency = 40
    write_latency = 40
    response_latency = 20
    mshrs = 64
    tgts_per_mshr = 12
    write_buffers = 16


# ---------------------------- Argument parsing ----------------------------
parser = argparse.ArgumentParser()
parser.add_argument("--cmd", required=True, help="Workload binary path")
parser.add_argument("--options", default="", help="Workload arguments")
parser.add_argument("--cwd", default="",
                    help="Working dir for the SE process(es). Multi-core uses "
                         "<cwd>/core<i> per core (matches se_mram_l3.py).")
parser.add_argument("--cpu-type", default="DerivO3CPU",
                    help="DerivO3CPU (default, Zen5-class) or TimingSimpleCPU")
parser.add_argument("--cpu-clock", default="4.7GHz",
                    help="Core clock (9800X3D base ~4.7 GHz)")
parser.add_argument("--mem-size", default="4GB")
parser.add_argument("--l1d-read-latency", type=int, default=4)
parser.add_argument("--l1d-write-latency", type=int, default=4)
parser.add_argument("--l2-read-latency", type=int, default=14)
parser.add_argument("--l2-write-latency", type=int, default=14)
parser.add_argument("--l3-read-latency", type=int, default=40)
parser.add_argument("--l3-write-latency", type=int, default=40)
parser.add_argument("--l3-write-buffers", type=int, default=16)
parser.add_argument("--l3-size", default="96MB",
                    help="L3 capacity (sweep {32,64,96,128}MB for the thesis).")
parser.add_argument("--ddr5-model", default="6400", choices=list(DDR5_MODELS),
                    help="DDR5 speed grade (stock gem5 part). 5600 is not a "
                         "stock model; 6400 is the closest default.")
parser.add_argument("--max-insts", type=int, default=0,
                    help="Stop each core after N instructions (0 = run to "
                         "completion). Use a fixed N for finite rate sweeps.")
parser.add_argument("--num-cpus", type=int, default=8,
                    help="Cores (default 8 = 9800X3D single CCD). CMP: private "
                         "L1+L2 per core, shared L3, multi-program.")
args = parser.parse_args()


# ---------------------------- System assembly ----------------------------
system = System()
system.clk_domain = SrcClockDomain(
    clock=args.cpu_clock, voltage_domain=VoltageDomain()
)
system.mem_mode = "timing"
system.mem_ranges = [AddrRange(args.mem_size)]


def make_cpu(cpu_id=0):
    if args.cpu_type == "TimingSimpleCPU":
        return TimingSimpleCPU(cpu_id=cpu_id)
    elif args.cpu_type in ("DerivO3CPU", "O3CPU"):
        if DerivO3CPU is None:
            raise SystemExit("DerivO3CPU not available in this gem5 build")
        return DerivO3CPU(cpu_id=cpu_id)
    else:
        raise SystemExit(f"Unsupported cpu-type: {args.cpu_type}")


system.l3bus = L2XBar(width=64)

if args.num_cpus <= 1:
    system.cpu = make_cpu(0)
    system.cpu.icache = L1ICache()
    system.cpu.dcache = L1DCache()
    system.cpu.dcache.tag_latency = args.l1d_read_latency
    system.cpu.dcache.data_latency = args.l1d_read_latency
    system.cpu.dcache.write_latency = args.l1d_write_latency
    system.cpu.icache.cpu_side = system.cpu.icache_port
    system.cpu.dcache.cpu_side = system.cpu.dcache_port
    system.l2bus = L2XBar()
    system.cpu.icache.mem_side = system.l2bus.cpu_side_ports
    system.cpu.dcache.mem_side = system.l2bus.cpu_side_ports
    system.l2 = L2Cache()
    system.l2.tag_latency = args.l2_read_latency
    system.l2.data_latency = args.l2_read_latency
    system.l2.write_latency = args.l2_write_latency
    system.l2.cpu_side = system.l2bus.mem_side_ports
    system.l2.mem_side = system.l3bus.cpu_side_ports
else:
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

# Shared L3
system.l3 = L3Cache()
system.l3.tag_latency = args.l3_read_latency
system.l3.data_latency = args.l3_read_latency
system.l3.write_latency = args.l3_write_latency
system.l3.write_buffers = args.l3_write_buffers
system.l3.size = args.l3_size
system.l3.cpu_side = system.l3bus.mem_side_ports

system.membus = SystemXBar()
system.l3.mem_side = system.membus.cpu_side_ports

if args.num_cpus <= 1:
    system.cpu.createInterruptController()
else:
    for cpu in system.cpu:
        cpu.createInterruptController()

# DDR5 main memory
system.mem_ctrl = MemCtrl()
system.mem_ctrl.dram = DDR5_MODELS[args.ddr5_model]()
system.mem_ctrl.dram.range = system.mem_ranges[0]
system.mem_ctrl.port = system.membus.mem_side_ports
system.system_port = system.membus.cpu_side_ports

# Workload (SE multi-program: each core an independent copy of --cmd)
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
        process = Process(pid=100 + i)
        process.cmd = cmd_line
        if args.cwd:
            process.cwd = f"{args.cwd}/core{i}"
        cpu.workload = process
        cpu.createThreads()
        if args.max_insts > 0:
            cpu.max_insts_any_thread = args.max_insts


print(
    f"[se_mram_modern] 9800X3D-class | cpu={args.cpu_type}x{args.num_cpus} "
    f"@ {args.cpu_clock} | L1D 48kB/12w wl={args.l1d_write_latency} | "
    f"L2 1MB/16w | L3 {args.l3_size}/16w "
    f"r/w={args.l3_read_latency}/{args.l3_write_latency} | "
    f"DDR5-{args.ddr5_model}"
    + (f" | max_insts={args.max_insts}" if args.max_insts else ""),
    flush=True,
)

root = Root(full_system=False, system=system)
m5.instantiate()
exit_event = m5.simulate()
print(f"Exiting @ tick {m5.curTick()} because {exit_event.getCause()}")
