# Negative results

Work that was measured and did not hold. Kept here rather than deleted: each
directory is the evidence behind a decision made elsewhere, and a rejected
hypothesis is only defensible while its measurement survives.

| Directory | What it was | Outcome |
|---|---|---|
| `hybrid-motivating/` | Adaptive per-frame hybrid LZ4/ZFP compressor for the SSCAD 2026 paper, selecting a codec from each wavefield frame's sampled zero fraction | **Dropped 2026-08-19.** `frame_analysis.csv` shows LZ4 winning **0 of 101 frames**. Even at frame 0, 100 % zeros — exactly the regime the selector was designed for — LZ4 reaches 245x against ZFP's 2048x. The selector has no regime to select. |

The hybrid result is what justifies the thesis turning to error-bounded lossy
ZFP for the wavefield: byte-level lossless does not earn its place on this data
even where the field is already zeroed, which extends to the sparse end the
conclusion ICCSA reached for the dense wavefield.
