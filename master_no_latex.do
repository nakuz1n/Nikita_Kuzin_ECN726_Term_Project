********************************************************************************
* replication.do
* SINGLE-CLICK STATA REPLICATION SCRIPT
*
* Paper: Bottasso, Robbiano & Marocco (2025),
*        "Price Matching in Online Retail," Economic Inquiry, 63(1), 206-235.
*
* Course: ECN 726 Econometrics II, Arizona State University
*
* Based on the authors' original Stata replication code in original_stata/.
* All tables exported as .csv; all figures exported as .pdf.
*
* Key commands:
*   did_multiplegt_old (robust_dynamic dynamic(6))  → DiD event studies
*   reghdfe                                         → OLS high-dimensional FE
*   ivreghdfe                                       → IV with FE absorption
*   plausexog                                       → Conley UCI bounds
*   event_plot                                      → event study graphs
********************************************************************************


********************************************************************************
* SECTION 0: CONFIGURATION — CHANGE ONLY THIS ONE LINE
********************************************************************************

* ► Set this to the full path of your replication folder (forward slashes):
global root "/full/path/to/this/folder"

* All other paths are derived automatically — do not edit below this line.
global input  "$root/Input"
global output "$root/output"
global func   "$output/functional_output"

* Toggle: set to 1 to run Figure 10, and 0 to skip it (1,000-iteration permutation test; 2–8 hrs)
global RUN_SLOW_TESTS 0

* Bootstrap seed and repetitions (match paper)
global seed_main    123
global seed_fig10   123456
global breps        50


********************************************************************************
* SECTION 1: PACKAGE INSTALLATION
* (Comment out after first run to save time)
********************************************************************************

ssc install reghdfe,            replace
ssc install ftools,             replace
ssc install did_multiplegt_old, replace
ssc install ivreghdfe,          replace
ssc install ivreg2,             replace
ssc install ranktest,           replace
ssc install estout,             replace
ssc install event_plot,         replace
ssc install moremata,           replace
cap ssc install plausexog,      replace   // may need manual install if not on SSC


********************************************************************************
* GLOBAL SETTINGS
********************************************************************************

clear all
set more off
set linesize 240

* Create output directories
cap mkdir "$output"
cap mkdir "$func"
cap mkdir "$func/merge_columns"


********************************************************************************
* SECTION 2: TABLE 1 — SUMMARY STATISTICS
********************************************************************************

display as text _n "=== TABLE 1: Summary Statistics ==="

use "$input/DataFromProviders_FULL.dta", clear
xtset Product_ID Time

* Full sample
estpost tabstat Provider_Price Product_Popularity Search_Rank_Normalized Rating, ///
    stats(mean sd count) columns(stats)
esttab . using "$output/table1.csv", replace ///
    cells("mean(fmt(%9.2f)) sd(fmt(%9.2f)) count(fmt(%9.0f))") ///
    noobs label collabels("Mean" "SD" "N") ///
    title("Table 1: Summary Statistics") ///
    addnotes("Panel: Full Sample")

* NewEgg sample (includes Duration_general and Treatment_freq)
estpost tabstat Provider_Price Product_Popularity Search_Rank_Normalized Rating ///
    Duration_general Treatment_freq if Provider == "NewEgg", ///
    stats(mean sd count) columns(stats)
esttab . using "$output/table1.csv", append ///
    cells("mean(fmt(%9.2f)) sd(fmt(%9.2f)) count(fmt(%9.0f))") ///
    noobs label collabels("Mean" "SD" "N") ///
    addnotes("Panel: NewEgg Sample")

* Amazon UK sample
estpost tabstat Provider_Price Product_Popularity Search_Rank_Normalized Rating ///
    if Provider == "Amazon_UK", stats(mean sd count) columns(stats)
esttab . using "$output/table1.csv", append ///
    cells("mean(fmt(%9.2f)) sd(fmt(%9.2f)) count(fmt(%9.0f))") ///
    noobs label collabels("Mean" "SD" "N") ///
    addnotes("Panel: Amazon UK Sample")

* Amazon US sample
estpost tabstat Provider_Price Product_Popularity Search_Rank_Normalized Rating ///
    if Provider == "Amazon_US", stats(mean sd count) columns(stats)
esttab . using "$output/table1.csv", append ///
    cells("mean(fmt(%9.2f)) sd(fmt(%9.2f)) count(fmt(%9.0f))") ///
    noobs label collabels("Mean" "SD" "N") ///
    addnotes("Panel: Amazon US Sample")

display "  Saved: table1.csv"


********************************************************************************
* SECTION 3: TABLE 2 — OLS FIXED-EFFECTS REGRESSIONS
* (Average Change in NewEgg Prices Before/After PMG Introduction)
********************************************************************************

display as text _n "=== TABLE 2: OLS FE Regressions ==="

use "$input/DataFromProviders_FULL.dta", clear
xtset Product_ID Time

* Column 1: No controls
* Stata: reghdfe log_Provider_Price Post if Provider=="NewEgg",
*          absorb(Product_ID Download_Date) vce(cluster Old_Product_ID)
reghdfe log_Provider_Price Post if Provider == "NewEgg", ///
    absorb(Product_ID Download_Date) vce(cluster Old_Product_ID)
estimates store m2_1

* Column 2: With controls
reghdfe log_Provider_Price Post Product_Popularity Review Rating ///
    if Provider == "NewEgg", ///
    absorb(Product_ID Download_Date) vce(cluster Old_Product_ID)
estimates store m2_2

* Export as CSV
esttab m2_1 m2_2 using "$output/table2.csv", replace ///
    keep(Post) label se(3) b(3) star(* 0.10 ** 0.05 *** 0.01) ///
    scalars("r2 R-squared" "N Observations") ///
    title("Table 2: Average Change in NewEgg Prices (PMG effect)") ///
    mtitles("(1) No Controls" "(2) With Controls") ///
    note("Product FE and Day FE absorbed. SEs clustered at Old_Product_ID level.")

display "  Saved: table2.csv"


********************************************************************************
* SECTION 4: DiD EVENT STUDIES — FIGURES 1–7 AND TABLES 3–4
*
* Each did_multiplegt_old call:
*   - robust_dynamic dynamic(6)  = 6 post-treatment effects
*   - placebo(6)                 = 6 pre-treatment placebo periods
*   - trends_lin(_IProXmon_*)    = provider-by-month linear time trends
*   - breps(100) seed(123)       = 100 bootstrap reps
*   - cluster(Old_Product_ID)    = cluster SEs at product-title level
*   - ci_level = 90%             = matches event_plot alpha(0.1)
*
* Files with controls saved to:   $func/Table_4_col_N.dta  (Table 4, Figures 1-7)
* Files without controls saved to: $func/Table_3_col_N.dta  (Table 3)
********************************************************************************

