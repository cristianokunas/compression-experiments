# plots_presentation.R - Slide-ready figures for an oral talk
#
# Tells the ARCTO story in four parts:
#   1. Adaptive aggregation (transfer-side optimization).
#   2. Chunk-size optimization (kernel-side).
#   3. ZFP (error-bounded path, orthogonal to both above), with the
#      Barbosa 2023 RTM-safe band and the Lindstrom 2016 F3DT-validated
#      band drawn as PSNR floor regions.
#   4. Time breakdown + peak pinned memory, including a synthetic
#      "GPU-resident" mode that removes the alloc and host staging
#      phases -- argument that a simulation workflow that produces
#      data directly on the GPU pays none of that overhead.
#
# Usage:
#   Rscript plots_presentation.R

suppressPackageStartupMessages({
  library(readr); library(dplyr); library(tidyr); library(ggplot2)
  library(stringr); library(scales)
})

OUTPUT_DIR <- "plots_presentation"
dir.create(OUTPUT_DIR, showWarnings = FALSE)

# ── design system (bumped font sizes for slides) ─────────────────────────────

ALGO_COLORS <- c("lz4"="#F4A582","snappy"="#92C5DE","cascaded"="#A6D96A",
                 "zfp"="#9E6FB9")
ALGO_LABELS <- c("lz4"="LZ4","snappy"="Snappy","cascaded"="Cascaded","zfp"="ZFP")

GPU_COLORS <- c("MI210"="#5B9BD5","MI300X"="#1F4E79","RX7900XT"="#C0392B")

MODE_COLORS <- c("baseline"="#9E9E9E","pinned"="#F4A582",
                 "adaptive"="#4393C3","gpu_resident"="#1A9850")
MODE_LABELS <- c("baseline"="Pageable","pinned"="Pinned (full)",
                 "adaptive"="Pinned adaptive","gpu_resident"="GPU-resident")

ZFP_MODE_COLORS <- c("acc"="#C0392B","rate"="#2166AC","prec"="#1A9850")
ZFP_MODE_LABELS <- c("acc"="Fixed accuracy","rate"="Fixed rate",
                     "prec"="Fixed precision")

PHASE_COLORS_BREAKDOWN <- c("H2D Transfer"="#92C5DE",
                            "Compression"="#F4A582",
                            "Decompression"="#A6D96A",
                            "D2H Transfer"="#FEE090",
                            "Alloc / H2H staging"="#BDA0CC")

GPU_ORDER  <- c("MI210","MI300X","RX7900XT")
ALGO_ORDER <- c("lz4","snappy","cascaded")
MODE_ORDER <- c("baseline","pinned","adaptive","gpu_resident")

SIZE_LABELS <- c("small"="10 MB","medium"="100 MB",
                 "large"="1 GB","xlarge"="4 GB")
SIZE_MAP    <- c("small"=10,"medium"=100,"large"=1024,"xlarge"=4096)

# Larger base font: 17 instead of 14
theme_slide <- function(base = 17) {
  theme_bw(base_size = base) +
    theme(
      panel.grid.minor   = element_blank(),
      panel.grid.major.x = element_blank(),
      panel.grid.major.y = element_line(color="#DDDDDD", linewidth=0.4,
                                        linetype="dashed"),
      panel.border       = element_rect(color="grey75", linewidth=0.6, fill=NA),
      strip.background   = element_rect(fill="grey92", color="grey75"),
      strip.text         = element_text(face="bold", size = base + 2,
                                        margin = margin(7,7,7,7)),
      legend.position    = "top",
      legend.title       = element_text(face="bold", size = base + 1),
      legend.text        = element_text(size = base),
      legend.key.size    = unit(1.2, "lines"),
      axis.title         = element_text(face="bold", size = base + 2),
      axis.text          = element_text(size = base, color="black"),
      plot.title         = element_text(face="bold", size = base + 4,
                                        margin = margin(0,0,6,0)),
      plot.subtitle      = element_text(size = base, color="grey30",
                                        margin = margin(0,0,10,0)),
      plot.margin        = margin(12, 14, 12, 12)
    )
}

