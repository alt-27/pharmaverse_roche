## ---- log file ----------------------------------------------------------------
sink("plots_log.txt", split = TRUE)
cat("Running AE plots creation script...\n\n")

# ---- Load libraries -----------------------------------------------------------
library(dplyr)
library(ggplot2)
library(pharmaverseadam)

# ---- Create output directory --------------------------------------------------
if (!dir.exists("outputs")) {
  dir.create("outputs", recursive = TRUE)
  cat("Created outputs directory.\n")
}

# ---- Load data ----------------------------------------------------------------
adae <- pharmaverseadam::adae

# ==============================================================================
# Plot 1: AE severity distribution by treatment
# - Per spec: AESEV by ACTARM
# - Here: Treatment-emergent AEs only (TRTEMFL == 'Y')
# ==============================================================================
cat("Preparing data for Plot 1 (severity distribution)...\n")

tbl1 <- adae %>%
  filter(
    TRTEMFL == "Y"
  ) %>%
  mutate(
    # Ensure severity order is consistent in stacked bars
    AESEV = factor(AESEV, levels = c("MILD", "MODERATE", "SEVERE"))
  )

cat("Creating Plot 1...\n")
severity_plot <- ggplot(tbl1, aes(x = ACTARM, fill = AESEV)) +
  geom_bar(position = "stack") +
  labs(
    title = "AE Severity Distribution by Treatment",
    x = "Treatment Arm",
    y = "Count of AEs",
    fill = "Severity/Intensity"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold"),
    legend.position = "right"
  )

# Saving plot
cat("Saving Plot 1 to outputs/plot1_severity_distribution.png...\n")

ggsave(
  filename = "outputs/plot1_severity_distribution.png",
  plot = severity_plot,
  width = 8,
  height = 6,
  dpi = 300
)

cat("Plot 1 saved.\n\n")

# ==============================================================================
# Plot 2: Top 10 most frequent AEs with 95% CI for incidence rates
# - Uses subject-level incidence (unique USUBJID per AETERM)
# - Denominator: unique subjects appearing in ADAE
# - 95% CI: Clopper-Pearson exact via stats::binom.test
# ==============================================================================
cat("Preparing data for Plot 2 (Top 10 AEs + 95% CI)...\n")

# Denominator = unique subjects that appear in ADAE
N <- adae %>%
  filter(!is.na(USUBJID)) %>%
  distinct(USUBJID) %>%
  nrow()

cat("Denominator N (unique subjects in ADAE):", N, "\n")

# Subject-level incidence (1 per subject per term)
ae_subj <- adae %>%
  filter(!is.na(USUBJID), !is.na(AETERM), AETERM != "") %>%
  distinct(USUBJID, AETERM)

# Top 10 most frequent AEs (by subjects)
tbl2 <- ae_subj %>%
  count(AETERM, name = "n_subj") %>%
  arrange(desc(n_subj), AETERM) %>%
  slice_head(n = 10) %>%
  mutate(
    prop = n_subj / N
  )

# 95% Clopper-Pearson exact CI using stats::binom.test (base R)
cat("\nCalculating 95% Clopper-Pearson CIs...\n")
ci_mat <- t(mapply(
  FUN = function(x) stats::binom.test(x, N)$conf.int,
  x = tbl2$n_subj
))

tbl2 <- tbl2 %>%
  mutate(
    lower = ci_mat[, 1],
    upper = ci_mat[, 2]
  )

cat("Creating Plot 2...\n")
p2 <- ggplot(tbl2, aes(x = prop, y = reorder(AETERM, prop))) +
  geom_errorbarh(aes(xmin = lower, xmax = upper), width = 0.2) +
  geom_point(size = 3) +
  scale_x_continuous() +
  labs(
    title = "Top 10 Most Frequent Adverse Events",
    subtitle = paste0("n = ", N, " subjects; 95% Clopper-Pearson CIs"),
    x = "Percentage of Patients (%)",
    y = NULL
  ) +
  theme_minimal(base_size = 12)

cat("Saving Plot 2 to outputs/plot2_top10AE.png...\n")

# Saving plot
ggsave(
  filename = "outputs/plot2_top10AE.png",
  plot = p2,
  width = 8,
  height = 6,
  dpi = 300
)

cat("Plot 2 saved.\n\n")
cat("Script completed without errors.\n")

sink()
