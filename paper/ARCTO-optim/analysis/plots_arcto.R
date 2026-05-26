# plots_arcto.R - Figuras para o paper ARCTO (SBAC-PAD 2026)
#
# Reads the consolidated CSV emitted by consolidate_results.py and
# produces the evaluation figures. The CSV schema is ICCSA26-aligned
# (Algorithm, TestFile, FileSizeBytes/MB, ChunkSize, CompressionRatio,
# CompThroughputGBs/DecompThroughputGBs, CompTimeMs, DecompTimeMs,
# TransferH2DMs/D2HMs, TotalTimeMs, *_StdDev*, EnvLabel/GPU/GPUArch,
# Iterations/Warmup/Timestamp) with ARCTO-specific extras (Mode,
# ZfpParam, AllocMs, MemcpyH2HMs, PeakPinnedBytes,
# AdaptiveWindowBytes, AdaptiveNumWindows, MaxAbsDiff, RMSE, PSNR,
# MaxRelErr, AmplitudeRange).
#
# Usage:
#   Rscript plots_arcto.R all_results.csv [pcie_curve.csv]
#
# The PCIe curve CSV is the output of microbench/pcie/run_pcie_sweep.sh
# (one row per (host, transfer_size) point).

suppressPackageStartupMessages({
  # Load tidyverse components individually so this works on hosts that
  # have the core packages but cannot install the `tidyverse`
  # meta-package (system deps for gargle/googledrive/ragg/etc.).
  library(readr)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(stringr)
  library(purrr)
  library(scales)
})

# ══════════════════════════════════════════════════════════════════════════════
#  DESIGN SYSTEM (lifted from plots_iccsa_v4.R)
# ══════════════════════════════════════════════════════════════════════════════

OUTPUT_DIR <- "plots_output"
dir.create(OUTPUT_DIR, showWarnings = FALSE)

ALGO_COLORS <- c(
  "lz4"      = "#F4A582",
  "snappy"   = "#92C5DE",
  "cascaded" = "#A6D96A",
  "zfp"      = "#9E6FB9"
)
ALGO_LABELS <- c(
  "lz4"      = "LZ4",
  "snappy"   = "Snappy",
  "cascaded" = "Cascaded",
  "zfp"      = "ZFP"
)

GPU_COLORS <- c(
  "MI50"     = "#A0A0A0",
  "MI210"    = "#5B9BD5",
  "MI300X"   = "#1F4E79",
  "RX7900XT" = "#C0392B"
)

MODE_COLORS <- c(
  "baseline" = "#9E9E9E",
  "pinned"   = "#F4A582",
  "adaptive" = "#4393C3"
)
MODE_LABELS <- c(
  "baseline" = "Pageable",
  "pinned"   = "Pinned (full)",
  "adaptive" = "Pinned adaptive"
)

PHASE_COLORS_OVERHEAD <- c(
  "Compute"            = "#F4A582",
  "H2D and D2H Transfer" = "#92C5DE"
)

GPU_ORDER      <- c("MI50", "MI210", "MI300X", "RX7900XT")
ALGO_ORDER     <- c("lz4", "snappy", "cascaded")
MODE_ORDER     <- c("baseline", "pinned", "adaptive")
DATASET_ORDER  <- c("zeros", "binary", "random", "TTI")
DATASET_LABELS <- c(
  "zeros"  = "Zeros",
  "binary" = "Binary",
  "random" = "Random",
  "TTI"    = "TTI (seismic)"
)
SIZE_ORDER  <- c("small", "medium", "large", "xlarge")
SIZE_LABELS <- c("small" = "10 MB", "medium" = "100 MB",
                 "large" = "1 GB",  "xlarge" = "4 GB")
SIZE_MAP    <- c("small" = 10, "medium" = 100, "large" = 1024, "xlarge" = 4096)

