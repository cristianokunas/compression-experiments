# plots_arcto_v2.R - Comprehensive figure suite for the ARCTO paper
# (SBAC-PAD 2026). Iteration 2: keeps v1's idiom but generates ALL the
# faceted views the evaluation needs, leaving v1 untouched as history.
#
# Reads the consolidated CSV emitted by consolidate_results.py
# (ICCSA26-aligned schema + ARCTO extras: Mode, ZfpParam, PeakPinnedBytes,
# AdaptiveWindowBytes, AllocMs, MemcpyH2HMs, MaxAbsDiff, RMSE, PSNR,
# MaxRelErr, AmplitudeRange, Campaign).
#
# Usage:
#   Rscript plots_arcto_v2.R all_results.csv [pcie_curve.csv]
#
# Figure groups:
#   A. Throughput (kernel-only Comp+Decomp)
#       a1_tput_xlarge          a3_tput_heatmap_xlarge
#       a2_tput_all_sizes       a4_tput_heatmap_per_size
#   B. End-to-end total time (with Mode)
#       b1_total_xlarge         b2_total_all_sizes
#       b3_total_vs_size_per_mode
#   C. Speedup vs Pageable
#       c1_speedup_xlarge
#       c2_speedup_per_size
#   D. Memory footprint
#       d1_peak_pinned_per_size
#       d2_alloc_time
#   E. Transfer breakdown
#       e1_overhead_pct_xlarge
#       e2_breakdown_abs_ms
#   F. Compression ratio
#       f1_ratio_heatmap_lossless
#   G. Asymmetry
#       g1_asymmetry_heatmap
#   H. ZFP
#       h1_zfp_acc_ratio        h5_zfp_prec_ratio_psnr
#       h2_zfp_acc_psnr         h6_zfp_pareto_unified
#       h3_zfp_rate_ratio       h7_zfp_throughput
#       h4_zfp_rate_psnr
#   I. PCIe
#       i1_pcie_curve_cross_gpu

suppressPackageStartupMessages({
  library(readr); library(dplyr); library(tidyr); library(ggplot2)
  library(stringr); library(purrr); library(scales)
})

# ══════════════════════════════════════════════════════════════════════════════
#  DESIGN SYSTEM (shared with v1; bumped output dir to keep both alive)
# ══════════════════════════════════════════════════════════════════════════════

OUTPUT_DIR <- "plots_output_v2"
dir.create(OUTPUT_DIR, showWarnings = FALSE)

ALGO_COLORS <- c("lz4" = "#F4A582", "snappy" = "#92C5DE",
                 "cascaded" = "#A6D96A", "zfp" = "#9E6FB9")
ALGO_LABELS <- c("lz4" = "LZ4", "snappy" = "Snappy",
                 "cascaded" = "Cascaded", "zfp" = "ZFP")

GPU_COLORS <- c("MI50" = "#A0A0A0", "MI210" = "#5B9BD5",
                "MI300X" = "#1F4E79", "RX7900XT" = "#C0392B")

MODE_COLORS <- c("baseline" = "#9E9E9E", "pinned" = "#F4A582",
                 "adaptive" = "#4393C3")
MODE_LABELS <- c("baseline" = "Pageable", "pinned" = "Pinned (full)",
                 "adaptive" = "Pinned adaptive")

PHASE_COLORS_OVERHEAD <- c("Compute" = "#F4A582",
                           "H2D and D2H Transfer" = "#92C5DE")
PHASE_COLORS_BREAKDOWN <- c("H2D Transfer" = "#92C5DE",
                            "Compression" = "#F4A582",
                            "Decompression" = "#A6D96A",
                            "D2H Transfer" = "#FEE090",
                            "Alloc / H2H staging" = "#BDA0CC")

ZFP_MODE_COLORS <- c("acc"  = "#C0392B", "rate" = "#2166AC", "prec" = "#1A9850")
ZFP_MODE_LABELS <- c("acc" = "Fixed accuracy",
                     "rate" = "Fixed rate",
                     "prec" = "Fixed precision")

GPU_ORDER      <- c("MI50", "MI210", "MI300X", "RX7900XT")
ALGO_ORDER     <- c("lz4", "snappy", "cascaded")
MODE_ORDER     <- c("baseline", "pinned", "adaptive")
DATASET_ORDER  <- c("zeros", "binary", "random", "TTI")
DATASET_LABELS <- c("zeros" = "Zeros", "binary" = "Binary",
                    "random" = "Random", "TTI" = "TTI (seismic)")
SIZE_ORDER  <- c("small", "medium", "large", "xlarge")
SIZE_LABELS <- c("small" = "10 MB", "medium" = "100 MB",
                 "large" = "1 GB", "xlarge" = "4 GB")
SIZE_MAP    <- c("small" = 10, "medium" = 100, "large" = 1024, "xlarge" = 4096)

# Combined Algorithm × GPU palette: hue per algorithm, intensity per GPU
ALGO_GPU_COLORS <- c(
  "lz4.MI50"      = "#FDDBC7", "lz4.MI210"     = "#F4A582",
  "lz4.MI300X"    = "#D6604D", "lz4.RX7900XT"  = "#B2182B",
  "snappy.MI50"      = "#D1E5F0", "snappy.MI210"     = "#92C5DE",
  "snappy.MI300X"    = "#4393C3", "snappy.RX7900XT"  = "#2166AC",
  "cascaded.MI50"      = "#D9EF8B", "cascaded.MI210"     = "#A6D96A",
  "cascaded.MI300X"    = "#66BD63", "cascaded.RX7900XT"  = "#1A9850"
)
ALGO_GPU_LABELS <- setNames(
  paste0(rep(c("LZ4", "Snappy", "Cascaded"), each = length(GPU_ORDER)),
         " - ", rep(GPU_ORDER, times = 3)),
  paste0(rep(ALGO_ORDER, each = length(GPU_ORDER)), ".",
         rep(GPU_ORDER, times = 3))
)

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
    if (col %in% names(df)) df[[col]] <- suppressWarnings(as.numeric(df[[col]]))
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
    Size      = factor(Size, levels = SIZE_ORDER)
  )
}

lossless_rows <- function(df) df |> filter(Algorithm %in% ALGO_ORDER)
zfp_rows      <- function(df) df |> filter(Algorithm == "zfp")

# ══════════════════════════════════════════════════════════════════════════════
#  GROUP A - Kernel-only throughput (Comp + Decomp)
#     We use the `adaptive` rows to extract kernel throughput because
#     all three modes share the same kernel; pinned/adaptive give clean
#     kernel-only numbers without pageable PCIe noise.
# ══════════════════════════════════════════════════════════════════════════════

