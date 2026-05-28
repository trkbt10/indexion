# formats/lcov

`render_lcov(report : @coverage.CoverageReport) -> String`

Emits an [lcov.info tracefile](https://github.com/linux-test-project/lcov)
consumed by `genhtml`, `lcov --summary`, SonarQube, Codecov, Coveralls,
and most CI viewers.

Record order matches the `geninfo(1)` spec:

```
TN:<test_name>
SF:<source_file>
FN:<line>,<name>
FNDA:<count>,<name>
FNF:<functions_found>
FNH:<functions_hit>
BRDA:<line>,<block>,<branch>,<taken|->
BRF:<branches_found>
BRH:<branches_hit>
DA:<line>,<count>
LF:<lines_found>
LH:<lines_hit>
end_of_record
```

Records inside each file block are sorted (line ascending) so the
emitted text is byte-stable across runs.

Depends on `@coverage` (for the IR and shared sort helpers).
