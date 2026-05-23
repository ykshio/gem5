# Round-3 J: L3 total energy (dynamic + leakage)

## Setup
- Workload: memstress WS=4MB (Round-2 F result)
- L3 16 MB, 22 nm
- Runtime taken from gem5 simTicks (1 tick = 1 ps)
- Dynamic energy = reads × Erd + writebacks-in × Ewr
- Leakage power: see `PARAMS_leakage.md` (literature values, pending DESTINY rerun)

## Per-technology energy components

| Technology     | time [ms] | E_dynamic [mJ] | E_leakage [mJ] | E_total [mJ] |
|----------------|----------:|---------------:|---------------:|-------------:|
| SRAM 40/40     | 64.529    | 0.049          | 322.644        | **322.693**  |
| STT-MRAM 10/35 | 48.824    | 62.380         | 9.765          | **72.145**   |
| SOT-MRAM 10/35 | 48.824    | 43.107         | 7.324          | **50.431**   |

## Total energy ratio vs SRAM (lower = better)

| Technology     | total ratio | speed ratio | dynamic ratio |
|----------------|-----------:|------------:|---------------:|
| STT-MRAM       | **0.224×** (77.6% reduction)  | 1.322× | 1273× (worse) |
| SOT-MRAM       | **0.156×** (84.4% reduction)  | 1.322× |  880× (worse) |

## The reversal

- **Dynamic only**: SRAM wins by 1000-1300×.
- **Add leakage**: SRAM's 5.0 W static drain over 64.5 ms dominates the
  comparison; MRAM's 0.20 W is negligible.
- **Net result**: MRAM L3 uses 4-6× LESS total energy AND runs 1.32×
  FASTER than SRAM L3.

This is the headline slide for the 6/10 presentation: a single
stacked bar showing red (dynamic) + blue (leakage) for SRAM /
STT / SOT making the inversion visually obvious.

## Three-line thesis takeaway

1. Static-power-dominated regime: SRAM L3 leaks 322 mJ over a 65 ms run.
2. MRAM L3 spends 62 mJ on dynamic writes (the "unhidden" cost), but
   only 10 mJ on leakage thanks to non-volatility.
3. Net energy reduction is 78-84% AND a 1.32× speedup — MRAM L3 is the
   right design choice on both axes simultaneously.

## Caveats
- Leakage powers are literature estimates (Mittal 2014, Sun 2011, Oboril 2015).
  Replace with DESTINY at 22 nm before thesis publication.
- Workload is small (~50 ms). On longer-running benchmarks the leakage
  advantage of MRAM grows, so the conclusion holds a fortiori.
- This analysis covers L3 only. L1 should remain SRAM (Round-2 H).
- L2 is not analyzed here; preliminary expectation: MRAM L2 is borderline
  (smaller capacity, less leakage savings, but higher dynamic write traffic).
