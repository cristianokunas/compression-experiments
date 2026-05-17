# plots_iccsa.R — Figuras para o paper ICCSA 2026
# "Mind the Gap: Characterizing GPU Data Compression Performance
#  Across AMD Architectures"
#
# Uso:
#   Rscript plots_iccsa.R results_rx7900xt.csv results_mi300x.csv
#   Rscript plots_iccsa.R results_rx7900xt.csv results_mi300x.csv results_mi50.csv
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

# ── Paleta de algoritmos ─────────────────────────────────────────────────────
# OPÇÃO A: Pastel (estilo visualizacoes_compressao.R)
ALGO_COLORS <- c(
  "lz4"      = "#F4A582",
  "snappy"   = "#92C5DE",
  "cascaded" = "#A6D96A"
)

# OPÇÃO B: Pastel saturado (melhor legibilidade em paper impresso)
# Descomente abaixo e comente acima para alternar.
# ALGO_COLORS <- c(
#   "lz4"      = "#E8734A",
#   "snappy"   = "#5BA3CF",
#   "cascaded" = "#7BB842"
# )

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
  "H2D Transfer"   = "#90CAF9",
  "Compression"    = "#F4A582",
  "Decompression"  = "#92C5DE",
  "D2H Transfer"   = "#FFCC80"
)

# ── Ordens canônicas ─────────────────────────────────────────────────────────
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

# ── Tema base — inspirado no visualizacoes_compressao.R ──────────────────────
#
# Princípios:
#   - Fundo branco, painel limpo
#   - Grid horizontal discreto, sem grid vertical
#   - Strips em cinza claro com borda suave
#   - Fontes bold em títulos e eixos
#   - Legenda no topo, compacta
#   - Compatível com 1 coluna (~8 cm) e 2 colunas (~17 cm) LNCS
theme_iccsa <- function(base_size = 14) {
  theme_bw(base_size = base_size) +
    theme(
      # Grid
      panel.grid.minor   = element_blank(),
      panel.grid.major.x = element_blank(),
      panel.grid.major.y = element_line(color = "#DDDDDD", linewidth = 0.35,
                                        linetype = "dashed"),

      # Painel
      panel.border       = element_rect(color = "grey80", linewidth = 0.5, fill = NA),
      panel.background   = element_rect(fill = "white", color = NA),

      # Strips (facets)
      strip.background   = element_rect(fill = "grey95", color = "grey80"),
      strip.text         = element_text(face = "bold", size = base_size,
                                        color = "black", margin = margin(4, 4, 4, 4)),

      # Legenda
      legend.position    = "top",
      legend.direction   = "horizontal",
      legend.title       = element_text(face = "bold", size = base_size - 1),
      legend.text        = element_text(size = base_size - 2),
      legend.background  = element_blank(),
      legend.key         = element_blank(),
      legend.key.size    = unit(0.85, "lines"),
      legend.margin      = margin(0, 0, 4, 0),
      legend.spacing.x   = unit(6, "pt"),

      # Eixos
      axis.title         = element_text(face = "bold", size = base_size),
      axis.text          = element_text(size = base_size - 2, color = "black"),
      axis.ticks         = element_line(color = "grey60", linewidth = 0.35),
      axis.ticks.length  = unit(3, "pt"),

      # Plot
      plot.background    = element_rect(fill = "white", color = NA),
      plot.margin        = margin(6, 8, 6, 6)
    )
}

# Variante para barras horizontais (Fig 6) — grid no eixo X
theme_iccsa_hbar <- function(base_size = 14) {
  theme_iccsa(base_size) +
    theme(
      panel.grid.major.x = element_line(color = "#DDDDDD", linewidth = 0.35,
                                        linetype = "dashed"),
      panel.grid.major.y = element_blank()
    )
}

