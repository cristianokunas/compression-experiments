# plots_paper.R - figures for SBAC-PAD'26 ARCTO paper.
#
# Layout requested (2026-05-25):
#
#   Byte-level codecs (NO ZFP), facet: Algo (cols) x GPU (rows)
#     fig_time_byte         total time  (lines vs size, color = Mode)
#     fig_throughput_byte   compression throughput (bars, size x Mode)
#     fig_speedup_byte      speedup of chunk-optimized (adaptive) vs baseline
#
#   ZFP only, faceted by GPU
#     fig_zfp_time_thr      time and throughput, side-by-side panels
#     fig_zfp_ratio_acc     ratio vs tau for fixed_accuracy across sizes
#     fig_zfp_err_corr      max_abs_diff and PSNR vs tau (correlation)
#
# Visual conventions adopted from plots_iccsa.R (theme_iccsa, pastel palette).
#
# Usage:
#   cd paper/ARCTO-optim/draft/analysis
#   R_LIBS_USER=~/Rlibs Rscript plots_paper.R

.libPaths(c("~/Rlibs", .libPaths()))
suppressPackageStartupMessages({
  library(ggplot2); library(dplyr); library(tidyr)
  library(readr);  library(stringr); library(scales)
})

# ── Resolve paths ─────────────────────────────────────────────────────────
args <- commandArgs(trailingOnly = FALSE)
file_arg <- args[grep("^--file=", args)]
HERE  <- if (length(file_arg) > 0) dirname(normalizePath(sub("^--file=", "", file_arg))) else normalizePath(".")
DRAFT <- normalizePath(file.path(HERE, ".."))
RES   <- normalizePath(file.path(DRAFT, "..", "results"))
OUT   <- file.path(DRAFT, "figures")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

# ══════════════════════════════════════════════════════════════════════════
#  DESIGN SYSTEM
# ══════════════════════════════════════════════════════════════════════════

MODE_COLORS <- c(baseline = "#999999",
                 pinned   = "#92C5DE",
                 adaptive = "#F4A582")
MODE_LABELS <- c(baseline = "Baseline (pageable)",
                 pinned   = "Single-shot pinned",
                 adaptive = "Adaptive tiled")

ALGO_LABELS <- c(lz4 = "LZ4", snappy = "Snappy", cascaded = "Cascaded")
ALGO_COLORS <- c(lz4 = "#F4A582", snappy = "#92C5DE", cascaded = "#A6D96A")

GPU_LABELS  <- c(gfx906 = "MI50 (gfx906)",
                 gfx90a = "MI210 (gfx90a)",
                 gfx942 = "MI300X (gfx942)",
                 gfx1100 = "RX 7900 XT (gfx1100)")
GPU_COLORS  <- c(gfx906 = "#A0A0A0", gfx90a = "#5B9BD5",
                 gfx942 = "#1F4E79", gfx1100 = "#C0392B")

ZFP_MODE_COLORS <- c(fixed_accuracy  = "#C0392B",
                     fixed_rate      = "#27AE60",
                     fixed_precision = "#F39C12")
ZFP_MODE_LABELS <- c(fixed_accuracy  = "fixed accuracy",
                     fixed_rate      = "fixed rate",
                     fixed_precision = "fixed precision")

SIZE_ORDER  <- c("10mb", "100mb", "1gb", "4gb", "8gb", "16gb")
SIZE_LABEL  <- c("10mb" = "10 MB", "100mb" = "100 MB",
                 "1gb"  = "1 GB",  "4gb"   = "4 GB",
                 "8gb"  = "8 GB",  "16gb"  = "16 GB")
SIZE_MAP    <- c("10mb" = 10, "100mb" = 100, "1gb" = 1024,
                 "4gb"  = 4096, "8gb" = 8192, "16gb" = 16384)
DATASET_LABEL <- c(zeros = "Zeros", binary = "Binary",
                   random = "Random", tti = "TTI (seismic)")

