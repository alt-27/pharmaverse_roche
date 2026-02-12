# Load libraries & data --------------------------------------
library(dplyr)
library(gtsummary)
library(gt)
library(pharmaverseadam)

## ---- log file ----------------------------------------------------------------
sink("summary_table_log.txt", split = TRUE)
cat("running summary table creation script...\n\n")


adsl <- pharmaverseadam::adsl
adae <- pharmaverseadam::adae

# Output folder ------------------------------------------------
if (!dir.exists("outputs")) dir.create("outputs", recursive = TRUE)

# Pre-processing ----------------------------------------------
# TEAEs only
teae <- adae %>%
  filter(
    TRTEMFL == "Y",
  ) 

# Filter the columns which matters (AETERM, AESOC, ACTARM, TRTEMFL)
teae <- teae %>%
  select(AETERM, AESOC, USUBJID, ACTARM, TRTEMFL)

# Build gtsummary table ---------------------------------------

# AESOC is the big group and AETERM is the subgroup, descending order count and bracket percentage of ACTARM
tbl_teae <- teae %>% 
  tbl_hierarchical(
    variables = c(AESOC, AETERM),
    by = ACTARM,
    id = USUBJID,
    denominator = adsl,
    overall_row = TRUE,
    label = "..ard_hierarchical_overall.." ~ "Treatment Emergent AEs"
  ) %>%
  add_overall(last = TRUE)

tbl_teae

# Save as HTML -------------------------------------------------
gt_tbl <- as_gt(tbl_teae)
gtsave(gt_tbl, "outputs/ae_summary_table.html")

cat("\nscript completed without errors.\n")
sink()