# ============================================================
# Question 3 – TEAE Summary Table (FDA Table 10 Style)
# ============================================================

sink("01_create_ae_summary_table.log", split = TRUE)

# ---- Libraries ----
library(dplyr)
library(gtsummary)
library(gt)
library(pharmaverseadam)

# ---- Create output directory ----
if (!dir.exists("outputs")) dir.create("outputs")

# ---- Load data ----
adae <- pharmaverseadam::adae
adsl <- pharmaverseadam::adsl

# ---- Treatment denominators ----
denoms <- adsl %>%
  filter(!is.na(ACTARM)) %>%
  count(ACTARM, name = "N")

# ---- Filter Treatment-Emergent AEs ----
teae <- adae %>%
  filter(TRTEMFL == "Y")

# ---- Create subject-level dataset (one row per subject per term) ----
teae_subj <- teae %>%
  distinct(USUBJID, ACTARM, AETERM)

# ---- Create Table using gtsummary ----
tbl_ae <- teae_subj %>%
  tbl_summary(
    by = ACTARM,
    include = AETERM,
    statistic = all_categorical() ~ "{n} ({p}%)",
    percent = "column",
    missing = "no"
  ) %>%
  add_overall(last = TRUE) %>%
  modify_header(label = "**Adverse Event Term**") %>%
  bold_labels()

# ---- Convert to gt for formatting ----
gt_table <- tbl_ae %>%
  as_gt() %>%
  tab_header(
    title = md("**Treatment-Emergent Adverse Events (Safety Population)**")
  )

# ---- Save HTML ----
gtsave(gt_table, "outputs/ae_summary_table.html")

sink()