theme_iccsa <- function(base_size = 9.4) {
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
      legend.spacing.x   = unit(6, "pt"),
      axis.title         = element_text(face = "bold", size = base_size),
      axis.text          = element_text(size = base_size - 2, color = "black"),
      axis.ticks         = element_line(color = "grey60", linewidth = 0.35),
      axis.ticks.length  = unit(3, "pt"),
      plot.background    = element_rect(fill = "white", color = NA),
      plot.margin        = margin(6, 8, 6, 6)
    )
}

save_fig <- function(p, name, width, height) {
  ggsave(file.path(OUT, paste0(name, ".pdf")), p,
         width = width, height = height, device = "pdf")
  # PNG at 150 dpi -- keeps long edge below 2000 px for preview, while
  # the PDF retains vector quality for the paper.
  ggsave(file.path(OUT, paste0(name, ".png")), p,
         width = width, height = height, dpi = 150, device = "png")
  cat(sprintf("  v  %s\n", name))
}

# ══════════════════════════════════════════════════════════════════════════
#  LOAD CSVs
# ══════════════════════════════════════════════════════════════════════════

CAMPAIGNS <- tibble::tribble(
  ~gpu_arch, ~dir,
  "gfx1100", "lunaris_FULL_20260525_154849",         # 6-tolerance set
  "gfx90a",  "larochette_FULL_20260525_165539",      # 4-tolerance set (pre-rerun)
) |> filter(dir.exists(file.path(RES, dir)))

pat_A <- "^(tti|zeros|random|binary)_(10mb|100mb|1gb|4gb|8gb|16gb)_(lz4|snappy|cascaded)_(baseline|pinned|adaptive)\\.csv$"
pat_B <- "^(tti|zeros|random|binary)_(10mb|100mb|1gb|4gb|8gb|16gb)_zfp_(acc|rate|prec)([0-9e]+)\\.csv$"

read_blockA <- function(arch, dir_) {
  csvs <- list.files(file.path(RES, dir_), pattern = pat_A, full.names = TRUE)
  bind_rows(lapply(csvs, function(f) {
    nm <- basename(f); m <- regmatches(nm, regexec(pat_A, nm))[[1]]
    df <- suppressWarnings(read_csv(f, show_col_types = FALSE, progress = FALSE))
    if (nrow(df) == 0) return(NULL)
    r <- df[1, ]
    tibble(
      gpu_arch       = arch,
      Dataset        = m[2],
      Size           = m[3],
      Algorithm      = m[4],
      Mode           = m[5],
      Ratio          = r$`Compression ratio`,
      CompGBs        = r$`Compression throughput (uncompressed) in GB/s`,
      CompGBs_std    = r$`Comp throughput stddev (GB/s)`,
      DecompGBs      = r$`Decompression throughput (uncompressed) in GB/s`,
      DecompGBs_std  = r$`Decomp throughput stddev (GB/s)`,
      TotalMs        = r$`Total time (ms)`,
      CompMs         = r$`Compression time (ms)`,
      CompMs_std     = r$`Comp time stddev (ms)`,
      DecompMs       = r$`Decompression time (ms)`,
      TransferH2D    = r$`Transfer H2D (ms)`,
      TransferD2H    = r$`Transfer D2H (ms)`,
      AllocMs        = r$t_alloc_ms,
      MemcpyH2H      = r$t_memcpy_h2h_ms,
    )
  }))
}

