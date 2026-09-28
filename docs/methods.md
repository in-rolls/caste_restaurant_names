
# Methods revision and migration audit

The archived Python estimates reproduce, but their original
interpretation was stronger than the collection design supports. The R
pipeline preserves all archived inputs, reports captured-listing shares,
and separates classification uncertainty from conditional bootstrap
variation. No new collection or model calls were made for this
migration.

## Claims and estimands

| Claim | Unit and denominator | Measurement and comparison | Supported interpretation |
|----|----|----|----|
| Identity branding varies across districts | Unique captured restaurant listing, within district | Union of confirmed dictionary groups; sampled collections in 2026 | Descriptive share in captured listings, conditional on the dictionary and saved verdicts |
| Branding composition differs regionally | Same listing denominator for each group | Regional, surname/title, merchant, explicit upper-caste indicators; groups may overlap | Descriptive composition, without a causal explanation for regional differences |
| SC/ST-informative surnames are rare | Unique captured listing; names selected from an external weighted lookup | Dictionary candidates require contextual review | Candidate screening only; owner caste and previously claimed manual exclusions are not established |
| Historical branding was common | Listed eating house within year, city, and coded segment | Broader identity/purity labels in directories | Within-corpus description; historical and modern coding/source coverage are not directly comparable |

## Numerical changes

| Collection | Old n | New n | Old confirmed | New confirmed | Old % | New confirmed % | Unresolved |
|:---|---:|---:|---:|---:|:---|:---|---:|
| Bengaluru grid | 7770 | 7769 | 414 | 415 | 5.33 | 5.34 | 5 |
| Chennai grid | 4962 | 4961 | 159 | 159 | 3.20 | 3.20 | 14 |
| Mysuru grid | 2175 | 2175 | 134 | 134 | 6.16 | 6.16 | 0 |
| Bengaluru sampled | 3447 | 3447 | 173 | 173 | 5.02 | 5.02 | 0 |
| Delhi sampled | 4009 | 4009 | 178 | 178 | 4.44 | 4.44 | 0 |
| Jaipur sampled | 1771 | 1771 | 65 | 65 | 3.67 | 3.67 | 0 |
| Kolkata sampled | 3768 | 3768 | 91 | 91 | 2.42 | 2.42 | 0 |
| Lucknow sampled | 1855 | 1855 | 101 | 101 | 5.44 | 5.44 | 0 |
| Chennai sampled | 5025 | 5025 | 153 | 153 | 3.04 | 3.04 | 1 |
| Mysuru sampled | 904 | 904 | 69 | 69 | 7.63 | 7.63 | 0 |
| Varanasi sampled | 940 | 940 | 39 | 39 | 4.15 | 4.15 | 0 |

All original sampled point estimates and density-weighted sensitivities
match the archived tables within their six-decimal rounding. Grid group
estimates and frozen screening-sample counts reproduce as well. These
gates run on the data and numerical outputs, not assertions about README
content. `out/tab/parity.csv` records the comparisons.

The new grid analysis applies the v3 dictionary consistently with the
sampled analysis. ICU normalization changes 1006 retained names; these
changes and their old keys are listed in `out/tab/normalization.csv`.
The match-level differences are in `out/tab/match_changes.csv`. There
are 20 unresolved restaurant–label pairs (16 distinct verdict keys). The
confirmed share is a lower endpoint for unresolved dictionary matches.
`identification_upper` counts those matches as positive while holding
all other coding decisions fixed; it does not bound dictionary false
negatives or platform selection.

The R linker searches all candidates within 200 m instead of using the
old fixed spatial bucket neighborhood. It chooses the highest token
Jaccard score, breaking ties by input order, and enforces one-to-one
links. Normalization and candidate-order changes can change matches even
where the old counts reproduced. Grid denominators change as shown
above; `out/tab/linkage_changes.csv` records changed links for
inspection. Linkage uncertainty is not included in any interval.

## Query-point bootstrap and selection

| District | Listings | Queries | With first captures | Without first captures | At 20-result cap, % |
|:---|---:|---:|---:|---:|:---|
| Bengaluru | 3447 | 400 | 298 | 102 | 25.75 |
| Delhi | 4009 | 400 | 347 | 53 | 30.00 |
| Jaipur | 1771 | 400 | 238 | 162 | 7.50 |
| Kolkata | 3768 | 400 | 349 | 51 | 53.00 |
| Lucknow | 1855 | 400 | 264 | 136 | 7.25 |
| Chennai | 5025 | 400 | 379 | 21 | 55.50 |
| Mysuru | 904 | 400 | 153 | 247 | 2.75 |
| Varanasi | 940 | 400 | 167 | 233 | 4.75 |

The old bootstrap conditioned on points with retained restaurants. The
revised bootstrap resamples all selected query points, including those
with no retained first captures, and recomputes the ratio of confirmed
listings to all retained listings. The same seeded R draws compare the
two conventions below, holding the archived classification fixed. R and
Python seeds do not imply identical random draws.

| District  | Occupied only, % | All query points, % |
|:----------|:-----------------|:--------------------|
| Bengaluru | \[4.26, 5.87\]   | \[4.23, 5.81\]      |
| Delhi     | \[3.85, 5.08\]   | \[3.78, 5.08\]      |
| Jaipur    | \[2.72, 4.69\]   | \[2.71, 4.65\]      |
| Kolkata   | \[1.90, 2.95\]   | \[1.92, 2.96\]      |
| Lucknow   | \[4.40, 6.60\]   | \[4.40, 6.55\]      |
| Chennai   | \[2.53, 3.58\]   | \[2.53, 3.59\]      |
| Mysuru    | \[5.93, 9.54\]   | \[5.82, 9.43\]      |
| Varanasi  | \[2.79, 5.65\]   | \[2.88, 5.67\]      |

