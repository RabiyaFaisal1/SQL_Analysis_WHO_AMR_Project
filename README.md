# WHO GLASS Antimicrobial Resistance — SQL Portfolio Project

**TL;DR:** SQL analysis of WHO's global antimicrobial resistance surveillance
data (5 bloodstream pathogens, 95 countries, 2018–2023) using MySQL — includes
staging tables, data-quality validation, and window functions (`RANK()`,
`LAG()`) for trend analysis. Key finding: Acinetobacter spp. resistance rose
8 percentage points from 2018 to 2023, the sharpest increase of any pathogen
tracked.

## Data Source

This dataset was of particular interest given a Biotechnology background, offering
an opportunity to bring biotechnology domain knowledge together with data analysis
skills. Data was obtained from the WHO Global Antimicrobial Resistance and Use
Surveillance System (GLASS) dashboard
(https://worldhealthorg.shinyapps.io/glass-dashboard/), which reports antimicrobial
resistance data submitted by participating countries from 2016–2023.

WHO's dashboard structure — per-chart, filtered downloads rather than a single bulk
file — allowed the analysis to be deliberately scoped to the relevant pathogens,
specimen type, and reporting years.

**Scope:** Bloodstream infections only, across 5 pathogens included in the WHO
GLASS dashboard for this specimen type (*Acinetobacter* spp., *Escherichia coli*,
*Klebsiella pneumoniae*, *Salmonella* spp., *Streptococcus pneumoniae*).

**Two tables were built:**
- `resistance_snapshot_2023` — per-country resistance rates across all antibiotics
  tested, for the most recent reporting year (2023)
- `resistance_timeseries` — per-country-per-year resistance rates (2018–2023) for
  one representative antibiotic per pathogen, selected based on clinical relevance

## Data Preparation

WHO's dashboard exports bundle multiple summary tables into a single CSV per
download. These raw exports were programmatically parsed to extract the granular
per-country records and consolidate the 5 pathogen-specific downloads into two
unified files (`resistance_snapshot_2023.csv`, `resistance_timeseries.csv`) ready
for import. WHO's own pre-computed summary statistics (medians, quartiles across
countries) were intentionally excluded from import — equivalent aggregates are
instead derived directly via SQL as part of the analysis below.

## Schema

Two fact tables imported via MySQL Workbench's Table Data Import Wizard:

- **`resistance_snapshot_2023`**: Specimen, PathogenName, AntibioticName, Iso3,
  CountryTerritoryArea, WHORegionName, InterpretableAST, Resistant,
  ResistancePercentage
- **`resistance_timeseries`**: Iso3, CountryTerritoryArea, WHORegionName, Year,
  Specimen, PathogenName, AbTargets, TotalSpecimenIsolates, InterpretableAST,
  Resistant, PercentResistant

(Note: `AbTargets` in the timeseries table is WHO's column name for what the
snapshot table calls `AntibioticName` — same meaning, different label.)

## Data Cleaning

For each table, a `_staging` copy was created first so the raw imported data
stays untouched, then the following checks were run on the staging copy.

**1. Missing values check**

Checked `ResistancePercentage`/`PercentResistant`, `PathogenName`, and `Iso3` —
the three columns the analysis actually depends on. `ResistancePercentage` is
the number being analyzed; a row with no pathogen can't be grouped; `Iso3` is
the link to the country. Result: 0 missing values in either table.

*Lesson learned:* an initial version of this check also compared the numeric
column with `= ''`. MySQL silently converts an empty string to `0` when compared
against a numeric column, so `0 = ''` evaluates to `TRUE` — meaning every row
with a genuine 0% resistance result was wrongly flagged as "missing." The
corrected check applies `= ''` only to text columns and relies on `IS NULL`
alone for numeric ones.

**2. Duplicate check** — `ROW_NUMBER() OVER (PARTITION BY ...)`

Grouped by the columns that define what makes one row unique:
- Snapshot table: `Iso3, PathogenName, AntibioticName` — country + pathogen +
  antibiotic together are the row's identity.
- Timeseries table: `Iso3, PathogenName, AbTargets, Year` — same idea, plus
  `Year`, since the same country/pathogen/antibiotic combination legitimately
  repeats once per year in a time series. Leaving `Year` out would falsely
  flag every normal year-over-year row as a duplicate.