save_fig <- function(p, name, w, h) {
  ggsave(file.path(OUTPUT_DIR, paste0(name, ".pdf")), p, width=w, height=h, device="pdf")
  ggsave(file.path(OUTPUT_DIR, paste0(name, ".png")), p, width=w, height=h, dpi=200, device="png")
  cat(sprintf("  ok  %s  (%.1f x %.1f in)\n", name, w, h))
}

# ── load CSVs ────────────────────────────────────────────────────────────────

load_main <- function() {
  df <- read_csv("all_results_chunk64.csv", show_col_types = FALSE,
                 col_types = cols(ZfpParam = col_character()))
  num <- c("FileSizeMB","CompressionRatio","CompThroughputGBs","DecompThroughputGBs",
           "CompTimeMs","DecompTimeMs","TransferH2DMs","TransferD2HMs",
           "TotalTimeMs","AllocMs","MemcpyH2HMs","PeakPinnedBytes",
           "AdaptiveWindowBytes","AdaptiveNumWindows",
           "MaxAbsDiff","RMSE","PSNR","MaxRelErr","AmplitudeRange")
  for (c in num) if (c %in% names(df)) df[[c]] <- suppressWarnings(as.numeric(df[[c]]))
  df |> mutate(
    Dataset = str_extract(TestFile, "(?<=_)(TTI|binary|random|zeros)(?=_)"),
    Size    = str_extract(TestFile, "^(small|medium|large|xlarge)"),
    Algorithm = str_to_lower(Algorithm),
    Mode    = ifelse(is.na(Mode), "", Mode),
    GPU     = factor(EnvLabel, levels = GPU_ORDER)
  )
}

load_chunk <- function() {
  read_csv("chunk_sweeps.csv", show_col_types = FALSE) |>
    mutate(
      CompThroughputGBs   = suppressWarnings(as.numeric(CompThroughputGBs)),
      DecompThroughputGBs = suppressWarnings(as.numeric(DecompThroughputGBs)),
      GPU       = factor(EnvLabel, levels = GPU_ORDER),
      Algorithm = factor(Algorithm, levels = ALGO_ORDER)
    )
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 1 - Adaptive aggregation
# ══════════════════════════════════════════════════════════════════════════════

fig1_adaptive <- function(df) {
  d <- df |>
    filter(Algorithm %in% ALGO_ORDER, Size == "xlarge", Dataset == "TTI") |>
    mutate(
      Algorithm = factor(Algorithm, levels = ALGO_ORDER),
      Mode      = factor(Mode, levels = c("baseline","pinned","adaptive"))
    )

  p <- ggplot(d, aes(x = Algorithm, y = TotalTimeMs, fill = Mode)) +
    geom_col(position = position_dodge(width = 0.8), width = 0.7) +
    geom_text(aes(label = sprintf("%.0f", TotalTimeMs)),
              position = position_dodge(width = 0.8),
              vjust = -0.4, size = 5.2, fontface = "bold") +
    facet_wrap(~GPU, nrow = 1, scales = "free_y") +
    scale_fill_manual(values = MODE_COLORS, labels = MODE_LABELS,
                      name = "Transfer mode") +
    scale_x_discrete(labels = ALGO_LABELS) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.22))) +
    labs(
      title    = "Adaptive aggregation reduces end-to-end time",
      subtitle = "TTI seismic 4 GiB, host-to-device + compress + device-to-host",
      x = "Algorithm",
      y = "Total time (ms)"
    ) +
    theme_slide(18)
  save_fig(p, "fig1_adaptive_total_time_xlarge_TTI", 14, 6.5)

  base <- d |> filter(Mode == "baseline") |>
    select(GPU, Algorithm, base = TotalTimeMs)
  ds <- d |> filter(Mode != "baseline") |>
    left_join(base, by = c("GPU","Algorithm")) |>
    mutate(Speedup = base / TotalTimeMs,
           Mode = factor(Mode, levels = c("pinned","adaptive")))

  p2 <- ggplot(ds, aes(x = Algorithm, y = Speedup, fill = Mode)) +
    geom_col(position = position_dodge(width = 0.8), width = 0.7) +
    geom_hline(yintercept = 1, linetype = "dashed", color = "#C0392B",
               linewidth = 0.7) +
    geom_text(aes(label = sprintf("%.1fx", Speedup)),
              position = position_dodge(width = 0.8),
              vjust = -0.4, size = 5.4, fontface = "bold") +
    facet_wrap(~GPU, nrow = 1) +
    scale_fill_manual(values = MODE_COLORS[c("pinned","adaptive")],
                      labels = MODE_LABELS[c("pinned","adaptive")],
                      name = "Mode (vs pageable baseline)") +
    scale_x_discrete(labels = ALGO_LABELS) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.22))) +
    labs(
      title    = "End-to-end speedup over pageable baseline",
      subtitle = "TTI seismic 4 GiB, three GPU architectures",
      x = "Algorithm",
      y = "Speedup x"
    ) +
    theme_slide(18)
  save_fig(p2, "fig1b_adaptive_speedup_xlarge_TTI", 14, 6.5)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 2 - Chunk-size optimization