prep_tput_long <- function(df, mode_pick = "adaptive") {
  lossless_rows(df) |>
    filter(Mode == mode_pick) |>
    pivot_longer(c(CompThroughputGBs, DecompThroughputGBs),
                 names_to = "Operation", values_to = "Throughput") |>
    mutate(
      StdDev = ifelse(Operation == "CompThroughputGBs",
                      CompThroughputStdDev, DecompThroughputStdDev),
      Operation = factor(Operation,
        levels = c("CompThroughputGBs", "DecompThroughputGBs"),
        labels = c("Compression", "Decompression")),
      Algorithm = factor(Algorithm, levels = ALGO_ORDER)
    )
}

fig_a1_tput_xlarge <- function(df) {
  data <- prep_tput_long(df) |> filter(Size == "xlarge")
  if (nrow(data) == 0) return(invisible(NULL))
  gpus <- nlevels(droplevels(data$GPU))

  p <- ggplot(data, aes(x = Dataset, y = Throughput, fill = Algorithm)) +
    geom_col(position = position_dodge(width = 0.8), width = 0.7, color = NA) +
    geom_errorbar(aes(ymin = pmax(Throughput - StdDev, 0),
                      ymax = Throughput + StdDev),
                  position = position_dodge(width = 0.8),
                  width = 0.25, linewidth = 0.4, color = "grey40") +
    geom_text(aes(label = round(Throughput, 1)),
              position = position_dodge(width = 0.8),
              vjust = -0.5, size = 2.4, check_overlap = TRUE) +
    facet_grid(Operation ~ GPU, scales = "free_y") +
    scale_fill_manual(values = ALGO_COLORS, labels = ALGO_LABELS,
                      name = "Algorithm") +
    scale_y_log10(expand = expansion(mult = c(0, 0.15))) +
    labs(x = "Dataset", y = "Throughput (GB/s)") +
    theme_arcto() +
    theme(axis.text.x = element_text(angle = 35, hjust = 1, size = 8.4))
  save_fig(p, "a1_tput_xlarge", 1.8 * gpus + 1, 4.5)
}

fig_a2_tput_all_sizes <- function(df) {
  data <- prep_tput_long(df) |>
    mutate(SizeLabel = factor(Size, levels = SIZE_ORDER,
                              labels = SIZE_LABELS[SIZE_ORDER]),
           AlgoGPU = interaction(Algorithm, GPU, sep = "."))
  if (nrow(data) == 0) return(invisible(NULL))

  present <- levels(droplevels(data$AlgoGPU))
  colors_sub <- ALGO_GPU_COLORS[present]
  labels_sub <- ALGO_GPU_LABELS[present]
  gpus <- nlevels(droplevels(data$GPU))

  p <- ggplot(data, aes(x = Dataset, y = Throughput, fill = AlgoGPU)) +
    geom_col(position = position_dodge(width = 0.9), width = 0.88, color = NA) +
    geom_errorbar(aes(ymin = pmax(Throughput - StdDev, 0),
                      ymax = Throughput + StdDev),
                  position = position_dodge(width = 0.9),
                  width = 0.2, linewidth = 0.3, color = "grey40") +
    facet_grid(Operation ~ SizeLabel, scales = "free_y") +
    scale_fill_manual(values = colors_sub, labels = labels_sub,
                      name = "Algorithm - GPU") +
    scale_y_continuous(expand = expansion(mult = c(0, 0.08))) +
    labs(x = "Dataset", y = "Throughput (GB/s)") +
    theme_arcto(base_size = 11) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 9),
          legend.key.size = unit(0.4, "cm")) +
    guides(fill = guide_legend(ncol = max(gpus, 1)))
  save_fig(p, "a2_tput_all_sizes", 14, 7.5)
}

prep_tput_heatmap <- function(df, mode_pick = "adaptive", size_filter = NULL) {
  d <- prep_tput_long(df, mode_pick)
  if (!is.null(size_filter)) d <- d |> filter(Size == size_filter)
  d |> mutate(
    log_tp = log10(pmax(Throughput, 0.1)),
    label_tp = case_when(
      Throughput < 10  ~ sprintf("%.1f", Throughput),
      Throughput < 100 ~ sprintf("%.0f", Throughput),
      TRUE             ~ sprintf("%.0f", Throughput)),
    text_color = ifelse(log_tp > 2.0, "white", "#1A1A1A")
  )
}

fig_a3_tput_heatmap_xlarge <- function(df) {
  data <- prep_tput_heatmap(df, size_filter = "xlarge")
  if (nrow(data) == 0) return(invisible(NULL))
  p <- ggplot(data, aes(x = Dataset, y = Algorithm, fill = log_tp)) +
    geom_tile(color = "white", linewidth = 1.0) +
    geom_text(aes(label = label_tp, color = text_color),
              size = 2.5, fontface = "bold") +
    facet_grid(Operation ~ GPU) +
    scale_fill_gradientn(colours = c("#D1E5F0", "#92C5DE", "#4393C3", "#2166AC"),
                         limits = c(0, 3.3), breaks = c(0, 1, 2, 3),
                         labels = c("1", "10", "100", "1000"), name = "GB/s") +
    scale_color_identity() +
    scale_y_discrete(labels = ALGO_LABELS) +
    labs(x = "Dataset", y = "Algorithm") +
    theme_arcto() +
    theme(panel.grid = element_blank(), panel.border = element_blank(),
          axis.text.x = element_text(angle = 15, hjust = 1),
          axis.ticks = element_blank(),
          legend.position = "right", legend.direction = "vertical",
          legend.key.height = unit(1.3, "cm"),
          legend.key.width  = unit(0.4, "cm"))
  gpus <- nlevels(droplevels(data$GPU))
  save_fig(p, "a3_tput_heatmap_xlarge", 2.0 * gpus + 1.2, 4)
}

fig_a4_tput_heatmap_per_size <- function(df) {
  data <- prep_tput_heatmap(df) |>
    mutate(SizeLabel = factor(Size, levels = SIZE_ORDER,
                              labels = SIZE_LABELS[SIZE_ORDER]))
  if (nrow(data) == 0) return(invisible(NULL))
  gpus <- nlevels(droplevels(data$GPU))

  for (op in levels(data$Operation)) {
    sub <- data |> filter(Operation == op)
    suffix <- ifelse(op == "Compression", "comp", "decomp")
    p <- ggplot(sub, aes(x = Dataset, y = Algorithm, fill = log_tp)) +
      geom_tile(color = "white", linewidth = 0.8) +
      geom_text(aes(label = label_tp, color = text_color),
                size = 2.8, fontface = "bold") +
      facet_grid(GPU ~ SizeLabel) +
      scale_fill_gradientn(colours = c("#D1E5F0", "#92C5DE", "#4393C3", "#2166AC"),
                           limits = c(0, 3.3), breaks = c(0, 1, 2, 3),
                           labels = c("1", "10", "100", "1000"), name = "GB/s") +
      scale_color_identity() +
      scale_y_discrete(labels = ALGO_LABELS) +
      labs(x = "Dataset", y = "Algorithm") +
      theme_arcto() +
      theme(panel.grid = element_blank(), panel.border = element_blank(),
            axis.text.x = element_text(angle = 25, hjust = 1, size = 7),
            axis.ticks = element_blank(),
            legend.position = "right", legend.direction = "vertical",
            legend.key.height = unit(1.2, "cm"),
            legend.key.width  = unit(0.35, "cm"))
    save_fig(p, paste0("a4_tput_heatmap_per_size_", suffix),
             12, 2.0 * gpus + 1)
  }
}