theme_arcto <- function(base_size = 9.4) {
  theme_bw(base_size = base_size) +
    theme(
      panel.grid.minor   = element_blank(),
      panel.grid.major.x = element_blank(),
      panel.grid.major.y = element_line(color = "#DDDDDD", linewidth = 0.35,
                                        linetype = "dashed"),
      panel.border       = element_rect(color = "grey80", linewidth = 0.5, fill = NA),
      panel.background   = element_rect(fill = "white", color = NA),
      strip.background   = element_rect(fill = "grey95", color = "grey80"),
      strip.text         = element_text(face = "bold", size = base_size,
                                        color = "black",
                                        margin = margin(4, 4, 4, 4)),
      legend.position    = "top",
      legend.direction   = "horizontal",
      legend.title       = element_text(face = "bold", size = base_size - 1),
      legend.text        = element_text(size = base_size - 2),
      legend.background  = element_blank(),
      legend.key         = element_blank(),
      legend.key.size    = unit(0.85, "lines"),
      legend.margin      = margin(0, 0, 4, 0),
      axis.title         = element_text(face = "bold", size = base_size),
      axis.text          = element_text(size = base_size - 2, color = "black"),
      axis.ticks         = element_line(color = "grey60", linewidth = 0.35),
      axis.ticks.length  = unit(3, "pt"),
      plot.background    = element_rect(fill = "white", color = NA),
      plot.margin        = margin(6, 8, 6, 6)
    )
}

save_fig <- function(p, name, width, height) {
  ggsave(file.path(OUTPUT_DIR, paste0(name, ".pdf")),
         p, width = width, height = height, device = "pdf")
  ggsave(file.path(OUTPUT_DIR, paste0(name, ".png")),
         p, width = width, height = height, dpi = 300, device = "png")
  cat(sprintf("  ok  %s\n", name))
}

# ══════════════════════════════════════════════════════════════════════════════
#  LOAD & PREPARE DATA
# ══════════════════════════════════════════════════════════════════════════════

load_csv <- function(path) {
  df <- read_csv(path, show_col_types = FALSE)

  # Coerce numerics (consolidate_results.py emits strings via DictWriter)
  num_cols <- c("FileSizeBytes", "FileSizeMB", "ChunkSize",
                "CompressionRatio",
                "CompThroughputGBs", "DecompThroughputGBs",
                "CompTimeMs", "DecompTimeMs",
                "TransferH2DMs", "TransferD2HMs", "TotalTimeMs", "AvgChunkTimeMs",
                "CompThroughputStdDev", "DecompThroughputStdDev",
                "CompTimeStdDevMs", "DecompTimeStdDevMs",
                "AllocMs", "MemcpyH2HMs",
                "PeakPinnedBytes", "AdaptiveWindowBytes", "AdaptiveNumWindows",
                "MaxAbsDiff", "RMSE", "PSNR", "MaxRelErr", "AmplitudeRange")
  for (col in num_cols) {
    if (col %in% names(df)) {
      df[[col]] <- suppressWarnings(as.numeric(df[[col]]))
    }
  }

  df <- df |>
    mutate(
      Dataset   = str_extract(TestFile, "(?<=_)(TTI|binary|random|zeros)(?=_)"),
      Size      = str_extract(TestFile, "^(small|medium|large|xlarge)"),
      Algorithm = str_to_lower(Algorithm),
      Mode      = ifelse(is.na(Mode), "", Mode),
      ZfpParam  = ifelse(is.na(ZfpParam), "", ZfpParam)
    )

  df |> mutate(
    GPU       = factor(EnvLabel, levels = GPU_ORDER),
    Dataset   = factor(Dataset, levels = DATASET_ORDER,
                       labels = DATASET_LABELS[DATASET_ORDER]),
    Size      = factor(Size,    levels = SIZE_ORDER)
  )
}

# Convenience splitters
lossless_rows <- function(df) df |> filter(Algorithm %in% ALGO_ORDER)
zfp_rows      <- function(df) df |> filter(Algorithm == "zfp")

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 1 - Cross-mode total time (CENTRAL)
#     Bars: baseline / pinned / adaptive TotalTimeMs, x = Algorithm,
#     facet by GPU. TTI 4 GiB canonical workload.
# ══════════════════════════════════════════════════════════════════════════════

