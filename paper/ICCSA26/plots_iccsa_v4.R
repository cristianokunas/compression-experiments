# plots_iccsa.R - Figuras para o paper ICCSA 2026
# "Mind the Gap: Characterizing GPU Data Compression Performance
#  Across AMD Architectures"
#
# Uso:
#   Rscript plots_iccsa.R results_lunaris.csv results_vianden.csv
#   Rscript plots_iccsa.R results_lunaris.csv results_vianden.csv results_mi50.csv
#
# Figuras geradas:
#   Fig 1 - Throughput compressão + descompressão (grid facetado)
#   Fig 2 - Transfer Overhead normalizado (PCIe vs compute)
#   Fig 3 - Compression Ratio heatmap + tabela LaTeX
#   Fig 4 - Asymmetry decomp/comp heatmap (facet GPU)
#   Fig 5 - Escalabilidade throughput vs tamanho (TTI)
#   Fig 6 - Speedup vs MI50 (placeholder se ausente)
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

# Cores para fases do overhead (Fig 2) - paleta pastel coerente
PHASE_COLORS_OVERHEAD <- c(
  "Computation"    = "#F4A582",
  "H2D and D2H Transfer"  = "#92C5DE"
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
SIZE_ORDER <- c("small", "medium", "large", "xlarge")
SIZE_LABELS <- c(
  "small"  = "10 MB",
  "medium" = "100 MB",
  "large"  = "1 GB",
  "xlarge" = "4 GB"
)
SIZE_MAP <- c("small" = 10, "medium" = 100, "large" = 1024, "xlarge" = 4096)

# ── Tema base - inspirado no visualizacoes_compressao.R ──────────────────────
theme_iccsa <- function(base_size = 9.4) {
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

# Variante para barras horizontais (Fig 6)
theme_iccsa_hbar <- function(base_size = 13) {
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
    GPU       = factor(GPU,       levels = GPU_ORDER),
    Size      = factor(Size,      levels = SIZE_ORDER)
  )
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 1a - Throughput Comp + Decomp (xlarge / 4 GB only)
#  Focused, clean version. facet_grid(Operation ~ GPU), bars = Algorithm.
# ══════════════════════════════════════════════════════════════════════════════

fig1a_throughput_xlarge <- function(df) {
  data <- df |>
    filter(Size == "xlarge") |>
    select(Algorithm, Dataset, GPU,
           CompThroughputGBs, DecompThroughputGBs,
           CompThroughputGBs_std, DecompThroughputGBs_std) |>
    pivot_longer(
      cols      = c(CompThroughputGBs, DecompThroughputGBs),
      names_to  = "Operation",
      values_to = "Throughput"
    ) |>
    mutate(
      Std = ifelse(Operation == "CompThroughputGBs",
                   CompThroughputGBs_std, DecompThroughputGBs_std),
      Operation = factor(Operation,
        levels = c("CompThroughputGBs", "DecompThroughputGBs"),
        labels = c("Compression", "Decompression"))
    )

  gpus <- levels(droplevels(data$GPU))

  p <- ggplot(data,
              aes(x = Dataset, y = Throughput, fill = Algorithm)) +
    geom_col(position = position_dodge(width = 0.8),
             width = 0.7, color = NA) +
    geom_errorbar(
      aes(ymin = pmax(Throughput - Std, 0),
          ymax = Throughput + Std),
      position = position_dodge(width = 0.8),
      width = 0.25, linewidth = 0.4, color = "grey40"
    ) +
    geom_text(aes(label = round(Throughput, 1)),
              position = position_dodge(width = 0.8),
              vjust = -0.5, size = 2.4, check_overlap = TRUE) +
    facet_grid(Operation ~ GPU, scales = "free_y") +
    scale_fill_manual(values = ALGO_COLORS, labels = ALGO_LABELS, name = "Algorithm") +
    # scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
    scale_y_log10(expand = expansion(mult = c(0, 0.15))) +
    labs(x = "Dataset", y = "Throughput (GB/s)") +
    theme_iccsa() +
    theme(axis.text.x = element_text(angle = 35, hjust = 1, size = 8.4))

  save_fig(p, "fig1a_throughput_xlarge", 1.8 * length(gpus), 4.5)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 1b - Throughput Comp + Decomp (all sizes, dense)
#  Uses interaction(Algorithm, GPU) with gradient palette per algorithm.
#  facet_grid(Operation ~ Size), bars = Algo × GPU grouped.
# ══════════════════════════════════════════════════════════════════════════════

# Paleta combinada: gradiente por algoritmo, intensidade por GPU
# Escuro → claro segue a ordem de GPU_ORDER
ALGO_GPU_COLORS <- c(
  # LZ4: tons de salmon/coral
  "lz4.MI50"      = "#FDDBC7",
  "lz4.MI210"     = "#F4A582",
  "lz4.MI300X"    = "#D6604D",
  "lz4.RX7900XT"  = "#B2182B",
  # Snappy: tons de azul
  "snappy.MI50"      = "#D1E5F0",
  "snappy.MI210"     = "#92C5DE",
  "snappy.MI300X"    = "#4393C3",
  "snappy.RX7900XT"  = "#2166AC",
  # Cascaded: tons de verde
  "cascaded.MI50"      = "#D9EF8B",
  "cascaded.MI210"     = "#A6D96A",
  "cascaded.MI300X"    = "#66BD63",
  "cascaded.RX7900XT"  = "#1A9850"
)

# Labels para a legenda (Algo - GPU)
ALGO_GPU_LABELS <- setNames(
  paste0(
    rep(c("LZ4", "Snappy", "Cascaded"), each = length(GPU_ORDER)),
    " - ",
    rep(GPU_ORDER, times = 3)
  ),
  paste0(
    rep(ALGO_ORDER, each = length(GPU_ORDER)),
    ".",
    rep(GPU_ORDER, times = 3)
  )
)

fig1b_throughput_all <- function(df) {
  data <- df |>
    select(Algorithm, Dataset, Size, GPU,
           CompThroughputGBs, DecompThroughputGBs,
           CompThroughputGBs_std, DecompThroughputGBs_std) |>
    pivot_longer(
      cols      = c(CompThroughputGBs, DecompThroughputGBs),
      names_to  = "Operation",
      values_to = "Throughput"
    ) |>
    mutate(
      Std = ifelse(Operation == "CompThroughputGBs",
                   CompThroughputGBs_std, DecompThroughputGBs_std),
      Operation = factor(Operation,
        levels = c("CompThroughputGBs", "DecompThroughputGBs"),
        labels = c("Compression", "Decompression")),
      SizeLabel = factor(Size, levels = SIZE_ORDER, labels = SIZE_LABELS[SIZE_ORDER]),
      AlgoGPU   = interaction(Algorithm, GPU, sep = ".")
    )

  # Filtrar apenas as combinações AlgoGPU que existem nos dados
  present_combos <- levels(droplevels(data$AlgoGPU))
  colors_sub <- ALGO_GPU_COLORS[present_combos]
  labels_sub <- ALGO_GPU_LABELS[present_combos]

  gpus <- levels(droplevels(data$GPU))
  n_bars <- length(present_combos)

  p <- ggplot(data,
              aes(x = Dataset, y = Throughput, fill = AlgoGPU)) +
    geom_col(position = position_dodge(width = 0.9),
             width = 0.88, color = NA) +
    geom_errorbar(
      aes(ymin = pmax(Throughput - Std, 0),
          ymax = Throughput + Std),
      position = position_dodge(width = 0.9),
      width = 0.2, linewidth = 0.3, color = "grey40"
    ) +
    facet_grid(Operation ~ SizeLabel, scales = "free_y") +
    scale_fill_manual(values = colors_sub, labels = labels_sub,
                      name = "Algorithm - GPU") +
    scale_y_continuous(expand = expansion(mult = c(0, 0.08))) +
    labs(x = "Dataset", y = "Throughput (GB/s)") +
    theme_iccsa(base_size = 13) +
    theme(
      axis.text.x     = element_text(angle = 45, hjust = 1, size = 10),
      strip.text      = element_text(size = 12),
      legend.key.size  = unit(0.4, "cm"),
      legend.text     = element_text(size = 10),
      legend.title    = element_text(size = 11),
      panel.spacing   = unit(0.4, "lines")
    ) +
    guides(fill = guide_legend(ncol = length(gpus)))

  save_fig(p, "fig1b_throughput_all", 14, 8)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 1c - Heatmap Throughput (xlarge / 4 GB only)
#  facet_grid(GPU ~ Operation), x = Dataset, y = Algorithm, fill = Throughput
# ══════════════════════════════════════════════════════════════════════════════

fig1c_heatmap_throughput_xlarge <- function(df) {
  data <- df |>
    filter(Size == "xlarge") |>
    select(Algorithm, Dataset, GPU,
           CompThroughputGBs, DecompThroughputGBs) |>
    pivot_longer(
      cols      = c(CompThroughputGBs, DecompThroughputGBs),
      names_to  = "Operation",
      values_to = "Throughput"
    ) |>
    mutate(
      Operation = factor(Operation,
                         levels = c("CompThroughputGBs", "DecompThroughputGBs"),
                         labels = c("Compression", "Decompression")),
      log_tp     = log10(pmax(Throughput, 0.1)),
      label_tp   = case_when(
        Throughput < 10   ~ sprintf("%.1f", Throughput),
        Throughput < 100  ~ sprintf("%.0f", Throughput),
        TRUE              ~ sprintf("%.0f", Throughput)
      ),
      text_color = ifelse(log_tp > 2.0, "white", "#1A1A1A")
    )
  
  p <- ggplot(data, aes(x = Dataset, y = Algorithm, fill = log_tp)) +
    geom_tile(color = "white", linewidth = 1.0) +
    geom_text(aes(label = label_tp, color = text_color),
              size = 2.5, fontface = "bold") +
    facet_grid(Operation ~ GPU) +
    scale_fill_gradientn(
      colours  = c("#D1E5F0", "#92C5DE", "#4393C3", "#2166AC"),
      limits   = c(0, 3.3),
      breaks   = c(0, 1, 2, 3),
      labels   = c("1", "10", "100", "1000"),
      name     = "GB/s"
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
      legend.title      = element_text(size = 9, face = "bold"),
      legend.key.height = unit(1.5, "cm"),
      legend.key.width  = unit(0.4, "cm"),
      plot.caption      = element_text(size = 7, color = "grey50",
                                       hjust = 0.5, margin = margin(t = 6))
    )
  
  gpus <- levels(droplevels(data$GPU))
  save_fig(p, "fig1c_heatmap_throughput_xlarge", 2.0 * length(gpus) + 1, 4)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 1d - Heatmap Throughput (all sizes)
#  facet_grid(GPU ~ Size), separate plots for Comp and Decomp
# ══════════════════════════════════════════════════════════════════════════════

fig1d_heatmap_throughput_all <- function(df) {
  data <- df |>
    select(Algorithm, Dataset, GPU, Size,
           CompThroughputGBs, DecompThroughputGBs) |>
    pivot_longer(
      cols      = c(CompThroughputGBs, DecompThroughputGBs),
      names_to  = "Operation",
      values_to = "Throughput"
    ) |>
    mutate(
      Operation = factor(Operation,
                         levels = c("CompThroughputGBs", "DecompThroughputGBs"),
                         labels = c("Compression", "Decompression")),
      SizeLabel  = factor(Size, levels = SIZE_ORDER, labels = SIZE_LABELS[SIZE_ORDER]),
      log_tp     = log10(pmax(Throughput, 0.1)),
      label_tp   = case_when(
        Throughput < 10   ~ sprintf("%.1f", Throughput),
        Throughput < 100  ~ sprintf("%.0f", Throughput),
        TRUE              ~ sprintf("%.0f", Throughput)
      ),
      text_color = ifelse(log_tp > 2.0, "white", "#1A1A1A")
    )
  
  gpus <- levels(droplevels(data$GPU))
  
  make_heatmap <- function(op_data, op_name, suffix) {
    p <- ggplot(op_data, aes(x = Dataset, y = Algorithm, fill = log_tp)) +
      geom_tile(color = "white", linewidth = 0.8) +
      geom_text(aes(label = label_tp, color = text_color),
                size = 2.8, fontface = "bold") +
      facet_grid(GPU ~ SizeLabel) +
      scale_fill_gradientn(
        colours  = c("#D1E5F0", "#92C5DE", "#4393C3", "#2166AC"),
        limits   = c(0, 3.3),
        breaks   = c(0, 1, 2, 3),
        labels   = c("1", "10", "100", "1000"),
        name     = "GB/s"
      ) +
      scale_color_identity() +
      scale_y_discrete(labels = ALGO_LABELS) +
      labs(x = "Dataset", y = "Algorithm") +
      theme_iccsa() +
      theme(
        panel.grid        = element_blank(),
        panel.border      = element_blank(),
        axis.text.x       = element_text(angle = 25, hjust = 1, size = 7),
        axis.ticks        = element_blank(),
        legend.position   = "right",
        legend.direction  = "vertical",
        legend.title      = element_text(size = 9, face = "bold"),
        legend.key.height = unit(1.2, "cm"),
        legend.key.width  = unit(0.35, "cm")
      )
    
    save_fig(p, paste0("fig1d_heatmap_throughput_", suffix),
             12, 2.0 * length(gpus) + 1)
  }
  
  make_heatmap(data |> filter(Operation == "Compression"), "Compression", "comp")
  make_heatmap(data |> filter(Operation == "Decompression"), "Decompression", "decomp")
}


# ══════════════════════════════════════════════════════════════════════════════
#  FIG 2 - Transfer Overhead (normalized 100% stacked bar)
#  PCIe transfer vs compute as % of total time
# ══════════════════════════════════════════════════════════════════════════════

fig2_transfer_overhead <- function(df) {
  data <- df |>
    filter(Size == "xlarge") |>
    mutate(
      TransferMs   = TransferH2DMs + TransferD2HMs,
      ComputeMs    = CompTimeMs + DecompTimeMs,
      TotalMs      = TransferMs + ComputeMs,
      PctTransfer  = TransferMs / TotalMs * 100,
      PctCompute   = ComputeMs / TotalMs * 100
    ) |>
    select(Algorithm, Dataset, GPU, PctTransfer, PctCompute) |>
    pivot_longer(
      cols      = c(PctCompute, PctTransfer),
      names_to  = "Phase",
      values_to = "Pct"
    ) |>
    mutate(
      Phase = factor(Phase,
        levels = c("PctCompute", "PctTransfer"),
        labels = c("Computation", "H2D and D2H Transfer"))
    )

  gpus <- levels(droplevels(data$GPU))

  # Labels: percentual dentro de cada segmento (se > 8%)
  labels_df <- data |>
    filter(Pct > 8) |>
    mutate(
      label = sprintf("%.0f%%", Pct),
      font_color = ifelse(Phase == "H2D and D2H Transfer", "white", "#333333")
    )

  p <- ggplot(data,
              aes(x = Dataset, y = Pct, fill = Phase)) +
    geom_col(position = "stack", width = 0.7,
             color = NA) +
    geom_text(data = labels_df,
              aes(label = label, color = font_color),
              position = position_stack(vjust = 0.5),
              size = 2.2, fontface = "bold") +
    scale_fill_manual(values = PHASE_COLORS_OVERHEAD, name = "Phase") +
    scale_color_identity() +
    scale_y_continuous(expand = expansion(mult = c(0, 0.02)),
                       labels = function(x) paste0(x, "%")) +
    labs(x = "Dataset", y = "Share of Total Time") +
    theme_iccsa() +
    theme(axis.text.x = element_text(angle = 35, hjust = 1, size = 9),
          plot.caption = element_text(size = 9, color = "grey50",
                                      hjust = 0.5, margin = margin(t = 7)))

  if (length(gpus) > 1) {
    p <- p + facet_grid(Algorithm ~ GPU, labeller = labeller(
      Algorithm = ALGO_LABELS
    ))
    save_fig(p, "fig2_transfer_overhead", 2.0 * length(gpus), 4.5)
  } else {
    p <- p + facet_wrap(~Algorithm, nrow = 1, labeller = labeller(
      Algorithm = ALGO_LABELS
    ))
    save_fig(p, "fig2_transfer_overhead", 7, 3)
  }
}

# # ══════════════════════════════════════════════════════════════════════════════
# #  FIG 2 - option 2 - Transfer Overhead (normalized 100% stacked bar)
# #  PCIe transfer vs compute as % of total time - 4 phases
# # ══════════════════════════════════════════════════════════════════════════════
# 
# fig2_transfer_overhead <- function(df) {
#   data <- df |>
#     filter(Size == "xlarge") |>
#     mutate(
#       TotalMs      = TransferH2DMs + CompTimeMs + DecompTimeMs + TransferD2HMs,
#       PctH2D       = TransferH2DMs / TotalMs * 100,
#       PctComp      = CompTimeMs    / TotalMs * 100,
#       PctDecomp    = DecompTimeMs  / TotalMs * 100,
#       PctD2H       = TransferD2HMs / TotalMs * 100
#     ) |>
#     select(Algorithm, Dataset, GPU, PctH2D, PctComp, PctDecomp, PctD2H) |>
#     pivot_longer(
#       cols      = c(PctH2D, PctComp, PctDecomp, PctD2H),
#       names_to  = "Phase",
#       values_to = "Pct"
#     ) |>
#     mutate(
#       Phase = factor(Phase,
#                      levels = c("PctH2D", "PctComp", "PctDecomp", "PctD2H"),
#                      labels = c("H2D Transfer", "Compression", "Decompression", "D2H Transfer"))
#     )
#   
#   gpus <- levels(droplevels(data$GPU))
#   
#   labels_df <- data |>
#     filter(Pct > 5) |>
#     mutate(
#       label = sprintf("%.0f%%", Pct),
#       font_color = case_when(
#         Phase == "H2D Transfer"   ~ "#333333",
#         Phase == "Compression"    ~ "#333333",
#         Phase == "Decompression"  ~ "#333333",
#         Phase == "D2H Transfer"   ~ "#333333",
#         TRUE                      ~ "#333333"
#       )
#     )
#   
#   p <- ggplot(data,
#               aes(x = Dataset, y = Pct, fill = Phase)) +
#     geom_col(position = "stack", width = 0.7,
#              color = NA) +
#     geom_text(data = labels_df,
#               aes(label = label, color = font_color),
#               position = position_stack(vjust = 0.5),
#               size = 3.2, fontface = "bold") +
#     scale_fill_manual(
#       values = c(
#         "H2D Transfer"   = "#92C5DE",
#         "Compression"    = "#F4A582",
#         "Decompression"  = "#A6D96A",
#         "D2H Transfer"   = "#FEE090"
#       ),
#       name = "Phase"
#     ) +
#     scale_color_identity() +
#     scale_y_continuous(expand = expansion(mult = c(0, 0.02)),
#                        labels = function(x) paste0(x, "%")) +
#     labs(x = "Dataset", y = "Share of Total Time",
#          caption = "4 GB input size") +
#     theme_iccsa() +
#     theme(axis.text.x = element_text(angle = 35, hjust = 1, size = 10),
#           plot.caption = element_text(size = 9, color = "grey50",
#                                       hjust = 0.5, margin = margin(t = 6)))
#   
#   if (length(gpus) > 1) {
#     p <- p + facet_grid(Algorithm ~ GPU, labeller = labeller(
#       Algorithm = ALGO_LABELS
#     ))
#     save_fig(p, "fig2_transfer_overhead", 4.5 * length(gpus), 8)
#   } else {
#     p <- p + facet_wrap(~Algorithm, nrow = 1, labeller = labeller(
#       Algorithm = ALGO_LABELS
#     ))
#     save_fig(p, "fig2_transfer_overhead", 12, 5)
#   }
# }

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 2b - Execution Time Breakdown (absolute stacked bar)
#  Alternative to Fig 2 - shows absolute time per phase.
#  Improved: distinct colors for H2D/D2H, labels outside thin slices.
# ══════════════════════════════════════════════════════════════════════════════

# Cores breakdown - paleta pastel coerente com o resto do paper
# H2D/D2H em tons de azul (transferência), Comp/Decomp em tons quentes (compute)
PHASE_COLORS_BREAKDOWN <- c(
  "H2D Transfer"   = "#92C5DE",
  "Compression"    = "#F4A582",
  "Decompression"  = "#A6D96A",
  "D2H Transfer"   = "#FEE090"
)

fig2b_breakdown <- function(df) {
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
      labels = names(PHASE_COLORS_BREAKDOWN)
    ))

  gpus <- levels(droplevels(data$GPU))

  # Labels: mostra valor em ms dentro da fatia se > 5% do total,
  # senão não mostra (evita sobreposição em fatias finas)
  labels_df <- data |>
    group_by(GPU, Algorithm) |>
    mutate(
      total = sum(TimeMs),
      pct   = TimeMs / total
    ) |>
    filter(pct > 0.05) |>
    ungroup() |>
    mutate(
      label = round(TimeMs, 0),
      # Cores legíveis para cada fatia
      font_color = case_when(
        Phase == "Compression"    ~ "#333333",
        Phase == "H2D Transfer"   ~ "#333333",
        Phase == "D2H Transfer"   ~ "#333333",
        Phase == "Decompression"  ~ "#333333",
        TRUE                      ~ "#333333"
      )
    )

  p <- ggplot(data, aes(x = Algorithm, y = TimeMs, fill = Phase)) +
    geom_col(width = 0.9, color = NA) +
    geom_text(data = labels_df,
              aes(label = label, color = font_color),
              position = position_stack(vjust = 0.5),
              size = 2.0, fontface = "bold") +
    scale_fill_manual(values = PHASE_COLORS_BREAKDOWN, name = "Phase") +
    scale_color_identity() +
    scale_y_continuous(expand = expansion(mult = c(0, 0.05))) +
    scale_x_discrete(labels = ALGO_LABELS) +
    labs(x = "Algorithm", y = "Execution Time (ms)") +
    # labs(x = "Algorithm", y = "Execution Time (ms)",
    #      caption = "TTI seismic dataset, 4 GB input") +
    theme_iccsa() +
    theme(plot.caption = element_text(size = 10, color = "grey50",
                                      hjust = 0.5, margin = margin(t = 6)))

  if (length(gpus) > 1) p <- p + facet_wrap(~GPU, nrow = 1)

  save_fig(p, "fig2b_breakdown", 1.6 * max(length(gpus), 1), 3.0)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 3 - Compression Ratio Heatmap (single, GPU-independent)
#  + LaTeX table output
# ══════════════════════════════════════════════════════════════════════════════

fig3_heatmap_ratio <- function(df) {
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
      text_color  = ifelse(CompressionRatio > 50, "white", "#1A1A1A")
    )

  # ── Heatmap ──
  p <- ggplot(data, aes(x = Dataset, y = Algorithm, fill = log_ratio)) +
    geom_tile(color = "white", linewidth = 1.2) +
    geom_text(aes(label = label_ratio, color = text_color),
              size = 5, fontface = "bold") +
    scale_fill_gradientn(
      colours   = c("#D1E5F0", "#92C5DE", "#4393C3", "#2166AC"),
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

  save_fig(p, "fig3_heatmap_ratio", 6.5, 4.0)

  # ── Tabela LaTeX ──
  table_data <- df |>
    filter(Size == "xlarge", GPU == first_gpu) |>
    select(Algorithm, Dataset, CompressionRatio) |>
    mutate(Algorithm = ALGO_LABELS[as.character(Algorithm)]) |>
    pivot_wider(names_from = Dataset, values_from = CompressionRatio)

  format_ratio <- function(x) {
    case_when(
      x < 10  ~ sprintf("%.2f", x),
      x < 100 ~ sprintf("%.1f", x),
      TRUE    ~ sprintf("%.0f", x)
    )
  }

  latex_lines <- c(
    "\\begin{table}[htbp]",
    "\\centering",
    "\\caption{Compression ratio by algorithm and dataset (4\\,GB input). Ratios are GPU-independent.}",
    "\\label{tab:compression_ratio}",
    sprintf("\\begin{tabular}{l%s}", paste(rep("r", ncol(table_data) - 1), collapse = "")),
    "\\toprule",
    paste0("Algorithm & ", paste(colnames(table_data)[-1], collapse = " & "), " \\\\"),
    "\\midrule"
  )

  for (i in seq_len(nrow(table_data))) {
    row_vals <- table_data[i, -1] |> mutate(across(everything(), format_ratio))
    latex_lines <- c(latex_lines,
      paste0(table_data$Algorithm[i], " & ",
             paste(row_vals, collapse = " & "), " \\\\"))
  }

  latex_lines <- c(latex_lines,
    "\\bottomrule",
    "\\end{tabular}",
    "\\end{table}"
  )

  tex_path <- file.path(OUTPUT_DIR, "tab_compression_ratio.tex")
  writeLines(latex_lines, tex_path)
  cat(sprintf("  ✓  tab_compression_ratio.tex\n"))
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 4 - Compression/Decompression Asymmetry Heatmap
#  Ratio = DecompThroughput / CompThroughput, faceted by GPU
# ══════════════════════════════════════════════════════════════════════════════

fig4_asymmetry <- function(df) {
  data <- df |>
    filter(Size == "xlarge") |>
    mutate(
      AsymRatio = DecompThroughputGBs / CompThroughputGBs,
      log_asym  = log10(AsymRatio),
      label_asym = case_when(
        AsymRatio < 1   ~ sprintf("%.1fx", AsymRatio),
        AsymRatio < 10  ~ sprintf("%.1fx", AsymRatio),
        TRUE            ~ sprintf("%.0fx", AsymRatio)
      ),
      text_color = ifelse(abs(log_asym) > 0.8, "white", "#1A1A1A")
    )

  gpus <- levels(droplevels(data$GPU))

  p <- ggplot(data, aes(x = Dataset, y = Algorithm, fill = log_asym)) +
    geom_tile(color = "white", linewidth = 1.0) +
    geom_text(aes(label = label_asym, color = text_color),
              size = 4, fontface = "bold") +
    scale_fill_gradient2(
      low      = "#F4A582",   # salmon = compressão domina (ou equilíbrio)
      mid      = "#FEE090",   # amarelo claro = equilíbrio
      high     = "#4393C3",   # azul = descompressão domina
      midpoint = 0,
      limits   = c(-0.6, 2.0),
      breaks   = c(-0.5, 0, 0.5, 1.0, 1.5),
      labels   = c("0.3x", "1x", "3x", "10x", "30x"),
      name     = "Decomp / Comp",
      oob      = squish
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
      legend.title      = element_text(size = 11, face = "bold"),
      legend.key.height = unit(1.5, "cm"),
      legend.key.width  = unit(0.4, "cm")
    )

  if (length(gpus) > 1) p <- p + facet_wrap(~GPU, nrow = 1)

  save_fig(p, "fig4_asymmetry", 4.5 * max(length(gpus), 1), 4)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 5a - Throughput Scalability (TTI only)
# ══════════════════════════════════════════════════════════════════════════════

fig5a_scale_tti <- function(df) {
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
    geom_line(linewidth = 0.8) +
    geom_point(shape = 16, size = 2.0, stroke = 1.2, fill = "white") +
    scale_color_manual(values = ALGO_COLORS, labels = ALGO_LABELS, name = "Algorithm") +
    scale_fill_manual(values  = ALGO_COLORS, labels = ALGO_LABELS, name = "Algorithm") +
    scale_x_log10(
      breaks = c(10, 100, 1024, 4096),
      labels = c("10 MB", "100 MB", "1,024 MB", "4,096 MB")
    ) +
    scale_y_continuous(expand = expansion(mult = c(0.02, 0.10))) +
    labs(x = "Input Size (MB)", y = "Compression Throughput (GB/s)") +
    theme_iccsa() + #, caption = "TTI seismic dataset"
    theme(
      # Strips (facets)
      strip.background   = element_rect(fill = "grey95", color = "grey80"),
      strip.text         = element_text(face = "bold", size = 14,
                                        color = "black", margin = margin(4, 4, 4, 4)),
      
      # Legenda
      legend.position    = "top",
      legend.direction   = "horizontal",
      legend.title       = element_text(face = "bold", size = 12),
      legend.text        = element_text(size = 14 - 2),
      legend.background  = element_blank(),
      legend.key         = element_blank(),
      legend.key.size    = unit(0.85, "lines"),
      legend.margin      = margin(0, 0, 4, 0),
      legend.spacing.x   = unit(6, "pt"),
      
      # Eixos
      axis.title         = element_text(face = "bold", size = 14),
      axis.text          = element_text(size = 12 - 2, color = "black"),
      axis.ticks         = element_line(color = "grey60", linewidth = 0.35),
      axis.ticks.length  = unit(3, "pt"),
      panel.grid.major.x = element_line(color = "#E4E4E4", linewidth = 0.4,
                                            linetype = "dashed"),
          plot.caption = element_text(size = 12, color = "grey50",
                                      hjust = 0.5, margin = margin(t = 6)))

  if (length(gpus) > 1) p <- p + facet_wrap(~GPU, nrow = 2, scales = "free_y")

  save_fig(p, "fig5a_scale_tti", 2.6 * max(length(gpus), 1), 4.4)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 5b - Throughput Scalability (all datasets, same panel)
#  Unique color per Algorithm × Dataset, linetype alternates solid/dashed.
#  Facet = GPU. Legend shows every combo clearly.
# ══════════════════════════════════════════════════════════════════════════════

# Cores: gradiente por algoritmo, tonalidade por dataset
# Ordem datasets: Zeros, Binary, Random, TTI (mais claro → mais escuro)
ALGO_DATASET_COLORS <- c(
  # LZ4: tons de salmon/coral
  "LZ4 - Zeros"         = "#FDDBC7",
  "LZ4 - Binary"        = "#F4A582",
  "LZ4 - Random"        = "#D6604D",
  "LZ4 - TTI (seismic)" = "#B2182B",
  # Snappy: tons de azul
  "Snappy - Zeros"         = "#D1E5F0",
  "Snappy - Binary"        = "#92C5DE",
  "Snappy - Random"        = "#4393C3",
  "Snappy - TTI (seismic)" = "#2166AC",
  # Cascaded: tons de verde
  "Cascaded - Zeros"         = "#D9EF8B",
  "Cascaded - Binary"        = "#A6D96A",
  "Cascaded - Random"        = "#66BD63",
  "Cascaded - TTI (seismic)" = "#1A9850"
)

# Linetype: alterna entre datasets para reforçar distinção
ALGO_DATASET_LINETYPES <- c(
  "LZ4 - Zeros"         = "solid",
  "LZ4 - Binary"        = "dashed",
  "LZ4 - Random"        = "dotted",
  "LZ4 - TTI (seismic)" = "longdash",
  "Snappy - Zeros"         = "solid",
  "Snappy - Binary"        = "dashed",
  "Snappy - Random"        = "dotted",
  "Snappy - TTI (seismic)" = "longdash",
  "Cascaded - Zeros"         = "solid",
  "Cascaded - Binary"        = "dashed",
  "Cascaded - Random"        = "dotted",
  "Cascaded - TTI (seismic)" = "longdash"
)

# Shapes: cada dataset tem um shape fixo, repetido por algoritmo
ALGO_DATASET_SHAPES <- c(
  "LZ4 - Zeros" = 16, "LZ4 - Binary" = 17, "LZ4 - Random" = 15, "LZ4 - TTI (seismic)" = 18,
  "Snappy - Zeros" = 16, "Snappy - Binary" = 17, "Snappy - Random" = 15, "Snappy - TTI (seismic)" = 18,
  "Cascaded - Zeros" = 16, "Cascaded - Binary" = 17, "Cascaded - Random" = 15, "Cascaded - TTI (seismic)" = 18
)

fig5b_scale_all <- function(df) {
  data <- df |>
    mutate(
      SizeMB   = SIZE_MAP[as.character(Size)],
      AlgoData = paste0(ALGO_LABELS[as.character(Algorithm)], " - ", Dataset)
    )

  # Manter apenas combos presentes
  present <- unique(data$AlgoData)
  colors_sub    <- ALGO_DATASET_COLORS[present]
  linetypes_sub <- ALGO_DATASET_LINETYPES[present]
  shapes_sub    <- ALGO_DATASET_SHAPES[present]

  # Ordenar factor para legenda agrupada por algoritmo
  data$AlgoData <- factor(data$AlgoData, levels = names(ALGO_DATASET_COLORS))

  gpus <- levels(droplevels(data$GPU))

  p <- ggplot(data,
              aes(x = SizeMB, y = CompThroughputGBs,
                  color = AlgoData, linetype = AlgoData, shape = AlgoData,
                  group = AlgoData)) +
    geom_line(linewidth = 0.6) +
    geom_point(size = 2.0, stroke = 0.8) +
    facet_wrap(~GPU, nrow = 1, scales = "free_y") +
    scale_color_manual(values = colors_sub, name = "Algorithm - Dataset") +
    scale_linetype_manual(values = linetypes_sub, name = "Algorithm - Dataset") +
    scale_shape_manual(values = shapes_sub, name = "Algorithm - Dataset") +
    scale_x_log10(
      breaks = c(10, 100, 1024, 4096),
      labels = c("10 MB", "100 MB", "1,024 MB", "4,096 MB")
    ) +
    scale_y_continuous(expand = expansion(mult = c(0.02, 0.10))) +
    labs(x = "Input Size (MB)", y = "Compression Throughput (GB/s)") +
    theme_iccsa() +
    theme(
      panel.grid.major.x = element_line(color = "#E4E4E4", linewidth = 0.4,
                                        linetype = "dashed"),
      legend.key.width  = unit(1.5, "cm"),
      legend.text       = element_text(size = 9),
      legend.title      = element_text(size = 10)
    ) +
    guides(
      color    = guide_legend(ncol = 6, byrow = FALSE),
      linetype = guide_legend(ncol = 6, byrow = FALSE),
      shape    = guide_legend(ncol = 6, byrow = FALSE)
    )

  save_fig(p, "fig5b_scale_all", 5.0 * max(length(gpus), 1), 5)
}

# ══════════════════════════════════════════════════════════════════════════════
#  FIG 6 - Speedup vs MI50
#  facet_grid(GPU ~ Size), x = Dataset, fill = Algorithm
#  Two figures: 6a (compression), 6b (decompression)
#  Automatically detects which GPUs are present besides MI50.
# ══════════════════════════════════════════════════════════════════════════════

fig6_speedup <- function(df) {
  gpus_present <- levels(droplevels(df$GPU))

  if (!"MI50" %in% gpus_present) {
    message("  ⚠️   Fig 6: MI50 ausente - placeholder gerado.")
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
    save_fig(p, "fig6a_speedup_comp", 8, 4)
    save_fig(p, "fig6b_speedup_decomp", 8, 4)
    return(invisible(NULL))
  }

  # ── Calcular speedup para todas as combinações ──
  baseline <- df |>
    filter(GPU == "MI50") |>
    select(Algorithm, Dataset, Size,
           base_comp   = CompThroughputGBs,
           base_decomp = DecompThroughputGBs)

  compare_gpus <- setdiff(gpus_present, "MI50")

  speedup_df <- df |>
    filter(GPU != "MI50") |>
    left_join(baseline, by = c("Algorithm", "Dataset", "Size")) |>
    mutate(
      SpeedupComp   = CompThroughputGBs   / base_comp,
      SpeedupDecomp = DecompThroughputGBs / base_decomp,
      SizeLabel = factor(Size, levels = SIZE_ORDER, labels = SIZE_LABELS[SIZE_ORDER])
    )

  n_compare <- length(compare_gpus)

  # ── Helper: gera um plot de speedup ──
  make_speedup_plot <- function(data, speedup_col, ylabel) {
    ggplot(data, aes(x = Dataset, y = .data[[speedup_col]], fill = Algorithm)) +
      geom_col(position = position_dodge(width = 0.8),
               width = 0.7, color = NA) +
      geom_hline(yintercept = 1, linetype = "dashed",
                 color = "#C0392B", linewidth = 0.6, alpha = 0.7) +
      geom_text(aes(label = sprintf("%.1f", .data[[speedup_col]])),
                position = position_dodge(width = 0.8),
                vjust = -0.3, size = 2.5, check_overlap = TRUE) +
      facet_grid(GPU ~ SizeLabel) +
      scale_fill_manual(values = ALGO_COLORS, labels = ALGO_LABELS, name = "Algorithm") +
      scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
      labs(x = "Dataset", y = ylabel) +
      theme_iccsa() +
      theme(axis.text.x = element_text(angle = 40, hjust = 1, size = 8))
  }

  # ── Fig 6a: Compression Speedup ──
  p6a <- make_speedup_plot(speedup_df, "SpeedupComp",
                           "Compression Speedup (GPU / MI50)")
  save_fig(p6a, "fig6a_speedup_comp", 6, 1.0 * n_compare + 1.4)

  # ── Fig 6b: Decompression Speedup ──
  p6b <- make_speedup_plot(speedup_df, "SpeedupDecomp",
                           "Decompression Speedup (GPU / MI50)")
  save_fig(p6b, "fig6b_speedup_decomp", 6, 1.0 * n_compare + 1.4)
  # save_fig(p6b, "fig6b_speedup_decomp", 14, 2.8 * n_compare + 1.5)
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
cat(sprintf("    Datasets  : %s\n", paste(levels(droplevels(df$Dataset)), collapse = ", ")))
cat(sprintf("    Sizes     : %s\n", paste(levels(droplevels(df$Size)),    collapse = ", ")))
cat(sprintf("    Linhas    : %d\n\n", nrow(df)))

cat("📊  Gerando figuras...\n")
fig1a_throughput_xlarge(df)
fig1b_throughput_all(df)
# fig1c_heatmap_throughput_xlarge(df)
# fig1d_heatmap_throughput_all(df)
fig2_transfer_overhead(df)
fig2b_breakdown(df)
fig3_heatmap_ratio(df)
fig4_asymmetry(df)
fig5a_scale_tti(df)
fig5b_scale_all(df)
fig6_speedup(df)

cat(sprintf("\n✅  Figuras salvas em ./%s/  (PDF + PNG)\n", OUTPUT_DIR))