Both calculations remain approximations conditional on first-capture
assignments. The collector discards repeat encounters across queries, so
we cannot reconstruct the restaurant union for hypothetical resampled
query sets. No finite-population or true restaurant
inclusion-probability correction is claimed. Query caps are frequent in
some districts, and captured listings may include establishments outside
the intended restaurant concept. These limitations can vary by district;
equal dilution is not assumed.

Settings are 2,000 draws, seed 7, sampling query points with
replacement, and R type-7 percentile endpoints. Draws with zero retained
denominator are counted and excluded; intervals are withheld if fewer
than 95% of draws are usable, fewer than two occupied points exist, or
no successes are observed. A zero observed count therefore does not
become a claim of zero population uncertainty. Intervals condition on
the classification of confirmed hits; they do not propagate dictionary,
transliteration, or model errors.

Inverse frame density at the first capturing point gives the separate
`density_sensitivity` series. It is a different weighted descriptive
quantity. The pipeline also reports excluding own-city Mysore/Mysuru
terms and ignoring the regional model veto in `out/tab/sensitivity.csv`.
Those alternatives retain the same denominator and expose measurement
choices without presenting them as competing causal models.

## Screening and supplementary analyses

The frozen false-negative sample was reconstructed with the original
Python `random.Random(42)` procedure, in sorted grid-region order, from
the v1 unmatched pool. Repeated restaurant names retain their original
sampling multiplicity, while saved verdicts join by name. The R pipeline
restricts that sample to names still unmatched under the revised
dictionary and reports missing first- or second-pass verdicts
explicitly. Model-positive screening calls remain model judgments, not
independently verified ground truth. We therefore report the screen
separately rather than promoting its implied prevalence adjustment to
the primary result.

| City | Sample | Two-pass positives | Missing verdicts | Confirmed screen share, % |
|:---|---:|---:|---:|:---|
| Bengaluru | 493 | 1 | 0 | 0.20 |
| Chennai | 485 | 3 | 1 | 0.62 |
| Mysuru | 497 | 4 | 0 | 0.80 |

The SC/ST supplement uses the archived lookup threshold
`p_sc + p_st >= 0.8`, at least 10,000 carriers, and normalized terms of
at least four characters. A listing matching multiple terms counts once
in the candidate summary. The lookup is external and its checksum is
recorded in the input manifest. Missing lookup data fail the full
analysis with an explicit path message; it is not silently skipped.

Historical coding is summarized directly from the committed hand-coded
CSV, with source-line references required. The OCR excerpts support
source inspection but the migration does not claim a fresh manual
transcription audit. Identity markers include the coded regional-place
category, which accounts for the fifteenth marked Indian-run Madras
entry in 1925; the previous prose enumerated only fourteen of the
fifteen.

## Check matrix

| Check | Finding or applicability |
|----|----|
| Denominator and unit | Entity-level unions prevent double counting across dictionary hits; modern captured listings and historical eating-house entries remain separate universes |
| Missing versus zero | Missing verdicts are unresolved; missing point assignments/density and incomplete query coverage fail; zero observed groups remain in all outputs |
| Aggregation | Shares are ratios of listing counts, not averages of point-level shares; density-weighted shares are separately labeled |
| Provenance | Frozen inputs and external lookup are checksummed; generated tables, plots, and prose share outputs; original tables reproduce |
| Internal consistency | Group numerators cannot exceed denominators; intervals, proportions, historical counts, and generated report numbers are checked during the build |
| EDA and support | Query occupancy and capped shares are reported for each district; zeros and small supports are explicit |
| Joins and construction | Keys and join cardinalities are enforced; normalization mapping, exclusions, verdicts, and source linkage are inspectable |
| Estimand and inference | Captured-listing description; query-point bootstrap is conditional and approximate; no design-based district-population claim |
| Skew and influence | Unequal cluster sizes are retained in ratio estimates; leave-one-point-out ranges are exported; inverse-density weighting remains sensitivity only |
| Design and measurement | Fixed dictionary and archived coding are preserved for the baseline; revised normalization and dictionary scope are disclosed; labels are not owner attributes |
| Statistical tests and causal designs | No randomized treatment, regression, panel, IV, RD, or causal effect is estimated; significance-filter, power, and interaction-test checks are inapplicable |
| Generated labels | Conditional intervals exclude classification uncertainty; unresolved-hit bounds and alternative coding rules are provided |
| Validation | Hand-calculated fixtures, deterministic simulation, archived numerical gates, Python mocked requests, checkpoint tests, linting, and rendered-figure checks |

Rejected or qualified concerns: excluding no-first-capture points
changes bootstrap intervals but not the point estimate; these points
cannot be identified as truly empty queries from retained rows. Density
weighting and unweighted shares need not coincide because they describe
different quantities. Reproducing the old output establishes numerical
parity, not valid population inference.

Untestable with the retained files: full query-overlap histories,
coverage of restaurants absent from either platform, independent
correctness of all model labels, and the README’s former hand-reviewed
surname claims. These are limitations of the retained evidence, not
repairs accomplished by a language port.

## Implementation references

The R implementation uses explicit join relationships from the [dplyr
join
documentation](https://dplyr.tidyverse.org/reference/mutate-joins.html),
ICU transformations through [stringi](https://stringi.gagolewski.com/),
and the standard [ggplot2 interval
geoms](https://ggplot2.tidyverse.org/reference/geom_linerange.html).
Dependency environments follow [renv](https://rstudio.github.io/renv/)
and [uv project
configuration](https://docs.astral.sh/uv/concepts/projects/config/).
