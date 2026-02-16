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
# DM domain is used as the basis for ADSL
adsl <- dm %>%
  select(-DOMAIN)

# start from one record per subject (dm) and derive baseline analysis flags/groups.
adsl <- adsl %>%
  mutate(
    # ITTFL: "y" if non-missing treatment arm assignment (ARM), otherwise "n"
    ITTFL = if_else(!is.na(ARM), "Y", "N"),
    # bucket AGE into <18, 18-50, >50
    AGEGR9 = case_when(
      is.na(AGE) ~ NA_character_,
      AGE < 18 ~ "<18",
      AGE >= 18 & AGE <= 50 ~ "18 - 50",
      AGE > 50 ~ ">50"
    ),
    # bucket AGEGR9 into 1 2 and 3
    AGEGR9N = case_when(
      AGEGR9 == "<18" ~ 1,
      AGEGR9 == "18 - 50" ~ 2,
      AGEGR9 == ">50" ~ 3,
      TRUE ~ NA_real_
    )
  )

## ---- derive exposure datetimes from ex ---------------------------------------
# converts iso8601 character datetimes (EXSTDTC/EXENDTC) into datetime and imputation flags
ex_ext <- ex %>%
  derive_vars_dtm(
    dtc = EXSTDTC,
    new_vars_prefix = "EXST",
    time_imputation = "first", # start of day (00:00:00)
    ignore_seconds_flag = TRUE # ignore missing seconds if hours and minutes (YYYY-MM-DDThh:mm)
  ) %>%
  derive_vars_dtm(
    dtc = EXENDTC,
    new_vars_prefix = "EXEN",
    time_imputation = "last", # end of day (23:59:59)
    ignore_seconds_flag = TRUE
  ) 

adsl <- adsl %>%
  derive_vars_merged(
    dataset_add = ex_ext,
    # Dose validity: EXDOSE > 0 OR EXDOSE == 0 AND EXTRT contains "placebo" (case-insensitive)
    filter_add = (EXDOSE > 0 |
                    (EXDOSE == 0 &
                       str_detect(EXTRT, "PLACEBO"))) & !is.na(EXSTDTM),
    new_vars = exprs(TRTSDTM = EXSTDTM, TRTSTMF = EXSTTMF),
    order = exprs(EXSTDTM, EXSEQ),
    mode = "first",
    by_vars = exprs(STUDYID, USUBJID)
  ) %>%
  derive_vars_merged(
    dataset_add = ex_ext,
    filter_add = (EXDOSE > 0 |
                    (EXDOSE == 0 &
                       str_detect(EXTRT, "PLACEBO"))) & !is.na(EXENDTM),
    new_vars = exprs(TRTEDTM = EXENDTM, TRTETMF = EXENTMF),
    order = exprs(EXENDTM, EXSEQ),
    mode = "last",
    by_vars = exprs(STUDYID, USUBJID)
  )

# derive date variables for TRTSDT and TRTEDT
adsl <- adsl %>%
  derive_vars_dtm_to_dt(source_vars = exprs(TRTSDTM, TRTEDTM))


## ---- derive lstavldt (last alive evidence) -----------------------------------
adsl <- adsl %>%
  derive_vars_extreme_event(
    by_vars = exprs(STUDYID, USUBJID),
    
    events = list(
      # (1) Last complete VS date with a valid test result
      event(
        dataset_name = "vs",
        order = exprs(VSDTC, VSSEQ),
        condition =
          !is.na(VSDTC) &
          # valid test result: not both missing
          !(is.na(VSSTRESN) & is.na(VSSTRESC)),
        set_values_to = exprs(
          LSTAVLDT = convert_dtc_to_dt(VSDTC, highest_imputation = "D"), # datepart present & complete
          seq = VSSEQ
        )
      ),
      
      # (2) Last complete AE onset date
      event(
        dataset_name = "ae",
        order = exprs(AESTDTC, AESEQ),
        condition = !is.na(AESTDTC),
        set_values_to = exprs(
          LSTAVLDT = convert_dtc_to_dt(AESTDTC, highest_imputation = "M"), 
          # highest imputation = M to avoid omitting cases where date is only a year
        )
      ),
      
      # (3) Last complete disposition date
      event(
        dataset_name = "ds",
        order = exprs(DSSTDTC, DSSEQ),
        condition = !is.na(DSSTDTC),
        set_values_to = exprs(
          LSTAVLDT = convert_dtc_to_dt(DSSTDTC, highest_imputation = "D"),
          seq = DSSEQ
        )
      ),
      
      # (4) Last date of treatment administration with valid dose
      # Uses ADSL.TRTEDTM which filtered valid dose records
      event(
        dataset_name = "adsl",
        condition = !is.na(TRTEDT),
        set_values_to = exprs(LSTAVLDT = TRTEDT, seq = 0)
      )
    ),
    
    source_datasets = list(vs = vs, ae = ae, ds = ds, adsl = adsl),
    tmp_event_nr_var = event_nr,
    # order so the "last" event is the max date (then tie-break)
    order = exprs(LSTAVLDT, seq, event_nr),
    mode = "last",
    new_vars = exprs(LSTAVLDT)
  )

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