read_blockB <- function(arch, dir_) {
  csvs <- list.files(file.path(RES, dir_), pattern = pat_B, full.names = TRUE)
  bind_rows(lapply(csvs, function(f) {
    nm <- basename(f); m <- regmatches(nm, regexec(pat_B, nm))[[1]]
    df <- suppressWarnings(read_csv(f, show_col_types = FALSE, progress = FALSE))
    if (nrow(df) == 0) return(NULL)
    r <- df[1, ]; short <- m[4]; raw <- m[5]
    if (short == "acc") {
      zmode <- "fixed_accuracy"
      zparam <- as.numeric(paste0(substr(raw, 1, 1), "e-", substr(raw, 3, nchar(raw))))
    } else if (short == "rate") {
      zmode <- "fixed_rate"; zparam <- as.numeric(raw)
    } else {
      zmode <- "fixed_precision"; zparam <- as.numeric(raw)
    }
    tibble(
      gpu_arch    = arch, Dataset = m[2], Size = m[3],
      ZMode       = zmode, ZParam = zparam,
      Ratio       = r$`Compression ratio`,
      CompGBs     = r$`Compression throughput (uncompressed) in GB/s`,
      DecompGBs   = r$`Decompression throughput (uncompressed) in GB/s`,
      TotalMs     = r$`Total time (ms)`,
      MaxAbsDiff  = r$`Max abs diff`,
      PSNR        = r$`PSNR (dB)`,
    )
  }))
}

dfA <- bind_rows(lapply(seq_len(nrow(CAMPAIGNS)), function(i)
  read_blockA(CAMPAIGNS$gpu_arch[i], CAMPAIGNS$dir[i]))) |>
  mutate(
    Size      = factor(Size, levels = SIZE_ORDER),
    Dataset   = factor(Dataset, levels = names(DATASET_LABEL),
                       labels = DATASET_LABEL),
    Algorithm = factor(Algorithm, levels = names(ALGO_LABELS)),
    Mode      = factor(Mode, levels = names(MODE_LABELS)),
    gpu_arch  = factor(gpu_arch, levels = names(GPU_LABELS))
  )

dfB <- bind_rows(lapply(seq_len(nrow(CAMPAIGNS)), function(i)
  read_blockB(CAMPAIGNS$gpu_arch[i], CAMPAIGNS$dir[i]))) |>
  mutate(
    Size     = factor(Size,    levels = SIZE_ORDER),
    Dataset  = factor(Dataset, levels = names(DATASET_LABEL),
                      labels = DATASET_LABEL),
    ZMode    = factor(ZMode,   levels = names(ZFP_MODE_LABELS)),
    gpu_arch = factor(gpu_arch, levels = names(GPU_LABELS))
  )

# Speedup of adaptive vs baseline (per gpu, dataset, size, algo)
baseA <- dfA |> filter(Mode == "baseline") |>
  select(gpu_arch, Dataset, Size, Algorithm, BaseTotalMs = TotalMs)
dfA <- dfA |> left_join(baseA, by = c("gpu_arch","Dataset","Size","Algorithm")) |>
  mutate(Speedup = BaseTotalMs / TotalMs)

cat("Campaigns:", paste(levels(droplevels(dfA$gpu_arch)), collapse = ", "), "\n")
cat(sprintf("Block A rows: %d  |  Block B rows: %d\n", nrow(dfA), nrow(dfB)))


# ══════════════════════════════════════════════════════════════════════════
#  BYTE-LEVEL FIGURE 1 -- TIME
#  Facet: Algorithm (cols) x GPU (rows). X = Size, Y = TotalMs (log).
#  Color = Mode. Bars dodged.
# ══════════════════════════════════════════════════════════════════════════

fig_time_byte <- function(df) {
  data <- df |> filter(Dataset == "TTI (seismic)")

  p <- ggplot(data, aes(x = Size, y = TotalMs, fill = Mode)) +
    geom_col(position = position_dodge(width = 0.85), width = 0.78, color = NA) +
    geom_text(aes(label = ifelse(TotalMs >= 100,
                                 sprintf("%.0f", TotalMs),
                                 sprintf("%.1f", TotalMs))),
              position = position_dodge(width = 0.85),
              vjust = -0.35, size = 2.0) +
    facet_grid(gpu_arch ~ Algorithm,
               labeller = labeller(gpu_arch = GPU_LABELS,
                                   Algorithm = ALGO_LABELS),
               scales = "free_y") +
    scale_fill_manual(values = MODE_COLORS, labels = MODE_LABELS, name = "Mode") +
    scale_x_discrete(labels = SIZE_LABEL) +
    scale_y_log10(expand = expansion(mult = c(0, 0.18)),
                  labels = label_number(big.mark = "")) +
    labs(x = NULL, y = "End-to-end time (ms, log)",
         title = "End-to-end time on TTI -- three transfer modes",
         subtitle = "n=30 per cell. Smaller is better.") +
    theme_iccsa() +
    theme(axis.text.x = element_text(angle = 35, hjust = 1))

  save_fig(p, "fig_time_byte",
           1.8 * length(levels(droplevels(data$Algorithm))) + 0.5, 5)
}


