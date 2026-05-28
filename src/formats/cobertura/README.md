# formats/cobertura

`render_cobertura(report : @coverage.CoverageReport) -> String`

Emits a [Cobertura `coverage.xml`](http://cobertura.sourceforge.net/xml/coverage-04.dtd)
consumed by Azure DevOps, GitLab, SonarQube, Codecov, and the Jenkins
Cobertura plugin.

The structure follows the DTD:

```xml
<coverage line-rate="…" branch-rate="…" lines-covered="…" lines-valid="…" …>
  <sources><source>…</source></sources>
  <packages>
    <package name="…" …>
      <classes>
        <class name="…" filename="…" …>
          <methods>…</methods>
          <lines>
            <line number="…" hits="…" branch="false"/>
            <line number="…" hits="…" branch="true" condition-coverage="50% (1/2)"/>
          </lines>
        </class>
      </classes>
    </package>
  </packages>
</coverage>
```

Files are grouped into `<package>` elements by `FileCoverage.pkg`; an
empty `pkg` value lands in a synthetic `(default)` package so the XML
never emits `name=""`.

Depends on `@coverage` (for the IR) and `@xml` (for the tree-based
writer that handles escaping, quoting, and indentation).
