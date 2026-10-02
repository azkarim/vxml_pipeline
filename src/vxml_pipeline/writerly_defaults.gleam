//// Writerly assembler, parser, and emitter adapters for the generic renderer.

import dirtree as dt
import gleam/list
import gleam/result
import gleam/string.{inspect as ins}
import vxml.{type VXML}
import vxml/blame.{type Blame}
import vxml/io_lines.{type InputLine, type OutputLine}
import vxml_pipeline.{
  type Feedback, type OutputFragment, type RendererOptions, AtRunnerMargin,
  FeedbackBlock, NoFeedback, OutputFragment, SomeFeedback,
}
import writerly as wl

// Builds a path selector from inclusive and exclusive path fragments.
//
// Ordinary fragments include paths containing that fragment. Fragments
// beginning with `!` exclude matching paths. With only exclusions, all other
// paths are included. With both forms, a path must match an inclusion and no
// exclusion. An empty list selects every path.
fn path_selector_from_filters(only_paths: List(String)) -> fn(String) -> Bool {
  let #(excluded_paths, included_paths) =
    list.partition(only_paths, string.starts_with(_, "!"))
  let excluded_paths = list.map(excluded_paths, string.drop_start(_, 1))

  case excluded_paths, included_paths {
    [], [] -> fn(_) { True }
    [], _ -> fn(path) { list.any(included_paths, string.contains(path, _)) }
    _, [] -> fn(path) { !list.any(excluded_paths, string.contains(path, _)) }
    _, _ -> fn(path) {
      list.any(included_paths, string.contains(path, _))
      && !list.any(excluded_paths, string.contains(path, _))
    }
  }
}

/// Assembles a Writerly file or directory using the renderer's path selectors.
///
/// The returned feedback describes the assembled directory tree. It is printed
/// only when verbose renderer feedback is enabled.
pub fn default_writerly_assembler(
  dirpath_or_filepath: String,
  options: RendererOptions(_),
) -> Result(#(List(InputLine), Feedback), wl.AssemblyError) {
  let path_selector = path_selector_from_filters(options.only_paths)
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

/// Parses assembled Writerly lines into exactly one VXML root.
pub fn default_writerly_parser(
  lines: List(InputLine),
) -> Result(#(VXML, Feedback), #(Blame, String)) {
  wl.input_lines_to_vxml(lines)
  |> result.map(fn(vxml) { #(vxml, NoFeedback) })
  |> result.map_error(fn(e) { #(e.blame, ins(e)) })
}

/// Emits one VXML fragment as Writerly output lines without feedback.
///
/// Conversion fails when the VXML cannot be represented by Writerly's
/// serializer contract.
pub fn default_writerly_emitter(
  fragment: OutputFragment(z, VXML),
) -> Result(
  #(OutputFragment(z, List(OutputLine)), Feedback),
  wl.SerializationError,
) {
  use writerly <- result.try(wl.vxml_to_writerly(fragment.payload))
  use lines <- result.try(wl.writerly_to_output_lines(writerly))

  Ok(#(OutputFragment(..fragment, payload: lines), NoFeedback))
}
