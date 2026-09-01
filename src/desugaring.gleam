import desugaring/core.{type Desugarer, type Pipeline}
import desugaring/desugarers as dl
import desugaring/feedback_boxes as fb
import desugaring/generate_local_desugarers_dot_gleam as local_desugarer_generator
import desugaring/renumber_local_desugarer_blames as local_desugarer_blame_renumberer
import desugaring/selectors as sl
import desugaring/tables as pr
import desugaring/testing
import desugaring/tracking.{type Selector}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject, receive, send, spawn}
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/pair
import gleam/regexp
import gleam/result
import gleam/string.{inspect as ins}
import gleam/time/duration.{type Duration}
import gleam/time/timestamp
import input
import on
import shellout
import simplifile
import vxml.{type VXML, T, V} as vp
import vxml/blame.{type Blame, Ext} as bl
import vxml/io_lines.{type InputLine, type OutputLine, OutputLine} as io_l

pub const help_message_margin = 3

const default_times_table_char_width = 90

const renderer_runner_margin = 2

const tracking_progress_interval = 10

const tracking_progress_quiet_steps = 3

const long_running_desugarer_report_interval_seconds = 10

pub type FeedbackMargin {
  AtRunnerMargin
  Verbatim
}

pub type FeedbackBlock {
  FeedbackBlock(lines: List(String), margin: FeedbackMargin)
}

pub type Feedback {
  NoFeedback
  SomeFeedback(List(FeedbackBlock))
}

pub type PipelineStepContext {
  PipelineStepContext(
    step_no: Int,
    previous_desugarer: Option(Desugarer),
    next_desugarer: Option(Desugarer),
  )
}

type MonitorUpdate {
  MonitorUpdate(next: Monitor, feedback: Feedback)
}

pub opaque type Monitor {
  Monitor(
    name: String,
    update: fn(VXML, PipelineStepContext) -> Result(MonitorUpdate, String),
  )
}

pub opaque type MonitorFactory {
  TrackingMonitorFactory(Tracker)
  DumpMonitorFactory(List(PipelineStepSpec), VxmlMonitorOutput)
  VxmlValidationMonitorFactory(VxmlValidationMode)
}

type VxmlValidationMode {
  ValidateAllVxml(warn_about_attribute_boundary_whitespace: Bool)
  ValidateTextLinesOnly
}