fig1_cross_mode_time <- function(df, size_pick = "xlarge", dataset_pick = "TTI (seismic)") {
  data <- lossless_rows(df) |>
    filter(Size == size_pick, Dataset == dataset_pick) |>
    mutate(
      Mode      = factor(Mode, levels = MODE_ORDER),
      Algorithm = factor(Algorithm, levels = ALGO_ORDER)
    )
  if (nrow(data) == 0) {
    message("  fig1: no rows for size=", size_pick, " dataset=", dataset_pick)
    return(invisible(NULL))
  }

  p <- ggplot(data,
              aes(x = Algorithm, y = TotalTimeMs, fill = Mode)) +
    geom_col(position = position_dodge(width = 0.8),
             width = 0.7, color = NA) +
    geom_text(aes(label = sprintf("%.0f", TotalTimeMs)),
              position = position_dodge(width = 0.8),
              vjust = -0.4, size = 2.4) +
    facet_wrap(~GPU, nrow = 1, scales = "free_y") +
    scale_fill_manual(values = MODE_COLORS, labels = MODE_LABELS, name = "Mode") +
    scale_x_discrete(labels = ALGO_LABELS) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.14))) +
    labs(x = "Algorithm",
         y = sprintf("Total time (ms)  -  %s %s",
                     dataset_pick, SIZE_LABELS[size_pick])) +
    theme_arcto()

  gpus <- max(nlevels(droplevels(data$GPU)), 1)
  save_fig(p, "fig1_cross_mode_time", 2.4 * gpus + 1, 3.4)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 2 - Peak pinned memory: pinned-full vs adaptive
#     y log scale; x = Size; facet GPU. LZ4/TTI default (all three algos
#     behave the same on peak_pinned, since that depends only on
#     window selection, not on the codec).
# ══════════════════════════════════════════════════════════════════════════════

