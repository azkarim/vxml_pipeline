import desugaring.{
  type Feedback, type OutputFragment, type RendererOptions, AtRunnerMargin,
  FeedbackBlock, NoFeedback, OutputFragment, SomeFeedback,
}
import dirtree as dt
import gleam/list
import gleam/result
import gleam/string.{inspect as ins}
import vxml.{type VXML}
import vxml/blame.{type Blame}
import vxml/io_lines.{type InputLine, type OutputLine}
import writerly as wl

/// Transitional Writerly adapter defaults for the generic renderer.
///
/// This module keeps Writerly-specific assembly, parsing, and emitting
/// separate from the input-format-agnostic renderer core. It is adapter glue,
/// not core renderer API.
pub fn default_writerly_assembler(
  dirpath_or_filepath: String,
  options: RendererOptions(_),
) -> Result(#(List(InputLine), Feedback), wl.AssemblyError) {
  let path_selector = wl.path_selector_from_only_paths(options.only_paths)
  use #(tree, assembled) <- result.try(
    wl.assemble_input_lines_with_path_selector(
      dirpath_or_filepath,
      path_selector,
    ),
  )
  let prefix = "-> assembled "
  let continuation = string.repeat(" ", string.length(prefix))
  let feedback_lines =
    tree
    |> dt.pretty_print(1)
    |> list.index_map(fn(line, index) {
      case index {
        0 -> prefix
        _ -> continuation
      }
      <> line
    })
  let feedback = FeedbackBlock(feedback_lines, AtRunnerMargin)
  Ok(#(assembled, SomeFeedback([feedback])))
}

pub fn default_writerly_parser(
  lines: List(InputLine),
) -> Result(#(VXML, Feedback), #(Blame, String)) {
  wl.input_lines_to_vxml(lines)
  |> result.map(fn(vxml) { #(vxml, NoFeedback) })
  |> result.map_error(fn(e) { #(e.blame, ins(e)) })
}

pub fn default_writerly_emitter(
  fragment: OutputFragment(z, VXML),
) -> Result(#(OutputFragment(z, List(OutputLine)), Feedback), b) {
  let lines =
    fragment.payload
    |> wl.vxml_to_writerlys
    |> wl.writerlys_to_output_lines

  Ok(#(OutputFragment(..fragment, payload: lines), NoFeedback))
}