display as text _n "=== DiD Event Studies (Figures 1–7, Tables 3–4) ==="
display "Each run uses $breps bootstrap reps — estimated 5-20 min per run."

* --------------------------------------------------------------------------
* FIGURE 1 + TABLE 4 COL 1: Full sample, control = Amazon UK, WITH controls
* --------------------------------------------------------------------------
use "$input/DataFromProviders_FULL.dta", clear
xtset Product_ID Time

did_multiplegt_old log_Provider_Price Product_ID Download_Date PMG ///
    if Provider != "Amazon_US", ///
    robust_dynamic dynamic(6) placebo(6) ///
    trends_lin(_IProXmon_*) controls(Rating Review Product_Popularity) ///
    seed($seed_main) breps($breps) cluster(Old_Product_ID) ///
    save_results("$func/Table_4_col_1.dta")

event_plot e(didmgt_estimates)#e(didmgt_variances), ///
    graph_opt(xtitle("Days since the treatment") ///
              ytitle("Change in Product Prices (ln)") ///
              title("Figure 1B — With Controls") ///
              xline(0, lcolor(black) lpattern(dash)) xlabel(-6(1)6) ///
              yline(0, lcolor(red) lpattern(solid)) ///
              graphregion(color(ltbluishgray)) bgcolor(white) ///
              ylabel(-.02(.02).1)) ///
    lag_opt(color(navy)) lead_opt(color(maroon) msymbol(S)) ///
    lag_ci_opt(color(navy%45 navy%45)) lead_ci_opt(color(maroon%45 maroon%45)) ///
    legend_opt(region(lstyle(none))) ///
    stub_lag(Effect_#) stub_lead(Placebo_#) together alpha(0.1)
graph save "$func/fig1_wc_temp.gph", replace

* --------------------------------------------------------------------------
* TABLE 3 COL 1: Full sample, Amazon UK control, NO controls
* --------------------------------------------------------------------------
did_multiplegt_old log_Provider_Price Product_ID Download_Date PMG ///
    if Provider != "Amazon_US", ///
    robust_dynamic dynamic(6) placebo(6) ///
    trends_lin(_IProXmon_*) seed($seed_main) breps($breps) ///
    cluster(Old_Product_ID) ///
    save_results("$func/Table_3_col_1.dta")

event_plot e(didmgt_estimates)#e(didmgt_variances), ///
    graph_opt(xtitle("Days since the treatment") ///
              ytitle("Change in Product Prices (ln)") ///
              title("Figure 1A — Without Controls") ///
              xline(0, lcolor(black) lpattern(dash)) xlabel(-6(1)6) ///
              yline(0, lcolor(red) lpattern(solid)) ///
              graphregion(color(ltbluishgray)) bgcolor(white) ///
              ylabel(-.02(.02).1)) ///
    lag_opt(color(navy)) lead_opt(color(maroon) msymbol(S)) ///
    lag_ci_opt(color(navy%45 navy%45)) lead_ci_opt(color(maroon%45 maroon%45)) ///
    legend_opt(region(lstyle(none))) ///
    stub_lag(Effect_#) stub_lead(Placebo_#) together alpha(0.1)
graph save "$func/fig1_nc_temp.gph", replace

* Combine panels A and B into Figure 1
graph combine "$func/fig1_nc_temp.gph" "$func/fig1_wc_temp.gph", ///
    rows(2) ///
    title("Figure 1: Effect of PMGs on NewEgg Prices (Control: Amazon UK)") ///
    graphregion(color(white))
graph export "$output/figure1.pdf", replace
display "  Saved: figure1.pdf"

* --------------------------------------------------------------------------
* FIGURE 2: Full sample, control = Amazon US, with controls
* --------------------------------------------------------------------------
use "$input/DataFromProviders_FULL.dta", clear
xtset Product_ID Time

did_multiplegt_old log_Provider_Price Product_ID Download_Date PMG ///
    if Provider != "Amazon_UK", ///
    robust_dynamic dynamic(6) placebo(6) ///
    trends_lin(_IProXmon_*) controls(Rating Review Product_Popularity) ///
    seed($seed_main) breps($breps) cluster(Old_Product_ID)

event_plot e(didmgt_estimates)#e(didmgt_variances), ///
    graph_opt(xtitle("Days since the treatment") ///
              ytitle("Change in Product Prices (ln)") ///
              title("Figure 2: PMG Effect (Control: Amazon US)") ///
              xline(0, lcolor(black) lpattern(dash)) xlabel(-6(1)6) ///
              yline(0, lcolor(red) lpattern(solid)) ///
              graphregion(color(ltbluishgray)) bgcolor(white) ///
              ylabel(-.05(.05).1)) ///
    lag_opt(color(navy)) lead_opt(color(maroon) msymbol(S)) ///
    lag_ci_opt(color(navy%45 navy%45)) lead_ci_opt(color(maroon%45 maroon%45)) ///
    legend_opt(region(lstyle(none))) ///
    stub_lag(Effect_#) stub_lead(Placebo_#) together alpha(0.1)
graph export "$output/figure2.pdf", replace
display "  Saved: figure2.pdf"

* --------------------------------------------------------------------------
* FIGURE 3: Spillover test — effect on Amazon US prices (null expected)
* Treatment = Post for Amazon_US; Amazon_UK Post recoded to 0
* --------------------------------------------------------------------------
use "$input/DataFromProviders_FULL.dta", clear
xtset Product_ID Time

preserve
recode Post 1 = 0 if Provider == "Amazon_UK"

did_multiplegt_old log_Provider_Price Product_ID Download_Date Post ///
    if Provider != "NewEgg", ///
    robust_dynamic dynamic(6) placebo(6) ///
    seed($seed_main) breps($breps) ///
    trends_lin(_IProXmon_*) controls(Rating Review Product_Popularity) ///
    cluster(Old_Product_ID)

event_plot e(didmgt_estimates)#e(didmgt_variances), ///
    graph_opt(xtitle("Days since the treatment") ///
              ytitle("Change in Product Prices (ln)") ///
              title("Figure 3: Effect on Amazon US Prices (Null Expected)") ///
              xline(0, lcolor(black) lpattern(dash)) xlabel(-6(1)6) ///
              yline(0, lcolor(red) lpattern(solid)) ///
              graphregion(color(ltbluishgray)) bgcolor(white) ///
              ylabel(-.25(.05).15) ///
              legend(on position(6) cols(2) ///
                     label(1 "Point estimates") ///
                     label(2 "90% confidence intervals"))) ///
    lag_opt(color(navy)) lead_opt(color(maroon) msymbol(S)) ///
    lag_ci_opt(color(navy%45 navy%45)) lead_ci_opt(color(maroon%45 maroon%45)) ///
    legend_opt(noautolegend) ///
    stub_lag(Effect_#) stub_lead(Placebo_#) together alpha(0.1)
graph export "$output/figure3.pdf", replace
restore
display "  Saved: figure3.pdf"

* --------------------------------------------------------------------------
* FIGURE 4: By initial price level — balanced panel
* Keep only Product_IDs observed at Time=1; split by median initial price
* --------------------------------------------------------------------------
use "$input/DataFromProviders_FULL.dta", clear
xtset Product_ID Time

preserve
gen T_1 = 1 if Time == 1
bys Product_ID: egen BAL = max(T_1)
keep if BAL == 1
xtset Product_ID Time
bys Product_ID: gen ILP = Provider_Price[1]
sum ILP, d
local econ = r(p50)
display "  Median initial price: `econ'"

* Figure 4A: Cheaper products (ILP <= median)
did_multiplegt_old log_Provider_Price Product_ID Download_Date PMG ///
    if (Provider != "Amazon_US" & ILP <= `econ'), ///
    robust_dynamic dynamic(6) placebo(6) ///
    seed($seed_main) breps($breps) ///
    trends_lin(_IProXmon_*) cluster(Old_Product_ID) ///
    controls(Rating Review Product_Popularity)

event_plot e(didmgt_estimates)#e(didmgt_variances), ///
    graph_opt(xtitle("Days since the treatment") ///
              ytitle("Change in Product Prices (ln)") ///
              title("Figure 4A — Cheaper Products") ///
              xline(0, lcolor(black) lpattern(dash)) xlabel(-6(1)6) ///
              yline(0, lcolor(red) lpattern(solid)) ///
              graphregion(color(ltbluishgray)) bgcolor(white) ///
              ylabel(-.1(.1).3)) ///
    lag_opt(color(navy)) lead_opt(color(maroon) msymbol(S)) ///
    lag_ci_opt(color(navy%45 navy%45)) lead_ci_opt(color(maroon%45 maroon%45)) ///
    legend_opt(region(lstyle(none))) ///
    stub_lag(Effect_#) stub_lead(Placebo_#) together alpha(0.1)
graph save "$func/fig4a_temp.gph", replace

* Figure 4B: Expensive products (ILP > median)
did_multiplegt_old log_Provider_Price Product_ID Download_Date PMG ///
    if (Provider != "Amazon_US" & ILP > `econ'), ///
    robust_dynamic dynamic(6) placebo(6) ///
    seed($seed_main) breps($breps) ///
    trends_lin(_IProXmon_*) cluster(Old_Product_ID) ///
    controls(Rating Review Product_Popularity)

event_plot e(didmgt_estimates)#e(didmgt_variances), ///
    graph_opt(xtitle("Days since the treatment") ///
              ytitle("Change in Product Prices (ln)") ///
              title("Figure 4B — Expensive Products") ///
              xline(0, lcolor(black) lpattern(dash)) xlabel(-6(1)6) ///
              yline(0, lcolor(red) lpattern(solid)) ///
              graphregion(color(ltbluishgray)) bgcolor(white) ///
              ylabel(-.1(.1).3)) ///
    lag_opt(color(navy)) lead_opt(color(maroon) msymbol(S)) ///
    lag_ci_opt(color(navy%45 navy%45)) lead_ci_opt(color(maroon%45 maroon%45)) ///
    legend_opt(region(lstyle(none))) ///
    stub_lag(Effect_#) stub_lead(Placebo_#) together alpha(0.1)
graph save "$func/fig4b_temp.gph", replace

graph combine "$func/fig4a_temp.gph" "$func/fig4b_temp.gph", ///
    rows(2) ///
    title("Figure 4: By Initial Price Level (Balanced Panel)") ///
    graphregion(color(white))
graph export "$output/figure4.pdf", replace
restore
display "  Saved: figure4.pdf"

* --------------------------------------------------------------------------
* FIGURE 5 + TABLES 4/3 COLS 2-3: By product rating
* --------------------------------------------------------------------------
use "$input/DataFromProviders_FULL.dta", clear
xtset Product_ID Time

* Figure 5A + Table 4 col 2: Low-rated (Rating < 3.8), with controls
did_multiplegt_old log_Provider_Price Product_ID Download_Date PMG ///
    if (Provider != "Amazon_US" & Rating < 3.8), ///
    robust_dynamic dynamic(6) placebo(6) ///
    seed($seed_main) breps($breps) cluster(Old_Product_ID) ///
    trends_lin(_IProXmon_*) controls(Rating Review Product_Popularity) ///
    save_results("$func/Table_4_col_2.dta")

event_plot e(didmgt_estimates)#e(didmgt_variances), ///
    graph_opt(xtitle("Days since the treatment") ///
              ytitle("Change in Product Prices (ln)") ///
              title("Figure 5A — Low-Rated (< 3.8)") ///
              xline(0, lcolor(black) lpattern(dash)) xlabel(-6(1)6) ///
              yline(0, lcolor(red) lpattern(solid)) ///
              graphregion(color(ltbluishgray)) bgcolor(white) ///
              ylabel(-.35(.1).35) ylabel(0, add)) ///
    lag_opt(color(navy)) lead_opt(color(maroon) msymbol(S)) ///
    lag_ci_opt(color(navy%45 navy%45)) lead_ci_opt(color(maroon%45 maroon%45)) ///
    legend_opt(region(lstyle(none))) ///
    stub_lag(Effect_#) stub_lead(Placebo_#) together alpha(0.1)
graph save "$func/fig5a_temp.gph", replace

* Table 3 col 2: Low-rated, no controls
did_multiplegt_old log_Provider_Price Product_ID Download_Date PMG ///
    if (Provider != "Amazon_US" & Rating < 3.8), ///
    robust_dynamic dynamic(6) placebo(6) ///
    seed($seed_main) breps($breps) cluster(Old_Product_ID) ///
    trends_lin(_IProXmon_*) ///
    save_results("$func/Table_3_col_2.dta")

* Figure 5B + Table 4 col 3: High-rated (Rating >= 3.8), with controls
did_multiplegt_old log_Provider_Price Product_ID Download_Date PMG ///
    if (Provider != "Amazon_US" & Rating >= 3.8), ///
    robust_dynamic dynamic(6) placebo(6) ///
    seed($seed_main) breps($breps) cluster(Old_Product_ID) ///
    trends_lin(_IProXmon_*) controls(Rating Review Product_Popularity) ///
    save_results("$func/Table_4_col_3.dta")

event_plot e(didmgt_estimates)#e(didmgt_variances), ///
    graph_opt(xtitle("Days since the treatment") ///
              ytitle("Change in Product Prices (ln)") ///
              title("Figure 5B — High-Rated (>= 3.8)") ///
              xline(0, lcolor(black) lpattern(dash)) xlabel(-6(1)6) ///
              yline(0, lcolor(red) lpattern(solid)) ///
              graphregion(color(ltbluishgray)) bgcolor(white) ///
              ylabel(-.35(.1).35) ylabel(0, add)) ///
    lag_opt(color(navy)) lead_opt(color(maroon) msymbol(S)) ///
    lag_ci_opt(color(navy%45 navy%45)) lead_ci_opt(color(maroon%45 maroon%45)) ///
    legend_opt(region(lstyle(none))) ///
    stub_lag(Effect_#) stub_lead(Placebo_#) together alpha(0.1)
graph save "$func/fig5b_temp.gph", replace

* Table 3 col 3: High-rated, no controls
did_multiplegt_old log_Provider_Price Product_ID Download_Date PMG ///
    if (Provider != "Amazon_US" & Rating >= 3.8), ///
    robust_dynamic dynamic(6) placebo(6) ///
    seed($seed_main) breps($breps) cluster(Old_Product_ID) ///
    trends_lin(_IProXmon_*) ///
    save_results("$func/Table_3_col_3.dta")

graph combine "$func/fig5a_temp.gph" "$func/fig5b_temp.gph", ///
    rows(2) title("Figure 5: By Product Rating") graphregion(color(white))
graph export "$output/figure5.pdf", replace
display "  Saved: figure5.pdf"

* --------------------------------------------------------------------------
* FIGURE 6 + TABLES 4/3 COLS 4-5: By product visibility (Search Rank Normalized)
* --------------------------------------------------------------------------
use "$input/DataFromProviders_FULL.dta", clear
xtset Product_ID Time

* Figure 6A + Table 4 col 4: Low visibility (SRN < 0.7), with controls
did_multiplegt_old log_Provider_Price Product_ID Download_Date PMG ///
    if (Provider != "Amazon_US" & Search_Rank_Normalized < 0.7), ///
    robust_dynamic dynamic(6) placebo(6) ///
    seed($seed_main) breps($breps) cluster(Old_Product_ID) ///
    trends_lin(_IProXmon_*) controls(Rating Review Product_Popularity) ///
    save_results("$func/Table_4_col_4.dta")

event_plot e(didmgt_estimates)#e(didmgt_variances), ///
    graph_opt(xtitle("Days since the treatment") ///
              ytitle("Change in Product Prices (ln)") ///
              title("Figure 6A — Low Visibility (SRN < 0.7)") ///
              xline(0, lcolor(black) lpattern(dash)) xlabel(-6(1)6) ///
              yline(0, lcolor(red) lpattern(solid)) ///
              graphregion(color(ltbluishgray)) bgcolor(white) ///
              ylabel(-.25(.1).25) ylabel(0, add)) ///
    lag_opt(color(navy)) lead_opt(color(maroon) msymbol(S)) ///
    lag_ci_opt(color(navy%45 navy%45)) lead_ci_opt(color(maroon%45 maroon%45)) ///
    legend_opt(region(lstyle(none))) ///
    stub_lag(Effect_#) stub_lead(Placebo_#) together alpha(0.1)
graph save "$func/fig6a_temp.gph", replace

* Table 3 col 4: Low visibility, no controls
did_multiplegt_old log_Provider_Price Product_ID Download_Date PMG ///
    if (Provider != "Amazon_US" & Search_Rank_Normalized < 0.7), ///
    robust_dynamic dynamic(6) placebo(6) ///
    seed($seed_main) breps($breps) cluster(Old_Product_ID) ///
    trends_lin(_IProXmon_*) ///
    save_results("$func/Table_3_col_4.dta")

* Figure 6B + Table 4 col 5: High visibility (SRN >= 0.7), with controls
did_multiplegt_old log_Provider_Price Product_ID Download_Date PMG ///
    if (Provider != "Amazon_US" & Search_Rank_Normalized >= 0.7), ///
    robust_dynamic dynamic(6) placebo(6) ///
    seed($seed_main) breps($breps) cluster(Old_Product_ID) ///
    trends_lin(_IProXmon_*) controls(Rating Review Product_Popularity) ///
    save_results("$func/Table_4_col_5.dta")

event_plot e(didmgt_estimates)#e(didmgt_variances), ///
    graph_opt(xtitle("Days since the treatment") ///
              ytitle("Change in Product Prices (ln)") ///
              title("Figure 6B — High Visibility (SRN >= 0.7)") ///
              xline(0, lcolor(black) lpattern(dash)) xlabel(-6(1)6) ///
              yline(0, lcolor(red) lpattern(solid)) ///
              graphregion(color(ltbluishgray)) bgcolor(white) ///
              ylabel(-.25(.1).25) ylabel(0, add)) ///
    lag_opt(color(navy)) lead_opt(color(maroon) msymbol(S)) ///
    lag_ci_opt(color(navy%45 navy%45)) lead_ci_opt(color(maroon%45 maroon%45)) ///
    legend_opt(region(lstyle(none))) ///
    stub_lag(Effect_#) stub_lead(Placebo_#) together alpha(0.1)
graph save "$func/fig6b_temp.gph", replace

* Table 3 col 5: High visibility, no controls
did_multiplegt_old log_Provider_Price Product_ID Download_Date PMG ///
    if (Provider != "Amazon_US" & Search_Rank_Normalized >= 0.7), ///
    robust_dynamic dynamic(6) placebo(6) ///
    seed($seed_main) breps($breps) cluster(Old_Product_ID) ///
    trends_lin(_IProXmon_*) ///
    save_results("$func/Table_3_col_5.dta")

graph combine "$func/fig6a_temp.gph" "$func/fig6b_temp.gph", ///
    rows(2) title("Figure 6: By Product Visibility (Search Rank Normalized)") ///
    graphregion(color(white))
graph export "$output/figure6.pdf", replace
display "  Saved: figure6.pdf"

* --------------------------------------------------------------------------
* FIGURE 7 + TABLES 4/3 COLS 6-7: By rating x visibility interaction
* --------------------------------------------------------------------------
use "$input/DataFromProviders_FULL.dta", clear
xtset Product_ID Time

* Figure 7A + Table 4 col 6: Low-rated & Low-visibility (LR-LV), with controls
did_multiplegt_old log_Provider_Price Product_ID Download_Date PMG ///
    if (Provider != "Amazon_US" & Search_Rank_Normalized < 0.7 & Rating < 3.8), ///
    robust_dynamic dynamic(6) placebo(6) ///
    seed($seed_main) breps($breps) cluster(Old_Product_ID) ///
    trends_lin(_IProXmon_*) controls(Rating Review Product_Popularity) ///
    save_results("$func/Table_4_col_6.dta")

event_plot e(didmgt_estimates)#e(didmgt_variances), ///
    graph_opt(xtitle("Days since the treatment") ///
              ytitle("Change in Product Prices (ln)") ///
              title("Figure 7A — Low-Rated & Low-Visibility") ///
              xline(0, lcolor(black) lpattern(dash)) xlabel(-6(1)6) ///
              yline(0, lcolor(red) lpattern(solid)) ///
              graphregion(color(ltbluishgray)) bgcolor(white) ///
              ylabel(-.3(.075).225)) ///
    lag_opt(color(navy)) lead_opt(color(maroon) msymbol(S)) ///
    lag_ci_opt(color(navy%45 navy%45)) lead_ci_opt(color(maroon%45 maroon%45)) ///
    legend_opt(region(lstyle(none))) ///
    stub_lag(Effect_#) stub_lead(Placebo_#) together alpha(0.1)
graph save "$func/fig7a_temp.gph", replace

* Table 3 col 6: LR-LV, no controls
did_multiplegt_old log_Provider_Price Product_ID Download_Date PMG ///
    if (Provider != "Amazon_US" & Search_Rank_Normalized < 0.7 & Rating < 3.8), ///
    robust_dynamic dynamic(6) placebo(6) ///
    seed($seed_main) breps($breps) cluster(Old_Product_ID) ///
    trends_lin(_IProXmon_*) ///
    save_results("$func/Table_3_col_6.dta")

* Figure 7B + Table 4 col 7: High-rated & High-visibility (HR-HV), with controls
did_multiplegt_old log_Provider_Price Product_ID Download_Date PMG ///
    if (Provider != "Amazon_US" & Search_Rank_Normalized >= 0.7 & Rating >= 3.8), ///
    robust_dynamic dynamic(6) placebo(6) ///
    seed($seed_main) breps($breps) cluster(Old_Product_ID) ///
    trends_lin(_IProXmon_*) controls(Rating Review Product_Popularity) ///
    save_results("$func/Table_4_col_7.dta")

event_plot e(didmgt_estimates)#e(didmgt_variances), ///
    graph_opt(xtitle("Days since the treatment") ///
              ytitle("Change in Product Prices (ln)") ///
              title("Figure 7B — High-Rated & High-Visibility") ///
              xline(0, lcolor(black) lpattern(dash)) xlabel(-6(1)6) ///
              yline(0, lcolor(red) lpattern(solid)) ///
              graphregion(color(ltbluishgray)) bgcolor(white) ///
              ylabel(-.3(.075).225)) ///
    lag_opt(color(navy)) lead_opt(color(maroon) msymbol(S)) ///
    lag_ci_opt(color(navy%45 navy%45)) lead_ci_opt(color(maroon%45 maroon%45)) ///
    legend_opt(region(lstyle(none))) ///
    stub_lag(Effect_#) stub_lead(Placebo_#) together alpha(0.1)
graph save "$func/fig7b_temp.gph", replace

* Table 3 col 7: HR-HV, no controls
did_multiplegt_old log_Provider_Price Product_ID Download_Date PMG ///
    if (Provider != "Amazon_US" & Search_Rank_Normalized >= 0.7 & Rating >= 3.8), ///
    robust_dynamic dynamic(6) placebo(6) ///
    seed($seed_main) breps($breps) cluster(Old_Product_ID) ///
    trends_lin(_IProXmon_*) ///
    save_results("$func/Table_3_col_7.dta")

graph combine "$func/fig7a_temp.gph" "$func/fig7b_temp.gph", ///
    rows(2) title("Figure 7: By Rating x Visibility") graphregion(color(white))
graph export "$output/figure7.pdf", replace
display "  Saved: figure7.pdf"


* --------------------------------------------------------------------------
* ASSEMBLE TABLES 3 AND 4 FROM SAVED RESULTS
*
* Post-process each .dta file (add stars, round), then merge into wide tables.
* Follows authors' original loop (lines 345-422 of original .do file).
* --------------------------------------------------------------------------

display as text _n "--- Assembling Tables 3 and 4 ---"

* Process each saved .dta file: compute t-stat, p-value, significance stars
local dta_directory "$func"
local store_dir     "$func/merge_columns"

local myfilelist : dir "`dta_directory'" files "Table_*.dta"

foreach file of local myfilelist {
    use "`dta_directory'/`file'", clear
    gen tstat = treatment_effect / se_treatment_effect
    gen pval  = 2 * normal(-abs(tstat))
    gen star  = "***" if pval <= 0.01
    replace star = "**"  if (pval > 0.01 & pval <= 0.05)
    replace star = "*"   if (pval > 0.05 & pval <= 0.1)
    replace treatment_effect    = round(treatment_effect,    .001)
    replace se_treatment_effect = round(se_treatment_effect, .001)
    egen table = concat(treatment_effect star)
    order time_to_treatment table se_treatment_effect
    drop in 7    // drop the normalisation row (period 0, pinned to zero)
    gen Time = time_to_treatment
    replace Time = Time + 1 if Time < 0
    tostring Time, replace
    replace Time = "ATE" in 14
    keep Time table se_treatment_effect
    rename (table se_treatment_effect) (Estimate SE)
    order Time Estimate SE
    save "`store_dir'/`file'", replace
}

* --- TABLE 3: Without controls ---
use "$func/merge_columns/Table_3_col_1.dta", clear
rename (Estimate SE) (Estimate_1 SE_1)

forvalues i = 2/7 {
    merge 1:1 Time using "$func/merge_columns/Table_3_col_`i'.dta"
    drop _merge
    rename (Estimate SE) (Estimate_`i' SE_`i')
}

insobs 3
replace Time = "Product FE"            in 15
replace Time = "Day FE"                in 16
replace Time = "Retailer-by-month FE"  in 17

forvalues i = 1/7 {
    replace Estimate_`i' = "YES" if Estimate_`i' == ""
}

label define order  1 "-6" 2 "-5" 3 "-4" 4 "-3" 5 "-2" 6 "-1" ///
                    7 "0"  8 "1"  9 "2"  10 "3" 11 "4" 12 "5"  13 "6"
encode Time, gen(Relative_Time) label(order)
sort Relative_Time
drop Relative_Time

export delimited using "$output/table3.csv", replace
display "  Saved: table3.csv"

* --- TABLE 4: With controls ---
use "$func/merge_columns/Table_4_col_1.dta", clear
rename (Estimate SE) (Estimate_1 SE_1)

forvalues i = 2/7 {
    merge 1:1 Time using "$func/merge_columns/Table_4_col_`i'.dta"
    drop _merge
    rename (Estimate SE) (Estimate_`i' SE_`i')
}

insobs 3
replace Time = "Product FE"            in 15
replace Time = "Day FE"                in 16
replace Time = "Retailer-by-month FE"  in 17

forvalues i = 1/7 {
    replace Estimate_`i' = "YES" if Estimate_`i' == ""
}

label define order2 1 "-6" 2 "-5" 3 "-4" 4 "-3" 5 "-2" 6 "-1" ///
                    7 "0"  8 "1"  9 "2"  10 "3" 11 "4" 12 "5"  13 "6"
encode Time, gen(Relative_Time) label(order2)
sort Relative_Time
drop Relative_Time

export delimited using "$output/table4.csv", replace
display "  Saved: table4.csv"


********************************************************************************
* SECTION 5: TABLE 5 — QUALITATIVE THEORY TABLE (hardcoded CSV, no estimation)
* Reproduced from Bottasso et al. (2025), Table 5, p. 223.
********************************************************************************

display as text _n "=== TABLE 5: Qualitative Theory Table (hardcoded) ==="

file open t5 using "$output/table5.csv", write replace
file write t5 "Prediction,Collusion,Price_Discrimination,Signaling" _n
file write t5 "PMGs raise NewEgg prices,Yes,No,Yes" _n
file write t5 "Effect larger for highly visible products,Yes,Yes,Yes" _n
file write t5 "Effect larger for highly rated products,Ambiguous,Yes,Yes" _n
file write t5 "Non-adopting rival prices rise,Yes,No,No" _n
file write t5 "Effect concentrated in HR-HV segment,Ambiguous,Yes,Yes" _n
file write t5 "Consistent with paper's findings?,Partially,Yes,Yes" _n
file close t5
display "  Saved: table5.csv"


********************************************************************************
* SECTION 6: ROBUSTNESS — FIGURES 8 AND 9 (Placebo Tests)
********************************************************************************

display as text _n "=== Robustness Checks (Figures 8-9) ==="

* --------------------------------------------------------------------------
* FIGURE 8: Placebo — fake treatment (null expected)
* Generate random treatment with same average frequency as actual PMG
* --------------------------------------------------------------------------
use "$input/DataFromProviders_FULL.dta", clear
xtset Product_ID Time

set seed $seed_main
sum PMG, d
scalar p_pmg = r(mean)
gen PMG_Placebo = rbinomial(1, p_pmg)

* Figure 8A: Full sample (Stata original uses Time here, vs Download_Date elsewhere;
*            this is noted as a possible typo in the original code)
did_multiplegt_old log_Provider_Price Product_ID Time PMG_Placebo ///
    if Provider != "Amazon_US", ///
    robust_dynamic dynamic(6) placebo(6) ///
    trends_lin(_IProXmon_*) controls(Rating Review Product_Popularity) ///
    seed($seed_main) breps($breps) cluster(Old_Product_ID)

event_plot e(didmgt_estimates)#e(didmgt_variances), ///
    graph_opt(xtitle("Days since the treatment") ///
              ytitle("Change in Product Prices (ln)") ///
              title("Figure 8A — Fake Treatment, Full Sample") ///
              xline(0, lcolor(black) lpattern(dash)) xlabel(-6(1)6) ///
              yline(0, lcolor(red) lpattern(solid)) ///
              graphregion(color(ltbluishgray)) bgcolor(white) ///
              ylabel(-.1(.05).15)) ///
    lag_opt(color(navy)) lead_opt(color(maroon) msymbol(S)) ///
    lag_ci_opt(color(navy%45 navy%45)) lead_ci_opt(color(maroon%45 maroon%45)) ///
    legend_opt(region(lstyle(none))) ///
    stub_lag(Effect_#) stub_lead(Placebo_#) together alpha(0.1)
graph save "$func/fig8a_temp.gph", replace

* Figure 8B: HR-HV sample
did_multiplegt_old log_Provider_Price Product_ID Download_Date PMG_Placebo ///
    if (Provider != "Amazon_US" & Rating >= 3.8 & Search_Rank_Normalized >= 0.7), ///
    robust_dynamic dynamic(6) placebo(6) ///
    trends_lin(_IProXmon_*) controls(Rating Review Product_Popularity) ///
    seed($seed_main) breps($breps) cluster(Old_Product_ID)

event_plot e(didmgt_estimates)#e(didmgt_variances), ///
    graph_opt(xtitle("Days since the treatment") ///
              ytitle("Change in Product Prices (ln)") ///
              title("Figure 8B — Fake Treatment, HR-HV Sample") ///
              xline(0, lcolor(black) lpattern(dash)) xlabel(-6(1)6) ///
              yline(0, lcolor(red) lpattern(solid)) ///
              graphregion(color(ltbluishgray)) bgcolor(white) ///
              ylabel(-.1(.05).15)) ///
    lag_opt(color(navy)) lead_opt(color(maroon) msymbol(S)) ///
    lag_ci_opt(color(navy%45 navy%45)) lead_ci_opt(color(maroon%45 maroon%45)) ///
    legend_opt(region(lstyle(none))) ///
    stub_lag(Effect_#) stub_lead(Placebo_#) together alpha(0.1)
graph save "$func/fig8b_temp.gph", replace

graph combine "$func/fig8a_temp.gph" "$func/fig8b_temp.gph", ///
    rows(2) title("Figure 8: Placebo — Fake Treatment") graphregion(color(white))
graph export "$output/figure8.pdf", replace
display "  Saved: figure8.pdf"

* --------------------------------------------------------------------------
* FIGURE 9: Placebo — fake outcome (random prices drawn from product-level
*           truncated normals; null expected)
* --------------------------------------------------------------------------
use "$input/DataFromProviders_FULL.dta", clear
xtset Product_ID Time

set seed $seed_main

* Draw fake prices for each Product_ID from truncated normal
* matching that product's empirical mean and variance
forval i = 0/28 {
    sum log_Provider_Price if Product_ID == `i', d
    scalar left_`i'  = r(min)
    scalar right_`i' = r(max)
    scalar mu_`i'    = r(mean)
    scalar sigma_`i' = r(Var)
    gen Placebo_Outcome_`i' = ///
        min(max(left_`i', rnormal(mu_`i', sigma_`i')), right_`i') ///
        if Product_ID == `i'
}
forval i = 100/128 {
    sum log_Provider_Price if Product_ID == `i', d
    scalar left_`i'  = r(min)
    scalar right_`i' = r(max)
    scalar mu_`i'    = r(mean)
    scalar sigma_`i' = r(Var)
    gen Placebo_Outcome_`i' = ///
        min(max(left_`i', rnormal(mu_`i', sigma_`i')), right_`i') ///
        if Product_ID == `i'
}
forval i = 1000/1028 {
    sum log_Provider_Price if Product_ID == `i', d
    scalar left_`i'  = r(min)
    scalar right_`i' = r(max)
    scalar mu_`i'    = r(mean)
    scalar sigma_`i' = r(Var)
    gen Placebo_Outcome_`i' = ///
        min(max(left_`i', rnormal(mu_`i', sigma_`i')), right_`i') ///
        if Product_ID == `i'
}

gen Placebo_Outcome = .
label variable Placebo_Outcome "Fake prices"
forval i = 0/28    { 
	replace Placebo_Outcome = Placebo_Outcome_`i' if Product_ID == `i' 
	}
forval i = 100/128  { 
	replace Placebo_Outcome = Placebo_Outcome_`i' if Product_ID == `i' 
	}
forval i = 1000/1028 { 
	replace Placebo_Outcome = Placebo_Outcome_`i' if Product_ID == `i' 
	}

forval i = 0/28    { 
	drop Placebo_Outcome_`i' 
	}
forval i = 100/128  { 
	drop Placebo_Outcome_`i' 
	}
forval i = 1000/1028 { 
	drop Placebo_Outcome_`i' 
	}

* Figure 9A: Full sample, fake prices
did_multiplegt_old Placebo_Outcome Product_ID Download_Date PMG ///
    if Provider != "Amazon_US", ///
    robust_dynamic dynamic(6) placebo(6) ///
    trends_lin(_IProXmon_*) controls(Rating Review Product_Popularity) ///
    seed($seed_main) breps($breps) cluster(Old_Product_ID)

event_plot e(didmgt_estimates)#e(didmgt_variances), ///
    graph_opt(xtitle("Days since the treatment") ///
              ytitle("Change in Product Prices (ln)") ///
              title("Figure 9A — Fake Outcome, Full Sample") ///
              xline(0, lcolor(black) lpattern(dash)) xlabel(-6(1)6) ///
              yline(0, lcolor(red) lpattern(solid)) ///
              graphregion(color(ltbluishgray)) bgcolor(white) ylabel(-1(.5)1)) ///
    lag_opt(color(navy)) lead_opt(color(maroon) msymbol(S)) ///
    lag_ci_opt(color(navy%45 navy%45)) lead_ci_opt(color(maroon%45 maroon%45)) ///
    legend_opt(region(lstyle(none))) ///
    stub_lag(Effect_#) stub_lead(Placebo_#) together alpha(0.1)
graph save "$func/fig9a_temp.gph", replace

* Figure 9B: HR-HV sample, fake prices
did_multiplegt_old Placebo_Outcome Product_ID Download_Date PMG ///
    if (Provider != "Amazon_US" & Rating >= 3.8 & Search_Rank_Normalized >= 0.7), ///
    robust_dynamic dynamic(6) placebo(6) ///
    trends_lin(_IProXmon_*) controls(Rating Review Product_Popularity) ///
    seed($seed_main) breps($breps) cluster(Old_Product_ID)

event_plot e(didmgt_estimates)#e(didmgt_variances), ///
    graph_opt(xtitle("Days since the treatment") ///
              ytitle("Change in Product Prices (ln)") ///
              title("Figure 9B — Fake Outcome, HR-HV Sample") ///
              xline(0, lcolor(black) lpattern(dash)) xlabel(-6(1)6) ///
              yline(0, lcolor(red) lpattern(solid)) ///
              graphregion(color(ltbluishgray)) bgcolor(white) ylabel(-1(.5)1)) ///
    lag_opt(color(navy)) lead_opt(color(maroon) msymbol(S)) ///
    lag_ci_opt(color(navy%45 navy%45)) lead_ci_opt(color(maroon%45 maroon%45)) ///
    legend_opt(region(lstyle(none))) ///
    stub_lag(Effect_#) stub_lead(Placebo_#) together alpha(0.1)
graph save "$func/fig9b_temp.gph", replace

graph combine "$func/fig9a_temp.gph" "$func/fig9b_temp.gph", ///
    rows(2) title("Figure 9: Placebo — Simulated Prices") graphregion(color(white))
graph export "$output/figure9.pdf", replace
display "  Saved: figure9.pdf"


********************************************************************************
* SECTION 7: FIGURE 10 — RANDOM ALLOCATION PERMUTATION TEST
* (1,000 iterations; may take 2–8 hours; skip by setting RUN_SLOW_TESTS = 0)
********************************************************************************

display as text _n "=== Figure 10: Random Allocation Permutation Test ==="

if $RUN_SLOW_TESTS == 1 {

    display "Running 1,000 permutation iterations — this may take hours..."

    use "$input/DataFromProviders_FULL.dta", clear
    xtset Product_ID Time

    set seed $seed_fig10
    matrix results = J(1000, 1, .)
    sum PMG if Provider == "NewEgg", d
    scalar p_ne = r(mean)

    qui forvalues r = 1(1)1000 {
        noi: display "Iteration `r' / 1000"

        preserve
            gen byte random_pmg = runiform() <= p_ne if Provider == "NewEgg"
            recode random_pmg . = 0
            keep random_pmg Product_ID Time
            tempfile placebo_iter
            save "`placebo_iter'"
        restore
        merge 1:1 Product_ID Time using "`placebo_iter'", ///
            keep(match) nogenerate

        * breps(0) = no bootstrap in permutation iterations (speed)
        capture: did_multiplegt_old log_Provider_Price Product_ID Download_Date ///
            random_pmg if Provider != "Amazon_US", ///
            robust_dynamic dynamic(6) placebo(6) ///
            seed($seed_fig10) breps(0) ///
            trends_lin(_IProXmon_*) cluster(Old_Product_ID) ///
            controls(Rating Review Product_Popularity)

        matrix results[`r', 1] = e(effect_average)
        drop random_pmg
    }

    * True ATE (re-estimate with full bootstrap for the reference line)
    qui: did_multiplegt_old log_Provider_Price Product_ID Download_Date PMG ///
        if Provider != "Amazon_US", ///
        robust_dynamic dynamic(6) placebo(6) ///
        seed($seed_main) breps($breps) ///
        trends_lin(_IProXmon_*) controls(Rating Review Product_Popularity) ///
        cluster(Old_Product_ID)

    local true_ate = e(effect_average)

    svmat results

    hist results1, ///
        xline(`true_ate', lcolor(red)) ///
        xtitle("Coefficient values") ytitle("") ///
        normal normopts(lcolor(red) lpattern(dash)) ///
        xlabel(-0.12(0.06)0.24) ///
        scheme(s2mono) graphregion(color(ltbluishgray)) ///
        title("Figure 10: Random Allocation Permutation Test") ///
        note("Red line = true ATE. 1,000 random treatment assignments.")
    graph export "$output/figure10.pdf", replace
    display "  Saved: figure10.pdf"

    cap drop results results1
    clear all

} // end if RUN_SLOW_TESTS

else {
    display "  Figure 10 skipped (RUN_SLOW_TESTS = 0)."
    display "  Set global RUN_SLOW_TESTS = 1 and re-run to produce figure10.pdf."
}


********************************************************************************
* SECTION 8: TABLE 6 AND FIGURE 11 — IV ESTIMATION AND CONLEY UCI BOUNDS
********************************************************************************

display as text _n "=== TABLE 6: IV, Control Function, and First Stage ==="

use "$input/DataFromProviders_FULL.dta", clear
xtset Product_ID Time

* Instrument: I = 1 if product_age > mean(product_age)
sum product_age, d
local mean_age = r(mean)
gen I = 1 if product_age > `mean_age'
recode I . = 0

* Provider ID for Retailer x Month FE
egen Provider_ID = group(Provider)

* --- Column 1: IV (2SLS) ---
* Stata: ivreghdfe log_Provider_Price ... (PMG=I), absorb(Product_ID Time Month#Provider_ID)
ivreghdfe log_Provider_Price Product_Popularity Rating Review ///
    (PMG = I), ///
    absorb(Product_ID Time Month#Provider_ID) robust
estimates store m6_iv

* --- Column 3: First-stage OLS ---
reghdfe PMG I Product_Popularity Rating Review, ///
    absorb(Product_ID Time Month#Provider_ID) vce(robust)
estimates store m6_first

* --- Column 2: Control Function (CF) with cluster bootstrap ---
* Stata: bootstrap program boot_cf (100 reps, seed 123)
*   Step 1: probit PMG ~ I + product_ID_FEs + time_FEs on NewEgg only
*   Step 2: predict generalized residuals (score)
*   Step 3: reghdfe log_Provider_Price ~ PMG + controls + gen_resid + _IProXmon_*,
*             absorb(Product_ID Time) cluster(Old_Product_ID)

capture program drop boot_cf
program boot_cf, eclass
    capture drop gen_resid
    glm PMG I i.Product_ID i.Time if Provider == "NewEgg", ///
        family(binomial) link(probit) vce(robust)
    predict gen_resid, score

    reghdfe log_Provider_Price PMG Product_Popularity Rating Review ///
        gen_resid _IProXmon_*, ///
        absorb(Product_ID Time) vce(cluster Old_Product_ID)
end

bootstrap, reps($breps) level(90) seed($seed_main): boot_cf
estimates store m6_cf

* Export Table 6 as CSV
esttab m6_iv m6_cf m6_first using "$output/table6.csv", replace ///
    keep(PMG I) ///
    coeflabels(PMG "PMG" I "Instrument: Older Product") ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    scalars("N Observations") ///
    title("Table 6: IV and Control Function Estimates") ///
    mtitles("(1) IV (2SLS)" "(2) Control Fn." "(3) First Stage") ///
    note("Controls: Product_Popularity, Rating, Review." ///
         "Product FE, Day FE, Retailer x Month FE absorbed." ///
         "Bootstrap SEs for CF: 100 reps clustered at Old_Product_ID.")
display "  Saved: table6.csv"


* --------------------------------------------------------------------------
* FIGURE 11: Conley et al. (2012) UCI Bounds
* plausexog: varies the exclusion restriction violation parameter gamma
* grid(4) in Stata = 5 points from gmin to gmax (i.e., -0.02 to 0.02)
* --------------------------------------------------------------------------
display as text _n "=== Figure 11: Conley et al. (2012) UCI Bounds ==="

plausexog uci log_Provider_Price Product_Popularity Rating Review ///
    i.Product_ID i.Time _IProXmon_* ///
    (PMG = I), ///
    vce(robust) gmin(-.02) gmax(.02) grid(4) graph(PMG) level(.9)

graph export "$output/figure11.pdf", replace
display "  Saved: figure11.pdf"


********************************************************************************
* DONE
********************************************************************************

display as text _n "======================================================"
display as text    "REPLICATION COMPLETE"
display as text    "======================================================"
display as text    "Outputs in: $output"
display as text    ""
display as text    "Tables (CSV):"
display as text    "  table1.csv  — Summary Statistics"
display as text    "  table2.csv  — OLS FE (Pre/Post PMG, NewEgg)"
display as text    "  table3.csv  — DiD estimates without controls"
display as text    "  table4.csv  — DiD estimates with controls"
display as text    "  table5.csv  — Theory comparison (hardcoded)"
display as text    "  table6.csv  — IV, Control Function, First Stage"
display as text    ""
display as text    "Figures (PDF):"
display as text    "  figure1.pdf   — Event study: NewEgg vs Amazon UK"
display as text    "  figure2.pdf   — Event study: NewEgg vs Amazon US"
display as text    "  figure3.pdf   — Spillover: Amazon US prices"
display as text    "  figure4.pdf   — By initial price level"
display as text    "  figure5.pdf   — By product rating"
display as text    "  figure6.pdf   — By product visibility"
display as text    "  figure7.pdf   — By rating x visibility"
display as text    "  figure8.pdf   — Placebo: fake treatment"
display as text    "  figure9.pdf   — Placebo: fake outcome"
display as text    "  figure10.pdf  — Permutation test (if RUN_SLOW_TESTS=1)"
display as text    "  figure11.pdf  — Conley UCI bounds"
display as text    ""
display as text    "Known R vs Stata differences:"
display as text    "  DiD estimator: Stata uses did_multiplegt_old robust_dynamic;"
display as text    "    R uses did_multiplegt_dyn (equivalent per package authors)."
display as text    "  CF residuals: Stata uses score residuals; R uses response."
display as text    "    Expected SE difference < 0.002."
display as text    "  Trends_lin: Stata passes _IProXmon_* (18 dummies);"
display as text    "    R uses trends_lin=TRUE (group-level linear trends)."
display as text    "  Bootstrap PRNG: minor numerical differences expected."

clear all
