import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type LatexDelimiterPair, DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/string
import vxml.{type VXML, Line, T, V}

pub const name = "normalize_math_delimiters_inside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Normalizes math delimiters inside configured ancestor
/// elements.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  #(
    // Target tag.
    String,
    // Delimiter pair to normalize to.
    LatexDelimiterPair,
  )

type InnerParam {
  InnerParam(
    opening_delimiters: List(String),
    closing_delimiters: List(String),
    opening_replacement: String,
    closing_replacement: String,
    target_tag: String,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(left_target, right_target) =
    core.opening_and_closing_string_for_pair(param.1)
  let #(left_delims, right_delims) =
    core.latex_strippable_delimiter_pairs()
    |> list.map(core.opening_and_closing_string_for_pair)
    |> list.unzip
  let left_delims = list.filter(left_delims, fn(c) { c != left_target })
  let right_delims = list.filter(right_delims, fn(c) { c != right_target })
  Ok(InnerParam(
    left_delims,
    // inner.opening_delimiters
    right_delims,
    // inner.closing_delimiters
    left_target,
    // inner.opening_replacement
    right_target,
    // inner.closing_replacement
    param.0,
    // inner.target_tag
  ))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap(_, inner)
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(node: VXML, inner: InnerParam) -> Result(VXML, DesugaringError) {
  case node {
    V(_, tag, _, children) if tag == inner.target_tag ->
      case children {
        [T(_, _) as t] -> Ok(V(..node, children: [normalize_t(t, inner)]))
        _ ->
          Error(DesugaringError(
            node.blame,
            "expecting unique text child in target tag",
          ))
      }
    _ -> Ok(node)
  }
}

fn normalize_t(t: VXML, inner: InnerParam) -> VXML {
  let assert T(blame, lines) = t
  let lines = core.lines_trim_start(lines)
  let assert [first, ..rest] = lines
  let lines = [
    Line(
      ..first,
      content: inner.opening_replacement
        <> remove_first_prefix_found(first.content, inner.opening_delimiters),
    ),
    ..rest
  ]
  let lines = core.reversed_lines_trim_end(lines |> list.reverse)
  let assert [first, ..rest] = lines
  let lines = [
    Line(
      ..first,
      content: remove_first_suffix_found(
          first.content,
          inner.closing_delimiters,
        )
        <> inner.closing_replacement,
    ),
    ..rest
  ]
  let lines = lines |> list.reverse
  T(blame, lines)
}

fn remove_first_prefix_found(c: String, prefixes: List(String)) -> String {
  case prefixes {
    [] -> c
    [first, ..rest] ->
      case string.starts_with(c, first) {
        True -> string.drop_start(c, string.length(first))
        False -> remove_first_prefix_found(c, rest)
      }
  }
}

fn remove_first_suffix_found(c: String, suffixes: List(String)) -> String {
  case suffixes {
    [] -> c
    [first, ..rest] ->
      case string.ends_with(c, first) {
        True -> string.drop_end(c, string.length(first))
        False -> remove_first_suffix_found(c, rest)
      }
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #("MathBlock", core.DoubleDollar),
      source: "
                <> MathBlock
                  <>
                    'x'
                ",
      expected: "
                <> MathBlock
                  <>
                    '$$x$$'
                ",
    ),
    testing.data(
      param: #("MathBlock", core.DoubleDollar),
      source: "
                <> MathBlock
                  <>
                    '\\[x\\]'
                ",
      expected: "
                <> MathBlock
                  <>
                    '$$x$$'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
