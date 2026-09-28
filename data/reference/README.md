# Frozen analytical references

These files were extracted before replacing the Python analysis. They are
research inputs, not generated reports.

- `dictionary.csv`: the ordered `TAXONOMY` literal in the former
  `scripts/analyze_caste_branding.py` (v3). Variant order determines which
  spelling is recorded when several match the same canonical term.
- `normalization.csv`: each distinct original name in the eleven frozen raw
  JSONL collections and its output from the former Python `normalize_text`.
  R joins this table by the exact original name to preserve adjudication and
  exclusion keys. New analytical matching uses ICU normalization, not this cache.
- `screening_sample.csv`: 500 unmatched rows per grid city, sampled from
  `data/analysis_2026_08_30_region_*_matches.jsonl` in sorted path order using
  one Python `random.Random(42)` instance and `random.sample`. Row multiplicity
  is retained. These rows reproduce the original v2 false-negative sample after
  restricting to names that v2 left unmatched.
- `source_checksums.csv`: SHA-256 checksums of the Python source and extracted
  reference files at migration. Deleted Python analysis remains available in
  Git history. The source revision is recorded below.

The frozen data can be audited without running the old Python normalization
package. The original script's Unicode handling covered five Indic blocks;
ICU also transliterates scripts it left unchanged. Changed matches are recorded
in `out/tab/match_changes.csv`, and unknown verdicts remain unresolved.

Source revision: a8af1e05d4d4eed457983c2fffb505c00ba2fd13
