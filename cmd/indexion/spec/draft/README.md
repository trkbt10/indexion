# indexion spec draft

`indexion spec draft` generates an SDD draft from usage-oriented Markdown such
as `README.md` files.

```sh
indexion spec draft --specs-dir=kgfs cmd/indexion/spec/align/README.md
```

The command is KGF-backed for document discovery and section extraction. It
uses heading sections and feature bullets to emit `sdd-requirement`
drafts that can be fed back into `indexion spec align`.

For an end-to-end dogfooding loop, run:

```sh
./scripts/spec-align-dogfood.sh
```

This drafts an SDD, runs align, and emits agent-oriented task files under
`.indexion/state/dogfood/spec-align/`.
