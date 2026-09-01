# Desugarer rewrite review queue

This file records source comments whose original column alignment or wording is
ambiguous enough to require later human confirmation. Rewriters should preserve
the apparent behavior and add an entry here rather than silently treating an
uncertain interpretation as authoritative.

## `add_between`

Original `Param` annotation:

```gleam
type Param = #(String,          String, String)
//             ↖                ↗       ↖
//             insert divs              tag name for
//             between adjacent         new element
//             siblings of these
//             two names
```

Interpretation used by the rewrite:

1. Tag of the first adjacent sibling.
2. Tag of the second adjacent sibling.
3. Tag of the element inserted between them.

The implementation agrees with this interpretation, but the crossed arrows and
shared first-two-field description should be confirmed by a human.

## Remaining top-down implementation ordering

The banner and whitespace audit found large library implementations whose
private functions are not yet consistently caller-before-callee:

- `counters_substitute_and_assign_handles`
- `fold_contents_into_text_if`
- `fold_custom_into_text`
- `fold_into_text`
- `fold_into_text__batch`
- `handles_grand_wrapper_generate_dictionary`
- `handles_generate_v_definitions_from_t_definitions`
- `handles_grand_wrapper_substitute`

These files contain substantial multi-pass implementations and semantic section
comments. Reorder each implementation as a dedicated pass so the comments move
with the functions they describe.

## `add_between_all_pairs_2`

Its original crossed-arrow `Param` annotation appears to mean: first list of
eligible left-sibling tags, second list of eligible right-sibling tags, and tag
of the inserted element. The implementation supports that reading. The `_2`
description says the second list should be smaller for efficiency; this agrees
with the short-circuit order of the two membership checks, but should be
confirmed by a human.