# ══════════════════════════════════════════════════════════════════════════════

# All values measured directly from dedicated chunk sweeps:
#   gfx942  - MI300X_CHUNK_SWEEP_*  (2026-05-18)
#   gfx1100 - RX7900XT_CHUNK_SWEEP_20260517_235720
#   gfx90a  - MI210_CHUNK_SWEEP_20260527_051510  (this campaign)
C_KER_OPT <- tribble(
  ~GPU,         ~Algorithm, ~CKerKiB,
  "MI300X",     "lz4",       8,
  "MI300X",     "snappy",    8,
  "MI300X",     "cascaded",  8,
  "RX7900XT",   "lz4",       8,
  "RX7900XT",   "snappy",   16,
  "RX7900XT",   "cascaded", 64,
  "MI210",      "lz4",       8,   # validated 2026-05-27: 8 KiB beats 16 KiB by +12%
  "MI210",      "snappy",    8,   # validated: 8 KiB matches the wave-saturation regime
  "MI210",      "cascaded", 64    # validated: peaks at 64 KiB on 1 GB workload
) |> mutate(
  GPU       = factor(GPU, levels = GPU_ORDER),
  Algorithm = factor(Algorithm, levels = ALGO_ORDER)
)

fig2_chunk <- function(ch) {
  d <- ch |>
    filter(Mode == "baseline",
           Dataset == "tti", Size == "large",
           ChunkSizeKiB >= 8, ChunkSizeKiB <= 4096) |>
    group_by(GPU, Algorithm, ChunkSizeKiB) |>
    summarise(CompThroughputGBs = mean(CompThroughputGBs, na.rm = TRUE), .groups = "drop")

  marks <- C_KER_OPT |>
    filter(GPU %in% levels(droplevels(d$GPU))) |>
    left_join(d, by = c("GPU","Algorithm","CKerKiB"="ChunkSizeKiB"))

  p <- ggplot(d, aes(x = ChunkSizeKiB, y = CompThroughputGBs,
                     color = Algorithm, shape = Algorithm, group = Algorithm)) +
    geom_line(linewidth = 1.2) +
    geom_point(size = 3.5) +
    geom_point(data = marks, aes(x = CKerKiB, y = CompThroughputGBs),
               size = 8, shape = 21, fill = NA, color = "#C0392B",
               stroke = 1.8, inherit.aes = FALSE) +
    facet_wrap(~GPU, nrow = 1, scales = "free_y") +
    scale_color_manual(values = ALGO_COLORS, labels = ALGO_LABELS,
                       name = "Algorithm") +
    scale_shape_manual(values = c("lz4"=16,"snappy"=17,"cascaded"=15),
                       labels = ALGO_LABELS, name = "Algorithm") +
    scale_x_log10(breaks = c(8,16,32,64,256,1024,4096),
                  labels = c("8","16","32","64","256","1024","4096")) +
    scale_y_continuous(expand = expansion(mult = c(0.05, 0.12))) +
    labs(
      title    = "Kernel throughput is chunk-size sensitive (TTI 1 GiB)",
      subtitle = "Red rings: c* picked by per-(arch, algo) profile",
      x = "Chunk size (KiB, log)",
      y = "Compression throughput (GB/s)"
    ) +
    theme_slide(18)
  save_fig(p, "fig2_chunk_sensitivity", 15, 6.5)

  tab <- C_KER_OPT |>
    pivot_wider(names_from = Algorithm, values_from = CKerKiB) |>
    arrange(factor(GPU, levels = GPU_ORDER))
  tab_long <- tab |> pivot_longer(-GPU, names_to = "Algorithm", values_to = "Ck") |>
    mutate(Algorithm = factor(Algorithm, levels = ALGO_ORDER))

  pt <- ggplot(tab_long,
               aes(x = Algorithm, y = factor(GPU, levels = rev(GPU_ORDER)),
                   fill = log2(Ck))) +
    geom_tile(color = "white", linewidth = 1.5) +
    geom_text(aes(label = sprintf("%d KiB", Ck)),
              size = 7.5, fontface = "bold", color = "#1A1A1A") +
    scale_x_discrete(labels = ALGO_LABELS) +
    scale_fill_gradient(low = "#FDDBC7", high = "#D6604D", guide = "none") +
    labs(title = "c* per (architecture, algorithm)",
         x = "Algorithm", y = "GPU") +
    theme_slide(18) +
    theme(panel.border = element_blank(), panel.grid = element_blank(),
          axis.ticks = element_blank())
  save_fig(pt, "fig2b_chunk_table", 10, 5.5)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 3 - ZFP Pareto with horizontal safe-zone bands
#
#  Barbosa & Coutinho 2023: tau=1e-6 preserves RTM migrated image. On
#  TTI 4 GiB this gives PSNR ~113 dB. So PSNR >= 113 dB is "RTM-safe".
#
#  Lindstrom et al. 2016: F3DT validated at tau in [1e-13, 1e-16],
#  beyond our sweep but corresponds to PSNR > ~170-180 dB. We mark
#  PSNR >= 175 dB as the "F3DT-validated" envelope.
# ══════════════════════════════════════════════════════════════════════════════

PSNR_BARBOSA   <- 113   # tau=1e-6 boundary (RTM-image-preserving)
PSNR_LINDSTROM <- 175   # tau~1e-13 envelope (F3DT-validated)

fig3_zfp <- function(df) {
  d <- df |>
    filter(Algorithm == "zfp", Dataset == "TTI", Size == "xlarge",
           !is.na(PSNR), is.finite(PSNR), PSNR > 0) |>
    mutate(
      ZfpMode = factor(Mode, levels = c("acc","rate","prec"),
                       labels = ZFP_MODE_LABELS),
      # sweep_canonical.sh strips the minus in the filename tag
      # (acc1e-6 -> acc1e6), so the persisted ZfpParam for fixed-accuracy
      # is "1eN" but actually denotes tau = 1e-N. Restore the sign here.
      ParamLabel = case_when(
        Mode == "acc"  ~ paste0("tau=", str_replace(ZfpParam, "e", "e-")),
        Mode == "rate" ~ paste0(ZfpParam, " bpv"),
        Mode == "prec" ~ paste0("p=", ZfpParam),
        TRUE           ~ as.character(ZfpParam)
      )
    )
  first_gpu <- levels(droplevels(d$GPU))[1]
  d1 <- d |> filter(GPU == first_gpu)

  x_lo <- min(0.95, min(d1$CompressionRatio, na.rm = TRUE) * 0.9)
  x_hi <- max(d1$CompressionRatio, na.rm = TRUE) * 1.6
  y_hi <- max(d1$PSNR, na.rm = TRUE) + 15

  p <- ggplot(d1, aes(x = CompressionRatio, y = PSNR)) +
    # Lindstrom-validated (top band)
    annotate("rect", xmin = x_lo, xmax = x_hi,
             ymin = PSNR_LINDSTROM, ymax = y_hi,
             fill = "#5B9BD5", alpha = 0.18) +
    # Barbosa RTM-safe (middle band, between Lindstrom and Barbosa floor)
    annotate("rect", xmin = x_lo, xmax = x_hi,
             ymin = PSNR_BARBOSA, ymax = PSNR_LINDSTROM,
             fill = "#A6D96A", alpha = 0.18) +
    # Boundary lines + labels
    geom_hline(yintercept = PSNR_BARBOSA,   color = "#1A9850",
               linetype = "dashed", linewidth = 0.7) +
    geom_hline(yintercept = PSNR_LINDSTROM, color = "#2166AC",
               linetype = "dashed", linewidth = 0.7) +
    annotate("text", x = x_hi, y = (PSNR_BARBOSA + PSNR_LINDSTROM)/2,
             label = "RTM-image-preserving\n(Barbosa 2023; tau <= 1e-6)",
             hjust = 1.05, size = 5.0, color = "#1A6028", fontface = "bold") +
    annotate("text", x = x_hi, y = (PSNR_LINDSTROM + y_hi)/2,
             label = "F3DT-validated envelope\n(Lindstrom 2016; tau <= 1e-13)",
             hjust = 1.05, size = 5.0, color = "#2050A0", fontface = "bold") +
    geom_point(aes(color = ZfpMode, shape = ZfpMode),
               size = 5.5, stroke = 1.0) +
    geom_text(aes(label = ParamLabel),
              hjust = -0.15, vjust = 0.3, size = 5.2,
              fontface = "bold") +
    scale_color_manual(values = setNames(unname(ZFP_MODE_COLORS),
                                         ZFP_MODE_LABELS[names(ZFP_MODE_COLORS)]),
                       name = "ZFP mode") +
    scale_shape_manual(values = setNames(c(16,17,15),
                                         ZFP_MODE_LABELS[names(ZFP_MODE_COLORS)]),
                       name = "ZFP mode") +
    scale_x_log10(limits = c(x_lo, x_hi),
                  breaks = c(0.8, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 2, 2.5, 3, 4, 5, 7, 10, 15),
                  minor_breaks = c(seq(0.8, 2, 0.1), seq(2, 5, 0.25), seq(5, 15, 1)),
                  expand = expansion(mult = c(0, 0))) +
    scale_y_continuous(limits = c(min(d1$PSNR, na.rm=TRUE) - 10, y_hi),
                       breaks = seq(20, 200, 10),
                       minor_breaks = seq(20, 200, 5),
                       expand = expansion(mult = c(0, 0))) +
    labs(
      title    = "ZFP: ratio vs reconstruction PSNR, with literature safe zones",
      subtitle = "TTI seismic 4 GiB. Green band: preserves RTM image. Blue band: F3DT-grade fidelity.",
      x = "Compression ratio (log)",
      y = "PSNR (dB)"
    ) +
    theme_slide(17) +
    theme(
      panel.grid.minor   = element_line(color = "#EEEEEE", linewidth = 0.3),
      panel.grid.major.x = element_line(color = "#DDDDDD", linewidth = 0.4,
                                        linetype = "dashed"),
      axis.text.x        = element_text(size = 12)
    )
  save_fig(p, "fig3_zfp_pareto", 14, 8)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 4 - ZFP PSNR vs ratio per mode, line-plot style (draft fig04 idiom)
# ══════════════════════════════════════════════════════════════════════════════

fig4_zfp_line <- function(df) {
  d <- df |>
    filter(Algorithm == "zfp", Dataset == "TTI", Size == "xlarge",
           !is.na(PSNR), is.finite(PSNR), PSNR > 0) |>
    mutate(ZfpMode = factor(Mode, levels = c("acc","rate","prec"),
                            labels = ZFP_MODE_LABELS),
           series = paste0(as.character(ZfpMode), " (", as.character(GPU), ")"))

  p <- ggplot(d, aes(x = CompressionRatio, y = PSNR,
                     color = ZfpMode, shape = ZfpMode, group = series)) +
    geom_line(linewidth = 1.0) +
    geom_point(size = 4.5, stroke = 1.0) +
    scale_color_manual(values = setNames(unname(ZFP_MODE_COLORS),
                                         ZFP_MODE_LABELS[names(ZFP_MODE_COLORS)]),
                       name = "ZFP mode") +
    scale_shape_manual(values = setNames(c(16,17,15),
                                         ZFP_MODE_LABELS[names(ZFP_MODE_COLORS)]),
                       name = "ZFP mode") +
    scale_x_log10(expand = expansion(mult = c(0.05, 0.10))) +
    scale_y_continuous(expand = expansion(mult = c(0.05, 0.10))) +
    labs(
      title    = "ZFP quality vs compression ratio (lines per mode)",
      subtitle = "TTI seismic 4 GiB; three GPUs overlap (ZFP is GPU-independent on these metrics)",
      x = "Compression ratio (log)",
      y = "PSNR (dB)"
    ) +
    theme_slide(17)
  save_fig(p, "fig4_zfp_ratio_vs_psnr", 13, 6.5)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 5 - Time breakdown by phase, including synthetic GPU-resident
#
#  Pageable / Pinned full / Pinned adaptive come from the measured CSV.
#  GPU-resident is a model: simulation produces data directly on the
#  GPU, so the H2D transfer disappears, and so does alloc and host
#  staging. We model:
#      GPU-resident time = Compression + Decompression + D2H (compressed)
#  using the kernel times already measured. (D2H is kept the same since
#  the compressed output still has to leave the device.)
# ══════════════════════════════════════════════════════════════════════════════

fig5_breakdown <- function(df) {
  d <- df |>
    filter(Algorithm %in% ALGO_ORDER, Size == "xlarge", Dataset == "TTI") |>
    mutate(StagingMs = pmax(coalesce(AllocMs, 0) + coalesce(MemcpyH2HMs, 0), 0),
           Algorithm = factor(Algorithm, levels = ALGO_ORDER))

  # Build the measured rows
  measured <- d |>
    select(GPU, Algorithm, Mode,
           TransferH2DMs, CompTimeMs, DecompTimeMs, TransferD2HMs, StagingMs)

  # Build the synthetic GPU-resident rows: take the adaptive run and
  # zero out alloc/h2h staging and H2D (input is already on the GPU).
  # D2H is preserved because the compressed payload still goes back to
  # the host.
  gpu_resident <- d |>
    filter(Mode == "adaptive") |>
    transmute(GPU, Algorithm,
              Mode = "gpu_resident",
              TransferH2DMs = 0,
              CompTimeMs    = CompTimeMs,
              DecompTimeMs  = DecompTimeMs,
              TransferD2HMs = TransferD2HMs,   # compressed payload still leaves the device
              StagingMs     = 0)

  data <- bind_rows(measured, gpu_resident) |>
    mutate(Mode = factor(Mode, levels = MODE_ORDER, labels = MODE_LABELS[MODE_ORDER])) |>
    pivot_longer(c(TransferH2DMs, CompTimeMs, DecompTimeMs,
                   TransferD2HMs, StagingMs),
                 names_to = "Phase", values_to = "TimeMs") |>
    mutate(Phase = factor(Phase,
      levels = c("StagingMs","TransferH2DMs","CompTimeMs",
                 "DecompTimeMs","TransferD2HMs"),
      labels = c("Alloc / H2H staging","H2D Transfer",
                 "Compression","Decompression","D2H Transfer")))

  p <- ggplot(data, aes(x = Mode, y = TimeMs, fill = Phase)) +
    geom_col(width = 0.85, color = NA) +
    facet_grid(Algorithm ~ GPU,
               labeller = labeller(Algorithm = ALGO_LABELS),
               scales = "free_y") +
    scale_fill_manual(values = PHASE_COLORS_BREAKDOWN, name = "Phase") +
    scale_y_continuous(expand = expansion(mult = c(0, 0.06))) +
    labs(
      title    = "Time breakdown per phase, with synthetic GPU-resident mode",
      subtitle = "TTI seismic 4 GiB. In a GPU-resident workflow the alloc/H2H and H2D phases disappear.",
      x = "Mode",
      y = "Execution time (ms)"
    ) +
    theme_slide(15) +
    theme(axis.text.x = element_text(angle = 30, hjust = 1, size = 12))
  save_fig(p, "fig5_breakdown_with_gpu_resident", 15, 9)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 6 - Peak pinned-host memory: full pinned vs adaptive across sizes
# ══════════════════════════════════════════════════════════════════════════════

fig6_peak_pinned <- function(df, algo_pick = "lz4") {
  d <- df |>
    filter(Algorithm == algo_pick, Dataset == "TTI",
           Mode %in% c("pinned","adaptive"),
           !is.na(PeakPinnedBytes), PeakPinnedBytes > 0) |>
    mutate(peak_MiB = PeakPinnedBytes / (1024 * 1024),
           Mode     = factor(Mode, levels = c("pinned","adaptive")),
           Size     = factor(Size, levels = c("small","medium","large","xlarge"),
                             labels = SIZE_LABELS))

  p <- ggplot(d, aes(x = Size, y = peak_MiB, fill = Mode)) +
    geom_col(position = position_dodge(width = 0.7), width = 0.6) +
    geom_text(aes(label = sprintf("%.0f", peak_MiB)),
              position = position_dodge(width = 0.7),
              vjust = -0.4, size = 4.5, fontface = "bold") +
    facet_wrap(~GPU, nrow = 1) +
    scale_fill_manual(values = MODE_COLORS[c("pinned","adaptive")],
                      labels = MODE_LABELS[c("pinned","adaptive")],
                      name = "Mode") +
    scale_y_log10(labels = function(x) sprintf("%g", x),
                  expand = expansion(mult = c(0.05, 0.20))) +
    labs(
      title    = "Adaptive aggregation bounds peak pinned host memory",
      subtitle = sprintf("%s / TTI: pinned-full scales with input, adaptive stays at the wave-saturation window",
                        toupper(algo_pick)),
      x = "Input size",
      y = "Peak pinned host memory (MiB, log)"
    ) +
    theme_slide(17)
  save_fig(p, "fig6_peak_pinned", 14, 6.5)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 7 - Lossless compression ratio: chunk64 vs chunkopt
#
#  Cascaded is chunk-insensitive (ratio identical at any chunk). LZ4
#  trades ratio for kernel throughput on highly compressible data:
#  small chunks compress the hash tables less effectively, so ratio
#  degrades on zeros (245x -> ~200x). Snappy can actually improve on
#  binary. TTI/random are near 1.0 in all cases (incompressible).
# ══════════════════════════════════════════════════════════════════════════════

fig7_lossless_ratio <- function(df_chunk64, df_chunkopt_path) {
  df_opt <- read_csv(df_chunkopt_path, show_col_types = FALSE) |>
    mutate(
      Dataset = str_extract(TestFile, "(?<=_)(TTI|binary|random|zeros)(?=_)"),
      Size    = str_extract(TestFile, "^(small|medium|large|xlarge)"),
      Algorithm = str_to_lower(Algorithm),
      Mode = ifelse(is.na(Mode), "", Mode),
      GPU  = factor(EnvLabel, levels = GPU_ORDER),
      CompressionRatio = suppressWarnings(as.numeric(CompressionRatio))
    ) |>
    filter(Algorithm %in% ALGO_ORDER, Mode == "adaptive", Size == "xlarge") |>
    select(GPU, Dataset, Algorithm, ratio_opt = CompressionRatio)

  df_a <- df_chunk64 |>
    filter(Algorithm %in% ALGO_ORDER, Mode == "adaptive", Size == "xlarge") |>
    select(GPU, Dataset, Algorithm, ratio_64 = CompressionRatio)

  common_gpus <- intersect(levels(droplevels(df_a$GPU)),
                           levels(droplevels(df_opt$GPU)))
  d <- df_a |>
    inner_join(df_opt, by = c("GPU","Dataset","Algorithm")) |>
    filter(GPU %in% common_gpus) |>
    pivot_longer(c(ratio_64, ratio_opt),
                 names_to = "Chunk", values_to = "Ratio") |>
    mutate(
      Chunk = factor(Chunk, levels = c("ratio_64","ratio_opt"),
                     labels = c("chunk64","chunk_opt")),
      Algorithm = factor(Algorithm, levels = ALGO_ORDER),
      Dataset   = factor(Dataset,
                         levels = c("zeros","binary","random","TTI"),
                         labels = c("Zeros","Binary","Random","TTI")),
      log_ratio = log10(pmax(Ratio, 1)),
      label_ratio = case_when(
        Ratio < 10  ~ sprintf("%.2fx", Ratio),
        Ratio < 100 ~ sprintf("%.1fx", Ratio),
        TRUE        ~ sprintf("%.0fx", Ratio)
      ),
      text_color = ifelse(log_ratio > 1.4, "white", "#1A1A1A")
    )

  # Main heatmap: facet_grid(Chunk ~ Algorithm), x = Dataset, y = GPU
  p <- ggplot(d, aes(x = Dataset, y = GPU, fill = log_ratio)) +
    geom_tile(color = "white", linewidth = 1.5) +
    geom_text(aes(label = label_ratio, color = text_color),
              size = 5.2, fontface = "bold") +
    facet_grid(Chunk ~ Algorithm, labeller = labeller(Algorithm = ALGO_LABELS)) +
    scale_fill_gradientn(
      colours = c("#D1E5F0","#92C5DE","#4393C3","#2166AC","#0F3F70"),
      limits  = c(0, log10(260)),
      breaks  = c(0, 1, 2),
      labels  = c("1x","10x","100x"),
      name    = "Ratio"
    ) +
    scale_color_identity() +
    scale_y_discrete(limits = rev) +
    labs(
      title    = "Lossless compression ratio: chunk = 64 KiB vs c*",
      subtitle = "TTI 4 GiB workload. Same color scale across panels for direct comparison.",
      x = "Dataset",
      y = "GPU"
    ) +
    theme_slide(17) +
    theme(panel.grid = element_blank(), panel.border = element_blank(),
          axis.ticks = element_blank(),
          legend.position = "right", legend.direction = "vertical",
          legend.key.height = unit(1.5, "cm"),
          legend.key.width  = unit(0.5, "cm"))

  ngpus <- length(common_gpus)
  save_fig(p, "fig7_lossless_ratio_heatmap", 16, 1.4 * ngpus + 5)

  # Companion: delta heatmap (chunkopt - chunk64) / chunk64 * 100
  delta <- df_a |>
    inner_join(df_opt, by = c("GPU","Dataset","Algorithm")) |>
    filter(GPU %in% common_gpus) |>
    mutate(
      delta_pct = (ratio_opt - ratio_64) / ratio_64 * 100,
      Algorithm = factor(Algorithm, levels = ALGO_ORDER),
      Dataset   = factor(Dataset,
                         levels = c("zeros","binary","random","TTI"),
                         labels = c("Zeros","Binary","Random","TTI")),
      label_d   = sprintf("%+.1f%%", delta_pct),
      text_d    = ifelse(abs(delta_pct) > 12, "white", "#1A1A1A")
    )

  p2 <- ggplot(delta, aes(x = Dataset, y = GPU, fill = delta_pct)) +
    geom_tile(color = "white", linewidth = 1.5) +
    geom_text(aes(label = label_d, color = text_d),
              size = 5.2, fontface = "bold") +
    facet_wrap(~Algorithm, nrow = 1, labeller = labeller(Algorithm = ALGO_LABELS)) +
    scale_fill_gradient2(low = "#C0392B", mid = "#FEE090", high = "#1A9850",
                         midpoint = 0, limits = c(-25, 15),
                         name = "Delta (%)", oob = squish) +
    scale_color_identity() +
    scale_y_discrete(limits = rev) +
    labs(
      title    = "Ratio change: chunkopt vs chunk-64",
      subtitle = "Red: chunkopt loses ratio. Green: chunkopt gains. Cascaded is chunk-insensitive.",
      x = "Dataset",
      y = "GPU"
    ) +
    theme_slide(17) +
    theme(panel.grid = element_blank(), panel.border = element_blank(),
          axis.ticks = element_blank(),
          legend.position = "right", legend.direction = "vertical",
          legend.key.height = unit(1.5, "cm"),
          legend.key.width  = unit(0.5, "cm"))

  save_fig(p2, "fig7b_lossless_ratio_delta", 16, 1.4 * ngpus + 3)
}

# ══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════════════════

cat("\nLoading consolidated CSVs ...\n")
df  <- load_main()
ch  <- load_chunk()
cat(sprintf("  main rows  : %d (%s)\n", nrow(df),
            paste(levels(droplevels(df$GPU)), collapse = ", ")))
cat(sprintf("  chunk rows : %d (%s)\n", nrow(ch),
            paste(levels(droplevels(ch$GPU)), collapse = ", ")))
cat("\n")

cat("FIG 1 - Adaptive aggregation\n")
fig1_adaptive(df)

cat("FIG 2 - Chunk-size optimization\n")
fig2_chunk(ch)

cat("FIG 3 - ZFP Pareto with safe-zone bands\n")
fig3_zfp(df)

cat("FIG 4 - ZFP PSNR vs ratio (line per mode)\n")
fig4_zfp_line(df)

cat("FIG 5 - Time breakdown with synthetic GPU-resident\n")
fig5_breakdown(df)

cat("FIG 6 - Peak pinned host memory\n")
fig6_peak_pinned(df)

cat("FIG 7 - Lossless compression ratio: chunk64 vs chunkopt\n")
fig7_lossless_ratio(df_chunk64 = df,
                    df_chunkopt_path = "all_results_chunkopt.csv")

cat(sprintf("\nDone. Figures in ./%s/\n", OUTPUT_DIR))
