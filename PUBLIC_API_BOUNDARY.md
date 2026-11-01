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

## Host-bound API (moved in 0.5.0)

This package performs no file access and spawns no processes, so it compiles
for both targets and runs in the browser. These public functions moved to the
Erlang-only `vxml_pipeline_cli` package with unchanged signatures:

| Before (`vxml_pipeline`) | After |
|---|---|
| `default_file_assembler`, `default_writer`, `default_prettier_prettifier` | `vxml_pipeline_cli` |
| `run_renderer` (interactive runner) | `vxml_pipeline_cli.run_renderer` |
| `run_pipeline` (interactive runner) | `vxml_pipeline_cli.run_pipeline` |
| `read_from_dot_last_command`, `write_to_dot_last_command` | `vxml_pipeline_cli` |
| `handle_maintenance_requests` | `vxml_pipeline_cli` |
| `vxml_pipeline/generate_local_desugarers_dot_gleam`, `vxml_pipeline/renumber_local_desugarer_blames` | `vxml_pipeline_cli/…` (same module names) |
| `vxml_pipeline/writerly_defaults.default_writerly_assembler` | `vxml_pipeline_cli/writerly.default_writerly_assembler` |

`vxml_pipeline.run_pipeline` and `vxml_pipeline.run_renderer` remain with the
same signatures, using the portable synchronous runner. `CLIError` and its
constructors stay in `vxml_pipeline`. New portable API: `run_pipeline_fold`,
`run_pipeline_with_events`, `PipelineEvent`, `PipelineResult`,
`PipelineRunner`, `run_renderer_with_pipeline_runner`, `print_feedback_block`,
and `writerly_defaults.assemble_writerly_sources`.

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
