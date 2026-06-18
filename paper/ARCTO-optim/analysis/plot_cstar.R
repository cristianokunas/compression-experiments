suppressMessages({
  library(ggplot2); library(dplyr); library(scales)
})

chunks <- c(8, 16, 32, 64, 256, 1024, 4096)   # KiB (128K not in the sweep)
mk <- function(gpu, algo, v) data.frame(gpu = gpu, algo = algo,
                                        chunk = chunks, thr = v)

# Large TTI, baseline, kernel-only compression throughput (GB/s) -- chunk_sweeps.csv
df <- rbind(
  mk("RX 7900 XT", "LZ4",      c(11.78, 11.19,  9.95,  7.42,  5.94,  6.29,  2.06)),
  mk("RX 7900 XT", "Snappy",   c(29.02, 28.60, 27.00, 26.08, 23.18, 17.30,  8.78)),
  mk("RX 7900 XT", "Cascaded", c(53.37, 57.42, 58.49, 61.06, 55.34, 45.75, 27.03)),
  mk("MI300X",     "LZ4",      c(18.13, 16.89, 11.61, 12.07,  7.62,  3.35,  0.90)),
  mk("MI300X",     "Snappy",   c(100.98, 98.59, 92.57, 83.42, 55.71, 27.27,  6.78)),
  mk("MI300X",     "Cascaded", c(126.54, 124.56, 122.23, 118.49, 90.87, 74.82, 18.87)),
  mk("MI210",      "LZ4",      c( 3.18,  2.84,  2.61,  2.39,  2.19,  2.14,  1.03)),
  mk("MI210",      "Snappy",   c(27.80, 27.67, 26.68, 25.71, 22.92, 16.14,  7.95)),
  mk("MI210",      "Cascaded", c(33.80, 33.43, 33.40, 35.22, 34.17, 29.04, 21.85))
)

gpu_lv  <- c("MI210", "MI300X", "RX 7900 XT")
algo_lv <- c("LZ4", "Snappy", "Cascaded")
df$gpu  <- factor(df$gpu,  levels = gpu_lv)
df$algo <- factor(df$algo, levels = algo_lv)

# c* = empirical optimum (max kernel throughput) per (GPU, codec)
cstar <- df %>% group_by(gpu, algo) %>%
  slice_max(thr, n = 1, with_ties = FALSE) %>% ungroup()

pal  <- c("LZ4" = "#F4A582", "Snappy" = "#92C5DE", "Cascaded" = "#A6D96A")
ring <- "#7F0000"

p <- ggplot(df, aes(chunk, thr, color = algo)) +
  geom_line(linewidth = 0.85) +
  geom_point(size = 1.7) +
  geom_point(data = cstar, shape = 21, size = 4.6, stroke = 1.4,
             fill = NA, color = ring) +
  facet_wrap(~gpu, scales = "free_y", nrow = 1) +
  scale_x_continuous(trans = "log2", breaks = chunks, labels = chunks,
                     expand = expansion(mult = 0.06)) +
  scale_y_continuous(expand = expansion(mult = c(0.04, 0.10))) +
  scale_color_manual(values = pal, name = NULL) +
  labs(x = "Chunk size (KiB, log scale)",
       y = "Compression throughput (GB/s)") +
  theme_minimal(base_size = 12) +
  theme(legend.position = "top",
        panel.grid.minor = element_blank(),
        strip.text  = element_text(face = "bold", size = 12),
        axis.text.x = element_text(size = 9))

ggsave("fig-chunk-csize.pdf", p, width = 9.0, height = 3.3, device = cairo_pdf)
ggsave("fig-chunk-csize.png", p, width = 9.0, height = 3.3, dpi = 150, bg = "white")