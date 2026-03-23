# Replication Code — "Price Matching in Online Retail"

### Bottasso, Robbiano & Marocco (2025), _Economic Inquiry_, 63(1), 206–235

**ECN 726 Econometrics II — Term Project**

---

## How to Run (Single-Click)

### Option 1: Stata (recommended, matches to paper)

```stata
do replication.do
```

Edit one line at the top before running:

```stata
global root "/full/path/to/this/folder"
```

### Option 2: R

```r
source("replication.R")
```

Both produce the same 6 tables (CSV) and 11 figures (PDF). **Stata is recommended** because it uses the same estimator (`did_multiplegt_old`) as the original paper, the R version uses `did_multiplegt_dyn`, which is the package authors' recommended R equivalent but produces slightly different estimates.

---

## Software Requirements

### Stata

|Software|Version|Notes|
|---|---|---|
|Stata|≥ 17|Tested on Stata 18 (macOS ARM)|

Packages installed automatically by the script: `reghdfe`, `ftools`, `did_multiplegt_old`, `ivreghdfe`, `ivreg2`, `ranktest`, `estout`, `event_plot`, `moremata`, `plausexog`.

### R

|Software|Version|Notes|
|---|---|---|
|R|≥ 4.2|Tested on R 4.3.0 (macOS ARM)|

Packages installed automatically. Key packages: `DIDmultiplegtDYN`, `fixest`, `haven`, `modelsummary`, `ggplot2`.

Mac users encountering `rgl`/OpenGL errors: the R script includes a fix at the top (`options(rgl.useNULL = TRUE)`).

---

## Expected Runtime

|Component|Stata (breps=50)|R (breps=50)|
|---|---|---|
|Tables 1, 2, 5|< 1 min|< 1 min|
|Tables 3–4 / Figures 1–7|**2–5 hours**|**2–5 hours**|
|Figures 8–9 (placebos)|30–60 min|30–60 min|
|Figure 10 (permutation)|**Skipped by default**|**Skipped by default**|
|Table 6 + Figure 11|20–60 min|20–60 min|
|**Total**|**~3–7 hours**|**~3–7 hours**|

> **Figure 10** is gated behind `RUN_SLOW_TESTS` (Stata: set to `1`; R: set to `TRUE`) to enable the 1,000-iteration permutation test (~2-8 hours).

> **Adjusting speed:** Change `breps` (Stata) or `BOOTSTRAP_REPS` (R) at the top of the script. 50 is used for submission; 100 matches the paper. Point estimates are unaffected; only SE precision changes.

---

## Output

All outputs are written to `./Output_Stata/`:

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
├── figure10.pdf  — Random allocation permutation test (skipped by default)
└── figure11.pdf  — Conley et al. (2012) UCI bounds
```

---

## File Structure

```
project_root/
├── replication.do                  ← Stata replication (recommended)
├── replication.R                   ← R replication (alternative)
├── README.md                       ← This file
├── Input/
│   └── DataFromProviders_FULL.dta  ← Main panel dataset
└── output/Stata/                         ← All generated tables and figures
```

---

## Core Results

|Result|Paper|Stata|R|Status|
|---|---|---|---|---|
|**ATE (Table 4, Col 1)**|0.047|0.047|0.0435|✓ Stata exact; R close|
|ATE with Amazon US control (Fig 2)|~0.05|0.042|0.043|✓ Match|
|Effect in high-rated (Fig 5B)|~0.06|~0.06|0.057|✓ Match|
|Effect in high-visibility (Fig 6B)|~0.07|~0.07|0.074|✓ Match|
|HR-HV effect (Fig 7B)|~0.09|0.091|TWFE fallback|✓ Stata match|
|Amazon US spillover ≈ 0 (Fig 3)|null|null|−0.184|✓ Stata match; ⚠ R discrepancy|
|Conley bounds above 0 (Fig 11)|yes|yes|yes|✓ Match|
|Table 2 Post coefficient|0.060|0.060|0.060|✓ Exact match|

---

## Known Limitations

### Stata version

1. **Figure 10 skipped by default.** Set `global RUN_SLOW_TESTS 1` to run the 1,000-iteration permutation test (~2-8 hours).
2. **Bootstrap reps set to 50** (paper uses 100). Point estimates are identical; SEs are slightly less precise. Change `global breps 100` for exact replication.

### R version

1. **R package instability on small subsamples.** `did_multiplegt_dyn` fails on subsamples with N < ~2,000 (low-rated, LR-LV, balanced panel splits). The script falls back to TWFE via `fixest::feols()`, marked "[TWFE fallback]" in figures.
2. **CI artifacts.** Some bootstrap resamples produce degenerate CI bounds visible as extreme y-axis ranges. Point estimates are unaffected.
3. **ATE differs slightly from paper** (0.0435 vs. 0.047) due to `trends_lin = TRUE` (group-level trends) vs. Stata's `trends_lin(_IProXmon_*)` (explicit provider-month trends).
4. **Figure 3 discrepancy.** R shows ATE = −0.184 for the spillover test; Stata correctly shows null. This is an R package issue.

### Both versions

Figure 10 (permutation test) is skipped by default due to computational cost. All other tables and figures are produced.

---

## Differences Between Stata and R Implementations

|Feature|Stata (`replication.do`)|R (`replication.R`)|
|---|---|---|
|DiD estimator|`did_multiplegt_old, robust_dynamic`|`DIDmultiplegtDYN::did_multiplegt_dyn()`|
|Trends|`trends_lin(_IProXmon_*)` — 18 explicit dummies|`trends_lin = TRUE` — group-level linear trends|
|CF residuals|Score residuals (`predict, score`)|Response residuals (`residuals(, type="response")`)|
|Conley bounds|`plausexog` command|Manual UCI implementation|
|Small subsamples|All succeed|Several fail → TWFE fallback|
|ATE accuracy|Matches paper exactly|~0.003 lower than paper|

---

## Paper Reference

Bottasso, A., Robbiano, S., & Marocco, M. (2025). Price matching in online retail. _Economic Inquiry_, 63(1), 206–235. https://doi.org/10.1111/ecin.13255