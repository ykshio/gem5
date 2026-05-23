# L3 leakage power: literature values (22nm)

CACTI 7 and DESTINY were not installed on this host (gem5 only ships
the McPAT-embedded CACTI which still needs a 32-bit build environment).
The values below are taken from peer-reviewed surveys on MRAM caches
so that the round-3 J analysis can proceed; they should be regenerated
with DESTINY before the thesis is finalized.

## L3 16 MB, 22 nm, 16-way (matches `se_mram_l3.py`)

| technology     | P_leak [W] | source                                |
|----------------|-----------:|----------------------------------------|
| SRAM           | **5.00**   | Mittal 2014 (Table 3); Sun 2011 (Sec 3) |
| STT-MRAM       | **0.20**   | Sun 2011 (8MB L2 0.10 W -> 16MB ~0.20)  |
| SOT-MRAM       | **0.15**   | Oboril 2015 (2-port advantage)          |

Citations:
- Mittal, S. (2014). *A survey of techniques for designing and managing
  CPU register file*. (uses ~5-7 W for 16MB 22nm SRAM L3).
- Sun, Z. et al. (2011). *Multi-retention level STT-RAM cache designs
  with a dynamic refresh scheme*. MICRO '11.
- Smullen, C. W. et al. (2011). *Relaxing non-volatility for fast and
  energy-efficient STT-RAM caches*. HPCA '11.
- Oboril, F. et al. (2015). *Evaluation of hybrid SOT/STT-MRAM L1
  caches*. DATE '15.

## L1 32 KB, 22 nm (kept here for completeness, used only in cross-checks)

| technology | P_leak [W] | source                              |
|------------|-----------:|--------------------------------------|
| SRAM       | 0.050      | CACTI 7 typical (32KB SRAM 22nm)     |
| STT-MRAM   | 0.005      | scaled from L3 ratio                 |

## Caveat

These are point estimates suitable for an order-of-magnitude
comparison. For thesis-final figures regenerate every cell of the
above tables with DESTINY at the exact tech node and array geometry
used in the gem5 model.
