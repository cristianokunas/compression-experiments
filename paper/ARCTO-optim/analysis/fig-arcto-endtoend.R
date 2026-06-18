# fig-arcto-endtoend.R
# End-to-end Fletcher result on the MI300X (408^3 grid, 200 wavefield snapshots).
# Left panel:  total simulation time, per-repetition distribution as violin + inner
#              box plot (Tukey 1.5*IQR whiskers), points beyond the whiskers drawn
#              individually. Median of 30 repetitions.
# Right panel: volume written to storage. Deterministic per codec, shown as a bar.
#
# Aggregation and display follow the end-to-end protocol of Chapter 5:
#   median / IQR, Tukey fence at 1.5*IQR, outliers flagged but never removed.

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(patchwork)   # to compose the two panels
})

# ----------------------------------------------------------------------------
# Data
# ----------------------------------------------------------------------------
# Reads the raw per-repetition CSV. Adjust the path to your data location.
df <- read.csv("/home/cak/Documentos/sbac-pad26/fletcher_endtoend_mi300x.csv", stringsAsFactors = FALSE)

# Canonical codec order and display labels.
codec_levels <- c("none", "lz4", "snappy", "cascaded", "zfp")
codec_labels <- c(none = "Raw",
                  lz4 = "LZ4",
                  snappy = "Snappy",
                  cascaded = "Cascaded",
                  zfp = "ZFP")

df <- df %>%
  mutate(codec = factor(codec, levels = codec_levels))

# ----------------------------------------------------------------------------
# Palette
# ----------------------------------------------------------------------------
# Byte-level codecs keep the palette used across the thesis figures.
# Uncompressed is a neutral gray, ZFP gets a distinct lossy-path color.
pal <- c(none     = "#9E9E9E",
         lz4      = "#F4A582",
         snappy   = "#92C5DE",
         cascaded = "#A6D96A",
         zfp      = "#C994C7")

# ----------------------------------------------------------------------------
# Helper: classify Tukey outliers per codec, so they can be drawn individually
# while the box plot itself hides its own outlier glyphs (outlier.shape = NA).
# ----------------------------------------------------------------------------
flag_outliers <- function(x) {
  q <- quantile(x, c(0.25, 0.75), names = FALSE)
  iqr <- q[2] - q[1]
  lo <- q[1] - 1.5 * iqr
  hi <- q[2] + 1.5 * iqr
  x < lo | x > hi
}

df <- df %>%
  group_by(codec) %>%
  mutate(is_outlier = flag_outliers(total)) %>%
  ungroup()

# Volume is constant per codec; take the first value of each group.
vol <- df %>%
  group_by(codec) %>%
  summarise(gb = first(rsf_bytes) / 1e9, .groups = "drop")

# Median time per codec, for the annotation on the left panel.
med <- df %>%
  group_by(codec) %>%
  summarise(med = median(total), .groups = "drop")

# ----------------------------------------------------------------------------
# Shared theme
# ----------------------------------------------------------------------------
base_size <- 11
thm <- theme_bw(base_size = base_size) +
  theme(
    panel.grid.minor   = element_blank(),
    panel.grid.major.x = element_blank(),
    axis.line.x        = element_line(color = "grey30", linewidth = 0.3),
    axis.ticks.x       = element_line(color = "grey30", linewidth = 0.3),
    axis.title.x       = element_blank(),
    legend.position    = "none",
    plot.title         = element_text(size = base_size, face = "plain", hjust = 0)
  )

# ----------------------------------------------------------------------------
# Left panel: total simulation time, violin + inner box + individual outliers
# ----------------------------------------------------------------------------
p_time <- ggplot(df, aes(x = codec, y = total, fill = codec)) +
  geom_violin(trim = FALSE, color = NA, alpha = 0.65, scale = "width",
              adjust = 0.9, width = 0.85) +
  geom_boxplot(width = 0.34, outlier.shape = 21, color = "grey20",
               linewidth = 0.35, alpha = 0.9, coef = 1.5) +
  stat_boxplot(geom = "errorbar", width = 0.17, coef = 1.5,
               color = "grey20", linewidth = 0.35) +
  # geom_point(data = subset(df, is_outlier),
             # shape = 21, size = 1.6, stroke = 0.3,
             # color = "grey20", fill = "white") +
  scale_fill_manual(values = pal) +
  scale_x_discrete(labels = codec_labels) +
  # scale_y_continuous(limits = c(0, NA), expand = expansion(mult = c(0, 0.05))) +
  scale_y_continuous(expand = expansion(mult = c(0.05, 0.05))) +
  labs(y = "Time (s)") +
  thm

# ----------------------------------------------------------------------------
# Right panel: volume written, one bar per codec (deterministic)
# ----------------------------------------------------------------------------
p_vol <- ggplot(vol, aes(x = codec, y = gb, fill = codec)) +
  geom_col(width = 0.8, alpha = 0.9, color = "black", linewidth = 0.3) +
  geom_text(aes(label = sprintf("%.0f", gb)),
            vjust = -0.4, size = 3.0, color = "grey20") +
  scale_fill_manual(values = pal) +
  scale_x_discrete(labels = codec_labels) +
  scale_y_continuous(limits = c(0, NA), expand = expansion(mult = c(0, 0.08))) +
  labs(y = "Volume (GB)") +
  thm

# ----------------------------------------------------------------------------
# Compose and export
# ----------------------------------------------------------------------------
fig <- p_time + p_vol + plot_layout(widths = c(1, 1))

ggsave("fig-arcto-endtoend.pdf", fig, width = 7.2, height = 3.1,
       device = cairo_pdf)

message("wrote fig-arcto-endtoend.pdf")
