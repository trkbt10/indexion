# verify

## API

- **`SpecSymbol`** (Struct) — A symbol (gap term) identified in spec but missing from implementation.
- **`run_to_string`** (Function) — Run spec verify analysis and return rendered output as a string.
- **`default`** (Function) — Create a default verify configuration with sensible defaults.
- **`run_analysis`** (Function) — Run the full analysis pipeline. Returns the verify report.
- **`VerifyReportConfig`** (Struct) — Snapshot of configuration stored within the verify report.
- **`VerifyConfig`** (Struct) — Runtime configuration for the spec verify command.
- **`render_output`** (Function) — Render the verify report in the requested format.
- **`render_github_issue`** (Function) — Render as GitHub issue format with checkboxes.
- **`command`** (Function) — Define the spec verify command for argparse.
- **`VerifySummary`** (Struct) — Summary statistics for the verify report.
- **`collect_unique_kinds`** (Function) — Collect unique kind values from items.
- **`ImplEvidence`** (Struct) — Evidence for the gap term finding.
- **`VerifyItem`** (Struct) — A single verify result item.
- **`VerifyReport`** (Struct) — Full verify report output.
- **`filter_by_kind`** (Function) — Filter items by kind.
- **`render_markdown`** (Function) — Render as markdown.
- **`empty_report`** (Function) — 
- **`format_weight`** (Function) — 
- **`build_summary`** (Function) — 
- **`expand_spec_patterns`** (Function) —