# ── Salvar figura ─────────────────────────────────────────────────────────────
save_fig <- function(p, name, width, height) {
  ggsave(file.path(OUTPUT_DIR, paste0(name, ".pdf")),
         p, width = width, height = height, device = "pdf")
  ggsave(file.path(OUTPUT_DIR, paste0(name, ".png")),
         p, width = width, height = height, dpi = 300, device = "png")
  cat(sprintf("  ✓  %s\n", name))
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
              aes(x = Dataset, y = CompThroughputGBs, fill = Algorithm)) +
    geom_col(position = position_dodge(width = 0.8),
             width = 0.7, color = "grey30", linewidth = 0.3) +
    geom_errorbar(
      aes(ymin = pmax(CompThroughputGBs - CompThroughputGBs_std, 0),
          ymax = CompThroughputGBs + CompThroughputGBs_std),
      position = position_dodge(width = 0.8),
      width = 0.25, linewidth = 0.5, color = "grey40"
    ) +
    geom_text(aes(label = round(CompThroughputGBs, 1)),
              position = position_dodge(width = 0.8),
              vjust = -0.5, size = 3, check_overlap = TRUE) +
    scale_fill_manual(values = ALGO_COLORS, labels = ALGO_LABELS, name = "Algorithm") +
    scale_y_continuous(expand = expansion(mult = c(0, 0.15)),
                       labels = label_number(accuracy = 1)) +
    labs(x = "Dataset", y = "Compression Throughput (GB/s)") +
    theme_iccsa() +
    theme(axis.text.x = element_text(angle = 30, hjust = 1))

  if (length(gpus) > 1) p <- p + facet_wrap(~GPU, nrow = 1)

  save_fig(p, "fig1_comp_throughput", 4.5 * max(length(gpus), 1), 5)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 2 — Decompression Throughput
# ══════════════════════════════════════════════════════════════════════════════