# ══════════════════════════════════════════════════════════════════════════
#  BYTE-LEVEL FIGURE 2 -- THROUGHPUT
#  Facet: Algorithm (cols) x GPU (rows). X = Size, Y = CompGBs (linear).
#  Color = Mode. Bars dodged. Error bars from stddev.
# ══════════════════════════════════════════════════════════════════════════

fig_throughput_byte <- function(df) {
  data <- df |> filter(Dataset == "TTI (seismic)")

  p <- ggplot(data, aes(x = Size, y = CompGBs, fill = Mode)) +
    geom_col(position = position_dodge(width = 0.85), width = 0.78, color = NA) +
    geom_errorbar(aes(ymin = pmax(CompGBs - CompGBs_std, 0),
                      ymax = CompGBs + CompGBs_std),
                  position = position_dodge(width = 0.85),
                  width = 0.22, linewidth = 0.35, color = "grey40") +
    geom_text(aes(label = sprintf("%.0f", CompGBs)),
              position = position_dodge(width = 0.85),
              vjust = -0.5, size = 2.0) +
    facet_grid(gpu_arch ~ Algorithm,
               labeller = labeller(gpu_arch = GPU_LABELS,
                                   Algorithm = ALGO_LABELS),
               scales = "free_y") +
    scale_fill_manual(values = MODE_COLORS, labels = MODE_LABELS, name = "Mode") +
    scale_x_discrete(labels = SIZE_LABEL) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
    labs(x = NULL, y = "Compression throughput (GB/s)",
         title = "Compression throughput on TTI -- three transfer modes",
         subtitle = "Error bars are 1 stddev across 30 iterations.") +
    theme_iccsa() +
    theme(axis.text.x = element_text(angle = 35, hjust = 1))

  save_fig(p, "fig_throughput_byte",
           1.8 * length(levels(droplevels(data$Algorithm))) + 0.5, 5)
}


# ══════════════════════════════════════════════════════════════════════════
#  BYTE-LEVEL FIGURE 3 -- SPEEDUP CHUNK-OPTIM (ADAPTIVE) VS BASELINE
#  Facet: Algorithm (cols) x GPU (rows). X = Size, Y = Speedup.
#  Single bar per (size, algo, gpu) -- only the optimized variant.
# ══════════════════════════════════════════════════════════════════════════

fig_speedup_byte <- function(df) {
  data <- df |>
    filter(Dataset == "TTI (seismic)", Mode == "adaptive")

  p <- ggplot(data, aes(x = Size, y = Speedup, fill = Algorithm)) +
    geom_col(width = 0.72, color = NA) +
    geom_hline(yintercept = 1, linetype = "dashed",
               color = "#C0392B", linewidth = 0.5, alpha = 0.7) +
    geom_text(aes(label = sprintf("%.1fx", Speedup)),
              vjust = -0.4, size = 2.6) +
    facet_grid(gpu_arch ~ Algorithm,
               labeller = labeller(gpu_arch = GPU_LABELS,
                                   Algorithm = ALGO_LABELS)) +
    scale_fill_manual(values = ALGO_COLORS, labels = ALGO_LABELS,
                      name = "Algorithm", guide = "none") +
    scale_x_discrete(labels = SIZE_LABEL) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.18))) +
    labs(x = NULL, y = "End-to-end speedup (adaptive / baseline)",
         title = "Speedup of the chunk-optimized adaptive pipeline vs.\\ baseline",
         subtitle = "Dashed line at 1x = no improvement.") +
    theme_iccsa() +
    theme(axis.text.x = element_text(angle = 35, hjust = 1))

  save_fig(p, "fig_speedup_byte",
           1.8 * length(levels(droplevels(data$Algorithm))) + 0.5, 5)
}


