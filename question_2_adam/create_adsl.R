# question_2_adam/01_create_adsl.R
# create adsl from pharmaversesdtm domains per provided rules

## ---- setup ------------------------------------------------------------------
library(pharmaversesdtm)
library(admiral)
library(dplyr)
library(lubridate)
library(stringr)

## ---- log file ----------------------------------------------------------------
sink("adsl_log.txt", split = TRUE)
cat("running adsl creation script...\n\n")

## ---- load sdtm inputs --------------------------------------------------------
# convert_blanks_to_na() standardizes sas-style blanks ("") into proper missing values (NA),
# which prevents accidental inclusion of empty strings in derived flags/filters.
dm <- convert_blanks_to_na(pharmaversesdtm::dm)
ex <- convert_blanks_to_na(pharmaversesdtm::ex)
vs <- convert_blanks_to_na(pharmaversesdtm::vs)
ae <- convert_blanks_to_na(pharmaversesdtm::ae)
ds <- convert_blanks_to_na(pharmaversesdtm::ds)

cat("inputs loaded.\n")
cat("dm:", nrow(dm), "subjects\n\n")

## ---- start adsl from dm ------------------------------------------------------
# start from one record per subject (dm) and derive baseline analysis flags/groups.
# ittfl:
#   - "y" if the subject has a non-missing treatment arm assignment (ARM)
#   - otherwise "n"
# agegr9 / agegr9n:
#   - bucket AGE into <18, 18-50, >50
#   - provide a numeric version for easy ordering/analysis
adsl <- dm %>%
  mutate(
    ITTFL = if_else(!is.na(ARM), "Y", "N"),
    AGEGR9 = case_when(
      is.na(AGE) ~ NA_character_,
      AGE < 18 ~ "<18",
      AGE >= 18 & AGE <= 50 ~ "18 - 50",
      AGE > 50 ~ ">50"
    ),
    AGEGR9N = case_when(
      AGEGR9 == "<18" ~ 1,
      AGEGR9 == "18 - 50" ~ 2,
      AGEGR9 == ">50" ~ 3,
      TRUE ~ NA_real_
    )
  )

## ---- derive exposure datetimes from ex ---------------------------------------
# derive_vars_dtm() converts iso8601 character datetimes (EXSTDTC/EXENDTC) into:
#   - EXSTDTM / EXENDTM: POSIXct datetime
#   - EXSTTMF / EXENTMF: imputation flag indicating time imputation (if applied)
#
# imputation rules:
#   - EXSTDTC: impute missing time to start of day (00:00:00) using time_imputation="first"
#   - EXENDTC: impute missing time to end of day (23:59:59) using time_imputation="last"
ex_ext <- ex %>%
  derive_vars_dtm(
    dtc = EXSTDTC,
    new_vars_prefix = "EXST",
    time_imputation = "first"
  ) %>%
  derive_vars_dtm(
    dtc = EXENDTC,
    new_vars_prefix = "EXEN",
    time_imputation = "last"
  ) %>%
  # spec detail:
  # if EXSTDTC is present with hh:mm only (YYYY-MM-DDThh:mm), seconds are missing but should
  # not be treated as "time imputed" for this deliverable; clear the imputation flag in that case.
  mutate(
    EXSTTMF = if_else(
      !is.na(EXSTDTC) & str_detect(EXSTDTC, "T\\d{2}:\\d{2}$"),
      NA_character_,
      EXSTTMF
    )
  )

## ---- keep only valid exposure records ----------------------------------------
# valid dose definition:
#   - EXDOSE > 0
#   - OR EXDOSE == 0 AND EXTRT contains "placebo" (case-insensitive)
#
# also require:
#   - EXSTDTM is non-missing (so ordering by datetime is possible)
#   - EXSTDTC has at least a complete datepart (YYYY-MM-DD) so the record is usable downstream
ex_valid <- ex_ext %>%
  filter(
    (EXDOSE > 0 |
       (EXDOSE == 0 & str_detect(toupper(coalesce(EXTRT, "")), "PLACEBO"))) &
      !is.na(EXSTDTM) &
      !is.na(EXSTDTC) &
      str_detect(EXSTDTC, "^\\d{4}-\\d{2}-\\d{2}")
  )

