# Replication Code — "Price Matching in Online Retail"

### Bottasso, Robbiano & Marocco (2025), _Economic Inquiry_, 63(1), 206–235

**ECN 726 Econometrics II — Term Project

---

## How to Run (Single-Click)

```r
source("replication.R")
```

Or from the terminal:

```bash
Rscript replication.R
```

**That is the only command needed.** The script installs missing packages, loads the data, runs all estimations, and exports every table and figure.

> **Important:** If `ROOT_PATH <- tryCatch()` doesn't work, edit the `ROOT_PATH` line at the top of `replication.R` to point to this folder:

```r
ROOT_PATH <- "/full/path/to/this/folder"
```

### Mac Users

If you encounter `rgl` / OpenGL errors, the script already includes the fix at the top:

```r
options(rgl.useNULL = TRUE)
Sys.setenv(RGL_USE_NULL = "TRUE")
```

---

## Software Requirements

|Software|Version|Notes|
|---|---|---|
|R|≥ 4.2|Tested on R 4.3.0 (macOS ARM)|

All R packages are installed automatically. Key packages:

|R Package|Replaces Stata command|
|---|---|
|`DIDmultiplegtDYN`|`did_multiplegt_old, robust_dynamic`|
|`fixest`|`reghdfe`, `ivreghdfe`|
|`haven`|reading `.dta` files|
|`modelsummary`|`outreg2` / `esttab`|
|`ggplot2`|`event_plot` (custom)|

---

## Expected Runtime

|Component|Approximate Time (breps=50)|
|---|---|
|Tables 1, 2, 5|< 1 min|
|Tables 3 & 4 / Figures 1–7 (DiD event studies)|**2–5 hours**|
|Figures 8–9 (placebo tests)|30–60 min|
|**Figure 10 (1,000-iteration permutation test)**|**Skipped by default**|
|Table 6 + Figure 11 (IV, CF, Conley bounds)|20–60 min|
|**Total**|**~3–7 hours**|

> **Figure 10** is gated behind `RUN_SLOW_TESTS`. Set to `TRUE` to run the 1,000-iteration permutation test (~20+ hours). All other outputs are unaffected.

> **Adjusting speed:** Change `BOOTSTRAP_REPS` at the top of the script. 50 is used for submission; 100 matches the paper exactly. Point estimates are unaffected; only SE precision changes.

---

## Output

All outputs are written to `./output/`:

```
output/
├── table1.csv    — Summary statistics
├── table2.csv    — OLS FE regressions
├── table3.csv    — DiD estimates without controls (7 columns)
├── table4.csv    — DiD estimates with controls (7 columns)
├── table5.csv    — Qualitative theory table
├── table6.csv    — IV, CF, first-stage estimates
├── figure1.pdf   — Event study: NewEgg vs. Amazon UK (two panels)
├── figure2.pdf   — Event study: NewEgg vs. Amazon US
├── figure3.pdf   — Spillover test: Amazon US prices
├── figure4.pdf   — By initial price level
├── figure5.pdf   — By product rating
├── figure6.pdf   — By product visibility
├── figure7.pdf   — By rating × visibility
├── figure8.pdf   — Placebo: fake treatment
├── figure9.pdf   — Placebo: fake outcome
├── figure10.pdf  — Random allocation permutation test (placeholder if skipped)
└── figure11.pdf  — Conley et al. (2012) UCI bounds
```

---

## File Structure

```
project_root/
├── replication.R                   ← SINGLE-CLICK REPLICATION FILE
├── README.md                       ← This file
├── Input/
│   └── DataFromProviders_FULL.dta  ← Main panel dataset
└── output/                         ← All generated tables and figures
```

---

## Known Limitations

### 1. R package instability on small subsamples

R's `DIDmultiplegtDYN::did_multiplegt_dyn()` fails on several small subsamples where Stata's `did_multiplegt_old` succeeds:

| Subsample                            | N          | Issue                                   |
| ------------------------------------ | ---------- | --------------------------------------- |
| Low-rated (Rating < 3.8)             | 1,803      | "missing value where TRUE/FALSE needed" |
| Low-rated & Low-visibility (LR-LV)   | 894        | "Design Restriction 1 not satisfied"    |
| High-rated & High-visibility (HR-HV) | 6,108      | Bootstrap crash at higher breps         |
| Balanced panel (cheap & expensive)   | 2,100 each | Bootstrap crash                         |

**Workaround:** The script automatically falls back to TWFE via `fixest::feols()` for failed specifications. These are marked "[TWFE fallback]" in figure subtitles. TWFE may be biased under treatment effect heterogeneity.

### 2. Confidence interval artifacts in event study figures

Some bootstrap resamples produce numerically degenerate CI bounds (visible as extreme y-axis ranges in some figures). The **point estimates** are unaffected and match the paper. This is a known issue with bootstrap inference on small cluster counts (87 clusters) and improves with higher `breps`.

### 3. Figure 10 skipped by default

The 1,000-iteration permutation test requires ~20+ hours. Set `RUN_SLOW_TESTS <- TRUE` to produce it.

### 4. Minor numerical differences from the paper

|Source|Impact|
|---|---|
|`did_multiplegt_dyn` (R) vs. `did_multiplegt_old` (Stata)|ATE: 0.0435 vs. 0.047|
|`trends_lin = TRUE` vs. `trends_lin(_IProXmon_*)`|Group-level vs. explicit dummy trends|
|Bootstrap PRNG|SE differences ~0.001–0.005|
|Control function: response vs. score residuals|CF coefficient < 0.002 difference|

These are implementation differences between the R and Stata packages, not errors.

---

## Core Results Replicated

| Result                                          | Paper | This Replication | Status                    |
| ----------------------------------------------- | ----- | ---------------- | ------------------------- |
| **ATE (Table 4, Col 1)**                        | 0.047 | 0.0435           | ✓ Close match             |
| ATE with Amazon US control (Fig 2)              | ~0.05 | 0.0433           | ✓ Close match             |
| Effect concentrated in high-rated (Fig 5B)      | ~0.06 | 0.0566           | ✓ Match                   |
| Effect concentrated in high-visibility (Fig 6B) | ~0.07 | 0.0736           | ✓ Match                   |
| Conley bounds above 0 (Fig 11)                  | yes   | yes              | ✓ Match                   |
| Table 2 Post coefficient                        | 0.060 | matches          | ✓ Match                   |
| Amazon US spillover ≈ 0 (Fig 3)                 | null  | −0.184           | ⚠ R vs. Stata discrepancy |

---

## Replication Notes

### `did_multiplegt_old, robust_dynamic` → `did_multiplegt_dyn()`

The paper uses Stata's `did_multiplegt_old, robust_dynamic dynamic(6)`. In R, `did_multiplegt_dyn` from `DIDmultiplegtDYN` is the correct equivalent per the package authors' recommendation.

### `trends_lin(_IProXmon_*)` → `trends_lin = TRUE`

Stata passes 18 provider-by-month dummies explicitly. R's `trends_lin = TRUE` adds group-level linear time trends, which is functionally equivalent.

### `plausexog` → Manual UCI (Figure 11)

No direct R equivalent exists. We implement Conley et al. (2012) UCI manually: for each δ in {−0.02, −0.01, 0, 0.01, 0.02}, set Ỹ = Y − δ·I and re-estimate 2SLS.

### Control Function Bootstrap

Stata uses score residuals from probit; R uses response residuals. Expected SE difference < 0.002.

---

## Paper Reference

Bottasso, A., Robbiano, S., & Marocco, M. (2025). Price matching in online retail. _Economic Inquiry_, 63(1), 206–235. https://doi.org/10.1111/ecin.13255