# Public API boundary

This document records the compatibility boundary preserved by the
`vxml_pipeline` package.

## Compatibility module paths

During the compatibility phase, existing Gleam module paths remain supported:

```gleam
import desugaring
import desugaring/core
import desugaring/authoring
import desugaring/nodemaps_2_transform
import desugaring/desugarers
```

The Gleam package is named `vxml_pipeline`, while these modules retain their
established names. Package names and Gleam module names do not have to match.
Preserving the module paths avoids a coordinated source migration in all
current consumers.

No `vxml_pipeline` facade should be presented as a replacement for these
modules while constructor-owning types remain here. Gleam type aliases do not
re-export custom type constructors, so such a facade would expose an
incomplete API.

## Constructor-owning public types

The following types have public constructors or variants that client code may
need to construct or pattern-match. Their defining modules own those
constructors and remain part of the compatibility API.

### `desugaring/core`

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
aliases in `desugaring/core` insufficient because aliases cannot preserve
constructor imports.

### `desugaring`

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

### `desugaring/tracking`

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
type if `desugaring.Monitor` and `desugaring.new_monitor` remain usable.

## Restructuring rules

Until a deliberate breaking module migration:

1. Keep constructor-owning public types in their current modules.
2. Extract implementation behind existing public entry points rather than
   moving their public types.
3. Do not use a public type alias as evidence that a constructor-owning API has
   been re-exported.
4. Prefer opaque types plus constructor/accessor functions only when that is
   the intended API, not as an incidental compatibility workaround.
5. Test every public-boundary change against the maintained consumers:
   `courses`, `dr`, `little-bo-peep-solid`, and `ti2_html`.
6. Reserve module-path renaming for a coordinated breaking release.

## First independent release

The compatibility-first release should change the dependency package to
`vxml_pipeline` while retaining the established `desugaring/*` module paths.
This separates package publication from a later, explicitly breaking module
namespace migration.
