# plots_iccsa.R — Figuras para o paper ICCSA 2026
# "Mind the Gap: Characterizing GPU Data Compression Performance Across AMD Architectures"
#
# Uso:
#   Rscript plots_iccsa.R results_lunaris.csv
#   Rscript plots_iccsa.R results_lunaris.csv results_mi50.csv results_mi210.csv results_mi300x.csv
#
# Dependências: tidyverse, scales

suppressPackageStartupMessages({
  library(tidyverse)
  library(scales)
})

# ══════════════════════════════════════════════════════════════════════════════
#  DESIGN SYSTEM
# ══════════════════════════════════════════════════════════════════════════════

OUTPUT_DIR <- "plots_output"
dir.create(OUTPUT_DIR, showWarnings = FALSE)

# ── Paleta ────────────────────────────────────────────────────────────────────
ALGO_COLORS <- c(
  "lz4"      = "#2196F3",
  "snappy"   = "#FF9800",
  "cascaded" = "#4CAF50"
)

ALGO_LABELS <- c(
  "lz4"      = "LZ4",
  "snappy"   = "Snappy",
  "cascaded" = "Cascaded"
)

GPU_COLORS <- c(
  "MI50"     = "#A0A0A0",
  "MI210"    = "#5B9BD5",
  "MI300X"   = "#1F4E79",
  "RX7900XT" = "#C0392B"
)

PHASE_COLORS <- c(
  "H->D Transfer" = "#90CAF9",
  "Compression"        = "#2196F3",
  "Decompression"      = "#FF9800",
  "D->H Transfer"  = "#FFCC80"
)

# ── Ordens canônicas ───────────────────────────────────────────────────────────
GPU_ORDER      <- c("MI50", "MI210", "MI300X", "RX7900XT")
ALGO_ORDER     <- c("lz4", "snappy", "cascaded")
DATASET_ORDER  <- c("zeros", "binary", "random", "TTI")
DATASET_LABELS <- c(
  "zeros"  = "Zeros",
  "binary" = "Binary",
  "random" = "Random",
  "TTI"    = "TTI (seismic)"
)
SIZE_MAP <- c("small" = 10, "medium" = 100, "large" = 1024, "xlarge" = 4096)

# ── Tema base ─────────────────────────────────────────────────────────────────
theme_iccsa <- function(base_size = 10) {
  theme_minimal(base_size = base_size) +
    theme(
      text                = element_text(color = "#333333"),
      plot.title          = element_text(size = 12, face = "bold",
                                         color = "#1A1A1A",
                                         margin = margin(b = 6)),
      plot.subtitle       = element_text(size = 10, color = "#555555",
                                         margin = margin(b = 8)),
      axis.title          = element_text(size = 10),
      axis.text           = element_text(size = 9, color = "#555555"),
      axis.ticks.x        = element_blank(),
      axis.ticks.y        = element_line(color = "#CCCCCC", linewidth = 0.4),
      axis.line.x         = element_line(color = "#CCCCCC", linewidth = 0.6),
      axis.line.y         = element_line(color = "#CCCCCC", linewidth = 0.6),
      panel.background    = element_rect(fill = "#FAFAFA", color = NA),
      panel.grid.major.y  = element_line(color = "#E4E4E4", linewidth = 0.5),
      panel.grid.major.x  = element_blank(),
      panel.grid.minor    = element_blank(),
      legend.position     = "top",
      legend.direction    = "horizontal",
      legend.title        = element_text(face = "bold", size = 9, vjust = 0.8),
      legend.text         = element_text(size = 9),
      legend.background   = element_rect(fill = alpha("white", 0.92),
                                         color = "#DDDDDD", linewidth = 0.4),
      legend.key.size     = unit(0.8, "lines"),
      strip.text          = element_text(face = "bold", size = 11),
      plot.background     = element_rect(fill = "white", color = NA),
      plot.margin         = margin(8, 8, 8, 8)
    )
}

