# question_2_adam/01_create_adsl.R
# Create ADSL from pharmaversesdtm domains per provided rules

library(pharmaversesdtm)
library(admiral)
library(dplyr)
library(lubridate)
library(stringr)

sink("adsl_log.txt", split = TRUE)
cat("Running ADSL creation script...\n\n")

#--------------------------------------------------------------------
# 1) Load SDTM input data and convert SAS-style blanks ("") to NA
#--------------------------------------------------------------------
dm <- convert_blanks_to_na(pharmaversesdtm::dm)
ex <- convert_blanks_to_na(pharmaversesdtm::ex)
vs <- convert_blanks_to_na(pharmaversesdtm::vs)
ae <- convert_blanks_to_na(pharmaversesdtm::ae)
ds <- convert_blanks_to_na(pharmaversesdtm::ds)

cat("Inputs loaded.\n")
cat("DM:", nrow(dm), "subjects\n\n")

#--------------------------------------------------------------------
# 2) Start ADSL from DM and derive ITTFL + AGEGR9/AGEGR9N
#   - ITTFL = "Y" if ARM not missing else "N"
#   - AGEGR9 bins: <18, 18-50, >50 with numeric 1,2,3
#--------------------------------------------------------------------
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

#--------------------------------------------------------------------
# 3) Create exposure datetime variables from EXSTDTC / EXENDTC
#   - Impute missing time to 00:00:00 for EXSTDTC (time_imputation="first")
#   - Create EXSTDTM and EXSTTMF (time imputation flag)
#--------------------------------------------------------------------
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
  # Spec detail: if only seconds are missing (YYYY-MM-DDThh:mm), do NOT set flag
  mutate(
    EXSTTMF = if_else(
      !is.na(EXSTDTC) & str_detect(EXSTDTC, "T\\d{2}:\\d{2}$"),
      NA_character_,
      EXSTTMF
    )
  )

#--------------------------------------------------------------------
# 4) Keep only VALID exposure records + complete datepart
#   Valid dose definition:
#     EXDOSE > 0 OR (EXDOSE == 0 and EXTRT contains 'PLACEBO')
#   Also require complete datepart of EXSTDTC (YYYY-MM-DD present)
#--------------------------------------------------------------------
ex_valid <- ex_ext %>%
  filter(
    (EXDOSE > 0 |
       (EXDOSE == 0 & str_detect(toupper(coalesce(EXTRT, "")), "PLACEBO"))) &
      !is.na(EXSTDTM) &
      !is.na(EXSTDTC) &
      str_detect(EXSTDTC, "^\\d{4}-\\d{2}-\\d{2}")
  )

#--------------------------------------------------------------------
# 5) TRTSDTM / TRTSTMF = first valid EXSTDTM (sorted by datetime)
#    TRTEDTM          = last  valid EXSTDTM (used later for LSTAVLDT rule #4)
#--------------------------------------------------------------------
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

#--------------------------------------------------------------------
# 6) LSTAVLDT = max of last documented "alive" evidence:
#   (1) last complete VS date with valid result (VSSTRESN and VSSTRESC not both missing)
#   (2) last complete AE onset date (AESTDTC datepart)
#   (3) last complete DS disposition date (DSSTDTC datepart)
#   (4) last valid treatment administration date (datepart of TRTEDTM)
#--------------------------------------------------------------------
vs_last <- vs %>%
  filter(
    !is.na(VSDTC) & str_detect(VSDTC, "^\\d{4}-\\d{2}-\\d{2}"),
    !(is.na(VSSTRESN) & is.na(VSSTRESC))
  ) %>%
  mutate(VSDT = ymd(substr(VSDTC, 1, 10))) %>%
  group_by(STUDYID, USUBJID) %>%
  summarise(LAST_VS = max(VSDT, na.rm = TRUE), .groups = "drop")

ae_last <- ae %>%
  filter(!is.na(AESTDTC) & str_detect(AESTDTC, "^\\d{4}-\\d{2}-\\d{2}")) %>%
  mutate(AESTDT = ymd(substr(AESTDTC, 1, 10))) %>%
  group_by(STUDYID, USUBJID) %>%
  summarise(LAST_AE = max(AESTDT, na.rm = TRUE), .groups = "drop")

ds_last <- ds %>%
  filter(!is.na(DSSTDTC) & str_detect(DSSTDTC, "^\\d{4}-\\d{2}-\\d{2}")) %>%
  mutate(DSSTDT = ymd(substr(DSSTDTC, 1, 10))) %>%
  group_by(STUDYID, USUBJID) %>%
  summarise(LAST_DS = max(DSSTDT, na.rm = TRUE), .groups = "drop")

adsl <- adsl %>%
  left_join(vs_last, by = c("STUDYID", "USUBJID")) %>%
  left_join(ae_last, by = c("STUDYID", "USUBJID")) %>%
  left_join(ds_last, by = c("STUDYID", "USUBJID")) %>%
  mutate(LAST_TRT = as.Date(TRTEDTM)) %>%
  rowwise() %>%
  mutate(LSTAVLDT = max(c(LAST_VS, LAST_AE, LAST_DS, LAST_TRT), na.rm = TRUE)) %>%
  ungroup() %>%
  select(-LAST_VS, -LAST_AE, -LAST_DS, -LAST_TRT)

#--------------------------------------------------------------------
# 7) Save outputs
#--------------------------------------------------------------------
dir.create("output", showWarnings = FALSE)
write.csv(adsl, "output/adsl.csv", row.names = FALSE)
saveRDS(adsl, "output/adsl.rds")

cat("\nADSL created successfully.\n")
cat("Subjects:", nrow(adsl), "\n")
cat("Saved: output/adsl.csv and output/adsl.rds\n")
cat("\nScript completed without errors.\n")
sink()
