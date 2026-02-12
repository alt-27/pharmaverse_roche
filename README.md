## pharmaverse_roche
# Roche PD Data Science Assessment

Welcome to my attempt in this assessment. Note that it is still a work in progress and please be patient :)
This repository contains my solutions to the Analytical Data Science Programmer Coding Assessment.

The goal of this assessment is to evaluate practical skills in:
- Working within the Pharmaverse ecosystem
- Building SDTM and ADaM datasets
- Creating regulatory-style Tables, Listings, and Graphs (TLGs)
- Writing clean, reproducible, well-structured R code
- Applying sound problem-solving practices

I’ve organized the repository to make it easy to review, follow, and run.

# Repository Structure
```
├── metadata/
├── question_1_sdtm/
├── question_2_adam/
├── question_3_tlg/
└── README.md
```

Inside each question folder, you’ll find:
- The main R script
- An output/ folder with generated datasets or files
- A log file showing the script runs without errors

I kept everything modular and self-contained so each question can be reviewed independently.

## Question 1 – SDTM DS Domain Creation
Folder: [question_1_sdtm](question_1_sdtm)

Script: `01_create_ds_domain.R`

For this question, I created the SDTM Disposition (DS) domain using:
- `pharmaverseraw::ds_raw`
- Study controlled terminology
- The `{sdtm.oak}` package

I’ve also included a metadata/ folder in this directory that contains the study controlled terminology (`study_ct.csv`) file used for the DS domain creation.

The script loads required libraries, prepares and maps raw values to controlled terminology, applies SDTM structure and naming conventions, and derives the required variables.

I followed SDTM IG guidance and tried to stay aligned with Pharmaverse best practices rather than manually recreating logic that already exists in `{sdtm.oak}`.

Output
- Final DS dataset (CSV) `ds.csv `
- Log file confirming error-free execution `ds_log.txt`

## Question 2 – ADaM ADSL Dataset Creation
Folder: [question_2_adam](question_2_adam)

Script: `create_adsl.R`

For this question, I built the ADSL (Subject-Level Analysis Dataset) using:
- `pharmaversesdtm::dm` as the base
- Supporting SDTM domains (`VS`, `EX`, `DS`, `AE`)
- `{admiral}` functions wherever possible

I structured the derivations step-by-step so it’s easy to follow how each variable was created.

Output
- Final ADSL dataset `adsl.csv`
- Log file confirming successful execution `adsl_log.txt`

## Question 3 – TLG: Adverse Events Reporting
Folder: [question_3_tlg](question_3_tlg)

This section focuses on generating regulatory-style outputs from _ADAE_ and _ADSL_ from pharmaverse.

Log files are included for all scripts to demonstrate error-free execution.

### Part 1 – AE Summary Table
Script: `01_create_ae_summary_table.R`

I created a treatment-emergent AE summary table using {gtsummary}:
- Filtered `TRTEMFL == "Y"`
- Rows: `AESOC` and `AETERM`
- Columns: `ACTARM`
- Cells: Count (n) and Percentage (%)
- Added total column
- Sorted by descending frequency

Output: `ae_summary_table.html`

### Part 2 – Visualizations
Script: `02_create_visualizations.R`

*Plot 1 – AE Severity Distribution*
- Bar chart grouped by treatment arm and factored by AE severity
- Output: `ae_severity_plot.png`

*Plot 2 – Top 10 Most Frequent AEs*
- Based on top incidence rates of `AETERM`
- Added 95% Clopper–Pearson confidence intervals
- Output: `top10_ae_plot.png`

# Next Steps
I’ll be implementing the GenAI Clinical Data Assistant (LLM & LangChain) next to complete the bonus Python portion of the assessment. Please be patient and stay tuned!


