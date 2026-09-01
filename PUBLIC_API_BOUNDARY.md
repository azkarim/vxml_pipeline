# Public API boundary

This document records the compatibility boundary preserved by the
`vxml_pipeline` package.

## Public module paths

The primary public modules are:

```gleam
import vxml_pipeline
import vxml_pipeline/core
import vxml_pipeline/authoring
import vxml_pipeline/nodemaps_2_transform
import vxml_pipeline/desugarers
```

## Constructor-owning public types

The following types have public constructors or variants that client code may
need to construct or pattern-match. Their defining modules own those
constructors and remain part of the compatibility API.

### `vxml_pipeline/core`

- `TrafficLight`
- `LatexDelimiterPair`
- `LatexDelimiterSingleton`
- `SingletonError`
- `DesugaringError`
- `DesugaringWarning`
- `Desugarer`
- assertive-testing data, collection, and error types

`DesugaringError`, `DesugaringWarning`, and `Desugarer` are especially
important to client-authored desugarers. Moving their definitions would make
aliases in `vxml_pipeline/core` insufficient because aliases cannot preserve
constructor imports.

### `vxml_pipeline`

- `FeedbackMargin`
- `FeedbackBlock`
- `Feedback`
- `PipelineStepContext`
- renderer stage and option records
- parsed command-line argument and error types
- pipeline and renderer result/error types

Monitor callbacks construct `Feedback` and `FeedbackBlock` values and inspect
`PipelineStepContext` values. These types therefore cannot be replaced by a
facade alias without also introducing a different constructor/accessor API.

### `vxml_pipeline/tracking`

- `SLine`
- `SelectionStatus`

Selectors inspect `SLine` variants and return `SelectionStatus` variants, so
the tracking module is the public owner of these constructors.

## Alias and opaque types

Aliases do not have constructors to re-export. They can appear in additional
API modules without losing functionality. Examples include:

- `Pipeline`
- `DesugarerTransform`
- `Selector`
- `LineSelector`
- `Assembler`
- `Parser`
- `Filterer`
- `Splitter`
- `Emitter`
- `Writer`
- `Prettifier`

`Monitor` is opaque and is created through `new_monitor`. Its constructor is
not part of the client API, so it can be moved more safely than a public custom
type if `vxml_pipeline.Monitor` and `vxml_pipeline.new_monitor` remain usable.

## Restructuring rules

1. Keep constructor-owning public types in their documented modules.
2. Extract implementation behind existing public entry points rather than
   moving their public types without a deliberate API change.
3. Do not use a public type alias as evidence that a constructor-owning API has
   been re-exported.
4. Prefer opaque types plus constructor/accessor functions only when that is
   the intended API.
5. Test every public-boundary change against the maintained consumers:
   `courses`, `dr`, `little-bo-peep-solid`, and `ti2_html`.