# ══════════════════════════════════════════════════════════════════════════════
#  GROUP B - End-to-end total time (with Mode)
# ══════════════════════════════════════════════════════════════════════════════

fig_b1_total_xlarge <- function(df) {
  data <- lossless_rows(df) |>
    filter(Size == "xlarge") |>
    mutate(Algorithm = factor(Algorithm, levels = ALGO_ORDER),
           Mode      = factor(Mode, levels = MODE_ORDER))
  if (nrow(data) == 0) return(invisible(NULL))

  p <- ggplot(data, aes(x = Dataset, y = TotalTimeMs, fill = Mode)) +
    geom_col(position = position_dodge(width = 0.8), width = 0.7, color = NA) +
    geom_text(aes(label = sprintf("%.0f", TotalTimeMs)),
              position = position_dodge(width = 0.8),
              vjust = -0.4, size = 2.0, check_overlap = TRUE) +
    facet_grid(Algorithm ~ GPU,
               labeller = labeller(Algorithm = ALGO_LABELS),
               scales = "free_y") +
    scale_fill_manual(values = MODE_COLORS, labels = MODE_LABELS, name = "Mode") +
    scale_y_continuous(expand = expansion(mult = c(0, 0.14))) +
    labs(x = "Dataset", y = "Total time (ms) at 4 GB input") +
    theme_arcto() +
    theme(axis.text.x = element_text(angle = 35, hjust = 1, size = 8))
  gpus <- nlevels(droplevels(data$GPU))
  save_fig(p, "b1_total_xlarge", 2.0 * gpus + 1, 6.0)
}

fig_b2_total_all_sizes <- function(df) {
  data <- lossless_rows(df) |>
    mutate(Algorithm = factor(Algorithm, levels = ALGO_ORDER),
           Mode      = factor(Mode, levels = MODE_ORDER),
           SizeLabel = factor(Size, levels = SIZE_ORDER,
                              labels = SIZE_LABELS[SIZE_ORDER]))
  if (nrow(data) == 0) return(invisible(NULL))

  p <- ggplot(data, aes(x = Dataset, y = TotalTimeMs, fill = Mode)) +
    geom_col(position = position_dodge(width = 0.8), width = 0.7, color = NA) +
    facet_grid(Algorithm + GPU ~ SizeLabel, scales = "free_y",
               labeller = labeller(Algorithm = ALGO_LABELS)) +
    scale_fill_manual(values = MODE_COLORS, labels = MODE_LABELS, name = "Mode") +
    scale_y_continuous(expand = expansion(mult = c(0, 0.10))) +
    labs(x = "Dataset", y = "Total time (ms)") +
    theme_arcto(base_size = 8.5) +
    theme(axis.text.x  = element_text(angle = 40, hjust = 1, size = 6),
          strip.text.y = element_text(size = 7))
  sizes <- nlevels(droplevels(data$SizeLabel))
  algos_gpus <- length(unique(paste(data$Algorithm, data$GPU)))
  save_fig(p, "b2_total_all_sizes", 2.0 * sizes + 1, 0.9 * algos_gpus + 1)
}

fig_b3_total_vs_size_per_mode <- function(df) {
  data <- lossless_rows(df) |>
    mutate(SizeMB = SIZE_MAP[as.character(Size)],
           Algorithm = factor(Algorithm, levels = ALGO_ORDER),
           Mode      = factor(Mode, levels = MODE_ORDER,
                              labels = MODE_LABELS[MODE_ORDER]))
  if (nrow(data) == 0) return(invisible(NULL))

  p <- ggplot(data,
              aes(x = SizeMB, y = TotalTimeMs,
                  color = Algorithm, group = Algorithm)) +
    geom_line(linewidth = 0.7) + geom_point(size = 1.8) +
    facet_grid(Mode ~ GPU + Dataset, scales = "free_y") +
    scale_color_manual(values = ALGO_COLORS, labels = ALGO_LABELS,
                       name = "Algorithm") +
    scale_x_log10(breaks = c(10, 100, 1024, 4096),
                  labels = c("10 MB", "100 MB", "1 GB", "4 GB")) +
    scale_y_continuous(expand = expansion(mult = c(0.05, 0.12))) +
    labs(x = "Input size", y = "Total time (ms)") +
    theme_arcto(base_size = 8.5) +
    theme(axis.text.x = element_text(angle = 35, hjust = 1, size = 6),
          strip.text  = element_text(size = 7))
  gpus_ds <- length(unique(paste(data$GPU, data$Dataset)))
  save_fig(p, "b3_total_vs_size_per_mode", 1.3 * gpus_ds + 1, 6.0)
}

# ══════════════════════════════════════════════════════════════════════════════
#  GROUP C - Speedup vs Pageable
# ══════════════════════════════════════════════════════════════════════════════

compute_speedup_df <- function(df) {
  base <- lossless_rows(df) |>
    filter(Mode == "baseline") |>
    select(Algorithm, Dataset, Size, GPU, base_total = TotalTimeMs)
  lossless_rows(df) |>
    filter(Mode != "baseline") |>
    left_join(base, by = c("Algorithm", "Dataset", "Size", "GPU")) |>
    mutate(Speedup = base_total / TotalTimeMs,
           Algorithm = factor(Algorithm, levels = ALGO_ORDER),
           Mode      = factor(Mode, levels = c("pinned", "adaptive")))
}

fig_c1_speedup_xlarge <- function(df) {
  data <- compute_speedup_df(df) |> filter(Size == "xlarge")
  if (nrow(data) == 0) return(invisible(NULL))

  p <- ggplot(data, aes(x = Dataset, y = Speedup, fill = Mode)) +
    geom_col(position = position_dodge(width = 0.8), width = 0.7, color = NA) +
    geom_hline(yintercept = 1, linetype = "dashed",
               color = "#C0392B", linewidth = 0.5) +
    geom_text(aes(label = sprintf("%.1f", Speedup)),
              position = position_dodge(width = 0.8),
              vjust = -0.4, size = 2.3, check_overlap = TRUE) +
    facet_grid(Algorithm ~ GPU,
               labeller = labeller(Algorithm = ALGO_LABELS)) +
    scale_fill_manual(values = MODE_COLORS[c("pinned", "adaptive")],
                      labels = MODE_LABELS[c("pinned", "adaptive")],
                      name = "Mode (vs pageable)") +
    scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
    labs(x = "Dataset",
         y = "End-to-end speedup vs pageable baseline (4 GB)") +
    theme_arcto() +
    theme(axis.text.x = element_text(angle = 35, hjust = 1, size = 8))
  gpus <- nlevels(droplevels(data$GPU))
  save_fig(p, "c1_speedup_xlarge", 2.0 * gpus + 1, 5.5)
}