Measurement columns (resistance %, isolate counts) were excluded from the
grouping — those are the row's result, not its identity. Result: 0 duplicates
in either table.

**3. Standardization check** — `SELECT DISTINCT` on each text column
separately, to catch spelling or encoding issues.

Finding: two country names showed encoding artifacts from WHO's original
export — Türkiye and Côte d'Ivoire displayed as broken Unicode character
sequences. Confirmed via the unaffected ISO3 codes (`TUR`, `CIV`), traced back
to WHO's raw source file (present before any processing on this end), and
corrected in SQL with `UPDATE` statements.

**4. Small sample size check**

```sql
WHERE InterpretableAST < 10;
```

WHO's own GLASS methodology flags resistance percentages calculated from fewer
than ~10 tested isolates as statistically unreliable. Result: 0 rows in either
table — every row meets the reliability threshold.

**5. Valid range check**

```sql
WHERE ResistancePercentage < 0 OR ResistancePercentage > 100;
```

Confirms no data or calculation errors produced an impossible percentage.
Result: 0 rows in either table.

## Exploratory Data Analysis

### Question 1: Which pathogen–antibiotic–country combinations had the highest resistance rates in 2023?

In 2023, 10 pathogen-antibiotic-country combinations were identified with 100%
resistance, covering a range of pathogens (Acinetobacter spp., Klebsiella
pneumoniae, E. coli) and a range of antibiotics — not a single isolated case.
Sample sizes behind these results ranged from 11 to 63 tested isolates. While
these meet the minimum 10-isolate threshold used in the analysis,
results toward the smaller end of that range should still be read with some
caution.

### Question 2: Which pathogen has the highest average resistance rate across all countries and antibiotics tested in 2023?

Acinetobacter spp. and Klebsiella pneumoniae showed the highest average
resistance rates (42.77% and 42.48% respectively) among all countries and
antibiotics tested in 2023. E. coli is notably lower at 32.56%. There is a
clear gap between these two pathogens with the highest average resistance
rates and the rest: Streptococcus pneumoniae (12.61%) and Salmonella spp.
(10.08%) show much lower average resistance.

### Question 3: For each pathogen, which country has the highest resistance rate?

Bangladesh and North Macedonia both show 100% resistance against
Acinetobacter spp.; Uganda and Côte d'Ivoire are tied at 100% resistance
against E. coli; seven countries (Maldives, Malawi, Côte d'Ivoire, Zambia,
Lebanon, Kosovo, Yemen) are tied at 100% resistance against Klebsiella
pneumoniae; Iraq leads with 95.3% resistance against Salmonella spp.; and the
Democratic Republic of Congo leads with 97.9% resistance against
Streptococcus pneumoniae. Several pathogens have multiple countries tied at
exactly 100%, which is why `RANK()` was used instead of `ROW_NUMBER()` —
`ROW_NUMBER()` would have arbitrarily shown only one top country per pathogen,
while `RANK()` correctly shows all ties as rank 1.

### Question 4: What was the year-over-year change in resistance for each pathogen from 2018 to 2023?

Acinetobacter spp. had a general increasing trend from 2018 to 2022, from
46.55% to 55.23%. However, there was a slight decrease in resistance in 2023,
dropping by 0.67 percentage points. The overall trend is positive, but it is
not continually increasing.

There was more variability from year to year for E. coli. Between 2019 and
2020, resistance grew; it decreased by 3.45 percentage points in 2021, but
rose once more in 2023. The relatively small net increase hides a number of
intermediate fluctuations that are not obvious from the endpoints alone.

For Klebsiella pneumoniae, the pattern was reversed — a downward trend for a
few years, followed by a strong rebound in 2023. Resistance fell from 55.10%
to 50.96% before increasing by 4.18 percentage points in 2023, to 55.14%. The
overall increase across 2018–2023 does not fully show the trajectory of the
pathogen.

Salmonella spp. declined through 2021, then increased during 2022 and 2023. Its resistance increased from 8.79% in 2018 to 9.19% in
2023 — a small overall rise visible only in the unrounded figures, which
differs from the earlier finding in Question 6, where both years rounded to
9%.