# Variante para barras horizontais (Fig 6) — grid no eixo X
theme_iccsa_hbar <- function(base_size = 10) {
  theme_iccsa(base_size) +
    theme(
      panel.grid.major.x = element_line(color = "#E4E4E4", linewidth = 0.5),
      panel.grid.major.y = element_blank(),
      axis.ticks.y       = element_blank(),
      axis.line.y        = element_blank()
    )
}

# ── Salvar figura ─────────────────────────────────────────────────────────────
save_fig <- function(p, name, width, height) {
  ggsave(file.path(OUTPUT_DIR, paste0(name, ".pdf")),
         p, width = width, height = height, device = "pdf")
  ggsave(file.path(OUTPUT_DIR, paste0(name, ".png")),
         p, width = width, height = height, dpi = 300, device = "png")
  cat(sprintf("  \u2713  %s\n", name))
}

# ══════════════════════════════════════════════════════════════════════════════
#  LOAD & PREPARE DATA
# ══════════════════════════════════════════════════════════════════════════════

load_csvs <- function(paths) {
  df <- map_dfr(paths, read_csv, show_col_types = FALSE)

  df <- df |>
    mutate(
      Dataset   = str_extract(TestFile, "(?<=_)(TTI|binary|random|zeros)(?=_)"),
      Size      = str_extract(TestFile, "^(small|medium|large|xlarge)"),
      GPU       = str_replace(EnvLabel, "XT$", "XT"),
      Algorithm = str_to_lower(Algorithm)
    ) |>
    rename(any_of(c(
      CompThroughputGBs_std   = "CompThroughputStdDev",
      DecompThroughputGBs_std = "DecompThroughputStdDev",
      CompTimeMs_std          = "CompTimeStdDevMs",
      DecompTimeMs_std        = "DecompTimeStdDevMs"
    )))

  # Fallback: colunas std zeradas se ausentes
  for (col in c("CompThroughputGBs_std", "DecompThroughputGBs_std",
                "CompTimeMs_std", "DecompTimeMs_std")) {
    if (!col %in% names(df)) df[[col]] <- 0
  }

  df |> mutate(
    Algorithm = factor(Algorithm, levels = ALGO_ORDER),
    Dataset   = factor(Dataset,   levels = DATASET_ORDER,
                       labels = DATASET_LABELS[DATASET_ORDER]),
    GPU       = factor(GPU,        levels = GPU_ORDER),
    Size      = factor(Size,       levels = names(SIZE_MAP))
  )
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 1 — Compression Throughput
# ══════════════════════════════════════════════════════════════════════════════

fig1_comp_throughput <- function(df) {
  data <- df |> filter(Size == "xlarge")
  gpus <- levels(droplevels(data$GPU))

  p <- ggplot(data,
              aes(x = Dataset, y = CompThroughputGBs, fill = Algorithm,
                  ymin = CompThroughputGBs - CompThroughputGBs_std,
                  ymax = CompThroughputGBs + CompThroughputGBs_std)) +
    geom_col(position = position_dodge(width = 0.8),
             width = 0.75, color = "white", linewidth = 0.4) +
    geom_errorbar(position = position_dodge(width = 0.8),
                  width = 0.25, linewidth = 0.7, color = "#222222", alpha = 0.7) +
    scale_fill_manual(values = ALGO_COLORS, labels = ALGO_LABELS, name = "Algorithm") +
    scale_y_continuous(expand = expansion(mult = c(0, 0.08)),
                       labels = label_number(accuracy = 1)) +
    labs(
         x = "Dataset", y = "Compression Throughput (GB/s)") +
    theme_iccsa()

  if (length(gpus) > 1) p <- p + facet_wrap(~GPU, nrow = 1)

  save_fig(p, "fig1_comp_throughput", 4.2 * length(gpus), 4.4)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 2 — Decompression Throughput
# ══════════════════════════════════════════════════════════════════════════════

fig2_decomp_throughput <- function(df) {
  data <- df |> filter(Size == "xlarge")
  gpus <- levels(droplevels(data$GPU))

  p <- ggplot(data,
              aes(x = Dataset, y = DecompThroughputGBs, fill = Algorithm,
                  ymin = DecompThroughputGBs - DecompThroughputGBs_std,
                  ymax = DecompThroughputGBs + DecompThroughputGBs_std)) +
    geom_col(position = position_dodge(width = 0.8),
             width = 0.75, color = "white", linewidth = 0.4) +
    geom_errorbar(position = position_dodge(width = 0.8),
                  width = 0.25, linewidth = 0.7, color = "#222222", alpha = 0.7) +
    scale_fill_manual(values = ALGO_COLORS, labels = ALGO_LABELS, name = "Algorithm") +
    scale_y_continuous(expand = expansion(mult = c(0, 0.08)),
                       labels = label_number(accuracy = 1)) +
    labs(
         x = "Dataset", y = "Decompression Throughput (GB/s)") +
    theme_iccsa()

  if (length(gpus) > 1) p <- p + facet_wrap(~GPU, nrow = 1)

  save_fig(p, "fig2_decomp_throughput", 4.2 * length(gpus), 4.4)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 3 — Execution Time Breakdown
# ══════════════════════════════════════════════════════════════════════════════

fig3_breakdown <- function(df) {
  data <- df |>
    filter(Size == "xlarge", Dataset == "TTI (seismic)") |>
    select(Algorithm, GPU, TransferH2DMs, CompTimeMs, DecompTimeMs, TransferD2HMs) |>
    pivot_longer(
      cols      = c(TransferH2DMs, CompTimeMs, DecompTimeMs, TransferD2HMs),
      names_to  = "Phase",
      values_to = "TimeMs"
    ) |>
    mutate(Phase = factor(Phase,
      levels = c("TransferH2DMs", "CompTimeMs", "DecompTimeMs", "TransferD2HMs"),
      labels = names(PHASE_COLORS)
    ))

  gpus <- levels(droplevels(data$GPU))

  labels_df <- data |>
    group_by(GPU, Algorithm) |>
    mutate(pct = TimeMs / sum(TimeMs)) |>
    filter(pct > 0.07) |>
    ungroup() |>
    mutate(font_color = ifelse(
      Phase %in% c("H->D Transfer", "Compression"), "white", "#333333"
    ))

  p <- ggplot(data, aes(x = Algorithm, y = TimeMs, fill = Phase)) +
    geom_col(width = 0.55, color = "white", linewidth = 0.4) +
    geom_text(data = labels_df,
              aes(label = round(TimeMs, 0), color = font_color),
              position = position_stack(vjust = 0.5),
              size = 3, fontface = "bold") +
    scale_fill_manual(values = PHASE_COLORS, name = "Phase") +
    scale_color_identity() +
    scale_y_continuous(expand = expansion(mult = c(0, 0.05))) +
    scale_x_discrete(labels = ALGO_LABELS) +
    labs(
         x = "Algorithm", y = "Execution Time (ms)") +
    theme_iccsa()

  if (length(gpus) > 1) p <- p + facet_wrap(~GPU, nrow = 1)

  save_fig(p, "fig3_breakdown", 3.8 * length(gpus), 4.4)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 4 — Heatmap Compression Ratio
# ══════════════════════════════════════════════════════════════════════════════

fig4_heatmap_ratio <- function(df) {
  data <- df |>
    filter(Size == "xlarge") |>
    mutate(
      log_ratio   = log10(pmax(CompressionRatio, 1)),
      label_ratio = case_when(
        CompressionRatio < 10 ~ sprintf("%.1fx", CompressionRatio),
        TRUE                  ~ sprintf("%.0fx", CompressionRatio)
      ),
      text_color  = ifelse(CompressionRatio > 20, "white", "#1A1A1A")
    )

  gpus <- levels(droplevels(data$GPU))

  p <- ggplot(data, aes(x = Dataset, y = Algorithm, fill = log_ratio)) +
    geom_tile(color = "white", linewidth = 1.0) +
    geom_text(aes(label = label_ratio, color = text_color),
              size = 3.5, fontface = "bold") +
    scale_fill_distiller(
      palette   = "YlOrRd", direction = 1,
      limits    = c(0, log10(260)),
      breaks    = c(0, 1, 2),
      labels    = c("1x", "10x", "100x"),
      name      = "Compression Ratio\n(log10 scale)"
    ) +
    scale_color_identity() +
    scale_y_discrete(labels = ALGO_LABELS) +
    labs(
         x = "Dataset", y = "Algorithm") +
    theme_iccsa() +
    theme(
      panel.grid  = element_blank(),
      axis.text.x = element_text(angle = 15, hjust = 1),
      axis.ticks  = element_blank(),
      axis.line   = element_blank()
    )

  if (length(gpus) > 1) p <- p + facet_wrap(~GPU, nrow = 1)

  save_fig(p, "fig4_heatmap_ratio", 3.8 * length(gpus), 3.6)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 5 — Throughput Scalability
# ══════════════════════════════════════════════════════════════════════════════

fig5_scale <- function(df) {
  data <- df |>
    filter(Dataset == "TTI (seismic)") |>
    mutate(SizeMB = SIZE_MAP[as.character(Size)])

  gpus <- levels(droplevels(data$GPU))

  p <- ggplot(data,
              aes(x = SizeMB, y = CompThroughputGBs,
                  color = Algorithm, fill = Algorithm)) +
    geom_ribbon(
      aes(ymin = pmax(CompThroughputGBs - CompThroughputGBs_std, 0),
          ymax = CompThroughputGBs + CompThroughputGBs_std),
      alpha = 0.15, color = NA
    ) +
    geom_line(linewidth = 1.8) +
    geom_point(shape = 21, size = 3, stroke = 1.8, fill = "white") +
    scale_color_manual(values = ALGO_COLORS, labels = ALGO_LABELS, name = "Algorithm") +
    scale_fill_manual(values  = ALGO_COLORS, labels = ALGO_LABELS, name = "Algorithm") +
    scale_x_log10(
      breaks = c(10, 100, 1024, 4096),
      labels = c("10 MB", "100 MB", "1,024 MB", "4,096 MB")
    ) +
    scale_y_continuous(expand = expansion(mult = c(0.02, 0.08))) +
    labs(
         x = "Input Size (MB)", y = "Compression Throughput (GB/s)") +
    theme_iccsa() +
    theme(panel.grid.major.x = element_line(color = "#E4E4E4", linewidth = 0.5))

  if (length(gpus) > 1) p <- p + facet_wrap(~GPU, nrow = 1)

  save_fig(p, "fig5_scale", 4.2 * length(gpus), 4.2)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 6 — Speedup vs MI50
# ══════════════════════════════════════════════════════════════════════════════

fig6_speedup <- function(df) {
  gpus_present <- levels(droplevels(df$GPU))

  if (!"MI50" %in% gpus_present) {
    message("  \u26a0\ufe0f   Fig 6: MI50 ausente -- placeholder gerado.")
    p <- ggplot() +
      annotate("text", x = 0.5, y = 0.55,
               label = "Awaiting MI50 baseline data",
               size = 5, color = "#AAAAAA", fontface = "italic") +
      annotate("text", x = 0.5, y = 0.38,
               label = "Figure populates automatically when MI50 CSV is provided.",
               size = 3.5, color = "#BBBBBB") +
      xlim(0, 1) + ylim(0, 1) +
      labs() +
      theme_void() +
      theme(
            plot.background = element_rect(fill = "#FAFAFA", color = "#E0E0E0"))
    save_fig(p, "fig6_speedup", 7, 3.5)
    return(invisible(NULL))
  }

  data <- df |> filter(Dataset == "TTI (seismic)", Size == "xlarge")

  baseline <- data |>
    filter(GPU == "MI50") |>
    select(Algorithm,
           base_comp     = CompThroughputGBs,
           base_comp_sd  = CompThroughputGBs_std,
           base_decomp   = DecompThroughputGBs,
           base_decomp_sd = DecompThroughputGBs_std)

  speedup_df <- data |>
    filter(GPU != "MI50") |>
    left_join(baseline, by = "Algorithm") |>
    mutate(
      SpeedupComp       = CompThroughputGBs   / base_comp,
      SpeedupDecomp     = DecompThroughputGBs / base_decomp,
      SpeedupComp_err   = SpeedupComp * sqrt(
        (CompThroughputGBs_std / (CompThroughputGBs + 1e-12))^2 +
        (base_comp_sd          / (base_comp          + 1e-12))^2),
      SpeedupDecomp_err = SpeedupDecomp * sqrt(
        (DecompThroughputGBs_std / (DecompThroughputGBs + 1e-12))^2 +
        (base_decomp_sd          / (base_decomp          + 1e-12))^2)
    ) |>
    pivot_longer(
      cols      = c(SpeedupComp, SpeedupDecomp),
      names_to  = "Metric",
      values_to = "Speedup"
    ) |>
    mutate(
      SpeedupErr  = ifelse(Metric == "SpeedupComp", SpeedupComp_err, SpeedupDecomp_err),
      MetricLabel = factor(Metric,
        levels = c("SpeedupComp", "SpeedupDecomp"),
        labels = c("Compression Speedup", "Decompression Speedup"))
    )

  compare_gpus <- levels(droplevels(speedup_df$GPU))

  p <- ggplot(speedup_df,
              aes(x = Speedup, y = GPU, fill = Algorithm,
                  xmin = Speedup - SpeedupErr,
                  xmax = Speedup + SpeedupErr)) +
    geom_col(position = position_dodge(width = 0.75),
             width = 0.7, color = "white", linewidth = 0.4) +
    geom_errorbar(position = position_dodge(width = 0.75),
                  width = 0.25, linewidth = 0.7, color = "#222222", alpha = 0.7) +
    geom_text(aes(label = sprintf("%.1fx", Speedup), x = Speedup + 0.06),
              position = position_dodge(width = 0.75),
              hjust = 0, size = 2.8, color = "#333333") +
    geom_vline(xintercept = 1, linetype = "dashed",
               color = "#888888", linewidth = 0.9, alpha = 0.7) +
    scale_fill_manual(values = ALGO_COLORS, labels = ALGO_LABELS, name = "Algorithm") +
    scale_x_continuous(expand = expansion(mult = c(0, 0.12))) +
    facet_wrap(~MetricLabel, nrow = 1) +
    labs(
         x = "Speedup vs. MI50", y = NULL) +
    theme_iccsa_hbar()

  save_fig(p, "fig6_speedup", 10, 3.8 + 0.4 * length(compare_gpus))
}

# ══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════════════════

args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0) {
  stop("Uso: Rscript plots_iccsa.R results1.csv [results2.csv ...]")
}

cat(sprintf("\n\U0001F4C2  Carregando %d arquivo(s)...\n", length(args)))
df <- load_csvs(args)
cat(sprintf("    GPUs      : %s\n", paste(levels(df$GPU),       collapse = ", ")))
cat(sprintf("    Algoritmos: %s\n", paste(levels(df$Algorithm), collapse = ", ")))
cat(sprintf("    Linhas    : %d\n\n", nrow(df)))

cat("\U0001F4CA  Gerando figuras...\n")
fig1_comp_throughput(df)
fig2_decomp_throughput(df)
fig3_breakdown(df)
fig4_heatmap_ratio(df)
fig5_scale(df)
fig6_speedup(df)

cat(sprintf("\n\u2705  Figuras salvas em ./%s/  (PDF + PNG)\n", OUTPUT_DIR))
