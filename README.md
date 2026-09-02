# VXML Pipeline

[![Package Version](https://img.shields.io/hexpm/v/vxml_pipeline)](https://hex.pm/packages/vxml_pipeline)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/vxml_pipeline/)

Run and debug [VXML](https://hex.pm/packages/vxml) transformation
pipelines.

The package provides two related execution layers:

- `run_pipeline` applies an ordered list of named VXML transformations to one
  VXML tree
- `run_renderer` runs a complete file-oriented render: assemble, parse,
  filter, transform, split, emit, write, and optionally prettify

The package also includes reusable desugarers, pipeline monitors, command-line
argument handling, local-desugarer tooling, and a test framework for
desugarers.

Add it to a Gleam project with:

```sh
gleam add vxml_pipeline
```

## Desugarers

The atomic unit encapsulating a named VXML-to-VXML transformation is a
_desugarer_. It accepts one VXML tree and either returns a transformed VXML
tree with warnings or returns a `DesugaringError`:

```gleam
pub type DesugaringError {
  DesugaringError(blame: Blame, message: String)
}

pub type DesugaringWarning {
  DesugaringWarning(blame: Blame, message: String)
}

pub type DesugarerTransform =
  fn(VXML) -> Result(#(VXML, List(DesugaringWarning)), DesugaringError)

pub type Desugarer {
  Desugarer(
    name: String,
    transform: DesugarerTransform,
    ...
  )
}
```

The generated `vxml_pipeline/desugarers` module exports the reusable desugarer
constructors:

```gleam
import vxml_pipeline/desugarers as ds

let pipeline = [
  ds.rename(#("Chapter", "section")),
  ds.append_class(#("section", "chapter")),
]
```

Each constructor validates or prepares its parameters when it creates the
`Desugarer`. The resulting transform is then ready to be applied repeatedly.

### Desugarer naming conventions

A desugarer whose name ends in `__batch` accepts a list as its parameter and
performs the same operation for each item in that list. This can express a
group of related transformations with one constructor call and, where the
implementation permits, one tree traversal.

A desugarer whose name ends in `__outside` has a constructor with a second
argument: a list of tag names that identify forbidden subtrees. The desugarer
does not operate inside subtrees rooted at any of those tags.

The variants can be combined, as in `name__batch__outside`, but the library
does not provide every possible variant of every desugarer. `__batch`,
`__outside`, and combined variants are generally added only after their use has
proved useful in an application.

### Authoring a desugarer

Client-defined desugarers are ordinary Gleam modules. Their constructors accept
a public-facing `Param`, prepare it once as a private `InnerParam`, and capture
the prepared value in a reusable transform. Preparation is the place for
validation and one-time work such as compiling a regular expression.

The `vxml_pipeline/authoring` module packages this preparation and transform
construction into a `Desugarer`:

```gleam
import gleam/list
import gleam/regexp.{type Regexp}
import vxml.{Line, T}
import vxml/blame as blame
import vxml_pipeline/authoring
import vxml_pipeline/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  DesugaringError,
}
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

pub const name = "redact_matching_lines"

pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param = String

type InnerParam {
  InnerParam(pattern: Regexp)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  case regexp.from_string(param) {
    Ok(pattern) -> Ok(InnerParam(pattern))
    Error(_) ->
      Error(DesugaringError(
        blame.no_blame,
        "Invalid regular expression: " <> param,
      ))
  }
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = fn(vxml) {
    case vxml {
      T(_, lines) ->
        T(
          ..vxml,
          lines: list.map(lines, fn(line) {
            Line(
              ..line,
              content: case regexp.check(inner.pattern, line.content) {
                True -> "[redacted]"
                False -> line.content
              },
            )
          }),
        )
      _ -> vxml
    }
  }

  n2t.one_to_one_no_error_nodemap_2_desugarer_transform(nodemap)
}
```

By convention, `Param` is a structural type composed from tuples, lists,
options, strings, integers, and booleans. A pipeline can therefore call the
constructor without importing a desugarer-specific record. `InnerParam` is
private and may use named records, compiled values, or any other representation
that makes the implementation clear and efficient.

`authoring` also provides constructors for infallible, no-parameter, and
`outside`-aware desugarers. `authoring.blame(name, line_no)` creates provenance
for VXML introduced by a desugarer.

Most reusable desugarers define a typed operation on one node and use
`vxml_pipeline/nodemaps_2_transform` to walk the complete tree. A desugarer may
instead implement `DesugarerTransform` directly when its operation requires
different traversal behavior.

The repository's desugarer conventions are recorded in the
[desugarer style guide](https://github.com/vistuleB/vxml_pipeline/blob/main/DESUGARER_STYLEGUIDE.md).
Desugarer testing and application-local desugarer registries are described
later in this README.

## Pipelines and `run_pipeline`

A `Pipeline` is an ordered list of desugarers:

```gleam
pub type Pipeline =
  List(Desugarer)
```

`run_pipeline` applies each desugarer to an existing VXML tree. It does not
assemble input, parse a source format, split output, emit another format, or
write files. This makes it suitable for standalone use when an application
already owns those operations.

The function requires:

- the initial VXML tree;
- the pipeline;
- a list of monitors, which may be empty;
- pipeline UX options controlling monitor interaction, long-running notices,
  and the margin of pipeline-owned feedback.

```gleam
import vxml_pipeline as vp
import vxml_pipeline/core
import vxml_pipeline/desugarers as ds

let pipeline: core.Pipeline = [
  ds.rename(#("Chapter", "section")),
]

let result =
  vp.run_pipeline(
    vxml,
    pipeline,
    [],    // monitors
    vp.PipelineUXOptions(
      monitor_interactive_mode: False,
      report_long_running_desugarers: True,
      feedback_margin: 0,
    ),
  )
```

On success, `run_pipeline` returns the transformed VXML, accumulated warnings,
and one duration per desugaring step, in pipeline order. It returns a
`PipelineExecutionError` when a desugarer fails, a monitor stops execution, or
the user exits an interactive run. Timing is part of pipeline execution;
monitors do not measure desugarer durations.

No renderer or command-line setup is required for standalone execution. A
Gleam program can construct or parse a VXML value, build a pipeline, call
`run_pipeline`, and handle the returned `Result` directly.

## Renderers

A `Renderer` places a pipeline inside a complete file-oriented process. It
coordinates application-provided stages for obtaining VXML and turning the
final VXML into output files.

### Data flow

The complete renderer has the following stages:

```text
input path
  -> Assembler
  -> List(InputLine)
  -> Parser
  -> VXML
  -> Filterer
  -> VXML
  -> Pipeline
  -> VXML
  -> Splitter
  -> List(OutputFragment(classifier, VXML))
  -> Emitter
  -> List(OutputFragment(classifier, List(OutputLine)))
  -> Writer
  -> output files
  -> optional Prettifier
```

Applications provide the stages that are specific to their input format and
output format. The package supplies defaults for common single-file XML,
[Writerly](https://hex.pm/packages/writerly), HTML, JSX, file-writing, and
Prettier workflows.

### Building a renderer

The following is a complete single-file XML-to-JSX renderer of the same shape
as `test/renderer_integration_test.gleam`:

```gleam
import vxml_pipeline as vp
import vxml_pipeline/core
import vxml_pipeline/desugarers as ds

fn pipeline() -> core.Pipeline {
  [
    ds.rename(#("Chapter", "section")),
    ds.append_class(#("section", "chapter")),
  ]
}

pub fn run() {
  let options = vp.vanilla_options()

  let parameters =
    vp.RendererParameters(
      input_dir: "input.xml",
      output_dir: "build/output",
      prettifier_behavior: vp.PrettifierOff,
    )

  let renderer =
    vp.Renderer(
      assembler: vp.default_file_assembler,
      parser: vp.default_xml_parser,
      filterer: vp.default_filterer(_, options, []),
      pipeline: pipeline(),
      splitter: vp.stub_splitter(".tsx"),
      emitter: vp.stub_jsx_emitter,
      writer: vp.default_writer,
      prettifier: vp.empty_prettifier,
    )

  vp.run_renderer(renderer, parameters, options)
}
```

`run_renderer` returns the relative paths written during the run. Its error
type retains the error type of each application-provided stage. It prints its
own progress block and terminates that block with one blank line.

The default writer creates missing parent directories and overwrites output
files. Prettifier modes are:

- `PrettifierOff`
- `PrettifierOverwriteOutputDir`
- `PrettifierToBespokeDir(Option(String))`

## Writerly input

[Writerly](https://hex.pm/packages/writerly) support is kept in a separate
adapter module because the renderer core operates on `InputLine`, `OutputLine`,
and VXML rather than on its syntax directly:

```gleam
import vxml_pipeline/writerly_defaults as wd

wd.default_writerly_assembler
wd.default_writerly_parser
wd.default_writerly_emitter
```

The assembler accepts either a file or a directory tree. It reports the
assembled directory tree as verbose feedback and respects the renderer's
path-selection options.

## Feedback

Assemblers, parsers, filterers, splitters, emitters, and writers return their
payload together with `Feedback`:

```gleam
pub type Feedback {
  NoFeedback
  SomeFeedback(List(FeedbackBlock))
}

pub type FeedbackBlock {
  FeedbackBlock(lines: List(String), margin: FeedbackMargin)
}

pub type FeedbackMargin {
  AtRunnerMargin
  Verbatim
}
```

Stage implementations construct their own feedback. The renderer prints it
when verbose output is enabled. `AtRunnerMargin` places the block at the
renderer runner's margin; `Verbatim` leaves its lines unindented.

## Monitors

A monitor observes the initial VXML and the result of every desugaring step.
It may retain state, produce feedback, or stop the pipeline with an error:

```gleam
vp.new_monitor(
  "example",
  initial_state,
  fn(vxml, state, context) {
    // context contains the step number and adjacent desugarers
    Ok(#(next_state, vp.NoFeedback))
  },
)
```

`PipelineStepContext` contains:

- the current step number;
- the previous desugarer, if any;
- the next desugarer, if any.

A monitor error becomes a `PipelineMonitorError` and identifies the monitor,
step number, and message. Monitor feedback is sent to the pipeline runner as
discrete feedback blocks. Interactive mode pauses once for each feedback block.

The built-in `--track`, `--dump`, and `--validate-vxml` facilities are
implemented as monitors. Applications can install VXML validation directly:

```gleam
vp.vxml_validation_monitor(
  False, // do not warn about leading whitespace in attribute values
)
```

Invalid VXML stops the pipeline at the first invalid state. Passing `True`
also reports leading attribute-value whitespace as monitor feedback. Leading
whitespace remains valid VXML; trailing spaces and tabs are invalid.

`empty_text_node_monitor()` is a narrower monitor that rejects only text nodes
with no lines. It does not validate tags, attributes, or individual line
contents. The corresponding command-line form is
`--validate-vxml -lines-only`. It cannot be combined with
`-warn-attribute-whitespace`.

## Renderer parameters and options

`RendererParameters` contains values required for a run:

```gleam
vp.RendererParameters(
  input_dir: "src/content",
  output_dir: "build/output",
  prettifier_behavior: vp.PrettifierOff,
)
```

`RendererOptions` controls optional behavior. Start from
`vanilla_options()` and update only the relevant fields:

```gleam
let options =
  vp.RendererOptions(
    ..vp.vanilla_options(),
    verbose: True,
    artifacts: True,
    warnings: True,
  )
```

Options include filtering selectors, monitor configuration, tracking and dump
factories, timing-table configuration, warning and artifact reporting,
long-running-step reports, output-table widths, and stage dumps.

`pipeline_table_default_desugarer_name_columns`,
`pipeline_table_default_param_columns`, and
`pipeline_table_default_outside_columns` set the corresponding maximum column
widths in the `--table` output. Each width has a minimum of 10 columns.

`pipeline_timing_table_default_desugarer_name_columns` and
`pipeline_timing_table_default_duration_columns` do the same for the
desugarer-name and duration columns in the `--times` output.

## Command-line integration

The package can parse its standard renderer options together with a declared
set of application-specific options. Application-specific values are stored in
`ParsedCLIArguments.user_args`; the package groups them but does not interpret
them.

A typical entry point has this shape:

```gleam
import argv
import vxml_pipeline as vp
import gleam/io
import local_desugarers
import on

pub fn main() {
  io.println("")

  let args = argv.load().arguments

  use args <- on.error_ok(
    vp.read_from_dot_last_command(args),
    handle_cli_error,
  )

  use arguments <- on.error_ok(
    vp.process_command_line_arguments(args, ["--local-option"]),
    handle_cli_error,
  )

  use help_requested <- on.error_ok(
    vp.handle_help_requests(arguments, local_cli_usage),
    handle_cli_error,
  )

  use maintenance_requested <- on.error_ok(
    vp.handle_maintenance_requests(
      arguments,
      local_desugarers.assertive_tests,
    ),
    handle_cli_error,
  )

  use _ <- on.stay(case help_requested || maintenance_requested {
    True -> on.Return(Nil)
    False -> on.Stay(Nil)
  })

  use _ <- on.error_ok(
    vp.write_to_dot_last_command(args),
    handle_cli_error,
  )

  // Construct and run the application renderer here.
}
```

The application can apply parsed standard values to its defaults with:

```gleam
vp.amend_renderer_parameters_by_arguments(parameters, arguments)
vp.amend_renderer_options_by_arguments(options, arguments)
```

`CLIError` distinguishes argument parsing, `.last-command` reading, decoding
and writing, maintenance operations, and application-defined failures.
Applications can wrap a local failure with `ClientSideError` and use
`cli_error_message` for a common presentation path.

### `.last-command`

`read_from_dot_last_command` replaces the argument list only when it is exactly
`["--last-command"]`. If `--last-command` appears with another argument,
command-line parsing rejects it. `write_to_dot_last_command` stores an
unambiguous encoding of the effective argument list in `.last-command`.

The read and write functions use the current working directory. Applications
normally write only a command that proceeds to ordinary rendering; help,
maintenance, and local one-off operations can return before the write.

### Standard diagnostic options

The built-in help describes all accepted forms. The principal options are:

- `--help`, `--esoteric`, and `--track-help`
- `--input-dir` and `--output-dir`
- `--only`
- `--track`, `--dump`, and `--validate-vxml`
- `--table` and `--times`
- `--verbose`, `--artifacts`, and `--warnings`
- `--prettier-off`, `--prettier-on`, and `--prettier-check`
- stage dumps for assembled input, parsed VXML, filtered VXML, splitter
  fragments, and emitter fragments

Use `--track-help` for the selector-window, step-range, and output-formatting
syntax accepted by `--track`.

`--table` accepts up to three positional maximum widths, for the desugarer
name, parameter, and `outside` columns respectively:

```text
--table [<name columns> [<param columns> [<outside columns>]]]
```

Use `-` to retain the configured default at a position. Trailing defaults may
be omitted, so `--table - 80` changes only the parameter column. Numeric
values smaller than 10 are raised to 10.

`--times` follows the same convention for its desugarer-name and duration
columns:

```text
--times [<name columns> [<duration columns>]]
```

For example, `--times - 80` changes only the duration column. Trailing
defaults may again be omitted, and numeric values have a minimum of 10.

## Testing desugarers

`vxml_pipeline/testing` provides VXML-to-VXML test data and collection helpers:

```gleam
pub fn assertive_tests() {
  testing.collection(
    name: name,
    data: [
      testing.data(
        param: "password|secret",
        source: "
          <> document
            <>
              'ordinary line'
              'the password is swordfish'
        ",
        expected: "
          <> document
            <>
              'ordinary line'
              '[redacted]'
        ",
      ),
    ],
    constructor: constructor,
  )
}
```

The test machinery parses the source VXML, applies the desugarer, serializes
the result, and compares it with the expected VXML.

Run the complete package test suite, including the renderer integration test
and generated desugarer tests, with:

```sh
gleam test
```

Run only the renderer integration test with
`gleam run -m renderer_integration_test`.

From a checkout of this repository, run the package's generated desugarer test
registry with:

```sh
gleam run -m desugarer_tests
gleam run -m desugarer_tests -- rename
```

## Local desugarers in an application

An application can keep private desugarers in this fixed layout:

```text
src/
  desugarers/
    example.gleam
  local_desugarers.gleam
  local_desugarer_tests.gleam
```

Generate `src/local_desugarers.gleam` from `src/desugarers/`:

```sh
gleam run -m vxml_pipeline/generate_local_desugarers_dot_gleam
```

Renumber `authoring.blame` line references:

```sh
gleam run -m vxml_pipeline/renumber_local_desugarer_blames
```

The generated registry exports each module's `constructor` and an
`assertive_tests` list. A small application-owned `local_desugarer_tests.gleam`
can pass that list to `vxml_pipeline/testing.test_desugarers`.

When command-line maintenance handling is installed, the application also
accepts:

- `--renumber`
- `--generate` and `--regenerate`
- `--desugarer-tests` and `--test-desugarers`
- `--desugarers`, which renumbers, regenerates, and tests

These operations use paths relative to the application's current working
directory.

## Module guide

- `vxml_pipeline` — renderer stages, execution, feedback, monitors, renderer
  options, CLI handling, and default generic stages.
- `vxml_pipeline/core` — desugarer and pipeline types, errors and warnings, VXML
  helpers, and lower-level utilities used by desugarers.
- `vxml_pipeline/desugarers` — generated registry of reusable desugarer
  constructors.
- `vxml_pipeline/delimited_syntax` — reusable multi-desugarer fragments for
  delimiters, inline markup, and link parsing.
- `vxml_pipeline/split_replacement` — literal and regular-expression splitting
  rules that replace matched segments with VXML.
- `vxml_pipeline/authoring` — constructors and blame helpers for client-authored
  desugarers.
- `vxml_pipeline/testing` — public desugarer testing API.
- `vxml_pipeline/nodemaps_2_transform` — tree walkers that convert typed nodemaps
  into desugarer transforms.
- `vxml_pipeline/tracking` and `vxml_pipeline/selectors` — VXML selection and monitor
  output.
- `vxml_pipeline/line_wrapping` — blame-preserving line wrapping.
- `vxml_pipeline/writerly_defaults` —
  [Writerly](https://hex.pm/packages/writerly) assembler, parser, and emitter
  adapters.

## License

MIT