Streptococcus pneumoniae was the most volatile organism. Resistance remained
relatively stable through 2021, then rose by 5.93 percentage points to
10.22% in 2022. This then dropped to 1.94% in 2023, a reduction of 8.28
percentage points — the largest year-over-year change of any of the five
pathogens.

**Overall Finding:** The year-by-year analysis shows that none of the five
pathogens had a consistent linear trend from 2018 to 2023. The overall
direction of change reported in Question 6 is still reflected in the annual
data, but it hides significant fluctuation between individual years. The most
notable patterns are Klebsiella pneumoniae's multi-year decline followed by a
late recovery, and the sharp rise-then-fall in Streptococcus pneumoniae
around 2022. This also highlights the value of working from unrounded data —
Salmonella spp.'s change from 8.79% to 9.19% appears as "no change" when
rounded to whole percentages.

### Question 5: Which countries had the highest testing volumes, and is there any relationship between testing volume and resistance?

The volume of testing is very different in different countries. The highest
testing volume was in Japan, with over 4.4 million isolates tested, and the
average resistance rate was a relatively low 3.97%. By contrast, countries
testing significantly less had much higher resistance rates. For instance, in
India, the average resistance rate was 67.4% with 511,000 isolates tested,
while in Iran, 39,000 isolates were tested with an average resistance rate of
61.18%. The Russian Federation had the lowest testing volume in this group,
about 19,700 isolates, but the highest average resistance rate at 85.87%.

In general, there is no obvious relationship between testing volume and
resistance based on this country-level comparison. An increased number of
isolates tested does not necessarily mean increased or decreased resistance.
Japan is an example of this, with very large testing volume but a low
resistance rate, while several countries with lower testing volumes reported
much higher resistance. These results should be interpreted with some
caution, as countries with lower numbers of tests may have less stable or
representative resistance estimates, even when the minimum threshold of 10
tests is reached.

### Question 6: Comparing 2018 to 2023, which pathogen's resistance rate worsened the most, and which improved?

Comparison of 2018 and 2023 shows a rise in resistance for three of the five
pathogens, no change for one, and a decrease for one.

Acinetobacter spp. recorded the sharpest increase, from 47% in 2018 to 55% in
2023 — an 8 percentage-point rise, the largest of all pathogens analyzed.
Klebsiella pneumoniae also rose, by 2 points, from 53% to 55%. E. coli
resistance rose slightly, from 36% to 37%, a change of only 1 percentage
point. Salmonella spp. appeared unchanged at 9% in both years when rounded to whole
percentages, although the unrounded values show a small increase from 8.79%
to 9.19%.
Streptococcus pneumoniae was the only pathogen that improved, with resistance
dropping from 4% to 2% — a 2 percentage-point decrease.

**Overall Finding:** In general, resistance levels increased during this
period (2018–2023). The majority of pathogens increased or held steady, while
only Streptococcus pneumoniae decreased. The clearest sign of worsening
resistance is Acinetobacter spp.'s 8 percentage-point rise.

## SQL Techniques Demonstrated

- Staging tables to preserve raw imported data
- `GROUP BY` with aggregate functions (`AVG`, `SUM`)
- Conditional aggregation with `CASE WHEN`
- Common Table Expressions (`WITH`)
- Window functions: `ROW_NUMBER()`, `RANK()`, `LAG()`
- `PARTITION BY` for per-group ranking and comparisons
- Duplicate detection and data-quality validation
- Filtering, sorting, and multi-condition `WHERE` clauses
- Year-over-year and multi-period comparison

## Limitations

- Two country names (Türkiye, Côte d'Ivoire) contained encoding artifacts in
  WHO's original CSV export itself, confirmed via ISO3 codes and corrected in
  SQL.
- Resistance percentages are only as reliable as each country's testing
  volume; countries testing few isolates may have less statistically stable
  figures, even above the 10-isolate reliability threshold used in cleaning.
- Time series antibiotic coverage was limited to one representative antibiotic
  per pathogen (selected for clinical relevance), not full antibiotic coverage
  across all years.
  
**Data source and attribution:** 
All data used in this analysis was obtained
from the WHO Global Antimicrobial Resistance and Use Surveillance System
(GLASS) dashboard (https://worldhealthorg.shinyapps.io/glass-dashboard/),
published by the World Health Organization. This is an independent analysis
and is not affiliated with or endorsed by WHO.