fig_c2_speedup_per_size <- function(df) {
  data <- compute_speedup_df(df) |>
    mutate(SizeLabel = factor(Size, levels = SIZE_ORDER,
                              labels = SIZE_LABELS[SIZE_ORDER]))
  if (nrow(data) == 0) return(invisible(NULL))

  p <- ggplot(data, aes(x = Dataset, y = Speedup, fill = Mode)) +
    geom_col(position = position_dodge(width = 0.7), width = 0.6, color = NA) +
    geom_hline(yintercept = 1, linetype = "dashed",
               color = "#C0392B", linewidth = 0.4) +
    facet_grid(Algorithm + GPU ~ SizeLabel,
               labeller = labeller(Algorithm = ALGO_LABELS)) +
    scale_fill_manual(values = MODE_COLORS[c("pinned", "adaptive")],
                      labels = MODE_LABELS[c("pinned", "adaptive")],
                      name = "Mode (vs pageable)") +
    scale_y_continuous(expand = expansion(mult = c(0, 0.12))) +
    labs(x = "Dataset", y = "Speedup vs pageable") +
    theme_arcto(base_size = 8.5) +
    theme(axis.text.x = element_text(angle = 35, hjust = 1, size = 6),
          strip.text  = element_text(size = 7))
  sizes <- nlevels(droplevels(data$SizeLabel))
  algos_gpus <- length(unique(paste(data$Algorithm, data$GPU)))
  save_fig(p, "c2_speedup_per_size", 2.0 * sizes + 1, 0.9 * algos_gpus + 1)
}

# ══════════════════════════════════════════════════════════════════════════════
#  GROUP D - Memory footprint
# ══════════════════════════════════════════════════════════════════════════════

fig_d1_peak_pinned_per_size <- function(df) {
  data <- lossless_rows(df) |>
    filter(Mode %in% c("pinned", "adaptive"),
           !is.na(PeakPinnedBytes), PeakPinnedBytes > 0) |>
    mutate(peak_MiB = PeakPinnedBytes / (1024 * 1024),
           Algorithm = factor(Algorithm, levels = ALGO_ORDER),
           Mode      = factor(Mode, levels = c("pinned", "adaptive")))
  if (nrow(data) == 0) return(invisible(NULL))

  p <- ggplot(data, aes(x = Size, y = peak_MiB, fill = Mode)) +
    geom_col(position = position_dodge(width = 0.7), width = 0.6, color = NA) +
    facet_grid(Algorithm ~ GPU,
               labeller = labeller(Algorithm = ALGO_LABELS)) +
    scale_fill_manual(values = MODE_COLORS[c("pinned", "adaptive")],
                      labels = MODE_LABELS[c("pinned", "adaptive")],
                      name = "Mode") +
    scale_x_discrete(labels = SIZE_LABELS) +
    scale_y_log10(labels = function(x) sprintf("%g", x),
                  expand = expansion(mult = c(0.05, 0.15))) +
    labs(x = "Input size", y = "Peak pinned host memory (MiB)") +
    theme_arcto()
  gpus <- nlevels(droplevels(data$GPU))
  save_fig(p, "d1_peak_pinned_per_size", 2.0 * gpus + 1, 5.5)
}

fig_d2_alloc_time <- function(df) {
  data <- lossless_rows(df) |>
    filter(Mode %in% c("pinned", "adaptive"),
           !is.na(AllocMs), AllocMs >= 0) |>
    mutate(Algorithm = factor(Algorithm, levels = ALGO_ORDER),
           Mode      = factor(Mode, levels = c("pinned", "adaptive")),
           SizeLabel = factor(Size, levels = SIZE_ORDER,
                              labels = SIZE_LABELS[SIZE_ORDER]))
  if (nrow(data) == 0) return(invisible(NULL))

  p <- ggplot(data, aes(x = SizeLabel, y = AllocMs, fill = Mode)) +
    geom_col(position = position_dodge(width = 0.7), width = 0.6, color = NA) +
    geom_text(aes(label = sprintf("%.0f", AllocMs)),
              position = position_dodge(width = 0.7),
              vjust = -0.3, size = 2.0, check_overlap = TRUE) +
    facet_grid(Algorithm ~ GPU,
               labeller = labeller(Algorithm = ALGO_LABELS),
               scales = "free_y") +
    scale_fill_manual(values = MODE_COLORS[c("pinned", "adaptive")],
                      labels = MODE_LABELS[c("pinned", "adaptive")],
                      name = "Mode") +
    scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
    labs(x = "Input size", y = "hipHostMalloc time (ms)") +
    theme_arcto() +
    theme(axis.text.x = element_text(angle = 35, hjust = 1, size = 8))
  gpus <- nlevels(droplevels(data$GPU))
  save_fig(p, "d2_alloc_time", 2.0 * gpus + 1, 5.5)
}

# ══════════════════════════════════════════════════════════════════════════════
#  GROUP E - Transfer breakdown
# ══════════════════════════════════════════════════════════════════════════════

