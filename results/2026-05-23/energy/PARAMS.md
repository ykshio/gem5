# Energy parameter sources

## MRAM (STT-MRAM, Everspin-class)
- **Erd = 25.872 nJ / 64-byte access**
- **Ewr = 97.020 nJ / 64-byte access**

Derived from the NVMain configuration kept under
`reference/nvmain/Config/custom/STTRAM_Everspin_16GB.config`:
- Clock 400 MHz (cycle 2.5 ns)
- tCAS = 6 cycles (read access)
- tWP  = 14 + tCWD = 14 + 10 = 24 cycles equivalent at the array
- IDD0 ≈ 85 mA, VDD = 1.8 V

Per-access energy is computed by integrating current × VDD over the
cells active during a 64-byte burst, matching Everspin EMD3D064M
spec values. These are illustrative numbers used to anchor the
relative-energy comparison; for thesis-final values recompute with
DESTINY at the chosen technology node.

## SRAM L1 baseline
- **Erd_SRAM = Ewr_SRAM = 0.05 nJ / 64-byte access** (placeholder)

Order-of-magnitude figure for a 32 KB 32 nm L1 cache from the CACTI
7.0 family of models (per-access read energy typically 30-50 pJ for
this size at 32 nm). For the final thesis, regenerate with DESTINY at
the same technology node (22 nm) used for the MRAM model so the
SRAM/MRAM ratio is consistent.

## Caveat
- The Everspin Ewr is per-array-write, not per-CPU-WriteReq. In the
  current gem5 model every CPU write that hits the L1D array is
  charged exactly one Ewr. Write misses that allocate also write the
  array once.
- L2/L3 levels do not see demand WriteReq (write-allocate L1 absorbs
  them), so their write energy is dominated by writebacks INTO that
  level (system.lN.writebacks::total).