## ---- derive trtsdtm/trtstmf and trtedtm --------------------------------------
# merge first/last valid treatment administration datetime back to adsl.
# ordering:
#   - EXSTDTM primary sort
#   - EXSEQ tie-breaker if two doses share the same datetime
#
# derived variables:
#   - TRTSDTM: first valid EXSTDTM
#   - TRTSTMF: imputation flag for the first dose datetime (if any)
#   - TRTEDTM: last  valid EXSTDTM (used later for last-alive evidence)
adsl <- adsl %>%
  derive_vars_merged(
    dataset_add = ex_valid,
    by_vars = exprs(STUDYID, USUBJID),
    new_vars = exprs(TRTSDTM = EXSTDTM, TRTSTMF = EXSTTMF),
    order = exprs(EXSTDTM, EXSEQ),
    mode = "first"
  ) %>%
  derive_vars_merged(
    dataset_add = ex_valid,
    by_vars = exprs(STUDYID, USUBJID),
    new_vars = exprs(TRTEDTM = EXSTDTM),
    order = exprs(EXSTDTM, EXSEQ),
    mode = "last"
  )

## ---- derive lstavldt (last alive evidence) -----------------------------------
# define the "last alive date" as the maximum (latest) date among these sources:
#   (1) last complete vs date with any usable result
#       - require VSDTC has a complete datepart
#       - require VSSTRESN and VSSTRESC are not BOTH missing
#   (2) last complete ae onset date (AESTDTC datepart)
#   (3) last complete ds disposition date (DSSTDTC datepart)
#   (4) last valid treatment administration date (datepart of TRTEDTM)
#
# note: we take dateparts (ymd) for cross-domain comparability.

# (1) last qualifying vital signs date
vs_last <- vs %>%
  filter(
    !is.na(VSDTC) & str_detect(VSDTC, "^\\d{4}-\\d{2}-\\d{2}"),
    !(is.na(VSSTRESN) & is.na(VSSTRESC))
  ) %>%
  mutate(VSDT = ymd(substr(VSDTC, 1, 10))) %>%
  group_by(STUDYID, USUBJID) %>%
  summarise(LAST_VS = max(VSDT, na.rm = TRUE), .groups = "drop")

# (2) last complete AE onset date
ae_last <- ae %>%
  filter(!is.na(AESTDTC) & str_detect(AESTDTC, "^\\d{4}-\\d{2}-\\d{2}")) %>%
  mutate(AESTDT = ymd(substr(AESTDTC, 1, 10))) %>%
  group_by(STUDYID, USUBJID) %>%
  summarise(LAST_AE = max(AESTDT, na.rm = TRUE), .groups = "drop")

# (3) last complete disposition date
ds_last <- ds %>%
  filter(!is.na(DSSTDTC) & str_detect(DSSTDTC, "^\\d{4}-\\d{2}-\\d{2}")) %>%
  mutate(DSSTDT = ymd(substr(DSSTDTC, 1, 10))) %>%
  group_by(STUDYID, USUBJID) %>%
  summarise(LAST_DS = max(DSSTDT, na.rm = TRUE), .groups = "drop")

# combine evidence and compute the maximum per subject
adsl <- adsl %>%
  left_join(vs_last, by = c("STUDYID", "USUBJID")) %>%
  left_join(ae_last, by = c("STUDYID", "USUBJID")) %>%
  left_join(ds_last, by = c("STUDYID", "USUBJID")) %>%
  mutate(
    # convert TRTEDTM datetime to a date for max() comparison with other sources
    LAST_TRT = as.Date(TRTEDTM)
  ) %>%
  rowwise() %>%
  mutate(LSTAVLDT = max(c(LAST_VS, LAST_AE, LAST_DS, LAST_TRT), na.rm = TRUE)) %>%
  ungroup() %>%
  select(-LAST_VS, -LAST_AE, -LAST_DS, -LAST_TRT)

## ---- save outputs ------------------------------------------------------------
# write analysis outputs to a dedicated folder to keep the project tidy
dir.create("output", showWarnings = FALSE)
write.csv(adsl, "output/adsl.csv", row.names = FALSE)
saveRDS(adsl, "output/adsl.rds")

cat("\nadsl created successfully.\n")
cat("subjects:", nrow(adsl), "\n")
cat("saved: output/adsl.csv and output/adsl.rds\n")
cat("\nscript completed without errors.\n")
sink()