fig_e1_overhead_pct_xlarge <- function(df) {
  data <- lossless_rows(df) |>
    filter(Size == "xlarge") |>
    mutate(TransferMs = TransferH2DMs + TransferD2HMs,
           ComputeMs  = CompTimeMs + DecompTimeMs,
           TotMs      = TransferMs + ComputeMs,
           PctTransfer = TransferMs / TotMs * 100,
           PctCompute  = ComputeMs  / TotMs * 100,
           Algorithm  = factor(Algorithm, levels = ALGO_ORDER),
           Mode       = factor(Mode, levels = MODE_ORDER,
                               labels = MODE_LABELS[MODE_ORDER])) |>
    select(Algorithm, Dataset, GPU, Mode, PctTransfer, PctCompute) |>
    pivot_longer(c(PctCompute, PctTransfer),
                 names_to = "Phase", values_to = "Pct") |>
    mutate(Phase = factor(Phase,
      levels = c("PctCompute", "PctTransfer"),
      labels = c("Compute", "H2D and D2H Transfer")))
  if (nrow(data) == 0) return(invisible(NULL))

  labels_df <- data |> filter(Pct > 12) |>
    mutate(label = sprintf("%.0f%%", Pct),
           font_color = ifelse(Phase == "H2D and D2H Transfer",
                               "white", "#333333"))

  p <- ggplot(data, aes(x = Dataset, y = Pct, fill = Phase)) +
    geom_col(position = "stack", width = 0.7, color = NA) +
    geom_text(data = labels_df,
              aes(label = label, color = font_color),
              position = position_stack(vjust = 0.5),
              size = 2.0, fontface = "bold") +
    facet_grid(Algorithm + Mode ~ GPU,
               labeller = labeller(Algorithm = ALGO_LABELS)) +
    scale_fill_manual(values = PHASE_COLORS_OVERHEAD, name = "Phase") +
    scale_color_identity() +
    scale_y_continuous(expand = expansion(mult = c(0, 0.02)),
                       labels = function(x) paste0(x, "%")) +
    labs(x = "Dataset", y = "Share of (Compute + Transfer)") +
    theme_arcto(base_size = 8.5) +
    theme(axis.text.x = element_text(angle = 35, hjust = 1, size = 7),
          strip.text  = element_text(size = 7))
  gpus <- nlevels(droplevels(data$GPU))
  save_fig(p, "e1_overhead_pct_xlarge", 2.0 * gpus + 1, 8.0)
}

fig_e2_breakdown_abs_ms <- function(df, dataset_pick = "TTI (seismic)") {
  data <- lossless_rows(df) |>
    filter(Size == "xlarge", Dataset == dataset_pick) |>
    mutate(StagingMs = pmax(coalesce(AllocMs, 0) + coalesce(MemcpyH2HMs, 0), 0),
           Algorithm = factor(Algorithm, levels = ALGO_ORDER),
           Mode      = factor(Mode, levels = MODE_ORDER,
                              labels = MODE_LABELS[MODE_ORDER])) |>
    select(Algorithm, GPU, Mode,
           TransferH2DMs, CompTimeMs, DecompTimeMs, TransferD2HMs, StagingMs) |>
    pivot_longer(c(TransferH2DMs, CompTimeMs, DecompTimeMs,
                   TransferD2HMs, StagingMs),
                 names_to = "Phase", values_to = "TimeMs") |>
    mutate(Phase = factor(Phase,
      levels = c("StagingMs", "TransferH2DMs", "CompTimeMs",
                 "DecompTimeMs", "TransferD2HMs"),
      labels = c("Alloc / H2H staging", "H2D Transfer",
                 "Compression", "Decompression", "D2H Transfer")))
  if (nrow(data) == 0) return(invisible(NULL))

  p <- ggplot(data, aes(x = Mode, y = TimeMs, fill = Phase)) +
    geom_col(width = 0.85, color = NA) +
    facet_grid(Algorithm ~ GPU,
               labeller = labeller(Algorithm = ALGO_LABELS),
               scales = "free_y") +
    scale_fill_manual(values = PHASE_COLORS_BREAKDOWN, name = "Phase") +
    scale_y_continuous(expand = expansion(mult = c(0, 0.05))) +
    labs(x = "Mode",
         y = sprintf("Execution time (ms), %s 4 GB", dataset_pick)) +
    theme_arcto() +
    theme(axis.text.x = element_text(angle = 25, hjust = 1, size = 7))
  gpus <- nlevels(droplevels(data$GPU))
  save_fig(p, "e2_breakdown_abs_ms", 2.0 * gpus + 1, 5.5)
}

# ══════════════════════════════════════════════════════════════════════════════
#  GROUP F - Compression ratio heatmap (lossless)
# ══════════════════════════════════════════════════════════════════════════════

fig_f1_ratio_heatmap_lossless <- function(df) {
  base <- lossless_rows(df) |>
    filter(Size == "xlarge", Mode == "adaptive")
  if (nrow(base) == 0) return(invisible(NULL))
  first_gpu <- levels(droplevels(base$GPU))[1]
  data <- base |> filter(GPU == first_gpu) |>
    mutate(log_ratio = log10(pmax(CompressionRatio, 1)),
           label_ratio = case_when(
             CompressionRatio < 10  ~ sprintf("%.2fx", CompressionRatio),
             CompressionRatio < 100 ~ sprintf("%.1fx", CompressionRatio),
             TRUE                   ~ sprintf("%.0fx", CompressionRatio)),
           text_color = ifelse(CompressionRatio > 50, "white", "#1A1A1A"),
           Algorithm  = factor(Algorithm, levels = ALGO_ORDER))

  p <- ggplot(data, aes(x = Dataset, y = Algorithm, fill = log_ratio)) +
    geom_tile(color = "white", linewidth = 1.0) +
    geom_text(aes(label = label_ratio, color = text_color),
              size = 4, fontface = "bold") +
    scale_fill_gradientn(colours = c("#D1E5F0", "#92C5DE", "#4393C3", "#2166AC"),
                         limits = c(0, log10(260)), breaks = c(0, 1, 2),
                         labels = c("1x", "10x", "100x"), name = "Ratio") +
    scale_color_identity() +
    scale_y_discrete(labels = ALGO_LABELS) +
    labs(x = "Dataset", y = "Algorithm") +
    theme_arcto() +
    theme(panel.grid = element_blank(), panel.border = element_blank(),
          axis.text.x = element_text(angle = 15, hjust = 1),
          axis.ticks = element_blank(),
          legend.position = "right", legend.direction = "vertical",
          legend.key.height = unit(1.3, "cm"),
          legend.key.width  = unit(0.4, "cm"))
  save_fig(p, "f1_ratio_heatmap_lossless", 5.0, 3.0)
}

# ══════════════════════════════════════════════════════════════════════════════
#  GROUP G - Compression / Decompression asymmetry
# ══════════════════════════════════════════════════════════════════════════════

