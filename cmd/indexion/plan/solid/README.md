# indexion plan solid

## Overview

`indexion plan solid` builds a solidification plan for extracting duplicated code from multiple source directories into a shared target.

The command parses `--from`, `--to`, `--rules`, `--rule`, `--threshold`, `--strategy`, `--include`, `--exclude`, `--output`, and `--format`, then:

1. collects files from the source directories
2. computes cross-package similarity
3. applies extraction rules to matched files
4. emits a `SolidPlanJSON` summary
5. converts that summary into a `PlanDocument`

The intermediate plan is organized around `ExtractionGroup`, `ExtractionFile`, `UnmatchedFile`, `SolidConfigJSON`, and `SolidSummaryJSON`.

## Usage

```bash
indexion plan solid --from=pkg1/,pkg2/ --to=components/
indexion plan solid --from=pkg1/,pkg2/ --rules=.solidrc
indexion plan solid --from=pkg1/,pkg2/ --to=components/ --rule="auth/** -> auth/"
```

Important options:

- `--from=DIRS`: comma-separated source directories
- `--to=DIR`: target directory for extracted code
- `--rules=FILE`: load rules from a rules file
- `--rule=RULE`: add inline extraction rules
- `--threshold=FLOAT`: minimum similarity score
- `--strategy=NAME`: similarity strategy such as `tfidf`, `apted`, or `tsed`
- `--include=PATTERN` / `--exclude=PATTERN`: filter collected files
- `--output=FILE`: write the rendered plan to a file
- `--format=md|json|github-issue`: choose the final renderer

Rule syntax is `pattern -> target`. Relative targets use `--to`, and absolute targets can use an `@pkg/...` prefix.

## Output

The rendered plan starts with a summary section that records:

- source directories
- target path
- similarity threshold
- rules count
- files matched by rules
- unmatched file count

Each extraction section groups related files by `target_path` and reports `relative_path`, `similarity`, and the planned action. Files that are similar but not covered by any rule remain in the unmatched section for manual follow-up.
