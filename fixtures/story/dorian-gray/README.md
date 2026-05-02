# Fixture — *The Picture of Dorian Gray* (Chapters I–III)

This is the primary English-language fixture for the `indexion story`
command. It is intended to exercise the tool's ability to detect
divergence between **the sources a writer works from** (plot
outlines, character sheets, setting notes, research, scene notes)
and **the prose those sources eventually produce**.

## What the fixture contains

- `prose/` — Chapters I, II, and III of *The Picture of Dorian Gray*
  by Oscar Wilde, taken verbatim from Project Gutenberg
  ([eBook #174](https://www.gutenberg.org/ebooks/174), public domain).
  The Project Gutenberg license header, the table of contents, and
  Wilde's preface have been stripped; only the prose itself remains.
  Original chapter boundaries are preserved.

- `sources/` — A set of **fictional** notebook artifacts representing
  the planning material a writer might have produced before drafting
  the prose. These are not Wilde's actual notes (those do not
  survive in this form). They have been authored to be plausible,
  internally consistent, and deliberately seeded with divergences
  from the prose so that the fixture has known ground truth.

```
fixtures/story/dorian-gray/
├── README.md                            (this file)
├── sources/
│   ├── plot/
│   │   ├── 01-outline.md
│   │   └── 02-revision.md
│   ├── references/
│   │   ├── characters.md
│   │   ├── settings.md
│   │   └── research-notes.md
│   └── scene-notes/
│       ├── studio-scene.md
│       ├── garden-scene.md
│       └── portrait-scene.md
└── prose/
    ├── 01-chapter.txt
    ├── 02-chapter.txt
    └── 03-chapter.txt
```

## What this fixture is for

A novel's prose is the *output* of an n-to-m mapping from many
sources (plot drafts, character bibles, research notebooks, scene
sketches) to many prose chapters. Divergence between sources and
prose is normal and often healthy — the writer's mind keeps
working — but some divergences are bugs:

- A plot beat that is planned but never written (under-coverage).
- A detail in the prose that no source supports (drift).
- A v1↔v2 conflict that the prose has silently resolved, leaving
  the older outline misleading.
- A character-sheet attribute the prose contradicts.

The `indexion story` command should be able to surface these. This
fixture is the test case it is verified against.

## How to run indexion against the fixture

The `indexion story` command does not yet exist as of this fixture's
authoring. The intended invocation, when it exists, is roughly:

```bash
moon run cmd/indexion --target native -- story \
  --sources fixtures/story/dorian-gray/sources \
  --prose   fixtures/story/dorian-gray/prose
```

Until then, the fixture can be exercised by the existing
`plan reconcile`, `explore`, and `search` commands run across the
combined directory tree. For example:

```bash
moon run cmd/indexion --target native -- search \
  "silver cigarette case" fixtures/story/dorian-gray/

moon run cmd/indexion --target native -- plan reconcile \
  fixtures/story/dorian-gray/
```

## The story arc covered

Chapters I–III span:

1. Basil Hallward's studio, and Lord Henry Wotton's first sight of
   the finished portrait.
2. Dorian Gray's arrival, his sitting for the portrait, Lord Henry's
   garden seduction-by-rhetoric, the unveiling of the canvas, and
   the wish.
3. The next day. Lord Henry calls on his uncle Lord Fermor in the
   Albany and learns Dorian's lineage.

This is a complete, self-contained narrative arc: introduction,
the planting of the moral seed, and the first move toward
investigation of its soil.

---

## Seeded test cases (ground-truth divergences)

These are the divergences the fixture is designed to test. An
implementation of `indexion story` is expected to flag at least
these. The list is exhaustive only in the sense that *these are the
ones that were planted on purpose*; natural drift may produce others.

### A. Plot-only items (planned but absent from prose)

A1. **The pink-flowering thorn as a recurring motif.**
   - Source: `sources/plot/02-revision.md` says of the thorn that
     it "is to recur" through the opening movement and serves as a
     small foreshadowing.
   - Prose: the thorn appears exactly once, in `prose/01-chapter.txt`
     line 4 ("the more delicate perfume of the pink-flowering
     thorn"). It does not recur. The recurrence is plot-only.

A2. **Lord Henry's walk to Berkeley Square as the moment he turns
     Dorian into a "project."**
   - Source: `sources/plot/02-revision.md` Act 5 calls out the
     walk from the Albany to Berkeley Square as "the first sign that
     Dorian has become, for him, a project." The walk is supposed
     to be "glanced at" in the prose.
   - Prose: `prose/03-chapter.txt` line 170 says only that he
     "turned his steps in the direction of Berkeley Square." There
     is no internal reflection, no moment of decision; the
     interpretive beat does not land on the page.

A3. **The walled studio garden's specific geography
     (south-wall roses, central laburnum, lilac at the side,
     thorn by the door).**
   - Source: `sources/references/settings.md` lays out the garden
     in detail.
   - Prose: the garden is described impressionistically. The
     specific spatial layout is not present.

### B. Prose-only items (in prose but not in any source)

B1. **The "Parker" the butler.**
   - Prose: `prose/02-chapter.txt` line 207 ("Just touch the bell,
     and when Parker comes...") and line 245 ("Parker has brought
     out the drinks").
   - Sources: no source mentions a servant by name. The studio
     setting note describes the room and the garden but staffs
     the establishment with no one.

B2. **The "olive-coloured face" / "flowerlike hands" physical
     description of Lord Henry.**
   - Prose: `prose/02-chapter.txt` lines 233 and 235 give Lord
     Henry "olive-coloured face" and "cool, white, flowerlike
     hands."
   - Sources: `sources/references/characters.md` describes Lord
     Henry as "tall, languid, fastidiously dressed" — no mention
     of olive complexion or of the flowerlike hands. These vivid
     details enter at the level of the prose itself.

### C. v1↔v2 conflicts where the prose follows one over the other

C1. **Where Lord Henry delivers the "Time is jealous" speech —
     studio (v2) or garden (v1)?**
   - `sources/plot/01-outline.md` Act 4 places the seduction
     speech in the **garden**.
   - `sources/plot/02-revision.md` Act 3 explicitly moves the
     "Time is jealous of beauty" line into the **studio**, as
     the load-bearing change of the revision.
   - Prose: the line "Time is jealous of you, and wars against
     your lilies and your roses" appears in `prose/02-chapter.txt`
     line 284, in the **garden** scene, after Basil has stayed
     behind to work on the background.
   - The prose follows **v1**. The v2 revision was not adopted.
     This is the kind of conflict the tool should surface: the
     newer outline is now misleading as a description of the
     book.

C2. **The silver cigarette case — Basil's family heirloom (v1)
     or dropped entirely (v2)?**
   - `sources/plot/01-outline.md` Act 1 introduces a *silver
     cigarette case* belonging to **Basil**, inherited from the
     painter's late father, picked up and turned over by Lord
     Henry.
   - `sources/plot/02-revision.md` Act 1 explicitly **cuts** the
     case as "clever but did not earn its keep."
   - Prose: a silver case appears in `prose/01-chapter.txt`
     line 437 — but it is **Lord Henry's own**, not Basil's, and
     it has no family history attached. The prose follows neither
     outline cleanly. v1 had the right object on the wrong
     person; v2 cut an object the prose actually keeps. A good
     story-divergence tool should recognise that "silver case"
     is a hit on v1's lexicon while contradicting v1's
     attribution.

### D. Character-sheet attributes the prose contradicts or omits

D1. **Lord Henry's wife "Lady Victoria."**
   - Source: `sources/references/characters.md` names her
     "Lady Victoria" and describes the marriage as "unhappily
     and decoratively" arranged.
   - Prose: Lord Henry's wife is referred to in Chapter I lines
     119–124 as "my wife" only. She is not named anywhere in
     Chapters I–III. The character-sheet name is unsupported by
     the prose at hand. (If she is named differently in later
     chapters, that is a further divergence the tool may detect
     when wider scope is loaded.)

D2. **The studio's neighbourhood (Kensington / Holland Park).**
   - Source: `sources/references/settings.md` places the studio
     "somewhere within walking distance of Holland Park, on the
     borders of Kensington" as a "working assumption."
   - Prose: the prose names no London neighbourhood for the
     studio at all. The setting note's specific working
     assumption has no anchor in the text.

D3. **Dorian Gray's age stated as exactly "twenty."**
   - Source: `sources/references/characters.md` first line:
     "Age at first appearance: twenty."
   - Prose: `prose/01-chapter.txt` line 351 has Basil say Dorian
     "is really over twenty." The character sheet has fixed a
     value that the prose has, in fact, deliberately blurred.

---

## Notes for fixture maintainers

- The prose is taken verbatim from Project Gutenberg's plain-text
  edition of the 1891 book. Do not edit the prose to make sources
  match; the prose is the authoritative text against which
  divergences are measured.
- The sources are the variable. If a future change to the seeded
  test cases is wanted, edit the sources, not the prose, and
  update the ledger above.
- Total source size is roughly 26 KB across eight files; total
  prose size roughly 85 KB across three files. This is sufficient
  to exercise vocabulary-based divergence detection but small
  enough to round-trip in a test in well under a second.