fig_g1_asymmetry_heatmap <- function(df) {
  data <- lossless_rows(df) |>
    filter(Size == "xlarge", Mode == "adaptive") |>
    mutate(AsymRatio = DecompThroughputGBs / CompThroughputGBs,
           log_asym  = log10(AsymRatio),
           label_asym = case_when(
             AsymRatio < 1   ~ sprintf("%.1fx", AsymRatio),
             AsymRatio < 10  ~ sprintf("%.1fx", AsymRatio),
             TRUE            ~ sprintf("%.0fx", AsymRatio)),
           text_color = ifelse(abs(log_asym) > 0.8, "white", "#1A1A1A"),
           Algorithm  = factor(Algorithm, levels = ALGO_ORDER))
  if (nrow(data) == 0) return(invisible(NULL))

  p <- ggplot(data, aes(x = Dataset, y = Algorithm, fill = log_asym)) +
    geom_tile(color = "white", linewidth = 1.0) +
    geom_text(aes(label = label_asym, color = text_color),
              size = 4, fontface = "bold") +
    facet_wrap(~GPU, nrow = 1) +
    scale_fill_gradient2(low = "#F4A582", mid = "#FEE090", high = "#4393C3",
                         midpoint = 0, limits = c(-0.6, 2.0),
                         breaks = c(-0.5, 0, 0.5, 1.0, 1.5),
                         labels = c("0.3x", "1x", "3x", "10x", "30x"),
                         name = "Decomp / Comp", oob = squish) +
    scale_color_identity() +
    scale_y_discrete(labels = ALGO_LABELS) +
    labs(x = "Dataset", y = "Algorithm") +
    theme_arcto() +
    theme(panel.grid = element_blank(), panel.border = element_blank(),
          axis.text.x = element_text(angle = 15, hjust = 1),
          axis.ticks = element_blank(),
          legend.position = "right", legend.direction = "vertical",
          legend.key.height = unit(1.3, "cm"),
          legend.key.width  = unit(0.4, "cm"))
  gpus <- nlevels(droplevels(data$GPU))
  save_fig(p, "g1_asymmetry_heatmap", 4.0 * gpus + 1, 4)
}

# ══════════════════════════════════════════════════════════════════════════════
#  GROUP H - ZFP plots
#
#  Reference bands:
#    Barbosa & Coutinho 2023 (RTM Marmousi): fixed_accuracy tau=1e-6
#    preserves the migrated image; tau=1e-4 damages it. We highlight
#    [1e-6 ... 1e-4] as the "RTM-degraded" zone (too aggressive) and
#    use tau<=1e-6 as the "RTM-safe" zone for ZFP fixed_accuracy.
#
#    Lindstrom, Chen & Lee 2016 (F3DT): wavefield-fidelity envelope
#    validated at tau in [1e-13 ... 1e-16] against the sensitivity
#    kernel. Stricter than our sweep; we mark tau<=1e-13 as the
#    "Lindstrom F3DT-validated" zone.
#
#    Our own sweep covers 1e-3 ... 1e-12; the 1e-9 and 1e-12 points
#    bridge the gap between Barbosa and Lindstrom.
# ══════════════════════════════════════════════════════════════════════════════

# Helper: numeric accuracy from ZfpParam labels like "1e3", "1e12"
zfp_acc_numeric <- function(zfp_param) {
  # ZfpParam stored as "1e3" / "1e12" => 1e-3 / 1e-12 (negative exponent)
  num <- suppressWarnings(as.numeric(str_remove(zfp_param, "^1e")))
  ifelse(is.na(num), NA_real_, 10^(-num))
}

prep_zfp_acc <- function(df) {
  zfp_rows(df) |>
    filter(Mode == "acc", Dataset == "TTI (seismic)") |>
    mutate(Accuracy  = zfp_acc_numeric(ZfpParam),
           SizeLabel = factor(Size, levels = SIZE_ORDER,
                              labels = SIZE_LABELS[SIZE_ORDER]))
}

# Band annotations shared across acc plots
add_acc_bands <- function(p, ymin = -Inf, ymax = Inf) {
  p +
    annotate("rect", xmin = 1e-6, xmax = 1e-3, ymin = ymin, ymax = ymax,
             fill = "#F4A582", alpha = 0.15) +
    annotate("rect", xmin = 1e-17, xmax = 1e-13, ymin = ymin, ymax = ymax,
             fill = "#92C5DE", alpha = 0.15) +
    annotate("text", x = 10^(-4.5), y = ymax, vjust = 1.5,
             label = "RTM-degraded\n(Barbosa 2023)",
             size = 2.4, hjust = 0.5, color = "#A04020") +
    annotate("text", x = 10^(-15), y = ymax, vjust = 1.5,
             label = "F3DT-validated\n(Lindstrom 2016)",
             size = 2.4, hjust = 0.5, color = "#2050A0") +
    geom_vline(xintercept = 1e-6, color = "#A04020",
               linetype = "dashed", linewidth = 0.4) +
    geom_vline(xintercept = 1e-13, color = "#2050A0",
               linetype = "dashed", linewidth = 0.4)
}

fig_h1_zfp_acc_ratio <- function(df) {
  data <- prep_zfp_acc(df) |> filter(!is.na(Accuracy), CompressionRatio > 0)
  if (nrow(data) == 0) return(invisible(NULL))
  y_lim <- range(data$CompressionRatio, finite = TRUE) * c(0.9, 1.2)

  p <- ggplot(data,
              aes(x = Accuracy, y = CompressionRatio,
                  color = GPU, shape = GPU, group = GPU)) +
    geom_line(linewidth = 0.7) + geom_point(size = 2.2) +
    facet_wrap(~SizeLabel, nrow = 1) +
    scale_color_manual(values = GPU_COLORS, name = "GPU") +
    scale_shape_manual(values = c("MI50" = 18, "MI210" = 17,
                                  "MI300X" = 16, "RX7900XT" = 15),
                       name = "GPU") +
    scale_x_log10(breaks = 10^(-(3:16)),
                  labels = trans_format("log10", math_format(10^.x))) +
    scale_y_log10(expand = expansion(mult = c(0.05, 0.12))) +
    labs(x = "ZFP fixed-accuracy tolerance (tau)",
         y = "Compression ratio") +
    theme_arcto() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 7))
  p <- add_acc_bands(p, ymin = y_lim[1], ymax = y_lim[2])
  sizes <- nlevels(droplevels(data$SizeLabel))
  save_fig(p, "h1_zfp_acc_ratio", 2.8 * sizes + 1, 3.6)
}

fig_h2_zfp_acc_psnr <- function(df) {
  data <- prep_zfp_acc(df) |>
    filter(!is.na(Accuracy), !is.na(PSNR), is.finite(PSNR))
  if (nrow(data) == 0) return(invisible(NULL))
  y_lim <- range(data$PSNR, finite = TRUE) + c(-5, 5)

  p <- ggplot(data,
              aes(x = Accuracy, y = PSNR,
                  color = GPU, shape = GPU, group = GPU)) +
    geom_line(linewidth = 0.7) + geom_point(size = 2.2) +
    facet_wrap(~SizeLabel, nrow = 1) +
    scale_color_manual(values = GPU_COLORS, name = "GPU") +
    scale_shape_manual(values = c("MI50" = 18, "MI210" = 17,
                                  "MI300X" = 16, "RX7900XT" = 15),
                       name = "GPU") +
    scale_x_log10(breaks = 10^(-(3:16)),
                  labels = trans_format("log10", math_format(10^.x))) +
    scale_y_continuous(expand = expansion(mult = c(0.05, 0.10))) +
    labs(x = "ZFP fixed-accuracy tolerance (tau)", y = "PSNR (dB)") +
    theme_arcto() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 7))
  p <- add_acc_bands(p, ymin = y_lim[1], ymax = y_lim[2])
  sizes <- nlevels(droplevels(data$SizeLabel))
  save_fig(p, "h2_zfp_acc_psnr", 2.8 * sizes + 1, 3.6)
}