fig2_peak_pinned <- function(df, algo_pick = "lz4", dataset_pick = "TTI (seismic)") {
  data <- lossless_rows(df) |>
    filter(Algorithm == algo_pick, Dataset == dataset_pick,
           Mode %in% c("pinned", "adaptive"),
           !is.na(PeakPinnedBytes), PeakPinnedBytes > 0) |>
    mutate(
      Mode     = factor(Mode, levels = c("pinned", "adaptive")),
      peak_MiB = PeakPinnedBytes / (1024 * 1024)
    )
  if (nrow(data) == 0) {
    message("  fig2: no peak-pinned data for ", algo_pick)
    return(invisible(NULL))
  }

  p <- ggplot(data,
              aes(x = Size, y = peak_MiB, fill = Mode)) +
    geom_col(position = position_dodge(width = 0.7),
             width = 0.6, color = NA) +
    geom_text(aes(label = sprintf("%.0f", peak_MiB)),
              position = position_dodge(width = 0.7),
              vjust = -0.4, size = 2.4) +
    facet_wrap(~GPU, nrow = 1) +
    scale_fill_manual(values = MODE_COLORS[c("pinned", "adaptive")],
                      labels = MODE_LABELS[c("pinned", "adaptive")],
                      name = "Mode") +
    scale_x_discrete(labels = SIZE_LABELS) +
    scale_y_log10(labels = function(x) sprintf("%g", x),
                  expand = expansion(mult = c(0.05, 0.15))) +
    labs(x = "Input size",
         y = sprintf("Peak pinned host memory (MiB)  -  %s/%s",
                     ALGO_LABELS[algo_pick], dataset_pick)) +
    theme_arcto()

  gpus <- max(nlevels(droplevels(data$GPU)), 1)
  save_fig(p, "fig2_peak_pinned", 2.4 * gpus + 1, 3.4)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 3 - Compression ratio heatmap (GPU-independent; picks first GPU)
#     adapted from plots_iccsa_v4 fig3.
# ══════════════════════════════════════════════════════════════════════════════

fig3_ratio_heatmap <- function(df, size_pick = "xlarge") {
  base <- lossless_rows(df) |>
    filter(Size == size_pick, Mode == "adaptive")
  if (nrow(base) == 0) {
    message("  fig3: no lossless adaptive data at size=", size_pick)
    return(invisible(NULL))
  }
  first_gpu <- levels(droplevels(base$GPU))[1]
  data <- base |> filter(GPU == first_gpu) |>
    mutate(
      log_ratio   = log10(pmax(CompressionRatio, 1)),
      label_ratio = case_when(
        CompressionRatio < 10  ~ sprintf("%.2fx", CompressionRatio),
        CompressionRatio < 100 ~ sprintf("%.1fx", CompressionRatio),
        TRUE                   ~ sprintf("%.0fx", CompressionRatio)
      ),
      text_color = ifelse(CompressionRatio > 50, "white", "#1A1A1A"),
      Algorithm  = factor(Algorithm, levels = ALGO_ORDER)
    )

  p <- ggplot(data, aes(x = Dataset, y = Algorithm, fill = log_ratio)) +
    geom_tile(color = "white", linewidth = 1.0) +
    geom_text(aes(label = label_ratio, color = text_color),
              size = 4, fontface = "bold") +
    scale_fill_gradientn(
      colours = c("#D1E5F0", "#92C5DE", "#4393C3", "#2166AC"),
      limits  = c(0, log10(260)),
      breaks  = c(0, 1, 2),
      labels  = c("1x", "10x", "100x"),
      name    = "Ratio"
    ) +
    scale_color_identity() +
    scale_y_discrete(labels = ALGO_LABELS) +
    labs(x = "Dataset", y = "Algorithm") +
    theme_arcto() +
    theme(
      panel.grid       = element_blank(),
      panel.border     = element_blank(),
      axis.text.x      = element_text(angle = 15, hjust = 1),
      axis.ticks       = element_blank(),
      legend.position  = "right", legend.direction = "vertical",
      legend.key.height = unit(1.3, "cm"),
      legend.key.width  = unit(0.4, "cm")
    )

  save_fig(p, "fig3_ratio_heatmap", 5.0, 3.0)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 4 - Transfer overhead (normalized 100% stacked)
#     Compute = CompTime + DecompTime; Transfer = H2D + D2H.
#     Facet Mode x GPU. Shows how pinned/adaptive shrinks transfer share.
# ══════════════════════════════════════════════════════════════════════════════

fig4_transfer_overhead <- function(df, size_pick = "xlarge") {
  data <- lossless_rows(df) |>
    filter(Size == size_pick) |>
    mutate(
      TransferMs  = TransferH2DMs + TransferD2HMs,
      ComputeMs   = CompTimeMs + DecompTimeMs,
      TotMs       = TransferMs + ComputeMs,
      PctTransfer = TransferMs / TotMs * 100,
      PctCompute  = ComputeMs  / TotMs * 100
    ) |>
    select(Algorithm, Dataset, GPU, Mode, PctTransfer, PctCompute) |>
    pivot_longer(c(PctCompute, PctTransfer),
                 names_to = "Phase", values_to = "Pct") |>
    mutate(
      Phase = factor(Phase,
        levels = c("PctCompute", "PctTransfer"),
        labels = c("Compute", "H2D and D2H Transfer")),
      Algorithm = factor(Algorithm, levels = ALGO_ORDER),
      Mode      = factor(Mode, levels = MODE_ORDER, labels = MODE_LABELS[MODE_ORDER])
    )
  if (nrow(data) == 0) return(invisible(NULL))

  labels_df <- data |>
    filter(Pct > 10) |>
    mutate(
      label      = sprintf("%.0f%%", Pct),
      font_color = ifelse(Phase == "H2D and D2H Transfer", "white", "#333333")
    )

  p <- ggplot(data,
              aes(x = Dataset, y = Pct, fill = Phase)) +
    geom_col(position = "stack", width = 0.7, color = NA) +
    geom_text(data = labels_df,
              aes(label = label, color = font_color),
              position = position_stack(vjust = 0.5),
              size = 2.0, fontface = "bold") +
    facet_grid(Algorithm ~ GPU + Mode,
               labeller = labeller(Algorithm = ALGO_LABELS)) +
    scale_fill_manual(values = PHASE_COLORS_OVERHEAD, name = "Phase") +
    scale_color_identity() +
    scale_y_continuous(expand = expansion(mult = c(0, 0.02)),
                       labels = function(x) paste0(x, "%")) +
    labs(x = "Dataset", y = "Share of total time") +
    theme_arcto() +
    theme(axis.text.x = element_text(angle = 35, hjust = 1, size = 7),
          strip.text  = element_text(size = 8))

  gpus  <- max(nlevels(droplevels(data$GPU)), 1)
  modes <- nlevels(droplevels(data$Mode))
  save_fig(p, "fig4_transfer_overhead", 1.6 * gpus * modes + 1, 6.0)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 5 - Total time vs input size (TTI only, all modes)
#     Lines per Algorithm, facet GPU x Mode.
# ══════════════════════════════════════════════════════════════════════════════

fig5_scale_total <- function(df, dataset_pick = "TTI (seismic)") {
  data <- lossless_rows(df) |>
    filter(Dataset == dataset_pick) |>
    mutate(
      SizeMB    = SIZE_MAP[as.character(Size)],
      Mode      = factor(Mode, levels = MODE_ORDER, labels = MODE_LABELS[MODE_ORDER]),
      Algorithm = factor(Algorithm, levels = ALGO_ORDER)
    )
  if (nrow(data) == 0) return(invisible(NULL))

  p <- ggplot(data,
              aes(x = SizeMB, y = TotalTimeMs,
                  color = Algorithm, group = Algorithm)) +
    geom_line(linewidth = 0.7) +
    geom_point(size = 1.8) +
    facet_grid(Mode ~ GPU, scales = "free_y") +
    scale_color_manual(values = ALGO_COLORS, labels = ALGO_LABELS,
                       name = "Algorithm") +
    scale_x_log10(breaks = c(10, 100, 1024, 4096),
                  labels = c("10 MB", "100 MB", "1 GB", "4 GB")) +
    scale_y_continuous(expand = expansion(mult = c(0.05, 0.12))) +
    labs(x = "Input size",
         y = sprintf("Total time (ms)  -  %s", dataset_pick)) +
    theme_arcto()

  gpus <- max(nlevels(droplevels(data$GPU)), 1)
  save_fig(p, "fig5_scale_total", 2.4 * gpus + 1, 5.8)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 6 - ZFP Pareto: ratio vs PSNR (TTI only)
#     Color = Mode (acc/rate/prec); facet GPU x Size.
# ══════════════════════════════════════════════════════════════════════════════

ZFP_MODE_COLORS <- c("acc" = "#C0392B", "rate" = "#2166AC", "prec" = "#1A9850")
ZFP_MODE_LABELS <- c("acc" = "Fixed accuracy",
                     "rate" = "Fixed rate",
                     "prec" = "Fixed precision")

fig6_zfp_pareto <- function(df) {
  data <- zfp_rows(df) |>
    filter(Dataset == "TTI (seismic)",
           !is.na(PSNR), is.finite(PSNR), PSNR > 0) |>
    mutate(
      ZfpMode = factor(Mode, levels = c("acc", "rate", "prec"),
                       labels = ZFP_MODE_LABELS),
      ParamLabel = case_when(
        Mode == "acc"  ~ paste0("tau=", ZfpParam),
        Mode == "rate" ~ paste0(ZfpParam, " b/v"),
        Mode == "prec" ~ paste0("p=", ZfpParam),
        TRUE           ~ as.character(ZfpParam)
      )
    )
  if (nrow(data) == 0) return(invisible(NULL))

  p <- ggplot(data,
              aes(x = CompressionRatio, y = PSNR,
                  color = ZfpMode, shape = ZfpMode)) +
    geom_point(size = 2.6, stroke = 0.8) +
    geom_text(aes(label = ParamLabel),
              hjust = -0.15, vjust = 0.3, size = 2.3,
              check_overlap = TRUE, show.legend = FALSE) +
    facet_grid(GPU ~ Size, labeller = labeller(Size = SIZE_LABELS)) +
    scale_color_manual(values = setNames(unname(ZFP_MODE_COLORS),
                                         ZFP_MODE_LABELS[names(ZFP_MODE_COLORS)]),
                       name = "ZFP mode") +
    scale_shape_manual(values = setNames(c(16, 17, 15),
                                         ZFP_MODE_LABELS[names(ZFP_MODE_COLORS)]),
                       name = "ZFP mode") +
    scale_x_log10(expand = expansion(mult = c(0.10, 0.20))) +
    scale_y_continuous(expand = expansion(mult = c(0.05, 0.10))) +
    labs(x = "Compression ratio (log)", y = "PSNR (dB)") +
    theme_arcto()

  gpus  <- max(nlevels(droplevels(data$GPU)), 1)
  sizes <- max(nlevels(droplevels(data$Size)), 1)
  save_fig(p, "fig6_zfp_pareto", 2.2 * sizes + 1, 2.0 * gpus + 1)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 7 - ZFP compression throughput per ZFP mode (TTI)
# ══════════════════════════════════════════════════════════════════════════════

fig7_zfp_throughput <- function(df) {
  data <- zfp_rows(df) |>
    filter(Dataset == "TTI (seismic)") |>
    mutate(
      ZfpMode = factor(Mode, levels = c("acc", "rate", "prec"),
                       labels = ZFP_MODE_LABELS),
      ParamShort = case_when(
        Mode == "acc"  ~ ZfpParam,
        Mode == "rate" ~ paste0(ZfpParam, "b"),
        Mode == "prec" ~ paste0("p", ZfpParam),
        TRUE           ~ ZfpParam
      )
    )
  if (nrow(data) == 0) return(invisible(NULL))

  p <- ggplot(data,
              aes(x = ParamShort, y = CompThroughputGBs, fill = ZfpMode)) +
    geom_col(width = 0.7, color = NA) +
    geom_text(aes(label = sprintf("%.1f", CompThroughputGBs)),
              vjust = -0.3, size = 2.0) +
    facet_grid(GPU ~ Size, scales = "free_x", space = "free_x",
               labeller = labeller(Size = SIZE_LABELS)) +
    scale_fill_manual(values = setNames(unname(ZFP_MODE_COLORS),
                                        ZFP_MODE_LABELS[names(ZFP_MODE_COLORS)]),
                      name = "ZFP mode") +
    scale_y_continuous(expand = expansion(mult = c(0, 0.12))) +
    labs(x = "ZFP parameter", y = "Compression throughput (GB/s)") +
    theme_arcto() +
    theme(axis.text.x = element_text(angle = 35, hjust = 1, size = 7))

  gpus  <- max(nlevels(droplevels(data$GPU)), 1)
  sizes <- max(nlevels(droplevels(data$Size)), 1)
  save_fig(p, "fig7_zfp_throughput", 2.5 * sizes + 1, 2.0 * gpus + 1)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 8 - PCIe pinned H2D BW curve (optional)
#     Reads a CSV with columns from run_pcie_sweep.sh:
#       host,timestamp,size_mb,size_bytes,
#       h2d_pageable_gbps,h2d_pinned_gbps,d2h_pageable_gbps,d2h_pinned_gbps
#     Marks the 16 MiB knee and the 64 MiB W_pcie_amort floor.
# ══════════════════════════════════════════════════════════════════════════════

fig8_pcie_curve <- function(pcie_csv) {
  if (is.null(pcie_csv) || !file.exists(pcie_csv)) return(invisible(NULL))
  pc <- read_csv(pcie_csv, show_col_types = FALSE) |>
    mutate(across(c(h2d_pinned_gbps, h2d_pageable_gbps,
                    d2h_pinned_gbps, d2h_pageable_gbps),
                  ~ suppressWarnings(as.numeric(.))))

  data <- pc |>
    pivot_longer(c(h2d_pinned_gbps, h2d_pageable_gbps,
                   d2h_pinned_gbps, d2h_pageable_gbps),
                 names_to = "Variant", values_to = "GBps") |>
    mutate(
      Direction = if_else(str_detect(Variant, "^h2d"), "H2D", "D2H"),
      HostMem   = if_else(str_detect(Variant, "pinned"), "Pinned", "Pageable"),
      Variant   = factor(paste(Direction, HostMem),
                         levels = c("H2D Pinned", "H2D Pageable",
                                    "D2H Pinned", "D2H Pageable"))
    )

  p <- ggplot(data,
              aes(x = size_mb, y = GBps,
                  color = Variant, linetype = HostMem, shape = HostMem,
                  group = Variant)) +
    geom_vline(xintercept = 16, color = "#888888", linetype = "dotted",
               linewidth = 0.5) +
    geom_vline(xintercept = 64, color = "#C0392B", linetype = "dashed",
               linewidth = 0.5) +
    annotate("text", x = 16, y = 1.5, label = "knee ~16 MiB",
             hjust = -0.05, size = 2.6, color = "#666666") +
    annotate("text", x = 64, y = 1.5, label = "W_pcie_amort = 64 MiB",
             hjust = -0.05, size = 2.6, color = "#C0392B") +
    geom_line(linewidth = 0.7) +
    geom_point(size = 2.0) +
    scale_color_manual(values = c("H2D Pinned"   = "#2166AC",
                                  "H2D Pageable" = "#92C5DE",
                                  "D2H Pinned"   = "#C0392B",
                                  "D2H Pageable" = "#F4A582"),
                       name = "Variant") +
    scale_linetype_manual(values = c("Pinned" = "solid", "Pageable" = "dashed"),
                          guide = "none") +
    scale_shape_manual(values = c("Pinned" = 16, "Pageable" = 17),
                       guide = "none") +
    scale_x_log10(breaks = c(1, 4, 16, 64, 256, 1024),
                  labels = c("1", "4", "16", "64", "256", "1024")) +
    scale_y_continuous(expand = expansion(mult = c(0.05, 0.10))) +
    labs(x = "Transfer size (MiB)", y = "Bandwidth (GB/s)") +
    theme_arcto()

  save_fig(p, "fig8_pcie_curve", 6.0, 3.5)
}

# ══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════════════════

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: Rscript plots_arcto.R all_results.csv [pcie_curve.csv]")
}

all_csv  <- args[[1]]
pcie_csv <- if (length(args) >= 2) args[[2]] else NULL

cat(sprintf("\nLoading %s ...\n", all_csv))
df <- load_csv(all_csv)
cat(sprintf("  GPUs       : %s\n",
            paste(levels(droplevels(df$GPU)), collapse = ", ")))
cat(sprintf("  Algorithms : %s\n",
            paste(sort(unique(df$Algorithm)), collapse = ", ")))
cat(sprintf("  Modes      : %s\n",
            paste(sort(unique(df$Mode)), collapse = ", ")))
cat(sprintf("  Datasets   : %s\n",
            paste(levels(droplevels(df$Dataset)), collapse = ", ")))
cat(sprintf("  Sizes      : %s\n",
            paste(levels(droplevels(df$Size)), collapse = ", ")))
cat(sprintf("  Rows       : %d\n\n", nrow(df)))

cat("Generating figures...\n")
fig1_cross_mode_time(df)
fig2_peak_pinned(df)
fig3_ratio_heatmap(df)
fig4_transfer_overhead(df)
fig5_scale_total(df)
fig6_zfp_pareto(df)
fig7_zfp_throughput(df)
if (!is.null(pcie_csv)) fig8_pcie_curve(pcie_csv)

cat(sprintf("\nFigures saved under ./%s/  (PDF + PNG)\n", OUTPUT_DIR))
