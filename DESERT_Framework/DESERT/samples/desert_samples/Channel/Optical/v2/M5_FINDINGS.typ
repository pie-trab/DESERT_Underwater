#set page(width: 16cm, height: auto, margin: 1.8cm)
#set text(size: 10pt)
#set par(justify: true)

= Milestone 5 final status

M5 is the final milestone. No new simulations were run and no physical
parameter was changed. The manuscript package is written in Typst.

== Deliverables

- `results_m5/manuscript/abstract.typ`: 185 words.
- `results_m5/manuscript/paper.typ`: short-paper draft; 2,533 words excluding
  the included abstract.
- `results_m5/manuscript/abstract_claims.csv`: machine-readable numeric
  claims mapped to the frozen M4 tables.
- `results_m5/REPRODUCE.typ`: exact reproduction sequence.
- `checks/milestone5.sh`: final manuscript/package check.

== Check result

`checks/milestone5.sh` prints PASS after the M4 package check. It verifies
abstract length and numeric consistency, the draft structure, figure
references, claim separation and protected result directories.

== Final status

The paper package is submission-ready except for author-supplied items:

- verified bibliography entries (the manuscript contains non-fabricated
  TODO placeholders);
- author names and affiliation;
- target-venue template and formatting.
- Typst source is provided, but the `typst` binary is not installed in this
  environment, so no PDF was compiled here.

No further milestone is planned. The acoustic equal-hop result remains
diagnostic-only; its exact first-hop mechanism is unresolved.