prep_zfp_rate <- function(df) {
  zfp_rows(df) |>
    filter(Mode == "rate", Dataset == "TTI (seismic)") |>
    mutate(BitsPerValue = suppressWarnings(as.numeric(ZfpParam)),
           SizeLabel = factor(Size, levels = SIZE_ORDER,
                              labels = SIZE_LABELS[SIZE_ORDER]))
}

fig_h3_zfp_rate_ratio <- function(df) {
  data <- prep_zfp_rate(df) |> filter(!is.na(BitsPerValue), CompressionRatio > 0)
  if (nrow(data) == 0) return(invisible(NULL))

  p <- ggplot(data,
              aes(x = BitsPerValue, y = CompressionRatio,
                  color = GPU, shape = GPU, group = GPU)) +
    geom_line(linewidth = 0.7) + geom_point(size = 2.4) +
    facet_wrap(~SizeLabel, nrow = 1) +
    scale_color_manual(values = GPU_COLORS, name = "GPU") +
    scale_shape_manual(values = c("MI50" = 18, "MI210" = 17,
                                  "MI300X" = 16, "RX7900XT" = 15),
                       name = "GPU") +
    scale_x_continuous(breaks = c(4, 8, 16, 24)) +
    labs(x = "ZFP fixed rate (bits per value)",
         y = "Compression ratio") +
    theme_arcto()
  sizes <- nlevels(droplevels(data$SizeLabel))
  save_fig(p, "h3_zfp_rate_ratio", 2.6 * sizes + 1, 3.3)
}

fig_h4_zfp_rate_psnr <- function(df) {
  data <- prep_zfp_rate(df) |>
    filter(!is.na(BitsPerValue), !is.na(PSNR), is.finite(PSNR))
  if (nrow(data) == 0) return(invisible(NULL))

  p <- ggplot(data,
              aes(x = BitsPerValue, y = PSNR,
                  color = GPU, shape = GPU, group = GPU)) +
    geom_line(linewidth = 0.7) + geom_point(size = 2.4) +
    facet_wrap(~SizeLabel, nrow = 1) +
    scale_color_manual(values = GPU_COLORS, name = "GPU") +
    scale_shape_manual(values = c("MI50" = 18, "MI210" = 17,
                                  "MI300X" = 16, "RX7900XT" = 15),
                       name = "GPU") +
    scale_x_continuous(breaks = c(4, 8, 16, 24)) +
    labs(x = "ZFP fixed rate (bits per value)",
         y = "PSNR (dB)") +
    theme_arcto()
  sizes <- nlevels(droplevels(data$SizeLabel))
  save_fig(p, "h4_zfp_rate_psnr", 2.6 * sizes + 1, 3.3)
}

fig_h5_zfp_prec_ratio_psnr <- function(df) {
  data <- zfp_rows(df) |>
    filter(Mode == "prec", Dataset == "TTI (seismic)") |>
    mutate(Precision = suppressWarnings(as.numeric(ZfpParam)),
           SizeLabel = factor(Size, levels = SIZE_ORDER,
                              labels = SIZE_LABELS[SIZE_ORDER]))
  if (nrow(data) == 0) return(invisible(NULL))

  long <- data |>
    pivot_longer(c(CompressionRatio, PSNR),
                 names_to = "Metric", values_to = "Value") |>
    mutate(Metric = factor(Metric, levels = c("CompressionRatio", "PSNR"),
                           labels = c("Ratio", "PSNR (dB)")))

  p <- ggplot(long,
              aes(x = Precision, y = Value,
                  color = GPU, shape = GPU, group = GPU)) +
    geom_line(linewidth = 0.7) + geom_point(size = 2.2) +
    facet_grid(Metric ~ SizeLabel, scales = "free_y") +
    scale_color_manual(values = GPU_COLORS, name = "GPU") +
    scale_shape_manual(values = c("MI50" = 18, "MI210" = 17,
                                  "MI300X" = 16, "RX7900XT" = 15),
                       name = "GPU") +
    scale_x_continuous(breaks = c(8, 16, 24)) +
    labs(x = "ZFP fixed precision (bit planes)", y = NULL) +
    theme_arcto()
  sizes <- nlevels(droplevels(data$SizeLabel))
  save_fig(p, "h5_zfp_prec_ratio_psnr", 2.4 * sizes + 1, 5.0)
}

fig_h6_zfp_pareto_unified <- function(df) {
  data <- zfp_rows(df) |>
    filter(Dataset == "TTI (seismic)",
           !is.na(PSNR), is.finite(PSNR), PSNR > 0) |>
    mutate(ZfpMode = factor(Mode, levels = c("acc", "rate", "prec"),
                            labels = ZFP_MODE_LABELS),
           ParamLabel = case_when(
             Mode == "acc"  ~ paste0("t=", ZfpParam),
             Mode == "rate" ~ paste0(ZfpParam, " b/v"),
             Mode == "prec" ~ paste0("p=", ZfpParam),
             TRUE           ~ as.character(ZfpParam)),
           SizeLabel = factor(Size, levels = SIZE_ORDER,
                              labels = SIZE_LABELS[SIZE_ORDER]))
  if (nrow(data) == 0) return(invisible(NULL))

  p <- ggplot(data,
              aes(x = CompressionRatio, y = PSNR,
                  color = ZfpMode, shape = ZfpMode)) +
    geom_point(size = 2.6, stroke = 0.8) +
    geom_text(aes(label = ParamLabel),
              hjust = -0.15, vjust = 0.3, size = 2.2,
              check_overlap = TRUE, show.legend = FALSE) +
    facet_grid(GPU ~ SizeLabel) +
    scale_color_manual(values = setNames(unname(ZFP_MODE_COLORS),
                                         ZFP_MODE_LABELS[names(ZFP_MODE_COLORS)]),
                       name = "ZFP mode") +
    scale_shape_manual(values = setNames(c(16, 17, 15),
                                         ZFP_MODE_LABELS[names(ZFP_MODE_COLORS)]),
                       name = "ZFP mode") +
    scale_x_log10(expand = expansion(mult = c(0.10, 0.25))) +
    scale_y_continuous(expand = expansion(mult = c(0.05, 0.10))) +
    labs(x = "Compression ratio (log)", y = "PSNR (dB)") +
    theme_arcto()
  gpus  <- nlevels(droplevels(data$GPU))
  sizes <- nlevels(droplevels(data$SizeLabel))
  save_fig(p, "h6_zfp_pareto_unified", 2.2 * sizes + 1, 2.0 * gpus + 1)
}

