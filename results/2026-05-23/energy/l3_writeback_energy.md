# L3 MRAM writeback energy (hidden cost)

From `writeback_hiding/sweep.csv` (memstress 32MB, all 6 configs):

| metric | value | note |
|---|---:|---|
| L3 accesses (total) | 4,195,630 | 100% miss (32MB > L3 16MB) |
| L3 writebacks IN | 2,097,305 | from L2, each writes the L3 array |
| L3 misses OUT | 4,195,630 | to DRAM |

Energy (Everspin Ewr = 97.020 nJ/write):
  E_writeback = 2,097,305 × 97.02 nJ = **203.4 mJ**

This is the energy charged to the MRAM array on every L2->L3 writeback.
None of it shows up in simTicks because writebacks are fire-and-forget
(pkt->needsResponse()==false in handleTimingReqHit).

L3 read energy on this workload = 0 (no L3 hits in a 32MB-streaming
benchmark). To exercise the read path we need a workload with a
working set between L2 (256KB) and L3 (16MB).

Take-away for the thesis: even though MRAM L3 wlat is invisible in
simTicks across (35/40/50) × (buffers 4/16), the **per-writeback
energy cost is fully exposed** (~200 mJ on this short workload).
This is the quantitative version of "speed is hidden, energy is not".