pub fn new_monitor(
  name: String,
  state: state,
  update: fn(VXML, state, PipelineStepContext) ->
    Result(#(state, Feedback), String),
) -> Monitor {
  Monitor(name: name, update: fn(vxml, context) {
    use #(next_state, feedback) <- on.ok(update(vxml, state, context))
    Ok(MonitorUpdate(
      next: new_monitor(name, next_state, update),
      feedback: feedback,
    ))
  })
}

// Source path -> assembled input lines and feedback blocks.

pub type Assembler(assembler_error) =
  fn(String) -> Result(#(List(InputLine), Feedback), assembler_error)

pub fn default_file_assembler(
  path: String,
) -> Result(#(List(InputLine), Feedback), simplifile.FileError) {
  io_l.read(path, 0)
  |> result.map(fn(lines) { #(lines, NoFeedback) })
}

// Assembled input lines -> VXML.

pub type Parser(parser_error) =
  fn(List(InputLine)) -> Result(#(VXML, Feedback), #(Blame, parser_error))

pub fn default_xml_parser(
  lines: List(InputLine),
) -> Result(#(VXML, Feedback), #(Blame, String)) {
  vp.parse_xml_input_lines(lines)
  |> result.map(fn(vxml) { #(vxml, NoFeedback) })
  |> result.map_error(fn(e) { #(bl.no_blame, "xml parse error: " <> ins(e)) })
}

pub const default_html_parser = default_xml_parser

// Parsed VXML -> filtered VXML.

pub type Filterer(filterer_error) =
  fn(VXML) -> Result(#(VXML, Feedback), filterer_error)

pub fn default_filterer(
  vxml: VXML,
  options: RendererOptions(_),
  saving: List(String),
) -> Result(#(VXML, Feedback), String) {
  use #(vxml, warnings) <- on.error_ok(
    dl.filter_nodes_by_path_key_values_while_saving(#(
      options.only_path_key_vals,
      saving,
    )).transform(vxml),
    fn(e) { Error(e.message) },
  )
  assert warnings == []
  use #(vxml, warnings) <- on.error_ok(
    dl.filter_nodes_by_key_values_while_saving(#(options.only_key_vals, saving)).transform(
      vxml,
    ),
    fn(e) { Error(e.message) },
  )
  assert warnings == []
  Ok(#(vxml, NoFeedback))
}

// VXML -> classified output fragments.

pub type OutputFragment(fragment_classifier, payload) {
  OutputFragment(
    classifier: fragment_classifier,
    path: String,
    payload: payload,
  )
}

pub type Splitter(fragment_classifier, splitter_error) =
  fn(VXML) ->
    Result(
      #(List(OutputFragment(fragment_classifier, VXML)), Feedback),
      splitter_error,
    )

/// emits 1 fragment whose 'path' is the tag
/// of the VXML root concatenated with a provided
/// suffix, e.g., "<> Book" -> "Book.html"
pub fn stub_splitter(suffix: String) -> Splitter(Nil, Nil) {
  fn(root) {
    let assert V(_, tag, _, _) = root
    Ok(#(
      [OutputFragment(classifier: Nil, path: tag <> suffix, payload: root)],
      NoFeedback,
    ))
  }
}

// VXML fragments -> output-line fragments.

pub type Emitter(fragment_classifier, emitter_error) =
  fn(OutputFragment(fragment_classifier, VXML)) ->
    Result(
      #(OutputFragment(fragment_classifier, List(OutputLine)), Feedback),
      emitter_error,
    )

pub fn stub_html_emitter(
  fragment: OutputFragment(fragment_classifier, VXML),
) -> Result(
  #(OutputFragment(fragment_classifier, List(OutputLine)), Feedback),
  emitter_error,
) {
  let blame = Ext([], "stub_html_emitter")
  let lines =
    list.flatten([
      [
        OutputLine(blame, 0, "<!DOCTYPE html>"),
        OutputLine(blame, 0, "<html>"),
        OutputLine(blame, 0, "<head>"),
        OutputLine(
          blame,
          2,
          "<link rel=\"icon\" type=\"image/x-icon\" href=\"logo.png\">",
        ),
        OutputLine(blame, 2, "<meta charset=\"utf-8\">"),
        OutputLine(
          blame,
          2,
          "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
        ),
        OutputLine(
          blame,
          2,
          "<script type=\"text/javascript\" src=\"./mathjax_setup.js\"></script>",
        ),
        OutputLine(
          blame,
          2,
          "<script type=\"text/javascript\" id=\"MathJax-script\" async src=\"https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-svg.js\"></script>",
        ),
        OutputLine(blame, 0, "</head>"),
        OutputLine(blame, 0, "<body>"),
      ],
      fragment.payload
        |> core.v_get_children
        |> list.map(fn(vxml) { vp.vxml_to_html_output_lines(vxml, 2, 2) })
        |> list.flatten,
      [
        OutputLine(blame, 0, "</body>"),
        OutputLine(blame, 0, ""),
      ],
    ])
  Ok(#(OutputFragment(..fragment, payload: lines), NoFeedback))
}

pub fn stub_jsx_emitter(
  fragment: OutputFragment(fragment_classifier, VXML),
) -> Result(
  #(OutputFragment(fragment_classifier, List(OutputLine)), Feedback),
  emitter_error,
) {
  let blame = Ext([], "panel_emitter")
  let lines =
    list.flatten([
      [
        OutputLine(blame, 0, "import Something from \"./Somewhere\";"),
        OutputLine(blame, 0, ""),
        OutputLine(blame, 0, "const OurSuperComponent = () => {"),
        OutputLine(blame, 2, "return ("),
        OutputLine(blame, 4, "<>"),
      ],
      vp.vxmls_to_jsx_output_lines(
        fragment.payload |> core.v_get_children,
        6,
        2,
      ),
      [
        OutputLine(blame, 4, "</>"),
        OutputLine(blame, 2, ");"),
        OutputLine(blame, 0, "};"),
        OutputLine(blame, 0, ""),
        OutputLine(blame, 0, "export default OurSuperComponent;"),
      ],
    ])
  Ok(#(OutputFragment(..fragment, payload: lines), NoFeedback))
}

// Rendered string fragments -> records of written fragments.

pub type Writer(fragment_classifier, writer_error) =
  fn(String, OutputFragment(fragment_classifier, String)) ->
    Result(
      #(GhostOfOutputFragment(fragment_classifier), Feedback),
      writer_error,
    )

fn output_dir_local_path_printer(
  output_dir: String,
  local_path: String,
  content: String,
) -> Result(Nil, simplifile.FileError) {
  let assert False = string.starts_with(local_path, "/")
  let assert False = string.ends_with(output_dir, "/")
  let path = output_dir <> "/" <> local_path
  use _ <- on.ok(create_dirs_on_path_to_file(path))
  simplifile.write(path, content)
}

pub fn default_writer(
  output_dir: String,
  fragment: OutputFragment(fragment_classifier, String),
) -> Result(#(GhostOfOutputFragment(fragment_classifier), Feedback), String) {
  case
    output_dir_local_path_printer(output_dir, fragment.path, fragment.payload)
  {
    Ok(Nil) -> {
      Ok(#(
        GhostOfOutputFragment(fragment.classifier, fragment.path),
        NoFeedback,
      ))
    }
    Error(file_error) -> {
      Error(
        ins(file_error) <> " on path " <> output_dir <> "/" <> fragment.path,
      )
    }
  }
}

pub type GhostOfOutputFragment(fragment_classifier) {
  GhostOfOutputFragment(classifier: fragment_classifier, path: String)
}

pub type PrettifierFeedback {
  PrettifierFeedback(warnings: List(String), errors: List(String))
}

pub type Prettifier(fragment_classifier) =
  fn(String, GhostOfOutputFragment(fragment_classifier), Option(String)) ->
    Option(PrettifierFeedback)

pub fn run_prettier(
  in: String,
  path: String,
  check: Bool,
) -> PrettifierFeedback {
  let result =
    shellout.command(
      run: "prettier",
      in: in,
      with: [
        case check {
          True -> "--check"
          False -> "--write"
        },
        path,
      ],
      opt: [],
    )
  let output = case result {
    Ok(s) -> s
    Error(#(_, s)) -> s
  }
  let lines = string.split(output, "\n")
  let warnings =
    lines
    |> list.filter(fn(l) { string.starts_with(l, "[warn]") })
    |> list.map(fn(s) { string.drop_start(s, 6) |> string.trim })
  let error_lines =
    lines
    |> list.filter(fn(l) { string.starts_with(l, "[error]") })
    |> list.map(fn(s) { string.drop_start(s, 7) |> string.trim })
  let errors = case result {
    Ok(_) -> error_lines
    Error(#(_, _)) ->
      case error_lines {
        [_, ..] -> error_lines
        [] -> {
          case check {
            True -> []
            False ->
              case string.trim(output) {
                "" -> []
                s -> [s]
              }
          }
        }
      }
  }
  PrettifierFeedback(warnings: warnings, errors: errors)
}

pub fn default_prettier_prettifier(
  output_dir: String,
  ghost: GhostOfOutputFragment(fragment_classifier),
  prettier_dir: Option(String),
) -> Option(PrettifierFeedback) {
  use <- on.eager_false_true(
    list.any([".html", ".tsx"], string.ends_with(ghost.path, _)),
    None,
  )

  let source_path = output_dir <> "/" <> ghost.path

  use #(dest_path, check) <- on.stay(case prettier_dir {
    None -> on.Stay(#(source_path, True))

    Some(dir) -> {
      let dest_path = dir <> "/" <> ghost.path
      use <- on.true_false(source_path == dest_path, fn() {
        on.Stay(#(dest_path, False))
      })
      use _ <- on.error_ok(create_dirs_on_path_to_file(dest_path), fn(e) {
        on.Return(
          Some(
            PrettifierFeedback(warnings: [], errors: [
              "could not create directories on path " <> ins(e),
            ]),
          ),
        )
      })
      case
        shellout.command(
          run: "cp",
          in: ".",
          with: [source_path, dest_path],
          opt: [],
        )
      {
        Error(#(_, msg)) -> {
          on.Return(
            Some(
              PrettifierFeedback(warnings: [], errors: [
                "unable to copy '"
                <> source_path
                <> "' to '"
                <> dest_path
                <> "':"
                <> string.trim(msg),
              ]),
            ),
          )
        }
        _ -> on.Stay(#(dest_path, False))
      }
    }
  })

  run_prettier(".", dest_path, check) |> Some
}

pub fn empty_prettifier(
  _: String,
  _: GhostOfOutputFragment(fragment_classifier),
  _: Option(String),
) -> Option(PrettifierFeedback) {
  Some(PrettifierFeedback(warnings: [], errors: []))
}

/// Wires source ingress, parsing, filtering, desugaring, splitting, emitting,
/// writing, and optional prettification.
pub type Renderer(
  assembler_error,
  parser_error,
  filterer_error,
  splitter_error,
  emitter_error,
  writer_error,
  fragment_classifier,
) {
  Renderer(
    assembler: Assembler(assembler_error),
    parser: Parser(parser_error),
    filterer: Filterer(filterer_error),
    pipeline: Pipeline,
    splitter: Splitter(fragment_classifier, splitter_error),
    emitter: Emitter(fragment_classifier, emitter_error),
    writer: Writer(fragment_classifier, writer_error),
    prettifier: Prettifier(fragment_classifier),
  )
}

pub type PrettifierMode {
  PrettifierOff
  PrettifierOverwriteOutputDir
  PrettifierToBespokeDir(Option(String))
}

pub type RendererParameters {
  RendererParameters(
    input_dir: String,
    output_dir: String,
    prettifier_behavior: PrettifierMode,
  )
}

pub type RendererOptions(fragment_classifier) {
  RendererOptions(
    verbose: Bool,
    artifacts: Bool,
    steps_table: Bool,
    profiling_table: Option(Int),
    monitor_interactive_mode: Bool,
    warnings: Bool,
    report_long_running_desugarers: Bool,
    only_paths: List(String),
    only_key_vals: List(#(String, String)),
    only_path_key_vals: List(#(String, String, String)),
    monitors: List(Monitor),
    monitor_factories: List(MonitorFactory),
    output_lines_table_default_comment_columns: Int,
    output_lines_table_default_blame_columns: Int,
    dump_assembled_lines: Bool,
    dump_parsed_vxml: Bool,
    dump_filtered_vxml: Bool,
    dump_splitter_fragments: fn(OutputFragment(fragment_classifier, VXML)) ->
      Bool,
    dump_emitter_fragments: fn(
      OutputFragment(fragment_classifier, List(OutputLine)),
    ) -> Bool,
  )
}

pub fn vanilla_options() -> RendererOptions(fragment_classifier) {
  RendererOptions(
    verbose: False,
    artifacts: False,
    steps_table: False,
    profiling_table: None,
    monitor_interactive_mode: False,
    warnings: False,
    report_long_running_desugarers: True,
    only_paths: [],
    only_key_vals: [],
    only_path_key_vals: [],
    monitors: [],
    monitor_factories: [],
    output_lines_table_default_comment_columns: 30,
    output_lines_table_default_blame_columns: 48,
    dump_assembled_lines: False,
    dump_parsed_vxml: False,
    dump_filtered_vxml: False,
    dump_splitter_fragments: fn(_) { False },
    dump_emitter_fragments: fn(
      _: OutputFragment(fragment_classifier, List(OutputLine)),
    ) {
      False
    },
  )
}

type Tracker {
  Tracker(
    printing_selector: Option(tracking.Selector),
    change_selector: Option(tracking.Selector),
    step_specs: List(PipelineStepSpec),
    monitor_interactive_mode: Bool,
    output: Option(VxmlMonitorOutput),
    include_selection_ellipses: Option(Bool),
  )
}

type VxmlMonitorOutput {
  TrackingTable(blame_columns: Option(Int), comment_columns: Option(Int))
  TrackingVerbatim
}

pub type ParsedCLIArguments {
  ParsedCLIArguments(
    help: Bool,
    esoteric: Bool,
    track_help: Bool,
    renumber: Bool,
    generate: Bool,
    desugarers: Bool,
    desugarer_tests: Option(List(String)),
    input_dir: Option(String),
    output_dir: Option(String),
    only_paths: List(String),
    only_key_vals: List(#(String, String)),
    only_path_key_vals: List(#(String, String, String)),
    prettier: Option(PrettifierMode),
    tracking_monitor_factory: Option(MonitorFactory),
    dump_monitor_factory: Option(MonitorFactory),
    vxml_validation_monitor_factory: Option(MonitorFactory),
    monitor_interactive_mode: Bool,
    table: Option(Bool),
    times: Option(Int),
    verbose: Option(Bool),
    artifacts: Option(Bool),
    warnings: Option(Bool),
    dump_assembled: Bool,
    dump_parsed: Bool,
    dump_filtered: Bool,
    splitter_fragment_path_matches: Option(List(String)),
    emitter_fragment_path_matches: Option(List(String)),
    user_args: Dict(String, List(String)),
  )
}

pub type CLIError {
  CommandLineArgumentError(CommandLineError)
  DotLastCommandReadError(String)
  DotLastCommandDecodeError(String)
  DotLastCommandWriteError(String)
  MaintenanceError(String)
  ClientSideError(String)
}

pub fn cli_error_message(error: CLIError) -> String {
  case error {
    CommandLineArgumentError(error) -> ins(error)
    DotLastCommandReadError(error) -> "unable to read .last-command: " <> error
    DotLastCommandDecodeError(error) -> "malformed .last-command: " <> error
    DotLastCommandWriteError(error) ->
      "unable to write .last-command: " <> error
    MaintenanceError(error) | ClientSideError(error) -> error
  }
}

fn empty_parsed_cli_arguments() -> ParsedCLIArguments {
  ParsedCLIArguments(
    help: False,
    esoteric: False,
    track_help: False,
    renumber: False,
    generate: False,
    desugarers: False,
    desugarer_tests: None,
    input_dir: None,
    output_dir: None,
    only_paths: [],
    only_key_vals: [],
    only_path_key_vals: [],
    prettier: None,
    tracking_monitor_factory: None,
    dump_monitor_factory: None,
    vxml_validation_monitor_factory: None,
    monitor_interactive_mode: False,
    table: None,
    times: None,
    verbose: None,
    artifacts: None,
    warnings: None,
    dump_assembled: False,
    dump_parsed: False,
    dump_filtered: False,
    splitter_fragment_path_matches: None,
    emitter_fragment_path_matches: None,
    user_args: dict.from_list([]),
  )
}

// Command-line help

fn print_cli_usage(header: String, lines: List(String)) -> Nil {
  let margin = string.repeat(" ", help_message_margin)
  let lines =
    list.map(lines, fn(line) {
      case line {
        "" -> ""
        _ -> margin <> line
      }
    })
  let lines = case header {
    "" -> lines
    _ -> [header, "", ..lines]
  }
  lines |> string.join("\n") |> io.println
}

pub fn basic_cli_usage(header: String) {
  print_cli_usage(header, [
    "--help",
    "  -> print the basic command line options (this message)",
    "",
    "--esoteric",
    "  -> print advanced command line options",
    "",
    "--only <string1> <string2> ...",
    "  -> restrict source to files whose paths contain at least one of",
    "     the given strings as a substring",
    "",
    "--only <key1=val1> <key2=val2> ...",
    "  -> restrict source to elements that have at least one of the",
    "     given key-value pairs as attrs (& ancestors of such)",
    "",
    "--dump <step numbers>",
    "  -> show entire document at given pipeline step numbers; leave",
    "     step numbers empty to output document at all steps; use",
    "     negative indices to indicate steps from end of pipeline",
    "",
    "--track <string> [<selector arguments>] [<step ranges>]",
    "  -> track changes near the document fragment matching <string>",
    "     (run with '--track-help' for complete instructions)",
    "",
    "     gleam run -- --track \"lorem ipsum\"",
    "     gleam run -- --track src=img/23.svg +5-2",
    "     gleam run -- --track \"<> ImageRight\" -track+0 -print+-5 \\",
    "",
    "--track-help",
    "  -> print detailed '--track' instructions and examples",
    "",
    "--last-command",
    "  -> repeat the command-line arguments saved in .last-command;",
    "     this option must appear alone",
    "",
    "--verbose",
    "  -> verbose renderer output",
    "",
    "--artifacts",
    "  -> subset of '--verbose' to show which files were printed",
    "",
    "--table",
    "  -> include a printout of the pipeline steps",
    "",
    "--times [<cols=" <> ins(default_times_table_char_width) <> ">]",
    "  -> include performance table (how long it takes each desugarer",
    "     to run) using <cols> columns",
    "",
  ])
}

pub fn track_cli_usage(header: String) {
  print_cli_usage(header, [
    "--track <string> [<selector arguments>] [<step ranges>]",
    "  -> print document fragments when the selected VXML changes",
    "",
    "  <string>",
    "     Matches any part of a line in the printed VXML, excluding",
    "     leading whitespace. Quote strings containing spaces.",
    "",
    "     gleam run -- --track \"lorem ipsum\"",
    "     gleam run -- --track src=img/23.svg",
    "     gleam run -- --track \"<> ImageRight\"",
    "",
    "  selector windows",
    "     A signed window selects lines before and after each match.",
    "     Write +<after>-<before>, or put the minus part first:",
    "",
    "       +5-2   five lines after and two before",
    "       -2+5   equivalent to +5-2",
    "       +-5    five lines on either side",
    "       -+5    equivalent to +-5",
    "       +0     only the matching line",
    "",
    "     A nonzero one-sided form such as '+5' or '-5' is rejected.",
    "     With no window, tracking and printing both use '-+1'.",
    "",
    "  tracking versus printing",
    "     The tracking selector decides whether the VXML changed; the",
    "     printing selector decides which lines appear in the output.",
    "",
    "     One unlabeled window is used for both tracking and printing.",
    "     With two, the first tracks and the second prints. The roles",
    "     can instead be labeled '-track' and '-print' explicitly.",
    "",
    "       +0 +-5                 track +0; print +-5",
    "       -track+0 -print+-5     the explicit equivalent",
    "",
    "     If only '-track' is present, its complete selector is copied",
    "     to '-print'. If only '-print' is present, tracking defaults",
    "     to '-track-+1'.",
    "",
    "  selector modifiers",
    "     with-ancestors            include ancestor tags",
    "     with-elder-siblings       also include elder sibling tags",
    "     with-ancestor-attrs       include ancestor attributes",
    "     with-attrs                alias for with-ancestor-attrs",
    "     with-elder-sibling-attrs  also include elder sibling attrs",
    "",
    "     Modifiers before the first labeled window apply to both",
    "     selectors. Modifiers after a label apply only to that one.",
    "",
    "       with-ancestors -track+0 -print+-5 with-ancestor-attrs",
    "",
    "  pipeline step ranges",
    "     Leave step ranges empty to observe changes at every step.",
    "     Otherwise, use absolute step numbers and ranges:",
    "",
    "       50        step 50",
    "       50-60     steps 50 through 60",
    "       50-       step 50 through the end",
    "       -5--1     the final five steps",
    "       !123      force output at step 123",
    "",
    "     A leading '!' forces output even if the tracked fragment did",
    "     not change. Negative absolute indices count from the end.",
    "",
    "     A desugarer name selects its occurrences in the pipeline.",
    "     Signed offsets following the name are relative to each",
    "     occurrence:",
    "",
    "       rename          each 'rename' step",
    "       rename-5        five steps before through rename",
    "       rename+5        rename through five steps after",
    "       rename-2+3      two before through three after",
    "       rename+2+5      two through five steps after",
    "",
    "     Prefix an absolute range with '!' when its text could be",
    "     mistaken for a desugarer-relative range, or to force output.",
    "",
    "  output formatting",
    "     -verbatim  print raw selected VXML without the blame table",
    "     -cc<n>     use n columns for blame comments",
    "     -bc<n>     use n columns for blame provenance",
    "     -no-ellipses  suppress lines marking omitted VXML",
    "",
    "     A column count of zero suppresses that table column.",
    "     Column options have no effect with '-verbatim'.",
    "",
    "       gleam run -- --track src=img/23.svg -cc10 -bc20",
    "       gleam run -- --track \"<> ImageRight\" -verbatim",
    "",
    "  interactive mode",
    "     Add '-i' to pause after each monitor output. At the prompt:",
    "       <enter>  continue to the next output",
    "       <n>      skip pauses for the next n outputs",
    "       e        leave interactive mode",
    "       c        cancel the pipeline",
    "",
    "  complete examples",
    "",
    "     gleam run -- --track \"lorem ipsum\" +0 +-5 50-100",
    "     gleam run -- --track \"<> ImageRight\" -track+0 -print+-5",
    "       with-ancestor-attrs rename-2+2 !-1",
    "",
  ])
}

pub fn advanced_cli_usage(header: String) {
  print_cli_usage(header, [
    "--prettier-off",
    "  -> disable the prettifier",
    "",
    "--prettier-on",
    "  -> run prettier --write on each output file in place",
    "",
    "--prettier-check",
    "  -> run prettier --check on each output file (read-only)",
    "",
    "--prettier <dir>",
    "  -> run prettier --write, outputting to <dir> instead of output_dir",
    "",
    "--warnings/--no-warnings",
    "  -> force/suppress long-form printout of warnings",
    "",
    "--validate-vxml [-warn-attribute-whitespace | -lines-only]",
    "  -> validate VXML before and after every pipeline step; optionally",
    "     warn about attribute boundary whitespace, or only reject empty",
    "     text nodes",
    "",
    "--dump-assembled",
    "  -> print the assembled input lines of source",
    "",
    "--dump-parsed",
    "  -> print the parsed VXML",
    "",
    "--dump-filtered",
    "  -> print the parsed VXML filtered for key-value pairs",
    "",
    "--dump-splitter [<path-match1> <path-match2> ...]",
    "  -> dump fragments whose paths contain one of the given subpaths",
    "     produced by the splitter; list none to match all",
    "",
    "--dump-emitter [<path-match1> <path-match2> ...]",
    "  -> dump fragments whose paths contain one of the given subpaths",
    "     produced by the emitter; list none to match all",
    "",
    "--track-steps",
    "  -> (re)set the tracking step numbers of the current tracker, if",
    "     any; takes arguments in the same form as the <step numbers>",
    "     sub-option of '--track' (e.g., '50-60 !123-125 !-1')",
    "",
  ])
}

fn print_with_terminal_blank_line(message: String) {
  let message = string.trim_end(message)
  case message {
    "" -> Nil
    _ -> {
      io.println(message)
      io.println("")
    }
  }
}

/// Print requested help sections.
///
/// Each requested help section is printed at most once. `local_cli_usage` is
/// evaluated and appended only when `--help` is present.
pub fn handle_help_requests(
  arguments: ParsedCLIArguments,
  local_cli_usage: fn() -> String,
) -> Result(Bool, CLIError) {
  case arguments.help {
    True -> {
      basic_cli_usage("'gleam run' command line options (basic):")
      case local_cli_usage() {
        "" -> Nil
        local_usage -> local_usage |> print_with_terminal_blank_line
      }
    }
    False -> Nil
  }
  case arguments.esoteric {
    True -> advanced_cli_usage("'gleam run' command line options (esoteric):")
    False -> Nil
  }
  case arguments.track_help {
    True -> track_cli_usage("'gleam run -- --track' command line options:")
    False -> Nil
  }
  Ok(arguments.help || arguments.esoteric || arguments.track_help)
}

/// Run requested local-desugarer maintenance.
///
/// Each operation runs at most once. `--desugarers` requests blame
/// renumbering, local-library generation, and all local desugarer tests.
pub fn handle_maintenance_requests(
  arguments: ParsedCLIArguments,
  local_desugarer_tests: List(fn() -> testing.AssertiveTestCollection),
) -> Result(Bool, CLIError) {
  let renumber = arguments.renumber || arguments.desugarers
  let generate = arguments.generate || arguments.desugarers
  let requested_test_names = case
    arguments.desugarer_tests,
    arguments.desugarers
  {
    None, True -> Some([])
    requested, _ -> requested
  }
  let tests_requested = option.is_some(requested_test_names)

  let #(maintenance_result, printed) =
    perform_requested_maintenance(
      renumber,
      generate,
      requested_test_names,
      local_desugarer_tests,
      False,
    )
  case printed {
    True -> io.println("")
    False -> Nil
  }
  use _ <- result.try(maintenance_result |> result.map_error(MaintenanceError))

  Ok(renumber || generate || tests_requested)
}

fn perform_requested_maintenance(
  renumber: Bool,
  generate: Bool,
  requested_test_names: Option(List(String)),
  local_desugarer_tests: List(fn() -> testing.AssertiveTestCollection),
  content_printed: Bool,
) -> #(Result(Nil, String), Bool) {
  case renumber {
    True ->
      case local_desugarer_blame_renumberer.perform() {
        Error(message) -> #(Error(message), content_printed)
        Ok(Nil) ->
          perform_requested_maintenance(
            False,
            generate,
            requested_test_names,
            local_desugarer_tests,
            True,
          )
      }
    False ->
      case generate {
        True ->
          case local_desugarer_generator.perform() {
            Error(message) -> #(Error(message), content_printed)
            Ok(Nil) ->
              perform_requested_maintenance(
                False,
                False,
                requested_test_names,
                local_desugarer_tests,
                True,
              )
          }
        False ->
          case requested_test_names {
            None -> #(Ok(Nil), content_printed)
            Some(names) -> {
              case content_printed {
                True -> io.println("")
                False -> Nil
              }
              #(
                testing.test_desugarers_content(local_desugarer_tests, names),
                True,
              )
            }
          }
      }
  }
}

pub type CommandLineError {
  ExpectedDoubleDashString(String)
  UnknownOptionArgument(String)
  UnexpectedArgumentsToOption(String)
  DuplicateOption(String)
  ConflictingOptionArguments(String)
  MissingArgumentToOption(String)
  TooManyArgumentsToOption(String)
  SelectorValues(String)
  OnlyValues(String)
  StepNoValues(String)
  TimesValues(String)
}

const dot_last_command_path = ".last-command"

/// Replace the lone `--last-command` option with the arguments saved in
/// `.last-command`. All other argument lists are returned unchanged.
pub fn read_from_dot_last_command(
  arguments: List(String),
) -> Result(List(String), CLIError) {
  case arguments {
    ["--last-command"] -> {
      use contents <- result.try(
        simplifile.read(dot_last_command_path)
        |> result.map_error(fn(error) { DotLastCommandReadError(ins(error)) }),
      )
      decode_dot_last_command(contents)
    }
    _ -> Ok(arguments)
  }
}

/// Overwrite `.last-command` with an unambiguous encoding of `arguments`.
pub fn write_to_dot_last_command(
  arguments: List(String),
) -> Result(Nil, CLIError) {
  arguments
  |> encode_dot_last_command
  |> simplifile.write(dot_last_command_path, _)
  |> result.map_error(fn(error) { DotLastCommandWriteError(ins(error)) })
}

fn encode_dot_last_command(arguments: List(String)) -> String {
  arguments
  |> list.map(fn(argument) {
    int.to_string(string.length(argument)) <> ":" <> argument
  })
  |> string.concat
}

fn decode_dot_last_command(contents: String) -> Result(List(String), CLIError) {
  case contents, string.starts_with(contents, "--") {
    "", _ -> Ok([])
    _, True ->
      contents
      |> string.split(" ")
      |> list.map(string.trim)
      |> list.filter(fn(argument) { !string.is_empty(argument) })
      |> Ok
    _, False -> {
      use #(length_string, after_colon) <- result.try(
        string.split_once(contents, ":")
        |> result.map_error(fn(_) {
          DotLastCommandDecodeError("missing argument-length separator")
        }),
      )
      use length <- result.try(
        int.parse(length_string)
        |> result.map_error(fn(_) {
          DotLastCommandDecodeError("invalid argument length")
        }),
      )
      use _ <- on.ok(case length >= 0 && string.length(after_colon) >= length {
        True -> Ok(Nil)
        False -> Error(DotLastCommandDecodeError("invalid argument payload"))
      })
      let argument = string.slice(after_colon, 0, length)
      let remainder =
        string.slice(after_colon, length, string.length(after_colon) - length)
      use arguments <- on.ok(decode_dot_last_command(remainder))
      Ok([argument, ..arguments])
    }
  }
}

pub fn process_command_line_arguments(
  arguments: List(String),
  user_keys: List(String),
) -> Result(ParsedCLIArguments, CLIError) {
  process_command_line_arguments_(arguments, user_keys)
  |> result.map_error(CommandLineArgumentError)
}

fn process_command_line_arguments_(
  arguments: List(String),
  user_keys: List(String),
) -> Result(ParsedCLIArguments, CommandLineError) {
  let arguments = list.map(arguments, normalize_command_line_option)
  use list_key_values <- on.error_ok(double_dash_keys(arguments), fn(bad_key) {
    Error(ExpectedDoubleDashString(bad_key))
  })

  list_key_values
  |> list.fold(
    Ok(empty_parsed_cli_arguments()),
    fn(
      result: Result(ParsedCLIArguments, CommandLineError),
      pair: #(String, List(String)),
    ) {
      use arguments <- on.ok(result)
      let #(option, values) = pair
      case option {
        "--last-command" -> Error(UnexpectedArgumentsToOption(option))

        "--help" ->
          case values {
            [] -> Ok(ParsedCLIArguments(..arguments, help: True))
            _ -> Error(UnexpectedArgumentsToOption(option))
          }

        "--esoteric" ->
          case values {
            [] -> Ok(ParsedCLIArguments(..arguments, esoteric: True))
            _ -> Error(UnexpectedArgumentsToOption(option))
          }

        "--track-help" ->
          case values {
            [] -> Ok(ParsedCLIArguments(..arguments, track_help: True))
            _ -> Error(UnexpectedArgumentsToOption(option))
          }

        "--renumber" ->
          case values {
            [] -> Ok(ParsedCLIArguments(..arguments, renumber: True))
            _ -> Error(UnexpectedArgumentsToOption(option))
          }

        "--generate" ->
          case values {
            [] -> Ok(ParsedCLIArguments(..arguments, generate: True))
            _ -> Error(UnexpectedArgumentsToOption(option))
          }

        "--desugarers" ->
          case values {
            [] -> Ok(ParsedCLIArguments(..arguments, desugarers: True))
            _ -> Error(UnexpectedArgumentsToOption(option))
          }

        "--desugarer-tests" -> {
          use _ <- on.ok(case arguments.desugarer_tests {
            None -> Ok(Nil)
            Some(_) -> Error(DuplicateOption(option))
          })
          Ok(ParsedCLIArguments(..arguments, desugarer_tests: Some(values)))
        }

        "--times" -> {
          use _ <- on.ok(case arguments.times {
            None -> Ok(Nil)
            Some(_) -> Error(DuplicateOption(option))
          })
          use arg <- on.ok(parse_times_args(values))
          Ok(
            ParsedCLIArguments(
              ..arguments,
              times: arg |> core.with_default(default_times_table_char_width),
            ),
          )
        }

        "--input-dir" -> {
          use _ <- on.ok(case arguments.input_dir {
            None -> Ok(Nil)
            Some(_) -> Error(DuplicateOption(option))
          })
          case values {
            [one] ->
              Ok(
                ParsedCLIArguments(
                  ..arguments,
                  input_dir: Some(one |> core.drop_ending_slash),
                ),
              )
            [] -> Error(MissingArgumentToOption("--input-dir"))
            _ -> Error(TooManyArgumentsToOption("--input-dir"))
          }
        }

        "--output-dir" -> {
          use _ <- on.ok(case arguments.output_dir {
            None -> Ok(Nil)
            Some(_) -> Error(DuplicateOption(option))
          })
          case values {
            [one] ->
              Ok(
                ParsedCLIArguments(
                  ..arguments,
                  output_dir: Some(one |> core.drop_ending_slash),
                ),
              )
            [] -> Error(MissingArgumentToOption("--output-dir"))
            _ -> Error(TooManyArgumentsToOption("--output-dir"))
          }
        }

        "--only" -> {
          use args <- on.ok(
            values
            |> list.map(parse_attr_value_args_in_filename)
            |> result.all
            |> result.map(list.flatten),
          )

          ParsedCLIArguments(
            ..arguments,
            warnings: Some(option.unwrap(arguments.warnings, False)),
          )
          |> amend_only_args(args)
          |> Ok
        }

        "--table" ->
          case list.is_empty(values) {
            True -> Ok(ParsedCLIArguments(..arguments, table: Some(True)))
            False -> Error(UnexpectedArgumentsToOption("--table"))
          }

        "--no-table" ->
          case list.is_empty(values) {
            True -> Ok(ParsedCLIArguments(..arguments, table: Some(False)))
            False -> Error(UnexpectedArgumentsToOption("--no-table"))
          }

        "--prettier-off" ->
          case values {
            [] ->
              Ok(ParsedCLIArguments(..arguments, prettier: Some(PrettifierOff)))
            _ -> Error(UnexpectedArgumentsToOption("--prettier-off"))
          }

        "--prettier-on" ->
          case values {
            [] ->
              Ok(
                ParsedCLIArguments(
                  ..arguments,
                  prettier: Some(PrettifierOverwriteOutputDir),
                ),
              )
            _ -> Error(UnexpectedArgumentsToOption("--prettier-on"))
          }

        "--prettier-check" ->
          case values {
            [] ->
              Ok(
                ParsedCLIArguments(
                  ..arguments,
                  prettier: Some(PrettifierToBespokeDir(None)),
                ),
              )
            _ -> Error(UnexpectedArgumentsToOption("--prettier-check"))
          }

        "--prettier" ->
          case values {
            [dir] ->
              Ok(
                ParsedCLIArguments(
                  ..arguments,
                  prettier: Some(PrettifierToBespokeDir(Some(dir))),
                ),
              )
            _ -> Error(UnexpectedArgumentsToOption("--prettier"))
          }

        "--track" -> {
          use tracker <- on.ok(parse_track_args(values))
          Ok(
            ParsedCLIArguments(
              ..arguments,
              tracking_monitor_factory: Some(join_tracking_monitor_factory(
                arguments.tracking_monitor_factory,
                tracker,
              )),
              monitor_interactive_mode: {
                arguments.monitor_interactive_mode
                || tracker.monitor_interactive_mode
              },
            ),
          )
        }

        "--track-steps" -> {
          use tracker <- on.ok(parse_track_steps_args(values))
          Ok(
            ParsedCLIArguments(
              ..arguments,
              tracking_monitor_factory: Some(join_tracking_monitor_factory(
                arguments.tracking_monitor_factory,
                tracker,
              )),
              monitor_interactive_mode: {
                arguments.monitor_interactive_mode
                || tracker.monitor_interactive_mode
              },
            ),
          )
        }

        "--dump" -> {
          use #(specs, output, monitor_interactive_mode) <- on.ok(
            parse_dump_args(values),
          )
          let arguments =
            ParsedCLIArguments(..arguments, monitor_interactive_mode: {
              arguments.monitor_interactive_mode || monitor_interactive_mode
            })
          case arguments.dump_monitor_factory {
            None ->
              Ok(
                ParsedCLIArguments(
                  ..arguments,
                  dump_monitor_factory: Some(DumpMonitorFactory(specs, output)),
                ),
              )
            Some(DumpMonitorFactory(existing_specs, existing_output)) -> {
              use output <- on.ok(combine_vxml_monitor_outputs(
                existing_output,
                output,
              ))
              Ok(
                ParsedCLIArguments(
                  ..arguments,
                  dump_monitor_factory: Some(DumpMonitorFactory(
                    list.append(existing_specs, specs),
                    output,
                  )),
                ),
              )
            }
            _ -> panic as "dump monitor factory had unexpected variant"
          }
        }

        "--validate-vxml" -> {
          use _ <- on.ok(case arguments.vxml_validation_monitor_factory {
            None -> Ok(Nil)
            Some(_) -> Error(DuplicateOption(option))
          })
          let conflicting =
            list.contains(values, "-warn-attribute-whitespace")
            && list.contains(values, "-lines-only")
          use mode <- on.ok(case conflicting {
            True -> Error(ConflictingOptionArguments("--validate-vxml"))
            False ->
              case values {
                [] -> Ok(ValidateAllVxml(False))
                ["-warn-attribute-whitespace"] -> Ok(ValidateAllVxml(True))
                ["-lines-only"] -> Ok(ValidateTextLinesOnly)
                _ -> Error(UnexpectedArgumentsToOption("--validate-vxml"))
              }
          })
          Ok(
            ParsedCLIArguments(
              ..arguments,
              vxml_validation_monitor_factory: Some(
                VxmlValidationMonitorFactory(mode),
              ),
            ),
          )
        }

        "--dump-assembled" ->
          case list.is_empty(values) {
            True -> Ok(ParsedCLIArguments(..arguments, dump_assembled: True))
            False -> Error(UnexpectedArgumentsToOption(option))
          }

        "--dump-parsed" ->
          case list.is_empty(values) {
            True -> Ok(ParsedCLIArguments(..arguments, dump_parsed: True))
            False -> Error(UnexpectedArgumentsToOption(option))
          }

        "--dump-filtered" ->
          case list.is_empty(values) {
            True -> Ok(ParsedCLIArguments(..arguments, dump_filtered: True))
            False -> Error(UnexpectedArgumentsToOption(option))
          }

        "--dump-splitter" ->
          Ok(
            ParsedCLIArguments(
              ..arguments,
              splitter_fragment_path_matches: combine_fragment_path_matches(
                arguments.splitter_fragment_path_matches,
                values,
              ),
            ),
          )

        "--dump-emitter" ->
          Ok(
            ParsedCLIArguments(
              ..arguments,
              emitter_fragment_path_matches: combine_fragment_path_matches(
                arguments.emitter_fragment_path_matches,
                values,
              ),
            ),
          )

        "--succinct" ->
          case list.is_empty(values) {
            True -> Ok(ParsedCLIArguments(..arguments, verbose: Some(False)))
            False -> Error(UnexpectedArgumentsToOption(option))
          }

        "--verbose" ->
          case list.is_empty(values) {
            True -> Ok(ParsedCLIArguments(..arguments, verbose: Some(True)))
            False -> Error(UnexpectedArgumentsToOption(option))
          }

        "--artifacts" ->
          case list.is_empty(values) {
            True -> Ok(ParsedCLIArguments(..arguments, artifacts: Some(True)))
            False -> Error(UnexpectedArgumentsToOption(option))
          }

        "--no-artifacts" ->
          case list.is_empty(values) {
            True -> Ok(ParsedCLIArguments(..arguments, artifacts: Some(False)))
            False -> Error(UnexpectedArgumentsToOption(option))
          }

        "--warnings" ->
          case list.is_empty(values) {
            True -> Ok(ParsedCLIArguments(..arguments, warnings: Some(True)))
            False -> Error(UnexpectedArgumentsToOption(option))
          }

        "--no-warnings" ->
          case list.is_empty(values) {
            True -> Ok(ParsedCLIArguments(..arguments, warnings: Some(False)))
            False -> Error(UnexpectedArgumentsToOption(option))
          }

        _ -> {
          case list.contains(user_keys, option) {
            True ->
              Ok(
                ParsedCLIArguments(
                  ..arguments,
                  user_args: dict.insert(arguments.user_args, option, values),
                ),
              )
            False -> Error(UnknownOptionArgument(option))
          }
        }
      }
    },
  )
}

fn normalize_command_line_option(argument: String) -> String {
  case argument {
    "-h" | "-help" -> "--help"
    "--regenerate" -> "--generate"
    "--test-desugarers" -> "--desugarer-tests"
    _ -> argument
  }
}

// General command-line tokenization

fn take_strings_while_not_key(
  upcoming: List(String),
  bundled: List(String),
) -> #(List(String), List(String)) {
  case upcoming {
    [] -> #(bundled |> list.reverse, upcoming)
    [first, ..rest] -> {
      case string.starts_with(first, "--") {
        True -> #(bundled |> list.reverse, upcoming)
        False -> take_strings_while_not_key(rest, [first, ..bundled])
      }
    }
  }
}

fn double_dash_keys(
  arguments: List(String),
) -> Result(List(#(String, List(String))), String) {
  case arguments {
    [] -> Ok([])
    [first, ..rest] -> {
      case string.starts_with(first, "--") {
        False -> Error(first)
        True -> {
          let #(arg_values, rest) = take_strings_while_not_key(rest, [])
          case double_dash_keys(rest) {
            Error(e) -> Error(e)
            Ok(parsed) -> Ok([#(first, arg_values), ..parsed])
          }
        }
      }
    }
  }
}

// --only parsing

fn amend_only_args(
  arguments: ParsedCLIArguments,
  args: List(#(String, String, String)),
) -> ParsedCLIArguments {
  ParsedCLIArguments(
    ..arguments,
    only_paths: list.append(
      arguments.only_paths,
      args
        |> list.filter(fn(a) { a.0 != "" })
        |> list.map(fn(a) { a.0 }),
    ),
    only_key_vals: list.append(
      arguments.only_key_vals,
      args
        |> list.filter(fn(a) { a.0 == "" && { a.1 != "" || a.2 != "" } })
        |> list.map(fn(a) { #(a.1, a.2) }),
    ),
    only_path_key_vals: list.append(
      arguments.only_path_key_vals,
      args
        |> list.filter(fn(a) { a.0 != "" && { a.1 != "" || a.2 != "" } }),
    ),
  )
}

fn parse_attr_value_args_in_filename(
  path: String,
) -> Result(List(#(String, String, String)), CommandLineError) {
  let assert [path, ..args] = string.split(path, "&")
  case args {
    // did not contain '&':
    [] -> {
      case string.split_once(path, "=") {
        Ok(#(key, value)) -> Ok([#("", key, value)])
        Error(Nil) -> Ok([#(path, "", "")])
      }
    }
    // did contain '&'
    _ -> {
      args
      |> list.map(fn(arg) {
        case string.split(arg, "=") {
          [key, value] -> Ok(#(path, key, value))
          _ -> Error(OnlyValues(arg))
        }
      })
      |> result.all
    }
  }
}

// --track, --track-steps, and --dump parsing

type SelectorLineWindow {
  SelectorLineWindow(lines_after: Int, lines_before: Int)
}

type AbsoluteStepRange {
  ClosedAbsoluteStepRange(first: Int, last: Int)
  AbsoluteStepsFrom(first: Int)
}

type DesugarerRelativeStepRange {
  DesugarerRelativeStepRange(
    desugarer_name: String,
    first_offset: Int,
    last_offset: Int,
  )
}

type PipelineStepRange {
  AbsoluteSteps(AbsoluteStepRange)
  DesugarerRelativeSteps(DesugarerRelativeStepRange)
}

type PipelineStepOutputMode {
  OnChange
  Forced
}

type PipelineStepSpec {
  PipelineStepSpec(
    range: PipelineStepRange,
    output_mode: PipelineStepOutputMode,
  )
}

fn parse_selector_line_window(s: String) -> Result(SelectorLineWindow, Nil) {
  case string.starts_with(s, "+-"), string.starts_with(s, "-+") {
    True, _ ->
      int.parse(string.drop_start(s, 2))
      |> result.map(fn(size) { SelectorLineWindow(size, size) })
    _, True ->
      int.parse(string.drop_start(s, 2))
      |> result.map(fn(size) { SelectorLineWindow(size, size) })
    _, _ -> parse_asymmetric_selector_line_window(s)
  }
}

fn parse_asymmetric_selector_line_window(
  s: String,
) -> Result(SelectorLineWindow, Nil) {
  case string.starts_with(s, "+"), string.starts_with(s, "-") {
    True, _ -> {
      let s = string.drop_start(s, 1)
      case string.split_once(s, "-") {
        Ok(#(before, after)) -> {
          case int.parse(before), int.parse(after) {
            Ok(p), Ok(m) -> Ok(SelectorLineWindow(p, m))
            _, _ -> Error(Nil)
          }
        }
        _ ->
          case int.parse(s) {
            Ok(0) -> Ok(SelectorLineWindow(0, 0))
            _ -> Error(Nil)
          }
      }
    }

    _, True -> {
      let s = string.drop_start(s, 1)
      case string.split_once(s, "+") {
        Ok(#(before, after)) -> {
          case int.parse(before), int.parse(after) {
            Ok(m), Ok(p) -> Ok(SelectorLineWindow(p, m))
            _, _ -> Error(Nil)
          }
        }
        _ ->
          case int.parse(s) {
            Ok(0) -> Ok(SelectorLineWindow(0, 0))
            _ -> Error(Nil)
          }
      }
    }

    _, _ -> Error(Nil)
  }
}

fn lo_hi_ints(lo: Int, hi: Int) -> List(Int) {
  case lo < hi {
    True -> [lo, ..lo_hi_ints(lo + 1, hi)]
    False -> [lo]
  }
}

pub fn extract_desugarer_name(input: String) -> #(String, String) {
  let assert Ok(re) = regexp.from_string("^([a-z_][a-z0-9_]*)(.*)")
  case regexp.scan(with: re, content: input) {
    [regexp.Match(_, [Some(prefix), rest, ..])] -> #(
      prefix,
      option.unwrap(rest, ""),
    )
    _ -> #("", input)
  }
}

fn regex_captures(pattern: String, input: String) -> List(Option(String)) {
  let assert Ok(regex) = regexp.from_string(pattern)
  case regexp.scan(with: regex, content: input) {
    [regexp.Match(_, captures)] -> captures
    _ -> []
  }
}

fn parse_absolute_step_range(
  input: String,
) -> Result(AbsoluteStepRange, CommandLineError) {
  case regex_captures("^(-?[0-9]+)-(-?[0-9]+)$", input) {
    [Some(first), Some(last), ..] -> {
      let assert Ok(first) = int.parse(first)
      let assert Ok(last) = int.parse(last)
      Ok(ClosedAbsoluteStepRange(first, last))
    }
    _ ->
      case regex_captures("^(-?[0-9]+)-$", input) {
        [Some(first), ..] -> {
          let assert Ok(first) = int.parse(first)
          Ok(AbsoluteStepsFrom(first))
        }
        _ ->
          case int.parse(input) {
            Ok(step) -> Ok(ClosedAbsoluteStepRange(step, step))
            Error(_) ->
              Error(StepNoValues(
                "unable to parse absolute step range '" <> input <> "'",
              ))
          }
      }
  }
}

fn parse_signed_offset(input: String) -> Result(Int, Nil) {
  case string.starts_with(input, "+") {
    True -> int.parse(string.drop_start(input, 1))
    False -> int.parse(input)
  }
}

fn parse_desugarer_relative_step_range(
  input: String,
) -> Result(DesugarerRelativeStepRange, CommandLineError) {
  let #(name, suffix) = extract_desugarer_name(input)
  use _ <- on.stay(case name {
    "" ->
      on.Return(
        Error(StepNoValues(
          "unable to parse desugarer-relative step range '" <> input <> "'",
        )),
      )
    _ -> on.Stay(Nil)
  })
  case suffix {
    "" -> Ok(DesugarerRelativeStepRange(name, 0, 0))
    _ ->
      case regex_captures("^([+-][0-9]+)([+-][0-9]+)?$", suffix) {
        [Some(first), ..] as captures -> {
          let assert Ok(first) = parse_signed_offset(first)
          let second = case list.drop(captures, 1) {
            [Some(second), ..] -> {
              let assert Ok(second) = parse_signed_offset(second)
              second
            }
            _ -> 0
          }
          Ok(DesugarerRelativeStepRange(
            name,
            int.min(first, second),
            int.max(first, second),
          ))
        }
        _ ->
          Error(StepNoValues(
            "unable to parse desugarer-relative step range '" <> input <> "'",
          ))
      }
  }
}

fn parse_pipeline_step_spec(
  input: String,
) -> Result(PipelineStepSpec, CommandLineError) {
  let #(mode, payload) = case string.starts_with(input, "!") {
    True -> #(Forced, string.drop_start(input, 1))
    False -> #(OnChange, input)
  }
  use _ <- on.stay(case payload {
    "" -> on.Return(Error(StepNoValues("missing step range after '!'")))
    _ -> on.Stay(Nil)
  })
  case string.starts_with(payload, "+") {
    True ->
      Error(StepNoValues(
        "absolute step ranges cannot start with '+' [" <> input <> "]",
      ))
    False -> {
      let #(name, _) = extract_desugarer_name(payload)
      case name {
        "" ->
          parse_absolute_step_range(payload)
          |> result.map(fn(range) {
            PipelineStepSpec(AbsoluteSteps(range), mode)
          })
        _ ->
          parse_desugarer_relative_step_range(payload)
          |> result.map(fn(range) {
            PipelineStepSpec(DesugarerRelativeSteps(range), mode)
          })
      }
    }
  }
}

fn parse_pipeline_step_specs(
  values: List(String),
) -> Result(List(PipelineStepSpec), CommandLineError) {
  list.try_map(values, parse_pipeline_step_spec)
}

type SelectorTarget {
  TrackSelector
  PrintSelector
}

type SelectorDefinition {
  SelectorDefinition(
    target: SelectorTarget,
    window: SelectorLineWindow,
    modifiers: List(String),
  )
}

type SelectorNormalizationState {
  SelectorNormalizationState(
    remaining_anchors: List(#(SelectorTarget, SelectorLineWindow)),
    common_modifiers: List(String),
    current_definition: Option(SelectorDefinition),
    completed_definitions: List(SelectorDefinition),
  )
}

fn selector_modifier(input: String) -> Bool {
  let input = string.replace(input, "-with", "with")
  list.contains(
    [
      "with-ancestors",
      "with-elder-siblings",
      "with-attrs",
      "with-attributes",
      "with-ancestor-attrs",
      "with-ancestor-attributes",
      "with-elder-sibling-attrs",
      "with-elder-sibling-attributes",
    ],
    input,
  )
}

fn parse_selector_anchor(
  input: String,
) -> Result(
  Option(#(Option(SelectorTarget), SelectorLineWindow)),
  CommandLineError,
) {
  let #(target, payload) = case
    string.starts_with(input, "-track"),
    string.starts_with(input, "-print")
  {
    True, _ -> #(Some(TrackSelector), string.drop_start(input, 6))
    _, True -> #(Some(PrintSelector), string.drop_start(input, 6))
    _, _ -> #(None, input)
  }
  case parse_selector_line_window(payload) {
    Ok(window) -> Ok(Some(#(target, window)))
    Error(_) ->
      case target {
        Some(_) ->
          Error(SelectorValues("invalid selector line window '" <> input <> "'"))
        None -> Ok(None)
      }
  }
}

type VxmlMonitorOutputArguments {
  VxmlMonitorOutputArguments(
    verbatim: Bool,
    blame_columns: Option(Int),
    comment_columns: Option(Int),
    remaining: List(String),
  )
}

fn parse_tracking_column_count(
  option: String,
  value: String,
) -> Result(Int, CommandLineError) {
  use columns <- on.error_ok(int.parse(value), fn(_) {
    Error(SelectorValues("invalid column count in '" <> option <> value <> "'"))
  })
  case columns >= 0 {
    True -> Ok(columns)
    False ->
      Error(SelectorValues(
        "column count cannot be negative in '" <> option <> value <> "'",
      ))
  }
}

fn parse_vxml_monitor_output_arguments(
  values: List(String),
) -> Result(#(VxmlMonitorOutput, List(String)), CommandLineError) {
  use parsed <- on.ok(
    list.try_fold(
      values,
      VxmlMonitorOutputArguments(False, None, None, []),
      fn(acc, value) {
        case
          value == "-verbatim",
          string.starts_with(value, "-bc"),
          string.starts_with(value, "-cc")
        {
          True, _, _ ->
            case acc.verbatim {
              True -> Error(SelectorValues("duplicate '-verbatim' option"))
              False -> Ok(VxmlMonitorOutputArguments(..acc, verbatim: True))
            }
          _, True, _ ->
            case acc.blame_columns {
              Some(_) -> Error(SelectorValues("duplicate '-bc' option"))
              None -> {
                use columns <- on.ok(parse_tracking_column_count(
                  "-bc",
                  string.drop_start(value, 3),
                ))
                Ok(
                  VxmlMonitorOutputArguments(
                    ..acc,
                    blame_columns: Some(columns),
                  ),
                )
              }
            }
          _, _, True ->
            case acc.comment_columns {
              Some(_) -> Error(SelectorValues("duplicate '-cc' option"))
              None -> {
                use columns <- on.ok(parse_tracking_column_count(
                  "-cc",
                  string.drop_start(value, 3),
                ))
                Ok(
                  VxmlMonitorOutputArguments(
                    ..acc,
                    comment_columns: Some(columns),
                  ),
                )
              }
            }
          _, _, _ ->
            Ok(
              VxmlMonitorOutputArguments(
                ..acc,
                remaining: list.append(acc.remaining, [value]),
              ),
            )
        }
      },
    ),
  )

  case parsed.verbatim {
    True -> Ok(#(TrackingVerbatim, parsed.remaining))
    False ->
      Ok(#(
        TrackingTable(parsed.blame_columns, parsed.comment_columns),
        parsed.remaining,
      ))
  }
}

fn parse_track_ellipsis_argument(
  values: List(String),
) -> Result(#(Bool, List(String)), CommandLineError) {
  use #(found, remaining) <- on.ok(
    list.try_fold(values, #(False, []), fn(acc, value) {
      case value == "-no-ellipses", acc.0 {
        True, True -> Error(SelectorValues("duplicate '-no-ellipses' option"))
        True, False -> Ok(#(True, acc.1))
        False, _ -> Ok(#(acc.0, list.append(acc.1, [value])))
      }
    }),
  )
  Ok(#(!found, remaining))
}

fn partition_track_arguments(
  values: List(String),
) -> Result(#(Bool, List(String), List(PipelineStepSpec)), CommandLineError) {
  list.try_fold(values, #(False, [], []), fn(acc, value) {
    case value {
      "-i" -> Ok(#(True, acc.1, acc.2))
      _ -> {
        use anchor <- on.ok(parse_selector_anchor(value))
        case anchor != None || selector_modifier(value) {
          True -> Ok(#(acc.0, list.append(acc.1, [value]), acc.2))
          False -> {
            use spec <- on.ok(parse_pipeline_step_spec(value))
            Ok(#(acc.0, acc.1, list.append(acc.2, [spec])))
          }
        }
      }
    }
  })
}

fn assign_selector_targets(
  anchors: List(#(Option(SelectorTarget), SelectorLineWindow)),
) -> Result(List(#(SelectorTarget, SelectorLineWindow)), CommandLineError) {
  case anchors {
    [] -> Ok([])
    [#(None, window)] -> Ok([#(TrackSelector, window)])
    [#(Some(target), window)] -> Ok([#(target, window)])
    [#(None, first), #(None, second)] ->
      Ok([#(TrackSelector, first), #(PrintSelector, second)])
    [#(Some(TrackSelector), first), #(None, second)] ->
      Ok([#(TrackSelector, first), #(PrintSelector, second)])
    [#(Some(PrintSelector), first), #(None, second)] ->
      Ok([#(PrintSelector, first), #(TrackSelector, second)])
    [#(None, first), #(Some(TrackSelector), second)] ->
      Ok([#(PrintSelector, first), #(TrackSelector, second)])
    [#(None, first), #(Some(PrintSelector), second)] ->
      Ok([#(TrackSelector, first), #(PrintSelector, second)])
    [#(Some(first_target), first), #(Some(second_target), second)] ->
      case first_target == second_target {
        True -> Error(SelectorValues("duplicate -track or -print selector"))
        False -> Ok([#(first_target, first), #(second_target, second)])
      }
    _ -> Error(SelectorValues("--track accepts at most two selector windows"))
  }
}

fn normalize_selector_definitions(
  values: List(String),
) -> Result(#(SelectorDefinition, SelectorDefinition), CommandLineError) {
  use anchors <- on.ok(
    values
    |> list.try_fold([], fn(anchors, value) {
      use anchor <- on.ok(parse_selector_anchor(value))
      case anchor {
        None -> Ok(anchors)
        Some(anchor) -> Ok(list.append(anchors, [anchor]))
      }
    }),
  )
  use assigned <- on.ok(assign_selector_targets(anchors))
  let default_window = SelectorLineWindow(1, 1)
  case assigned {
    [] -> {
      let track = SelectorDefinition(TrackSelector, default_window, values)
      Ok(#(track, SelectorDefinition(PrintSelector, default_window, values)))
    }
    _ -> {
      let assert Ok(SelectorNormalizationState(
        remaining_anchors: [],
        common_modifiers: common,
        current_definition: current,
        completed_definitions: definitions,
      )) =
        list.try_fold(
          values,
          SelectorNormalizationState(assigned, [], None, []),
          fn(acc, value) {
            use anchor <- on.ok(parse_selector_anchor(value))
            case anchor {
              None ->
                case acc.current_definition {
                  None ->
                    Ok(
                      SelectorNormalizationState(
                        ..acc,
                        common_modifiers: list.append(acc.common_modifiers, [
                          value,
                        ]),
                      ),
                    )
                  Some(definition) ->
                    Ok(
                      SelectorNormalizationState(
                        ..acc,
                        current_definition: Some(
                          SelectorDefinition(
                            ..definition,
                            modifiers: list.append(definition.modifiers, [value]),
                          ),
                        ),
                      ),
                    )
                }
              Some(_) -> {
                let assert [#(target, window), ..remaining] =
                  acc.remaining_anchors
                let definitions = case acc.current_definition {
                  None -> acc.completed_definitions
                  Some(definition) ->
                    list.append(acc.completed_definitions, [definition])
                }
                Ok(SelectorNormalizationState(
                  remaining_anchors: remaining,
                  common_modifiers: acc.common_modifiers,
                  current_definition: Some(
                    SelectorDefinition(target, window, []),
                  ),
                  completed_definitions: definitions,
                ))
              }
            }
          },
        )
      let definitions = case current {
        None -> definitions
        Some(definition) -> list.append(definitions, [definition])
      }
      let definitions =
        list.map(definitions, fn(definition) {
          SelectorDefinition(
            ..definition,
            modifiers: list.append(common, definition.modifiers),
          )
        })
      case definitions {
        [SelectorDefinition(TrackSelector, window, modifiers)] ->
          Ok(#(
            SelectorDefinition(TrackSelector, window, modifiers),
            SelectorDefinition(PrintSelector, window, modifiers),
          ))
        [SelectorDefinition(PrintSelector, window, modifiers)] ->
          Ok(#(
            SelectorDefinition(TrackSelector, default_window, common),
            SelectorDefinition(PrintSelector, window, modifiers),
          ))
        [first, second] ->
          case first.target {
            TrackSelector -> Ok(#(first, second))
            PrintSelector -> Ok(#(second, first))
          }
        _ -> Error(SelectorValues("unable to normalize selector arguments"))
      }
    }
  }
}

fn selector_from_definition(
  base_selector: Selector,
  definition: SelectorDefinition,
) -> Result(Selector, CommandLineError) {
  let values =
    list.map(definition.modifiers, fn(value) {
      string.replace(value, "-with", "with")
    })
  let #(with_ancestors, values) = core.delete(values, "with-ancestors")
  let #(with_elder_siblings, values) =
    core.delete(values, "with-elder-siblings")
  let #(with_attrs, values) = core.delete(values, "with-attrs")
  let #(with_attrs_v2, values) = core.delete(values, "with-attributes")
  let #(with_ancestor_attrs, values) =
    core.delete(values, "with-ancestor-attrs")
  let #(with_ancestor_attrs_v2, values) =
    core.delete(values, "with-ancestor-attributes")
  let #(with_elder_sibling_attrs, values) =
    core.delete(values, "with-elder-sibling-attrs")
  let #(with_elder_sibling_attrs_v2, values) =
    core.delete(values, "with-elder-sibling-attributes")
  use _ <- on.stay(case values {
    [] -> on.Stay(Nil)
    _ ->
      on.Return(
        Error(SelectorValues("unexpected selector arguments " <> ins(values))),
      )
  })
  let with_attrs = with_attrs || with_attrs_v2
  let with_elder_sibling_attrs =
    with_elder_sibling_attrs || with_elder_sibling_attrs_v2 || with_attrs
  let with_ancestor_attrs =
    with_ancestor_attrs || with_ancestor_attrs_v2 || with_elder_sibling_attrs
  let with_elder_siblings = with_elder_siblings || with_elder_sibling_attrs
  let with_ancestors =
    with_ancestors || with_elder_siblings || with_ancestor_attrs
  let selector =
    base_selector
    |> tracking.extend_selector_up(definition.window.lines_before)
    |> tracking.extend_selector_down(definition.window.lines_after)
  case with_ancestors {
    False -> Ok(selector)
    True ->
      Ok(tracking.extend_selector_to_ancestors(
        selector,
        with_elder_siblings,
        with_ancestor_attrs,
        with_elder_sibling_attrs,
      ))
  }
}

fn parse_track_args(values: List(String)) -> Result(Tracker, CommandLineError) {
  use first_payload, values <- on.empty_nonempty(values, fn() {
    Error(SelectorValues("missing 1st argument"))
  })

  let assert True = first_payload != ""
  use #(include_selection_ellipses, values) <- on.ok(
    parse_track_ellipsis_argument(values),
  )
  use #(output, values) <- on.ok(parse_vxml_monitor_output_arguments(values))
  use #(with_enter, selector_arguments, step_specs) <- on.ok(
    partition_track_arguments(values),
  )
  use #(track_definition, print_definition) <- on.ok(
    normalize_selector_definitions(selector_arguments),
  )
  let base_selector = sl.verbatim(first_payload)
  use change_selector <- on.ok(selector_from_definition(
    base_selector,
    track_definition,
  ))
  use printing_selector <- on.ok(selector_from_definition(
    base_selector,
    print_definition,
  ))

  Ok(Tracker(
    printing_selector: Some(printing_selector),
    change_selector: Some(change_selector),
    step_specs: step_specs,
    monitor_interactive_mode: with_enter,
    output: Some(output),
    include_selection_ellipses: Some(include_selection_ellipses),
  ))
}

fn parse_track_steps_args(
  values: List(String),
) -> Result(Tracker, CommandLineError) {
  let #(with_enter, values) = core.delete(values, "-i")
  use step_specs <- on.ok(parse_pipeline_step_specs(values))
  Ok(Tracker(
    printing_selector: None,
    change_selector: None,
    step_specs: step_specs,
    monitor_interactive_mode: with_enter,
    output: None,
    include_selection_ellipses: None,
  ))
}

fn join_trackers(pm1: Option(Tracker), pm2: Tracker) -> Tracker {
  use pm1 <- on.eager_none_some(pm1, pm2)
  Tracker(
    printing_selector: case pm1.printing_selector, pm2.printing_selector {
      Some(s1), Some(s2) -> Some(tracking.or_selectors(s1, s2))
      _, _ -> option.or(pm1.printing_selector, pm2.printing_selector)
    },
    change_selector: case pm1.change_selector, pm2.change_selector {
      Some(s1), Some(s2) -> Some(tracking.or_selectors(s1, s2))
      _, _ -> option.or(pm1.change_selector, pm2.change_selector)
    },
    step_specs: list.append(pm1.step_specs, pm2.step_specs),
    monitor_interactive_mode: {
      pm1.monitor_interactive_mode || pm2.monitor_interactive_mode
    },
    output: case pm2.output {
      Some(_) -> pm2.output
      None -> pm1.output
    },
    include_selection_ellipses: case pm2.include_selection_ellipses {
      Some(_) -> pm2.include_selection_ellipses
      None -> pm1.include_selection_ellipses
    },
  )
}

fn join_tracking_monitor_factory(
  existing: Option(MonitorFactory),
  tracker: Tracker,
) -> MonitorFactory {
  case existing {
    Some(TrackingMonitorFactory(existing_tracker)) ->
      TrackingMonitorFactory(join_trackers(Some(existing_tracker), tracker))
    _ -> TrackingMonitorFactory(tracker)
  }
}

fn parse_dump_args(
  values: List(String),
) -> Result(
  #(List(PipelineStepSpec), VxmlMonitorOutput, Bool),
  CommandLineError,
) {
  let #(monitor_interactive_mode, values) = core.delete(values, "-i")
  use #(output, values) <- on.ok(parse_vxml_monitor_output_arguments(values))
  use specs <- on.ok(parse_pipeline_step_specs(values))
  Ok(#(specs, output, monitor_interactive_mode))
}

fn combine_optional_dump_column_counts(
  first: Option(Int),
  second: Option(Int),
) -> Result(Option(Int), CommandLineError) {
  case first, second {
    Some(first), Some(second) if first != second ->
      Error(ConflictingOptionArguments("--dump"))
    Some(first), _ -> Ok(Some(first))
    _, Some(second) -> Ok(Some(second))
    None, None -> Ok(None)
  }
}

fn combine_vxml_monitor_outputs(
  first: VxmlMonitorOutput,
  second: VxmlMonitorOutput,
) -> Result(VxmlMonitorOutput, CommandLineError) {
  case first, second {
    TrackingVerbatim, TrackingVerbatim -> Ok(TrackingVerbatim)
    TrackingTable(first_blame, first_comment),
      TrackingTable(second_blame, second_comment)
    -> {
      use blame <- on.ok(combine_optional_dump_column_counts(
        first_blame,
        second_blame,
      ))
      use comment <- on.ok(combine_optional_dump_column_counts(
        first_comment,
        second_comment,
      ))
      Ok(TrackingTable(blame, comment))
    }
    _, _ -> Error(ConflictingOptionArguments("--dump"))
  }
}

// --times parsing

fn parse_times_args(
  values: List(String),
) -> Result(Option(Int), CommandLineError) {
  case values {
    [] -> Ok(None)
    [x] -> {
      use x <- on.error_ok(int.parse(x), fn(_) {
        Error(TimesValues(
          "could not parse --times argument '" <> x <> "' as integer",
        ))
      })
      let x = int.max(x, 1)
      Ok(Some(x))
    }
    _ -> Error(UnexpectedArgumentsToOption("--times"))
  }
}

pub fn amend_renderer_parameters_by_arguments(
  parameters: RendererParameters,
  arguments: ParsedCLIArguments,
) -> RendererParameters {
  RendererParameters(
    input_dir: option.unwrap(arguments.input_dir, parameters.input_dir),
    output_dir: option.unwrap(arguments.output_dir, parameters.output_dir),
    prettifier_behavior: option.unwrap(
      arguments.prettier,
      parameters.prettifier_behavior,
    ),
  )
}

fn exists_match(
  z: Option(List(a)),
  // List(a) = list of things that might cause a match, left empty if we always want a match
  e: fn(a) -> Bool,
  // match tester
) -> Bool {
  case z {
    None -> False
    Some([]) -> True
    Some(x) -> list.any(x, e)
  }
}

fn combine_fragment_path_matches(
  existing: Option(List(String)),
  additional: List(String),
) -> Option(List(String)) {
  case existing, additional {
    None, additional -> Some(additional)
    Some([]), _ | Some(_), [] -> Some([])
    Some(existing), additional -> Some(list.append(existing, additional))
  }
}

fn append_optional_monitor_factory(
  factories: List(MonitorFactory),
  factory: Option(MonitorFactory),
) -> List(MonitorFactory) {
  case factory {
    None -> factories
    Some(factory) -> list.append(factories, [factory])
  }
}

pub fn amend_renderer_options_by_arguments(
  options: RendererOptions(fragment_classifier),
  arguments: ParsedCLIArguments,
) -> RendererOptions(fragment_classifier) {
  RendererOptions(
    verbose: option.unwrap(arguments.verbose, options.verbose),
    artifacts: option.unwrap(arguments.artifacts, options.artifacts),
    steps_table: option.unwrap(arguments.table, options.steps_table),
    profiling_table: option.or(arguments.times, options.profiling_table),
    monitor_interactive_mode: {
      options.monitor_interactive_mode || arguments.monitor_interactive_mode
    },
    warnings: option.unwrap(arguments.warnings, options.warnings),
    report_long_running_desugarers: options.report_long_running_desugarers,
    only_paths: list.append(options.only_paths, arguments.only_paths),
    only_key_vals: list.append(options.only_key_vals, arguments.only_key_vals),
    only_path_key_vals: list.append(
      options.only_path_key_vals,
      arguments.only_path_key_vals,
    ),
    monitors: options.monitors,
    monitor_factories: options.monitor_factories
      |> append_optional_monitor_factory(arguments.tracking_monitor_factory)
      |> append_optional_monitor_factory(arguments.dump_monitor_factory)
      |> append_optional_monitor_factory(
        arguments.vxml_validation_monitor_factory,
      ),
    output_lines_table_default_comment_columns: options.output_lines_table_default_comment_columns,
    output_lines_table_default_blame_columns: options.output_lines_table_default_blame_columns,
    dump_assembled_lines: arguments.dump_assembled
      || options.dump_assembled_lines,
    dump_parsed_vxml: arguments.dump_parsed || options.dump_parsed_vxml,
    dump_filtered_vxml: arguments.dump_filtered || options.dump_filtered_vxml,
    dump_splitter_fragments: fn(fr: OutputFragment(fragment_classifier, VXML)) {
      options.dump_splitter_fragments(fr)
      || exists_match(arguments.splitter_fragment_path_matches, string.contains(
        fr.path,
        _,
      ))
    },
    dump_emitter_fragments: fn(
      fr: OutputFragment(fragment_classifier, List(OutputLine)),
    ) {
      options.dump_emitter_fragments(fr)
      || exists_match(arguments.emitter_fragment_path_matches, string.contains(
        fr.path,
        _,
      ))
    },
  )
}

fn resolve_absolute_step(step: Int, pipeline: Pipeline) -> Int {
  let num_steps = list.length(pipeline)
  case step < 0 {
    True -> num_steps + step + 1
    False -> step
  }
}

// Monitor construction and pipeline-step resolution

fn vxml_validation_problem_message(
  problem: vp.VXMLSerializationProblem,
) -> String {
  case problem {
    vp.BadTag(problem) -> "invalid tag: " <> ins(problem)
    vp.BadAttributeKey(problem) -> "invalid attribute key: " <> ins(problem)
    vp.BadAttributeValue(problem) -> "invalid attribute value: " <> ins(problem)
    vp.BadText(problem) -> "invalid text node: " <> ins(problem)
  }
}

fn blame_location_suffix(blame: Blame) -> String {
  case bl.blame_digest(blame) {
    "" -> " (no blame)"
    digest -> " at " <> digest
  }
}

fn attribute_boundary_whitespace_warnings(vxml: VXML) -> List(String) {
  case vxml {
    T(..) -> []
    V(_, _, attrs, children) -> {
      let local_warnings =
        attrs
        |> list.filter(fn(attr) { string.trim(attr.val) != attr.val })
        |> list.map(fn(attr) {
          "attribute "
          <> ins(attr.key)
          <> " has leading or trailing whitespace"
          <> blame_location_suffix(attr.blame)
        })
      list.append(
        local_warnings,
        children |> list.flat_map(attribute_boundary_whitespace_warnings),
      )
    }
  }
}

/// Builds a monitor that validates VXML before and after every pipeline step.
///
/// Invalid VXML stops the pipeline. When
/// `warn_about_attribute_boundary_whitespace` is `True`, the monitor also
/// emits feedback for attribute values with leading or trailing whitespace.
/// Such whitespace is valid VXML and is not otherwise rejected.
pub fn vxml_validation_monitor(
  warn_about_attribute_boundary_whitespace: Bool,
) -> Monitor {
  new_monitor("validate-vxml", [], fn(vxml, previous_warnings, _) {
    use _ <- on.error_ok(vp.validate(vxml), fn(error) {
      let vp.VXMLValidationError(blame, problem) = error
      Error(
        vxml_validation_problem_message(problem) <> blame_location_suffix(blame),
      )
    })
    let warnings = case warn_about_attribute_boundary_whitespace {
      False -> []
      True ->
        vxml
        |> attribute_boundary_whitespace_warnings
        |> list.unique
    }
    let new_warnings =
      warnings
      |> list.filter(fn(warning) { !list.contains(previous_warnings, warning) })
    let feedback = case new_warnings {
      [] -> NoFeedback
      warnings ->
        SomeFeedback([
          FeedbackBlock(
            lines: [
              "⚠️ VXML attribute-whitespace warning:",
              ..list.map(warnings, fn(warning) { "- " <> warning })
            ],
            margin: AtRunnerMargin,
          ),
        ])
    }
    Ok(#(warnings, feedback))
  })
}

fn first_empty_text_node_blame(vxml: VXML) -> Option(Blame) {
  case vxml {
    T(blame, []) -> Some(blame)
    T(_, [_, ..]) -> None
    V(_, _, _, children) -> first_empty_text_node_blame_in(children)
  }
}

fn first_empty_text_node_blame_in(vxmls: List(VXML)) -> Option(Blame) {
  case vxmls {
    [] -> None
    [first, ..rest] ->
      case first_empty_text_node_blame(first) {
        Some(blame) -> Some(blame)
        None -> first_empty_text_node_blame_in(rest)
      }
  }
}

/// Builds a monitor that rejects empty VXML text nodes.
///
/// Unlike `vxml_validation_monitor`, this monitor does not validate tags,
/// attributes, or text-line contents.
pub fn empty_text_node_monitor() -> Monitor {
  new_monitor("validate-vxml-lines", Nil, fn(vxml, state, _) {
    case first_empty_text_node_blame(vxml) {
      None -> Ok(#(state, NoFeedback))
      Some(blame) -> Error("empty text node" <> blame_location_suffix(blame))
    }
  })
}

fn list_int_cleaner(ze_list: List(Int)) -> List(Int) {
  ze_list |> list.unique |> list.sort(int.compare)
}

type ResolvedStepSelection {
  ResolvedStepSelection(on_change: List(Int), forced: List(Int))
}

fn resolve_absolute_step_range(
  range: AbsoluteStepRange,
  pipeline: Pipeline,
) -> List(Int) {
  let num_steps = list.length(pipeline)
  let #(first, last) = case range {
    ClosedAbsoluteStepRange(first, last) -> #(
      resolve_absolute_step(first, pipeline),
      resolve_absolute_step(last, pipeline),
    )
    AbsoluteStepsFrom(first) -> #(
      resolve_absolute_step(first, pipeline),
      num_steps,
    )
  }
  lo_hi_ints(int.min(first, last), int.max(first, last))
  |> list.filter(fn(step) { step >= 0 && step <= num_steps })
}

fn resolve_desugarer_relative_step_range(
  range: DesugarerRelativeStepRange,
  pipeline: Pipeline,
) -> Result(List(Int), String) {
  let DesugarerRelativeStepRange(name, first_offset, last_offset) = range
  let indices =
    list.index_fold(pipeline, [], fn(acc, desugarer, i) {
      case desugarer.name == name {
        True -> [i, ..acc]
        False -> acc
      }
    })
  use _ <- on.stay(case indices {
    [] -> on.Return(Error("desugarer name not found: " <> name))
    _ -> on.Stay(Nil)
  })
  let num_steps = list.length(pipeline)
  let relative_range = lo_hi_ints(first_offset, last_offset)
  let final_range =
    list.fold(indices, [], fn(acc, index) {
      let step_no = index + 1
      list.fold(relative_range, acc, fn(sub_acc, x) { [step_no + x, ..sub_acc] })
    })
  final_range
  |> list.filter(fn(step) { step >= 0 && step <= num_steps })
  |> list_int_cleaner
  |> Ok
}

fn resolve_pipeline_step_specs(
  specs: List(PipelineStepSpec),
  pipeline: Pipeline,
) -> Result(ResolvedStepSelection, String) {
  use #(on_change, forced) <- on.ok(
    list.try_fold(specs, #([], []), fn(acc, spec) {
      let PipelineStepSpec(range, mode) = spec
      use steps <- on.ok(case range {
        AbsoluteSteps(range) -> Ok(resolve_absolute_step_range(range, pipeline))
        DesugarerRelativeSteps(range) ->
          resolve_desugarer_relative_step_range(range, pipeline)
      })
      case mode {
        OnChange -> Ok(#(list.append(acc.0, steps), acc.1))
        Forced -> Ok(#(acc.0, list.append(acc.1, steps)))
      }
    }),
  )
  let forced = list_int_cleaner(forced)
  let on_change =
    on_change
    |> list_int_cleaner
    |> list.filter(fn(step) { !list.contains(forced, step) })
  Ok(ResolvedStepSelection(on_change, forced))
}

fn monitor_output_heading(context: PipelineStepContext) -> List(String) {
  case context.previous_desugarer {
    None -> ["0. initial pipeline state"]
    Some(desugarer) ->
      pr.name_and_param_string_lines(desugarer, context.step_no, 0)
  }
}

fn selected_vxml(vxml: VXML, selector: Selector) {
  vxml
  |> tracking.vxml_to_s_lines
  |> selector
}

fn selected_output_lines(
  vxml: VXML,
  selector: Selector,
  output: VxmlMonitorOutput,
  include_ellipses: Bool,
  table_indent: Int,
  default_blame_columns: Int,
  default_comment_columns: Int,
) -> List(String) {
  let lines = selected_vxml(vxml, selector)
  case output {
    TrackingVerbatim ->
      tracking.s_lines_verbatim_lines_with_options(
        lines,
        False,
        include_ellipses,
      )
    TrackingTable(blame_columns, comment_columns) -> {
      let blame_columns = option.unwrap(blame_columns, default_blame_columns)
      let comment_columns =
        option.unwrap(comment_columns, default_comment_columns)
      tracking.s_lines_table_lines_with_options(
        lines,
        "",
        False,
        table_indent,
        bl.BlameTableMarginColumnsMinMax(blame_columns, blame_columns),
        bl.BlameTableMarginColumnsMinMax(comment_columns, comment_columns),
        include_ellipses,
      )
    }
  }
}

fn selected_comparison_string(vxml: VXML, selector: Selector) -> String {
  selected_vxml(vxml, selector)
  |> tracking.s_lines_table("", True, 0)
}

fn vxml_monitor_output_margin(output: VxmlMonitorOutput) -> FeedbackMargin {
  case output {
    TrackingTable(_, _) -> AtRunnerMargin
    TrackingVerbatim -> Verbatim
  }
}

fn tracking_monitor_output(
  vxml: VXML,
  selector: Selector,
  context: PipelineStepContext,
  output: VxmlMonitorOutput,
  include_ellipses: Bool,
  default_blame_columns: Int,
  default_comment_columns: Int,
) -> FeedbackBlock {
  FeedbackBlock(
    lines: [
      "💠",
      ..list.append(monitor_output_heading(context), [
        "💠",
        ..selected_output_lines(
          vxml,
          selector,
          output,
          include_ellipses,
          0,
          default_blame_columns,
          default_comment_columns,
        )
      ])
    ],
    margin: vxml_monitor_output_margin(output),
  )
}

fn make_tracking_monitor(
  tracker: Tracker,
  pipeline: Pipeline,
  default_blame_columns: Int,
  default_comment_columns: Int,
) -> Result(Monitor, String) {
  use ResolvedStepSelection(on_change_steps, forced_steps) <- on.ok(
    resolve_pipeline_step_specs(tracker.step_specs, pipeline),
  )
  let track_all = on_change_steps == [] && forced_steps == []
  let printing_selector =
    option.unwrap(tracker.printing_selector, fn(lines) { lines })
  let change_selector =
    option.unwrap(tracker.change_selector, printing_selector)
  let output = option.unwrap(tracker.output, TrackingTable(None, None))
  let output_margin = vxml_monitor_output_margin(output)
  let include_selection_ellipses =
    option.unwrap(tracker.include_selection_ellipses, True)
  new_monitor("track", #(None, None), fn(vxml, state, context) {
    let #(previous, last_output_step) = state
    let forced = list.contains(forced_steps, context.step_no)
    let on_change = track_all || list.contains(on_change_steps, context.step_no)
    let #(previous, feedback_blocks) = case forced || on_change {
      False -> #(previous, [])
      True -> {
        let comparison = selected_comparison_string(vxml, change_selector)
        let monitor_output =
          tracking_monitor_output(
            vxml,
            printing_selector,
            context,
            output,
            include_selection_ellipses,
            default_blame_columns,
            default_comment_columns,
          )
        case forced || Some(comparison) != previous {
          True -> #(Some(comparison), [monitor_output])
          False -> #(Some(comparison), [])
        }
      }
    }
    let feedback_blocks = case feedback_blocks, context.previous_desugarer {
      [], Some(desugarer)
        if context.step_no > 0
        && context.step_no % tracking_progress_interval == 0
      -> {
        let enough_steps_since_last_output = case last_output_step {
          None -> True
          Some(step_no) ->
            context.step_no - step_no >= tracking_progress_quiet_steps
        }
        case enough_steps_since_last_output {
          True -> [
            FeedbackBlock(
              lines: ["..." <> ins(context.step_no) <> ". " <> desugarer.name],
              margin: output_margin,
            ),
          ]
          False -> []
        }
      }
      _, _ -> feedback_blocks
    }
    let last_output_step = case feedback_blocks {
      [] -> last_output_step
      _ -> Some(context.step_no)
    }
    let feedback = case feedback_blocks {
      [] -> NoFeedback
      blocks -> SomeFeedback(blocks)
    }
    Ok(#(#(previous, last_output_step), feedback))
  })
  |> Ok
}

fn make_dump_monitor(
  specs: List(PipelineStepSpec),
  output: VxmlMonitorOutput,
  pipeline: Pipeline,
  default_blame_columns: Int,
  default_comment_columns: Int,
) -> Result(Monitor, String) {
  use ResolvedStepSelection(on_change_steps, forced_steps) <- on.ok(
    resolve_pipeline_step_specs(specs, pipeline),
  )
  let selected_steps =
    list.append(on_change_steps, forced_steps) |> list_int_cleaner
  let dump_all = specs == []
  new_monitor("dump", Nil, fn(vxml, state, context) {
    case dump_all || list.contains(selected_steps, context.step_no) {
      False -> Ok(#(state, NoFeedback))
      True -> {
        let monitor_output =
          FeedbackBlock(
            lines: [
              "💠",
              ..list.append(monitor_output_heading(context), [
                "💠",
                ..selected_output_lines(
                  vxml,
                  sl.all(),
                  output,
                  True,
                  0,
                  default_blame_columns,
                  default_comment_columns,
                )
              ])
            ],
            margin: vxml_monitor_output_margin(output),
          )
        Ok(#(state, SomeFeedback([monitor_output])))
      }
    }
  })
  |> Ok
}

fn make_monitors(
  options: RendererOptions(fragment_classifier),
  pipeline: Pipeline,
) -> Result(
  List(Monitor),
  RendererError(
    assembler_error,
    parser_error,
    filterer_error,
    splitter_error,
    emitter_error,
    writer_error,
  ),
) {
  use built <- on.error_ok(
    list.try_map(options.monitor_factories, fn(factory) {
      case factory {
        TrackingMonitorFactory(tracker) ->
          make_tracking_monitor(
            tracker,
            pipeline,
            options.output_lines_table_default_blame_columns,
            options.output_lines_table_default_comment_columns,
          )
        DumpMonitorFactory(specs, output) ->
          make_dump_monitor(
            specs,
            output,
            pipeline,
            options.output_lines_table_default_blame_columns,
            options.output_lines_table_default_comment_columns,
          )
        VxmlValidationMonitorFactory(mode) ->
          case mode {
            ValidateAllVxml(warn_about_attribute_boundary_whitespace) ->
              Ok(vxml_validation_monitor(
                warn_about_attribute_boundary_whitespace,
              ))
            ValidateTextLinesOnly -> Ok(empty_text_node_monitor())
          }
      }
    }),
    fn(message) { Error(DesugarerNameNotFoundError(message)) },
  )
  Ok(list.append(options.monitors, built))
}

pub type UserExit {
  UserExit(step_no: Int)
}

pub type InSituDesugaringError {
  InSituDesugaringError(
    desugarer: Desugarer,
    step_no: Int,
    message: String,
    blame: Blame,
  )
}

pub type InSituDesugaringWarning {
  InSituDesugaringWarning(
    desugarer: Desugarer,
    step_no: Int,
    message: String,
    blame: Blame,
  )
}

pub type MonitorFailure {
  MonitorFailure(monitor_name: String, step_no: Int, message: String)
}

pub type PipelineExecutionError {
  PipelineUserExit(UserExit)
  PipelineDesugaringError(InSituDesugaringError)
  PipelineMonitorError(MonitorFailure)
}

/// Terminal presentation and interaction settings for `run_pipeline`.
pub type PipelineUXOptions {
  PipelineUXOptions(
    monitor_interactive_mode: Bool,
    report_long_running_desugarers: Bool,
    feedback_margin: Int,
  )
}

type PipelineProducerState {
  PipelineProducerState(
    vxml: VXML,
    warnings: List(InSituDesugaringWarning),
    durations: List(Duration),
    monitors: List(Monitor),
  )
}

type Message {
  ProducerStartedDesugarer(Desugarer, Int)
  ProducerFinishedDesugarer
  MonitorProducedOutput(FeedbackBlock, Int)
  ProducerFinished(
    Result(
      #(VXML, List(InSituDesugaringWarning), List(Duration)),
      PipelineExecutionError,
    ),
  )
}

fn update_monitors(
  main_process_subject: Subject(Message),
  monitors: List(Monitor),
  vxml: VXML,
  context: PipelineStepContext,
) -> Result(List(Monitor), MonitorFailure) {
  monitors
  |> list.try_fold([], fn(next_monitors, monitor) {
    use update <- on.error_ok(monitor.update(vxml, context), fn(message) {
      Error(MonitorFailure(
        monitor_name: monitor.name,
        step_no: context.step_no,
        message: message,
      ))
    })
    let MonitorUpdate(next, feedback) = update
    case feedback {
      NoFeedback -> Nil
      SomeFeedback(blocks) ->
        list.each(blocks, fn(block) {
          send(
            main_process_subject,
            MonitorProducedOutput(block, context.step_no),
          )
        })
    }
    Ok([next, ..next_monitors])
  })
  |> result.map(list.reverse)
}

fn producer(
  main_process_subject: Subject(Message),
  vxml: VXML,
  pipeline: Pipeline,
  monitors: List(Monitor),
) -> Nil {
  let first_desugarer = case list.first(pipeline) {
    Ok(desugarer) -> Some(desugarer)
    Error(_) -> None
  }
  let initial_context =
    PipelineStepContext(
      step_no: 0,
      previous_desugarer: None,
      next_desugarer: first_desugarer,
    )
  let final = case
    update_monitors(main_process_subject, monitors, vxml, initial_context)
  {
    Error(failure) -> Error(PipelineMonitorError(failure))
    Ok(monitors) ->
      pipeline
      |> list.index_map(fn(desugarer, index) { #(desugarer, index) })
      |> list.try_fold(
        PipelineProducerState(vxml, [], [], monitors),
        fn(state, indexed_desugarer) {
          let #(desugarer, index) = indexed_desugarer
          let step_no = index + 1
          send(
            main_process_subject,
            ProducerStartedDesugarer(desugarer, step_no),
          )
          let now = timestamp.system_time()
          use #(vxml, new_warnings) <- on.error_ok(
            desugarer.transform(state.vxml),
            fn(error) {
              InSituDesugaringError(
                desugarer: desugarer,
                step_no: step_no,
                blame: error.blame,
                message: error.message,
              )
              |> PipelineDesugaringError
              |> Error
            },
          )
          let then = timestamp.system_time()
          send(main_process_subject, ProducerFinishedDesugarer)
          let durations = [timestamp.difference(now, then), ..state.durations]
          let new_warnings =
            list.map(new_warnings, fn(warning) {
              InSituDesugaringWarning(
                desugarer: desugarer,
                step_no: step_no,
                blame: warning.blame,
                message: warning.message,
              )
            })
          let next_desugarer = case list.first(list.drop(pipeline, step_no)) {
            Ok(desugarer) -> Some(desugarer)
            Error(_) -> None
          }
          let context =
            PipelineStepContext(
              step_no: step_no,
              previous_desugarer: Some(desugarer),
              next_desugarer: next_desugarer,
            )
          use monitors <- on.error_ok(
            update_monitors(main_process_subject, state.monitors, vxml, context),
            fn(failure) { Error(PipelineMonitorError(failure)) },
          )
          Ok(PipelineProducerState(
            vxml: vxml,
            warnings: list.append(state.warnings, new_warnings),
            durations: durations,
            monitors: monitors,
          ))
        },
      )
      |> result.map(fn(state) {
        #(state.vxml, state.warnings, list.reverse(state.durations))
      })
  }

  send(main_process_subject, ProducerFinished(final))
}

fn print_feedback_block(feedback: FeedbackBlock, runner_margin: Int) -> Nil {
  let FeedbackBlock(lines, margin) = feedback
  let margin = case margin {
    AtRunnerMargin -> string.repeat(" ", runner_margin)
    Verbatim -> ""
  }
  lines
  |> list.map(fn(line) { margin <> line })
  |> string.join("\n")
  |> io.println
}

fn print_feedback(feedback: Feedback, runner_margin: Int) -> Nil {
  case feedback {
    NoFeedback -> Nil
    SomeFeedback(blocks) ->
      list.each(blocks, print_feedback_block(_, runner_margin))
  }
}

fn print_verbose_feedback(feedback: Feedback, verbose: Bool) -> Nil {
  case verbose {
    True -> print_feedback(feedback, renderer_runner_margin)
    False -> Nil
  }
}

fn loop(
  subject: Subject(Message),
  countdown: Int,
  running_desugarer: Option(#(Desugarer, Int)),
  running_seconds: Int,
  ux_options: PipelineUXOptions,
  // pause for user only when countdown == 0
) -> Result(
  #(VXML, List(InSituDesugaringWarning), List(Duration)),
  PipelineExecutionError,
) {
  case
    receive(
      subject,
      within: long_running_desugarer_report_interval_seconds * 1000,
    )
  {
    Ok(ProducerStartedDesugarer(desugarer, step_no)) ->
      loop(subject, countdown, Some(#(desugarer, step_no)), 0, ux_options)

    Ok(ProducerFinishedDesugarer) ->
      loop(subject, countdown, None, 0, ux_options)

    Ok(MonitorProducedOutput(output, step_no)) -> {
      print_feedback_block(output, ux_options.feedback_margin)
      case countdown == 0 {
        False -> {
          loop(
            subject,
            countdown - 1,
            running_desugarer,
            running_seconds,
            ux_options,
          )
        }
        True ->
          case input.input("(↵|<n>|e|c) ") {
            Ok(msg) -> {
              let #(countdown, quit) = case int.parse(msg) {
                Ok(q) -> #(q, False)
                Error(_) ->
                  case msg {
                    "e" -> #(-1, False)
                    "c" -> #(-1, True)
                    _ -> #(1, False)
                  }
              }
              case quit {
                True -> Error(PipelineUserExit(UserExit(step_no)))
                False ->
                  loop(
                    subject,
                    countdown - 1,
                    running_desugarer,
                    running_seconds,
                    ux_options,
                  )
              }
            }
            Error(_) -> {
              panic as "error reading input"
            }
          }
      }
    }

    Ok(ProducerFinished(result)) -> {
      case result {
        Ok(value) -> Ok(value)
        Error(error) -> Error(error)
      }
    }

    Error(_) -> {
      let running_seconds =
        running_seconds + long_running_desugarer_report_interval_seconds
      case running_desugarer, ux_options.report_long_running_desugarers {
        Some(#(desugarer, step_no)), True ->
          io.println(
            string.repeat(" ", ux_options.feedback_margin)
            <> "[desugarer "
            <> ins(step_no)
            <> ". "
            <> desugarer.name
            <> " still running after "
            <> ins(running_seconds)
            <> "s]",
          )
        _, _ -> Nil
      }
      loop(subject, countdown, running_desugarer, running_seconds, ux_options)
    }
  }
}

pub fn run_pipeline(
  vxml: VXML,
  pipeline: Pipeline,
  monitors: List(Monitor),
  ux_options: PipelineUXOptions,
) -> Result(
  #(VXML, List(InSituDesugaringWarning), List(Duration)),
  PipelineExecutionError,
) {
  let main_subject = process.new_subject()

  let producer_pid =
    spawn(fn() { producer(main_subject, vxml, pipeline, monitors) })

  process.link(producer_pid)

  let countdown = case ux_options.monitor_interactive_mode {
    True -> 0
    False -> -1
  }

  loop(main_subject, countdown, None, 0, ux_options)
}

// Renderer helpers

fn sanitize_input_output_dirs(
  parameters: RendererParameters,
) -> RendererParameters {
  RendererParameters(
    ..parameters,
    input_dir: core.drop_ending_slash(parameters.input_dir),
    output_dir: core.drop_ending_slash(parameters.output_dir),
  )
}

fn dump_vxml(vxml: VXML, banner: String, indent: Int) -> Nil {
  case vp.vxml_to_output_lines(vxml) {
    Ok(lines) -> lines |> io_l.output_lines_table(banner, indent) |> io.println
    Error(error) -> {
      error.partial |> io_l.output_lines_table(banner, indent) |> io.println
      io.println("VXML serialization error: " <> ins(error))
    }
  }
}

fn create_dirs_on_path_to_file(
  path_to_file: String,
) -> Result(Nil, simplifile.FileError) {
  let pieces = path_to_file |> string.split("/")
  let pieces = core.drop_last(pieces)
  list.try_fold(pieces, ".", fn(acc, piece) {
    let acc = acc <> "/" <> piece
    use exists <- on.ok(simplifile.is_directory(acc))
    use _ <- on.ok(case exists {
      True -> Ok(Nil)
      False -> simplifile.create_directory(acc)
    })
    Ok(acc)
  })
  |> result.map(fn(_) { Nil })
}

pub type EmitterOrWriterError(emitter_error, writer_error) {
  EmitterError(emitter_error)
  WriterError(writer_error)
}

pub type RendererError(
  assembler_error,
  parser_error,
  filterer_error,
  splitter_error,
  emitter_error,
  writer_error,
) {
  AssemblerError(assembler_error)
  ParserError(Blame, parser_error)
  FiltererError(filterer_error)
  DesugarerNameNotFoundError(String)
  PipelineError(InSituDesugaringError)
  MonitorError(MonitorFailure)
  UserExitError(Int)
  SplitterError(splitter_error)
  EmittingOrWritingErrors(
    List(EmitterOrWriterError(emitter_error, writer_error)),
  )
}

pub fn run_renderer(
  renderer: Renderer(
    assembler_error,
    parser_error,
    filterer_error,
    splitter_error,
    emitter_error,
    writer_error,
    fragment_classifier,
  ),
  parameters: RendererParameters,
  options: RendererOptions(fragment_classifier),
) -> Result(
  List(String),
  RendererError(
    assembler_error,
    parser_error,
    filterer_error,
    splitter_error,
    emitter_error,
    writer_error,
  ),
) {
  let result = run_renderer_(renderer, parameters, options)
  io.println("")
  result
}

fn run_renderer_(
  renderer: Renderer(
    assembler_error,
    parser_error,
    filterer_error,
    splitter_error,
    emitter_error,
    writer_error,
    fragment_classifier,
  ),
  parameters: RendererParameters,
  options: RendererOptions(fragment_classifier),
) -> Result(
  List(String),
  RendererError(
    assembler_error,
    parser_error,
    filterer_error,
    splitter_error,
    emitter_error,
    writer_error,
  ),
) {
  let parameters = sanitize_input_output_dirs(parameters)

  let input_dir = parameters.input_dir
  let output_dir = parameters.output_dir
  let prettifier_mode = parameters.prettifier_behavior

  case options.steps_table {
    True -> pr.print_pipeline(renderer.pipeline)
    False -> Nil
  }

  // 🌸 assembling 🌸

  io.println("• assembling...")

  use #(assembled, assembler_feedback) <- on.error_ok(
    renderer.assembler(input_dir),
    fn(error_a) {
      io.println("  ...assembler error on input_dir " <> input_dir <> ":")
      io.println("")
      [
        #(" ", ins(error_a)),
      ]
      |> fb.error_announcement(0, 60, "💥", 2, "/ assembler error /")
      |> io.println
      Error(AssemblerError(error_a))
    },
  )

  print_verbose_feedback(assembler_feedback, options.verbose)

  case options.dump_assembled_lines {
    False -> Nil
    True -> {
      assembled
      |> io_l.input_lines_table("", 2)
      |> io.println
    }
  }

  // 🌸 parsing 🌸

  io.println("• parsing input lines to VXML...")

  use #(parsed, parser_feedback) <- on.error_ok(
    renderer.parser(assembled),
    on_error: fn(error) {
      let #(blame, c) = error
      io.println("  ...parser error:")
      io.println("")
      [
        #(" blame:", pr.our_blame_digest(blame)),
        #(" error: ", ins(c) |> pr.strip_quotes),
      ]
      |> fb.error_announcement(0, 70, "💥", 2, "/ parser error /")
      |> io.println
      Error(ParserError(blame, c))
    },
  )

  print_verbose_feedback(parser_feedback, options.verbose)

  case options.dump_parsed_vxml {
    False -> Nil
    True -> dump_vxml(parsed, "parsed:", 2)
  }

  use #(filtered, filterer_feedback) <- on.error_ok(
    renderer.filterer(parsed),
    fn(c) {
      io.println("  ...filtration error:")
      io.println("")
      [
        #("", ins(c) |> pr.strip_quotes),
      ]
      |> fb.error_announcement(0, 70, "💥", 2, "/ filtration error /")
      |> io.println
      Error(FiltererError(c))
    },
  )

  print_verbose_feedback(filterer_feedback, options.verbose)

  case options.dump_filtered_vxml {
    False -> Nil
    True -> dump_vxml(filtered, "filtered:", 2)
  }

  // 🌸 pipeline 🌸

  io.println("• starting pipeline...")
  let t0 = timestamp.system_time()

  use monitors <- on.error_ok(
    make_monitors(options, renderer.pipeline),
    on_error: fn(error) {
      io.println("  ...error:")
      io.println("")
      [#("", ins(error))]
      |> fb.error_announcement(0, 70, "💥", 2, "/ monitor option error /")
      |> io.println
      Error(error)
    },
  )

  use #(desugared, warnings, durations) <- on.error_ok(
    run_pipeline(
      filtered,
      renderer.pipeline,
      monitors,
      PipelineUXOptions(
        monitor_interactive_mode: options.monitor_interactive_mode,
        report_long_running_desugarers: options.report_long_running_desugarers,
        feedback_margin: renderer_runner_margin,
      ),
    ),
    on_error: fn(e) {
      case e {
        PipelineUserExit(UserExit(step_no)) -> {
          io.println("")
          io.println("user exit at step_no " <> ins(step_no))
          Error(UserExitError(step_no))
        }
        PipelineDesugaringError(e) -> {
          io.println("  ...desugaring error:")
          io.println("")
          [
            #(" desugarer:  ", e.desugarer.name <> ".gleam"),
            #(" step: ", ins(e.step_no)),
            #(" blame:", pr.our_blame_digest(e.blame)),
            #(" message:", e.message),
          ]
          |> fb.mushroom_error_announcement("DesugaringError", _)
          |> io.println
          Error(PipelineError(e))
        }
        PipelineMonitorError(failure) -> {
          let MonitorFailure(name, step_no, message) = failure
          io.println("  ...pipeline stopped by monitor:")
          io.println("")
          [
            #(" step:", ins(step_no)),
            #(" message:", message),
          ]
          |> fb.mushroom_error_announcement("'" <> name <> "' monitor error", _)
          |> io.println
          Error(MonitorError(failure))
        }
      }
    },
  )

  let t1 = timestamp.system_time()
  let seconds =
    timestamp.difference(t0, t1) |> duration.to_seconds |> float.to_precision(3)

  case options.profiling_table {
    None -> {
      io.println("  ..ended pipeline (" <> ins(seconds) <> "s)")
    }

    Some(total_chars) -> {
      let all_seconds = durations |> list.map(duration.to_seconds)
      let max_secs = case list.max(all_seconds, float.compare) {
        Ok(max_secs) -> max_secs
        Error(_) -> 0.0
      }
      let num_hundreth_seconds = case float.ceiling(max_secs *. 100.0) {
        measured_hundreths if measured_hundreths >. 0.0 -> measured_hundreths
        _ -> 1.0
      }
      let one_hundreth_seconds_num_bars =
        int.to_float(total_chars) /. num_hundreth_seconds
      let scale =
        list.repeat(Nil, float.round(num_hundreth_seconds) + 1)
        |> list.map_fold(0.0, fn(x, _) { #(x +. 0.01, x) })
        |> pair.second
        |> list.index_fold("", fn(acc, seconds, i) {
          let start_char =
            float.round(int.to_float(i) *. one_hundreth_seconds_num_bars)
          let num_spaces = start_char - string.length(acc)
          case num_spaces > 0 || acc == "" {
            False -> acc
            True -> {
              let label = ins(seconds |> float.to_precision(2)) <> "s"
              acc <> string.repeat(" ", num_spaces) <> label
            }
          }
        })
      assert list.length(all_seconds) == list.length(renderer.pipeline)
      let bars =
        list.map(all_seconds, fn(seconds) {
          seconds *. 100.0 *. one_hundreth_seconds_num_bars
          |> float.round
          |> pr.blocks
        })
      pr.pipeline_timing_table(renderer.pipeline, bars, scale)
      |> pr.print_lines_at_indent(2)
      io.println("  ...ended pipeline in " <> ins(seconds) <> "s")
    }
  }

  // 🌸 splitting 🌸

  io.println("• splitting...")

  use #(fragments, splitter_feedback) <- on.error_ok(
    renderer.splitter(desugared),
    on_error: fn(error) {
      io.println("  ...splitter error:")
      io.println("")
      [
        #("", ins(error)),
      ]
      |> fb.mushroom_error_announcement("splitter error", _)
      |> io.println
      Error(SplitterError(error))
    },
  )

  print_verbose_feedback(splitter_feedback, options.verbose)

  let prefix = "[" <> output_dir <> "/]"
  let fragments_types_and_paths_4_table =
    list.map(fragments, fn(fr) { #(ins(fr.classifier), prefix <> fr.path) })

  case options.verbose {
    False -> {
      io.println(
        "  -> obtained "
        <> pr.how_many("fragment", "fragments", list.length(fragments)),
      )
    }
    True -> {
      io.println(
        "  -> obtained "
        <> pr.how_many("fragment", "fragments", list.length(fragments))
        <> ":",
      )
      [#("classifier", "path"), ..fragments_types_and_paths_4_table]
      |> pr.two_column_table
      |> pr.print_lines_at_indent(2)
    }
  }

  fragments
  |> list.each(fn(fr) {
    case options.dump_splitter_fragments(fr) {
      False -> Nil
      True -> dump_vxml(fr.payload, "splitter: " <> fr.path, 2)
    }
  })

  // 🌸 emitting 🌸

  io.print("• converting VXML fragments to List(OutputLine) fragments...")

  let fragments =
    fragments
    |> list.map(renderer.emitter)

  io.println("")

  fragments
  |> list.each(fn(result) {
    case result {
      Error(_) -> Nil
      Ok(#(fr, feedback)) -> {
        print_verbose_feedback(feedback, options.verbose)
        case options.dump_emitter_fragments(fr) {
          False -> Nil
          True -> {
            fr.payload
            |> io_l.output_lines_table("emitter: " <> fr.path, 2)
            |> io.println
          }
        }
      }
    }
  })

  let num_emitter_errors =
    list.fold(fragments, 0, fn(acc, fr) {
      case fr {
        Ok(_) -> acc
        _ -> acc + 1
      }
    })

  list.each(fragments, fn(fr) {
    use error <- on.ok_error(fr, fn(_) { Nil })
    io.println("  emitter error:")
    io.println("")
    [
      #("", ins(error)),
    ]
    |> fb.mushroom_error_announcement("emitter error", _)
    |> io.println
  })

  case num_emitter_errors {
    0 -> Nil
    _ -> io.println("")
  }

  io.println("• converting List(OutputLine) fragments to String fragments...")

  let fragments = {
    fragments
    |> list.map(
      on.error_ok(_, fn(error) { Error(EmitterError(error)) }, fn(result) {
        let #(fr, _) = result
        Ok(
          OutputFragment(..fr, payload: io_l.output_lines_to_string(fr.payload)),
        )
      }),
    )
  }

  // 🌸 writing 🌸

  io.println("• writing String fragments to files...")

  let singleton_fragment = case fragments {
    [_] -> True
    _ -> False
  }

  let #(count, fragments) =
    fragments
    |> list.map_fold(0, fn(acc, result) {
      use fr <- on.error_ok(result, fn(e) { #(acc, Error(e)) })
      case renderer.writer(output_dir, fr) {
        Error(e) -> #(acc, Error(WriterError(e)))
        Ok(#(z, feedback)) -> {
          print_verbose_feedback(feedback, options.verbose)
          case singleton_fragment {
            True -> io.println("  -> wrote [" <> output_dir <> "/]" <> fr.path)
            False ->
              case options.verbose || options.artifacts {
                True -> io.println("  wrote [" <> output_dir <> "/]" <> fr.path)
                False -> Nil
              }
          }
          #(acc + 1, Ok(z))
        }
      }
    })

  case options.verbose || options.artifacts {
    False ->
      case count {
        1 ->
          case singleton_fragment {
            True -> Nil
            // we already announced (see above)
            False ->
              io.println(
                "  -> wrote 1 file (use '--artifacts' or '--verbose' to see)",
              )
          }
        _ ->
          io.println(
            "  -> wrote "
            <> ins(count)
            <> " files (use '--artifacts' or '--verbose' to see)",
          )
      }
    True -> Nil
  }

  // 🌸 prettifying 🌸

  let run_prettification = fn(result, dest_dir) {
    use fr: GhostOfOutputFragment(fragment_classifier) <- on.eager_error_ok(
      result,
      Nil,
    )
    case dest_dir {
      None ->
        io.print(
          "  prettify-checking [" <> output_dir <> "]" <> fr.path <> "...",
        )
      Some(dir) ->
        io.print(
          "  prettifying ["
          <> output_dir
          <> "/]"
          <> fr.path
          <> " -> ["
          <> dir
          <> "/]"
          <> fr.path
          <> "...",
        )
    }
    case renderer.prettifier(output_dir, fr, dest_dir) {
      None -> {
        io.println("skipped")
      }
      Some(PrettifierFeedback(warnings: warns, errors: errs)) -> {
        let x = list.length(warns)
        let y = list.length(errs)
        let warn_suffix = case x > 0 && !options.warnings {
          True -> " (use '--warnings' to see)"
          False -> ","
        }
        let end = case y > 0 || { x > 0 && options.warnings } {
          True -> ":\n"
          False -> "\n"
        }
        io.print(
          " "
          <> ins(x)
          <> " warnings"
          <> warn_suffix
          <> " "
          <> ins(y)
          <> " errors"
          <> end,
        )
        case options.warnings {
          True ->
            list.each(warns, fn(w) {
              io.println("  👾👾--- warning ---👾👾: " <> w)
            })
          False -> Nil
        }
        list.each(errs, fn(e) { io.println("  🍄🍄--- error ---🍄🍄: " <> e) })
      }
    }
  }

  case prettifier_mode {
    PrettifierOff -> Nil
    _ -> {
      io.println("• prettifying:")
      let dest_dir = case prettifier_mode {
        PrettifierOverwriteOutputDir -> Some(output_dir)
        PrettifierToBespokeDir(dir) -> dir
        _ -> panic
      }
      list.each(fragments, run_prettification(_, dest_dir))
    }
  }

  // 👾 warnings 👾

  case list.length(warnings) {
    0 -> Nil
    _ -> {
      case options.warnings {
        True ->
          io.println(
            "\n👉 "
            <> pr.how_many("warning", "warnings", list.length(warnings))
            <> ":",
          )
        False ->
          io.println(
            "\n["
            <> pr.how_many(
              "suppressed warning",
              "suppressed warnings",
              list.length(warnings),
            )
            <> " (use '--warnings' option to see)]",
          )
      }
    }
  }

  case options.warnings {
    True ->
      list.each(warnings, fn(w) {
        io.println("")
        [
          #(" from:", w.desugarer.name <> " (desugarer)"),
          #(" pipeline step: ", ins(w.step_no)),
          #(" blame:", bl.blame_digest(w.blame)),
          #(" message:", w.message),
        ]
        |> fb.error_announcement(0, 60, "👾", 2, "")
        |> io.println
      })
    False -> Nil
  }

  let #(oks, errors) = result.partition(fragments)

  case errors {
    [] -> Ok(oks |> list.map(fn(ghost) { ghost.path }))
    _ -> Error(EmittingOrWritingErrors(errors))
  }
}