fig2_decomp_throughput <- function(df) {
  data <- df |> filter(Size == "xlarge")
  gpus <- levels(droplevels(data$GPU))

  p <- ggplot(data,
              aes(x = Dataset, y = DecompThroughputGBs, fill = Algorithm)) +
    geom_col(position = position_dodge(width = 0.8),
             width = 0.7, color = "grey30", linewidth = 0.3) +
    geom_errorbar(
      aes(ymin = pmax(DecompThroughputGBs - DecompThroughputGBs_std, 0),
          ymax = DecompThroughputGBs + DecompThroughputGBs_std),
      position = position_dodge(width = 0.8),
      width = 0.25, linewidth = 0.5, color = "grey40"
    ) +
    geom_text(aes(label = round(DecompThroughputGBs, 1)),
              position = position_dodge(width = 0.8),
              vjust = -0.5, size = 3, check_overlap = TRUE) +
    scale_fill_manual(values = ALGO_COLORS, labels = ALGO_LABELS, name = "Algorithm") +
    scale_y_continuous(expand = expansion(mult = c(0, 0.15)),
                       labels = label_number(accuracy = 1)) +
    labs(x = "Dataset", y = "Decompression Throughput (GB/s)") +
    theme_iccsa() +
    theme(axis.text.x = element_text(angle = 30, hjust = 1))

  if (length(gpus) > 1) p <- p + facet_wrap(~GPU, nrow = 1)

  save_fig(p, "fig2_decomp_throughput", 4.5 * max(length(gpus), 1), 5)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 3 — Execution Time Breakdown (transfers + compute)
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

  # Labels internas: só mostra se fatia > 7% do total
  labels_df <- data |>
    group_by(GPU, Algorithm) |>
    mutate(pct = TimeMs / sum(TimeMs)) |>
    filter(pct > 0.07) |>
    ungroup() |>
    mutate(font_color = ifelse(
      Phase %in% c("H2D Transfer", "Compression"), "white", "#333333"
    ))

  p <- ggplot(data, aes(x = Algorithm, y = TimeMs, fill = Phase)) +
    geom_col(width = 0.6, color = "grey30", linewidth = 0.3) +
    geom_text(data = labels_df,
              aes(label = round(TimeMs, 0), color = font_color),
              position = position_stack(vjust = 0.5),
              size = 3.2, fontface = "bold") +
    scale_fill_manual(values = PHASE_COLORS, name = "Phase") +
    scale_color_identity() +
    scale_y_continuous(expand = expansion(mult = c(0, 0.08))) +
    scale_x_discrete(labels = ALGO_LABELS) +
    labs(x = "Algorithm", y = "Execution Time (ms)") +
    theme_iccsa()

  if (length(gpus) > 1) p <- p + facet_wrap(~GPU, nrow = 1)

  save_fig(p, "fig3_breakdown", 4.0 * max(length(gpus), 1), 5)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 4 — Heatmap Compression Ratio (1 only — ratio is GPU-independent)
# ══════════════════════════════════════════════════════════════════════════════

fig4_heatmap_ratio <- function(df) {
  # Usa apenas a primeira GPU encontrada — ratio é o mesmo para todas
  first_gpu <- levels(droplevels(df$GPU))[1]
  data <- df |>
    filter(Size == "xlarge", GPU == first_gpu) |>
    mutate(
      log_ratio   = log10(pmax(CompressionRatio, 1)),
      label_ratio = case_when(
        CompressionRatio < 10  ~ sprintf("%.2fx", CompressionRatio),
        CompressionRatio < 100 ~ sprintf("%.1fx", CompressionRatio),
        TRUE                   ~ sprintf("%.0fx", CompressionRatio)
      ),
      text_color  = ifelse(CompressionRatio > 20, "white", "#1A1A1A")
    )

  p <- ggplot(data, aes(x = Dataset, y = Algorithm, fill = log_ratio)) +
    geom_tile(color = "white", linewidth = 1.2) +
    geom_text(aes(label = label_ratio, color = text_color),
              size = 4.5, fontface = "bold") +
    scale_fill_distiller(
      palette   = "YlOrRd", direction = 1,
      limits    = c(0, log10(260)),
      breaks    = c(0, 1, 2),
      labels    = c("1x", "10x", "100x"),
      name      = "Ratio"
    ) +
    scale_color_identity() +
    scale_y_discrete(labels = ALGO_LABELS) +
    labs(x = "Dataset", y = "Algorithm") +
    theme_iccsa() +
    theme(
      panel.grid        = element_blank(),
      panel.border      = element_blank(),
      axis.text.x       = element_text(angle = 15, hjust = 1),
      axis.ticks        = element_blank(),
      legend.position   = "right",
      legend.direction  = "vertical",
      legend.title      = element_text(size = 12, face = "bold"),
      legend.key.height = unit(1.5, "cm"),
      legend.key.width  = unit(0.4, "cm")
    )

  save_fig(p, "fig4_heatmap_ratio", 6, 4)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 5 — Throughput Scalability (line chart, TTI)
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
      alpha = 0.18, color = NA
    ) +
    geom_line(linewidth = 1.4) +
    geom_point(shape = 21, size = 3.5, stroke = 1.4, fill = "white") +
    scale_color_manual(values = ALGO_COLORS, labels = ALGO_LABELS, name = "Algorithm") +
    scale_fill_manual(values  = ALGO_COLORS, labels = ALGO_LABELS, name = "Algorithm") +
    scale_x_log10(
      breaks = c(10, 100, 1024, 4096),
      labels = c("10 MB", "100 MB", "1,024 MB", "4,096 MB")
    ) +
    scale_y_continuous(expand = expansion(mult = c(0.02, 0.10))) +
    labs(x = "Input Size (MB)", y = "Compression Throughput (GB/s)") +
    theme_iccsa() +
    theme(panel.grid.major.x = element_line(color = "#E4E4E4", linewidth = 0.4,
                                            linetype = "dashed"))

  if (length(gpus) > 1) p <- p + facet_wrap(~GPU, nrow = 1)

  save_fig(p, "fig5_scale", 4.5 * max(length(gpus), 1), 4.8)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 6 — Speedup vs MI50 (horizontal bar)
# ══════════════════════════════════════════════════════════════════════════════

fig6_speedup <- function(df) {
  gpus_present <- levels(droplevels(df$GPU))

  # ── Placeholder se MI50 não está presente ──────────────────────────────────
  if (!"MI50" %in% gpus_present) {
    message("  ⚠️   Fig 6: MI50 ausente — placeholder gerado.")
    p <- ggplot() +
      annotate("text", x = 0.5, y = 0.58,
               label = "Awaiting MI50 baseline data",
               size = 6, color = "#999999", fontface = "italic",
               family = "sans") +
      annotate("text", x = 0.5, y = 0.40,
               label = "Figure populates automatically when MI50 CSV is provided.",
               size = 4, color = "#BBBBBB", family = "sans") +
      annotate("segment", x = 0.25, xend = 0.75, y = 0.50, yend = 0.50,
               linetype = "dashed", color = "#CCCCCC", linewidth = 0.8) +
      xlim(0, 1) + ylim(0, 1) +
      theme_void() +
      theme(
        plot.background = element_rect(fill = "#FAFAFA", color = "#E0E0E0",
                                       linewidth = 0.5))
    save_fig(p, "fig6_speedup", 8, 4)
    return(invisible(NULL))
  }

  # ── Speedup real ───────────────────────────────────────────────────────────
  data <- df |> filter(Dataset == "TTI (seismic)", Size == "xlarge")

  baseline <- data |>
    filter(GPU == "MI50") |>
    select(Algorithm,
           base_comp      = CompThroughputGBs,
           base_comp_sd   = CompThroughputGBs_std,
           base_decomp    = DecompThroughputGBs,
           base_decomp_sd = DecompThroughputGBs_std)

  speedup_df <- data |>
    filter(GPU != "MI50") |>
    left_join(baseline, by = "Algorithm") |>
    mutate(
      SpeedupComp   = CompThroughputGBs   / base_comp,
      SpeedupDecomp = DecompThroughputGBs / base_decomp,
      # Propagação de erro: δ(a/b) = (a/b) * sqrt((δa/a)² + (δb/b)²)
      SpeedupComp_err = SpeedupComp * sqrt(
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
        labels = c("Compression", "Decompression"))
    )

  compare_gpus <- levels(droplevels(speedup_df$GPU))

  p <- ggplot(speedup_df,
              aes(x = Speedup, y = GPU, fill = Algorithm)) +
    geom_col(position = position_dodge(width = 0.75),
             width = 0.65, color = "grey30", linewidth = 0.3) +
    geom_errorbar(
      aes(xmin = pmax(Speedup - SpeedupErr, 0),
          xmax = Speedup + SpeedupErr),
      position = position_dodge(width = 0.75),
      width = 0.2, linewidth = 0.5, color = "grey40"
    ) +
    geom_text(aes(label = sprintf("%.1fx", Speedup), x = Speedup + SpeedupErr + 0.08),
              position = position_dodge(width = 0.75),
              hjust = 0, size = 3.2, color = "#333333") +
    geom_vline(xintercept = 1, linetype = "dashed",
               color = "#888888", linewidth = 0.9, alpha = 0.7) +
    scale_fill_manual(values = ALGO_COLORS, labels = ALGO_LABELS, name = "Algorithm") +
    scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
    facet_wrap(~MetricLabel, nrow = 1) +
    labs(x = "Speedup vs. MI50", y = NULL) +
    theme_iccsa_hbar()

  save_fig(p, "fig6_speedup", 11, 4.2 + 0.5 * length(compare_gpus))
}

# ══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════════════════

args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0) {
  stop("Uso: Rscript plots_iccsa.R results1.csv [results2.csv ...]")
}

cat(sprintf("\n📂  Carregando %d arquivo(s)...\n", length(args)))
df <- load_csvs(args)
cat(sprintf("    GPUs      : %s\n", paste(levels(droplevels(df$GPU)), collapse = ", ")))
cat(sprintf("    Algoritmos: %s\n", paste(levels(droplevels(df$Algorithm)), collapse = ", ")))
cat(sprintf("    Linhas    : %d\n\n", nrow(df)))

cat("📊  Gerando figuras...\n")
fig1_comp_throughput(df)
fig2_decomp_throughput(df)
fig3_breakdown(df)
fig4_heatmap_ratio(df)
fig5_scale(df)
fig6_speedup(df)

cat(sprintf("\n✅  Figuras salvas em ./%s/  (PDF + PNG)\n", OUTPUT_DIR))