fig_h7_zfp_throughput <- function(df) {
  data <- zfp_rows(df) |>
    filter(Dataset == "TTI (seismic)") |>
    mutate(ZfpMode = factor(Mode, levels = c("acc", "rate", "prec"),
                            labels = ZFP_MODE_LABELS),
           ParamShort = case_when(
             Mode == "acc"  ~ ZfpParam,
             Mode == "rate" ~ paste0(ZfpParam, "b"),
             Mode == "prec" ~ paste0("p", ZfpParam),
             TRUE           ~ ZfpParam),
           SizeLabel = factor(Size, levels = SIZE_ORDER,
                              labels = SIZE_LABELS[SIZE_ORDER]))
  if (nrow(data) == 0) return(invisible(NULL))

  long <- data |>
    pivot_longer(c(CompThroughputGBs, DecompThroughputGBs),
                 names_to = "Operation", values_to = "Throughput") |>
    mutate(Operation = factor(Operation,
      levels = c("CompThroughputGBs", "DecompThroughputGBs"),
      labels = c("Compression", "Decompression")))

  p <- ggplot(long,
              aes(x = ParamShort, y = Throughput, fill = ZfpMode)) +
    geom_col(width = 0.7, color = NA) +
    facet_grid(Operation + GPU ~ SizeLabel,
               scales = "free_x", space = "free_x") +
    scale_fill_manual(values = setNames(unname(ZFP_MODE_COLORS),
                                        ZFP_MODE_LABELS[names(ZFP_MODE_COLORS)]),
                      name = "ZFP mode") +
    scale_y_continuous(expand = expansion(mult = c(0, 0.12))) +
    labs(x = "ZFP parameter", y = "Throughput (GB/s)") +
    theme_arcto(base_size = 8.5) +
    theme(axis.text.x = element_text(angle = 35, hjust = 1, size = 6),
          strip.text  = element_text(size = 7))
  gpus  <- nlevels(droplevels(data$GPU))
  sizes <- nlevels(droplevels(data$SizeLabel))
  save_fig(p, "h7_zfp_throughput", 2.4 * sizes + 1, 2.0 * gpus * 2 + 1)
}

# ══════════════════════════════════════════════════════════════════════════════
#  GROUP I - PCIe bandwidth curve (cross-GPU)
# ══════════════════════════════════════════════════════════════════════════════

fig_i1_pcie_curve_cross_gpu <- function(pcie_csv) {
  if (is.null(pcie_csv) || !file.exists(pcie_csv)) return(invisible(NULL))
  pc <- read_csv(pcie_csv, show_col_types = FALSE) |>
    mutate(across(c(h2d_pinned_gbps, h2d_pageable_gbps,
                    d2h_pinned_gbps, d2h_pageable_gbps),
                  ~ suppressWarnings(as.numeric(.))))

  # Map known host -> GPU label
  host_to_gpu <- c("lunaris" = "RX7900XT",
                   "larochette-5" = "MI210",
                   "vianden-1" = "MI300X")
  pc <- pc |>
    mutate(GPU = factor(host_to_gpu[host], levels = GPU_ORDER))

  data <- pc |>
    pivot_longer(c(h2d_pinned_gbps, h2d_pageable_gbps,
                   d2h_pinned_gbps, d2h_pageable_gbps),
                 names_to = "Variant", values_to = "GBps") |>
    mutate(Direction = if_else(str_detect(Variant, "^h2d"), "H2D", "D2H"),
           HostMem   = if_else(str_detect(Variant, "pinned"), "Pinned", "Pageable"))

  p <- ggplot(data,
              aes(x = size_mb, y = GBps,
                  color = GPU, linetype = HostMem, shape = HostMem,
                  group = interaction(GPU, Variant))) +
    geom_vline(xintercept = 16, color = "#888888", linetype = "dotted",
               linewidth = 0.5) +
    geom_vline(xintercept = 64, color = "#C0392B", linetype = "dashed",
               linewidth = 0.5) +
    annotate("text", x = 16, y = 2, label = "knee ~16 MiB",
             hjust = -0.05, size = 2.5, color = "#666666") +
    annotate("text", x = 64, y = 2, label = "W_pcie_amort = 64 MiB",
             hjust = -0.05, size = 2.5, color = "#C0392B") +
    geom_line(linewidth = 0.6) +
    geom_point(size = 1.8) +
    facet_wrap(~Direction, nrow = 1) +
    scale_color_manual(values = GPU_COLORS, name = "GPU") +
    scale_linetype_manual(values = c("Pinned" = "solid", "Pageable" = "dashed"),
                          name = "Host memory") +
    scale_shape_manual(values = c("Pinned" = 16, "Pageable" = 17),
                       name = "Host memory") +
    scale_x_log10(breaks = c(1, 4, 16, 64, 256, 1024),
                  labels = c("1", "4", "16", "64", "256", "1024")) +
    labs(x = "Transfer size (MiB)", y = "Bandwidth (GB/s)") +
    theme_arcto()
  save_fig(p, "i1_pcie_curve_cross_gpu", 8.0, 3.8)
}

# ══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════════════════

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: Rscript plots_arcto_v2.R all_results.csv [pcie_curve.csv]")
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

cat("Group A - Throughput (kernel)\n")
fig_a1_tput_xlarge(df)
fig_a2_tput_all_sizes(df)
fig_a3_tput_heatmap_xlarge(df)
fig_a4_tput_heatmap_per_size(df)

cat("Group B - Total time (end-to-end)\n")
fig_b1_total_xlarge(df)
fig_b2_total_all_sizes(df)
fig_b3_total_vs_size_per_mode(df)

cat("Group C - Speedup vs pageable\n")
fig_c1_speedup_xlarge(df)
fig_c2_speedup_per_size(df)

cat("Group D - Memory footprint\n")
fig_d1_peak_pinned_per_size(df)
fig_d2_alloc_time(df)

cat("Group E - Transfer breakdown\n")
fig_e1_overhead_pct_xlarge(df)
fig_e2_breakdown_abs_ms(df)

cat("Group F - Compression ratio\n")
fig_f1_ratio_heatmap_lossless(df)

cat("Group G - Asymmetry\n")
fig_g1_asymmetry_heatmap(df)

cat("Group H - ZFP\n")
fig_h1_zfp_acc_ratio(df)
fig_h2_zfp_acc_psnr(df)
fig_h3_zfp_rate_ratio(df)
fig_h4_zfp_rate_psnr(df)
fig_h5_zfp_prec_ratio_psnr(df)
fig_h6_zfp_pareto_unified(df)
fig_h7_zfp_throughput(df)

cat("Group I - PCIe curve\n")
if (!is.null(pcie_csv)) fig_i1_pcie_curve_cross_gpu(pcie_csv)

cat(sprintf("\nFigures saved under ./%s/  (PDF + PNG)\n", OUTPUT_DIR))
