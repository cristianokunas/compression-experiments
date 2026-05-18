# plots_paper2_exploratory.R
#
# Exploratory figure candidates for paper #2 (ARCTO: Efficient Compression
# for AMD GPUs). Generates 4 main figures, each with 1-2 variants, to
# decide visualization direction before settling on a final set.
#
# Usage:
#   cd paper/ARCTO-optim
#   Rscript plots_paper2_exploratory.R
#
# Outputs land in plots_paper2_output/ as PDF + PNG.
#
# Inputs (all in paper/ARCTO-optim):
#   results_paper2_progression.csv         -- 288 rows (baseline/+pinned/+chunk_optim)
#   results_paper2_lossless_comparison.csv -- 28 rows (LZ4 vs ZFP-Reversible)
#   results/RX7900XT_ZFP_FIDELITY_*/results_zfp_fidelity.csv -- 18 rows

.libPaths(c("~/Rlibs", .libPaths()))   # allow user-installed packages
suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(stringr)
  library(scales)
})

OUT <- "plots_paper2_output"
dir.create(OUT, showWarnings = FALSE)

# ── Palette + ordering (mirrors plots_iccsa_v4.R for consistency) ────────────
ALGO_COLORS <- c(
  "lz4"      = "#F4A582",
  "snappy"   = "#92C5DE",
  "cascaded" = "#A6D96A"
)
ALGO_LABELS <- c(lz4 = "LZ4", snappy = "Snappy", cascaded = "Cascaded")
GPU_COLORS  <- c("MI300X" = "#1F4E79", "RX7900XT" = "#C0392B")
STAGE_COLORS <- c(
  "baseline"     = "#999999",
  "+pinned"      = "#92C5DE",
  "+chunk_optim" = "#F4A582"
)
DATASET_ORDER  <- c("zeros", "binary", "random", "TTI")
SIZE_ORDER     <- c("small", "medium", "large", "xlarge")
SIZE_LABELS    <- c(small = "10 MB", medium = "100 MB", large = "1 GB", xlarge = "4 GB")

BASE_THEME <- theme_minimal(base_size = 11) +
  theme(
    panel.grid.minor = element_blank(),
    legend.position  = "bottom",
    strip.background = element_rect(fill = "grey92", color = NA),
    strip.text       = element_text(face = "bold", size = 10)
  )

# ── Load + tidy ──────────────────────────────────────────────────────────────
prog <- read_csv("results_paper2_progression.csv", show_col_types = FALSE) |>
  mutate(
    size    = str_extract(TestFile, "^[a-z]+"),
    dtype   = str_match(TestFile, "_(zeros|binary|random|TTI)_")[, 2],
    size    = factor(size, levels = SIZE_ORDER),
    dtype   = factor(dtype, levels = DATASET_ORDER),
    Stage   = factor(Stage, levels = c("baseline", "+pinned", "+chunk_optim")),
    AlgoLab = factor(Algo, levels = names(ALGO_LABELS), labels = ALGO_LABELS)
  )

# Find the fidelity CSV (timestamped dir)
fid_path <- list.files("results", pattern = "results_zfp_fidelity.csv",
                       recursive = TRUE, full.names = TRUE)[1]
fid <- if (!is.na(fid_path)) read_csv(fid_path, show_col_types = FALSE) else NULL

lossless <- read_csv("results_paper2_lossless_comparison.csv", show_col_types = FALSE)

cat(sprintf("loaded: %d progression rows, %d lossless rows, %d fidelity rows\n",
            nrow(prog),
            nrow(lossless),
            if (is.null(fid)) 0 else nrow(fid)))

# ═════════════════════════════════════════════════════════════════════════════
#  FIGURE 1 -- PROGRESSION SPEEDUP (the headline)
# ═════════════════════════════════════════════════════════════════════════════
# Story: "how much did each optimization contribute, per algo, per GPU?"
# Variant A: TTI-only side-by-side bars (cleaner, paper-figure quality).
# Variant B: All-datatype faceted heatmap (richer, supplementary-style).

# -- 1A: TTI-only bar chart by stage (medium + large only -- the paper anchor)
fig1a_data <- prog |>
  filter(dtype == "TTI", size %in% c("medium", "large"))