# ══════════════════════════════════════════════════════════════════════════
#  ZFP FIGURE 1 -- TIME AND THROUGHPUT, two panels
#  X = ZFP config (within mode), Y_left = time, Y_right = throughput.
#  Facet: gpu (cols), metric (rows).
# ══════════════════════════════════════════════════════════════════════════

fig_zfp_time_thr <- function(df) {
  # Order configs naturally: accuracy -> precision -> rate
  data <- df |>
    filter(Dataset == "TTI (seismic)") |>
    mutate(Config = case_when(
      ZMode == "fixed_accuracy"  ~ sprintf("acc\n%.0e", ZParam),
      ZMode == "fixed_precision" ~ sprintf("prec\n%d",  as.integer(ZParam)),
      ZMode == "fixed_rate"      ~ sprintf("rate\n%d",  as.integer(ZParam))
    )) |>
    mutate(Config = factor(Config, levels = unique(Config[order(ZMode, ZParam)])))

  long <- data |>
    select(gpu_arch, Size, ZMode, Config, TotalMs, CompGBs) |>
    pivot_longer(c(TotalMs, CompGBs), names_to = "Metric", values_to = "Value") |>
    mutate(Metric = factor(Metric, levels = c("TotalMs", "CompGBs"),
                           labels = c("End-to-end time (ms, log)",
                                      "Compression throughput (GB/s)")))

  p <- ggplot(long |> filter(Size %in% c("1gb", "4gb", "8gb")),
              aes(x = Config, y = Value, fill = ZMode)) +
    geom_col(position = position_dodge(width = 0.85), width = 0.78, color = NA) +
    facet_grid(Metric ~ gpu_arch + Size,
               labeller = labeller(gpu_arch = GPU_LABELS,
                                   Size = SIZE_LABEL),
               scales = "free_y") +
    scale_fill_manual(values = ZFP_MODE_COLORS,
                      labels = ZFP_MODE_LABELS,
                      name = "ZFP mode") +
    labs(x = NULL, y = NULL,
         title = "ZFP time and throughput on TTI",
         subtitle = "Per architecture, per input size, all 11 lossy configurations.") +
    theme_iccsa() +
    theme(axis.text.x = element_text(angle = 0, size = 6.5),
          panel.spacing.x = unit(0.3, "lines"),
          strip.text.x   = element_text(size = 8))

  save_fig(p, "fig_zfp_time_thr", 12, 6)
}


# ══════════════════════════════════════════════════════════════════════════
#  ZFP FIGURE 2 -- RATIO PER FIXED-ACCURACY
#  Fixed-accuracy mode only. X = tau, Y = compression ratio.
#  Lines per Size, facet by GPU.
# ══════════════════════════════════════════════════════════════════════════

fig_zfp_ratio_acc <- function(df) {
  data <- df |>
    filter(Dataset == "TTI (seismic)",
           ZMode == "fixed_accuracy")

  p <- ggplot(data, aes(x = ZParam, y = Ratio,
                        color = Size, group = Size, shape = Size)) +
    geom_line(linewidth = 0.7) +
    geom_point(size = 2.6, stroke = 0.6) +
    geom_text(aes(label = sprintf("%.1fx", Ratio)),
              vjust = -1.0, size = 2.3, show.legend = FALSE) +
    facet_wrap(~gpu_arch, nrow = 1,
               labeller = labeller(gpu_arch = GPU_LABELS)) +
    scale_x_log10(breaks = c(1e-3, 1e-4, 1e-5, 1e-6),
                  labels = function(x) sprintf("%.0e", x)) +
    scale_y_continuous(expand = expansion(mult = c(0.05, 0.18))) +
    scale_color_brewer(palette = "Set2", name = "Input size",
                       labels = SIZE_LABEL) +
    scale_shape_discrete(name = "Input size", labels = SIZE_LABEL) +
    labs(x = expression("Requested tolerance " ~ tau ~ " (log)"),
         y = "Compression ratio",
         title = "ZFP fixed-accuracy: compression ratio vs.\\ tolerance on TTI",
         subtitle = "Tighter tolerance (smaller tau, right) -> less compression.") +
    theme_iccsa() +
    theme(panel.grid.major.x = element_line(color = "#E4E4E4",
                                            linewidth = 0.3, linetype = "dashed"))

  save_fig(p, "fig_zfp_ratio_acc", 8.5, 4)
}


