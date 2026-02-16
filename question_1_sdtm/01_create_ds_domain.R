

## ---- Setup ------------------------------------------------------------------
library(sdtm.oak)
library(pharmaverseraw)
library(pharmaversesdtm)
library(dplyr)
library(lubridate)

## ---- Log File ----------------------------------------------------------------
sink("ds_log.txt", split = TRUE)
cat("Running DS domain creation script...\n\n")

## ---- Load Inputs ------------------------------------------------------------
ds_raw   <- pharmaverseraw::ds_raw
dm       <- pharmaversesdtm::dm
study_ct <- read.csv("metadata/sdtm_ct.csv")

cat("Inputs loaded.\n")
cat("ds_raw rows:", nrow(ds_raw), " cols:", ncol(ds_raw), "\n")
cat("dm rows:", nrow(dm), " cols:", ncol(dm), "\n\n")

## ---- Generate OAK ID Variables ----------------------------------------------
ds_raw <- ds_raw %>%
  generate_oak_id_vars(
    pat_var = "PATNUM",
    raw_src = "ds_raw"
  )

cat("OAK ID variables generated.\n\n")

## ---- DSTERM (Derive topic variable) ------------------------------------------------------
ds <- assign_no_ct(
  raw_dat = ds_raw,
  raw_var = "IT.DSTERM",
  tgt_var = "DSTERM",
  id_vars = oak_id_vars()
)

# Override DSTERM where OTHERSP is not blank
ds <- ds %>%
  mutate(
    DSTERM = ifelse(
      !is.na(ds_raw$OTHERSP),
      as.character(ds_raw$OTHERSP),
      DSTERM
    )
  )

cat("DSTERM derived from IT.DSTERM.\n\n")

## ---- DSSTDTC: actual disposition date ---------------------------------------
ds <- ds %>%
  assign_datetime(
    raw_dat = ds_raw,
    raw_var = "IT.DSSTDAT",
    tgt_var = "DSSTDTC",
    raw_fmt = "mm-dd-yyyy",
    id_vars = oak_id_vars()
  )

## ---- DSDTC: collection date+time to ISO8601 ---------------------------------
# combine IT.DSSTDAT and IT.DSTMCOL, with time imputation if time is missing.
ds <- ds %>%
  mutate(
    DSDTC = {
      d <- mdy(ds_raw$DSDTCOL)
      t_raw <- trimws(as.character(ds_raw$DSTMCOL))
      has_t <- !is.na(t_raw) & t_raw != ""
      t <- hm(t_raw)
      
      ifelse(
        !is.na(d) & has_t & !is.na(t),
        paste0(format(d, "%Y-%m-%d"), "T", format(t, "%H:%M")),
        ifelse(!is.na(d), format(d, "%Y-%m-%d"), NA_character_)
      )
    }
  )


## ---- DSDECOD and DSCAT (spec logic) -----------------------------------------
# derive DSDECOD using OTHERSP if not blank, otherwise IT.DSDECOD
ds <- ds %>%
  mutate(
    DSDECOD = ifelse(
      !is.na(ds_raw$OTHERSP) & trimws(as.character(ds_raw$OTHERSP)) != "",
      toupper(as.character(ds_raw$OTHERSP)),
      toupper(as.character(ds_raw$`IT.DSDECOD`))
    )
  )

cat("DSDECOD derived using OTHERSP/IT.DSDECOD logic.\n")

# derive DSCAT based on DSDECOD values (RANDOMIZED, DISPOSITION EVENT, OTHER EVENT) 
ds <- ds %>%
  mutate(
    DSDECOD_CLEAN = toupper(trimws(as.character(ds_raw$`IT.DSDECOD`))),
    
    DSCAT = case_when(
      is.na(DSDECOD_CLEAN) | DSDECOD_CLEAN == "" ~ "OTHER EVENT",
      DSDECOD_CLEAN == "RANDOMIZED" ~ "PROTOCOL MILESTONE",
      TRUE ~ "DISPOSITION EVENT"
    )
  ) %>%
  select(-DSDECOD_CLEAN)

cat("DSCAT derived using IT.DSDECOD == RANDOMIZED rule.\n\n")

# renaming and reformatting variables to match spec and adding core identifiers
ds <- ds %>%
  mutate(
    STUDYID  = as.character(ds_raw$STUDY),
    DOMAIN   = "DS",
    USUBJID  = paste0("01-", ds_raw$PATNUM),
    VISIT    = as.character(ds_raw$INSTANCE)
    # VISITNUM = suppressWarnings(as.numeric(ds_raw$INSTANCE))
  )

# visit and visitnum not explicitly specified how to get in the assessment
# we will use the INSTANCE variable as VISIT for now
# for visitnum we can take from pharmaversesdtm::ds by VISIT

ds_original <- pharmaversesdtm::ds

# Ensure VISIT values match in both datasets (uppercase)
ds <- ds %>%
  mutate(VISIT = toupper(VISIT))

ds <- ds %>%
  left_join(
    ds_original %>% select(VISIT, VISITNUM),
    by = "VISIT",
    relationship = "many-to-many" 
  )

cat("Core identifiers (STUDYID/DOMAIN/USUBJID) added.\n\n")

## ---- Derive DSSEQ -----------------------------------------------------------
ds <- ds %>%
  derive_seq(
    tgt_var  = "DSSEQ",
    rec_vars = c("USUBJID", "DSTERM")
  )

cat("DSSEQ derived.\n\n")

## ---- Derive DSSTDY using DM -------------------------------------------------
refdt_col <- if ("RFXSTDTC" %in% names(dm)) "RFXSTDTC" else "RFSTDTC"
cat("Using DM reference date column for study day:", refdt_col, "\n")

ds <- ds %>%
  derive_study_day(
    sdtm_in       = .,
    dm_domain     = dm,
    tgdt          = "DSSTDTC",
    refdt         = refdt_col,
    study_day_var = "DSSTDY"
  )

cat("DSSTDY derived.\n\n")

## ---- Final variable order ---------------------------------------------------
ds <- ds %>%
  select(
    STUDYID, DOMAIN, USUBJID, DSSEQ,
    DSTERM, DSDECOD, DSCAT,
    VISITNUM, VISIT,
    DSDTC, DSSTDTC, DSSTDY
  )

cat("Final DS dataset assembled with required variables.\n\n")

## ---- Save Outputs -----------------------------------------------------------
write.csv(ds, "output/ds.csv", row.names = FALSE)
saveRDS(ds, "output/ds.rds")

cat("Outputs saved:\n")
cat(" - ds.csv\n")
cat(" - ds.rds\n\n")

cat("DS domain successfully created.\n")
cat("Records:", nrow(ds), "\n")
cat("Columns:", ncol(ds), "\n")

## ---- Close log --------------------------------------------------------------
cat("\nScript completed without errors.\n")
sink()