fig1a <- ggplot(fig1a_data,
                aes(x = AlgoLab, y = Speedup_vs_baseline, fill = Stage)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  geom_text(aes(label = sprintf("%.1fx", Speedup_vs_baseline)),
            position = position_dodge(width = 0.8), vjust = -0.3, size = 2.8) +
  facet_grid(size ~ GPU,
             labeller = labeller(size = c(medium = "Medium TTI (100 MB)",
                                          large  = "Large TTI (686 MB)"))) +
  scale_fill_manual(values = STAGE_COLORS, name = "Stage") +
  scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(x = NULL, y = "Total-time speedup vs baseline (×)",
       title = "Cumulative optimization speedup -- TTI seismic workload",
       subtitle = "baseline = pageable 64K chunks (ICCSA26 config)") +
  BASE_THEME

ggsave(file.path(OUT, "fig1a_progression_TTI.pdf"), fig1a, width = 9, height = 6)
ggsave(file.path(OUT, "fig1a_progression_TTI.png"), fig1a, width = 9, height = 6, dpi = 150)

# -- 1B: Full-matrix heatmap (all 16 datasets)
fig1b_data <- prog |>
  filter(Stage == "+chunk_optim") |>      # only the final stage
  mutate(
    size_lab = SIZE_LABELS[as.character(size)]
  )

fig1b <- ggplot(fig1b_data,
                aes(x = size, y = dtype, fill = Speedup_vs_baseline)) +
  geom_tile(color = "white") +
  geom_text(aes(label = sprintf("%.1fx", Speedup_vs_baseline)),
            size = 2.8, color = "white", fontface = "bold") +
  facet_grid(GPU ~ AlgoLab) +
  scale_fill_gradient(low = "#92C5DE", high = "#08306B",
                      name = "Final speedup\nvs baseline",
                      limits = c(1, NA)) +
  scale_x_discrete(labels = SIZE_LABELS) +
  labs(x = "Input size", y = "Data type",
       title = "Final-state speedup matrix (baseline+pinned+chunk_optim vs baseline)",
       subtitle = "Heatmap shows speedup magnitude across all 16 dataset variants") +
  BASE_THEME +
  theme(axis.text.x = element_text(angle = 0))

ggsave(file.path(OUT, "fig1b_progression_heatmap.pdf"), fig1b, width = 10, height = 6)
ggsave(file.path(OUT, "fig1b_progression_heatmap.png"), fig1b, width = 10, height = 6, dpi = 150)

# ═════════════════════════════════════════════════════════════════════════════
#  FIGURE 2 -- ABSOLUTE TIME WATERFALL (per-stage attribution)
# ═════════════════════════════════════════════════════════════════════════════
# Story: "what was the actual bottleneck before vs after?". Shows the time
# each optim stage SHAVES OFF. Helpful when reviewers ask "is this real or
# just relative-number gymnastics".

fig2_data <- prog |>
  filter(dtype == "TTI", size == "medium")

fig2 <- ggplot(fig2_data,
               aes(x = AlgoLab, y = TotalMs, fill = Stage)) +
  geom_col(position = "dodge", width = 0.7) +
  geom_text(aes(label = sprintf("%.1f ms", TotalMs)),
            position = position_dodge(width = 0.7), vjust = -0.3, size = 2.8) +
  facet_wrap(~ GPU) +
  scale_fill_manual(values = STAGE_COLORS) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(x = NULL, y = "Total time (ms)",
       title = "End-to-end pipeline time per stage -- Medium TTI 100 MB",
       subtitle = "Smaller is better. Stage colors match Fig 1.") +
  BASE_THEME

ggsave(file.path(OUT, "fig2_total_time.pdf"), fig2, width = 8, height = 5)
ggsave(file.path(OUT, "fig2_total_time.png"), fig2, width = 8, height = 5, dpi = 150)

# ═════════════════════════════════════════════════════════════════════════════
#  FIGURE 3 -- LOSSLESS HEAD-TO-HEAD (LZ4 vs ZFP-Reversible)
# ═════════════════════════════════════════════════════════════════════════════
# Story: "for lossless float compression of seismic data, neither byte
# compression (LZ4) nor float-aware lossless (ZFP-Reversible) really
# compresses; ZFP-Rev wins on speed, LZ4 on ratio. Hence: need lossy."

if (any(grepl("ZFP-Reversible", lossless$Algo))) {
  fig3_data <- lossless |>
    filter(grepl("TTI|zeros|random|binary", Dataset)) |>
    mutate(
      Dataset = str_replace(Dataset, "_(\\d+)\\.bin$", "")
    ) |>
    pivot_longer(c(Ratio, CompGBs, DecompGBs), names_to = "metric", values_to = "value")

  # Variant A: faceted by metric, color by algo
  fig3a <- ggplot(fig3_data |> filter(metric %in% c("Ratio", "CompGBs", "DecompGBs")),
                  aes(x = Dataset, y = value, fill = Algo)) +
    geom_col(position = "dodge", width = 0.7) +
    facet_grid(metric ~ GPU, scales = "free_y",
               labeller = labeller(metric = c(Ratio = "Compression Ratio (x)",
                                              CompGBs = "Comp throughput (GB/s)",
                                              DecompGBs = "Decomp throughput (GB/s)"))) +
    scale_fill_manual(values = c("LZ4-pinned" = "#F4A582", "ZFP-Reversible" = "#A6D96A")) +
    labs(x = NULL, y = NULL,
         title = "Lossless comparison: LZ4 (byte) vs ZFP-Reversible (float-aware)",
         subtitle = "Both bit-exact; ZFP-Rev wins comp speed, LZ4 wins ratio on TTI") +
    BASE_THEME +
    theme(axis.text.x = element_text(angle = 35, hjust = 1))

  ggsave(file.path(OUT, "fig3_lossless_compare.pdf"), fig3a, width = 11, height = 7)
  ggsave(file.path(OUT, "fig3_lossless_compare.png"), fig3a, width = 11, height = 7, dpi = 150)
}

# ═════════════════════════════════════════════════════════════════════════════
#  FIGURE 4 -- LOSSY FIDELITY PARETO (ratio vs PSNR)
# ═════════════════════════════════════════════════════════════════════════════
# Story: "the lossy trade-off curve is monotonic, tolerance-honored, and the
# RTM production point (fixed_accuracy 1e-3) is clearly identifiable on it"

if (!is.null(fid)) {
  fid_clean <- fid |>
    mutate(
      # Make mode + param into a single label
      ModeLabel = case_when(
        Mode == "reversible"      ~ "Reversible (lossless)",
        Mode == "fixed_accuracy"  ~ sprintf("fixed_acc %.0e", as.numeric(Param)),
        Mode == "fixed_precision" ~ sprintf("fixed_prec %s",   Param),
        Mode == "fixed_rate"      ~ sprintf("fixed_rate %s",   Param),
        TRUE                      ~ paste(Mode, Param)
      ),
      ModeFamily = case_when(
        Mode == "reversible"      ~ "Reversible",
        Mode == "fixed_accuracy"  ~ "fixed_accuracy",
        Mode == "fixed_precision" ~ "fixed_precision",
        Mode == "fixed_rate"      ~ "fixed_rate"
      ),
      DatasetShort = str_replace(TestFile, "_(\\d+)\\.bin$", "")
    )

  fig4 <- ggplot(fid_clean,
                 aes(x = PSNR_dB, y = CompressionRatio,
                     color = ModeFamily, shape = DatasetShort)) +
    geom_point(size = 3.5, alpha = 0.85) +
    geom_text(aes(label = ModeLabel),
              size = 2.6, vjust = -1.1, show.legend = FALSE) +
    scale_y_log10(breaks = c(1, 2, 5, 10, 20, 50),
                  labels = function(x) sprintf("%gx", x)) +
    scale_color_manual(values = c(
      "Reversible"      = "#08306B",
      "fixed_accuracy"  = "#C0392B",
      "fixed_precision" = "#F39C12",
      "fixed_rate"      = "#27AE60"
    )) +
    labs(x = "PSNR (dB) -- higher = lower error",
         y = "Compression ratio (log scale)",
         color = "Mode family", shape = "Dataset",
         title = "Lossy validation -- ratio vs PSNR Pareto on TTI",
         subtitle = "RTM production sweet spot: fixed_accuracy 1e-3 = 60 dB / 21x") +
    annotate("rect", xmin = 55, xmax = 70, ymin = 10, ymax = 30,
             alpha = 0.1, fill = "#C0392B") +
    annotate("text", x = 62.5, y = 7, label = "RTM production zone",
             color = "#C0392B", fontface = "italic", size = 3) +
    BASE_THEME

  ggsave(file.path(OUT, "fig4_lossy_pareto.pdf"), fig4, width = 9, height = 6)
  ggsave(file.path(OUT, "fig4_lossy_pareto.png"), fig4, width = 9, height = 6, dpi = 150)

  # Variant: tolerance honored (requested vs measured) for fixed_accuracy
  fig4b_data <- fid_clean |>
    filter(Mode == "fixed_accuracy") |>
    mutate(requested = as.numeric(Param))

  fig4b <- ggplot(fig4b_data,
                  aes(x = requested, y = MaxAbsDiff,
                      color = TestFile, shape = TestFile)) +
    geom_point(size = 3.5) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey50") +
    geom_text(aes(x = 1e-3, y = 1e-3, label = "y = x (requested = measured)"),
              color = "grey40", size = 2.8, angle = 45, vjust = -0.5,
              hjust = 0.5, show.legend = FALSE) +
    scale_x_log10(breaks = c(1e-3, 1e-4, 1e-5, 1e-6),
                  labels = function(x) sprintf("%.0e", x)) +
    scale_y_log10(breaks = 10^seq(-7, -3),
                  labels = function(x) sprintf("%.0e", x)) +
    labs(x = "Requested tolerance (epsilon)",
         y = "Measured max_abs_diff",
         title = "ZFP fixed_accuracy honors its tolerance guarantee on AMD",
         subtitle = "Measured error consistently 4-6x below requested -- empirical validation of Lindstrom 2014 Theorem 1") +
    BASE_THEME

  ggsave(file.path(OUT, "fig4b_tolerance_honored.pdf"), fig4b, width = 8, height = 5)
  ggsave(file.path(OUT, "fig4b_tolerance_honored.png"), fig4b, width = 8, height = 5, dpi = 150)
}

cat("\nDone. Figures written to:", OUT, "\n")
cat("Generated files:\n")
print(list.files(OUT))