# ══════════════════════════════════════════════════════════════════════════
#  ZFP FIGURE 3 -- ERROR METRICS CORRELATION
#  Fixed-accuracy. X = tau, Y_left = max_abs_diff, Y_right = PSNR.
#  Two panels (Metric facets), color by gpu, point by size.
# ══════════════════════════════════════════════════════════════════════════

fig_zfp_err_corr <- function(df) {
  base <- df |>
    filter(Dataset == "TTI (seismic)", ZMode == "fixed_accuracy")

  err <- base |>
    select(gpu_arch, Size, ZParam, MaxAbsDiff, PSNR) |>
    pivot_longer(c(MaxAbsDiff, PSNR),
                 names_to = "Metric", values_to = "Value") |>
    mutate(Metric = factor(Metric,
            levels = c("MaxAbsDiff", "PSNR"),
            labels = c("Max abs diff (L_inf error, log)",
                       "PSNR (dB)")))

  # Diagonal y=x trace only for the MaxAbsDiff panel
  diag_df <- tibble(
    Metric = factor("Max abs diff (L_inf error, log)",
                    levels = levels(err$Metric)),
    x = c(1e-6, 1e-3),
    y = c(1e-6, 1e-3)
  )

  p <- ggplot(err, aes(x = ZParam, y = Value,
                       color = gpu_arch, shape = Size,
                       group = interaction(gpu_arch, Size))) +
    geom_line(data = diag_df,
              aes(x = x, y = y),
              inherit.aes = FALSE,
              linetype = "dashed", color = "grey55", linewidth = 0.5) +
    geom_line(linewidth = 0.5, alpha = 0.6) +
    geom_point(size = 2.6, stroke = 0.6) +
    facet_wrap(~Metric, nrow = 1, scales = "free_y") +
    scale_x_log10(breaks = c(1e-3, 1e-4, 1e-5, 1e-6),
                  labels = function(x) sprintf("%.0e", x)) +
    scale_color_manual(values = GPU_COLORS, labels = GPU_LABELS,
                       name = "Architecture") +
    scale_shape_discrete(name = "Input size", labels = SIZE_LABEL) +
    labs(x = expression("Requested tolerance " ~ tau ~ " (log)"),
         y = NULL,
         title = "ZFP fixed-accuracy: how error tracks the requested tolerance",
         subtitle = "Left: measured L_inf error stays below tau (dashed y=x). Right: PSNR grows as tau tightens.") +
    theme_iccsa()

  # Apply log scale only to the MaxAbsDiff facet via faceted_scales would
  # require a helper; fall back to log of the actual values for that panel.
  # Simpler: set a free y-scale per facet (already done) and let the
  # MaxAbsDiff range render on log via secondary transform per facet.
  # Workaround: use scale_y_log10() for the whole plot but PSNR is also
  # positive, so log of PSNR is harmless and keeps both panels readable.
  p <- p + scale_y_log10()

  save_fig(p, "fig_zfp_err_corr", 9, 4.2)
}


# ══════════════════════════════════════════════════════════════════════════
#  GO
# ══════════════════════════════════════════════════════════════════════════

cat("\nGenerating figures...\n")
fig_time_byte(dfA)
fig_throughput_byte(dfA)
fig_speedup_byte(dfA)
fig_zfp_time_thr(dfB)
fig_zfp_ratio_acc(dfB)
fig_zfp_err_corr(dfB)
cat(sprintf("\nDone. Figures in: %s\n", OUT))
