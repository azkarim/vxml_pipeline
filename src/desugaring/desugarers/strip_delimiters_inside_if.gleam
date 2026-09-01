import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/string
import vxml.{type Line, type VXML, Line, T, V}

pub const name = "strip_delimiters_inside_if"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Removes configured LaTeX delimiters from matching target
/// elements that satisfy a condition.
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
    // Delimiters to remove.
    List(core.LatexDelimiterPair),
    // Condition on the target element.
    fn(VXML) -> Bool,
  )

type InnerParam {
  InnerParam(
    target_tag: String,
    opening_delimiters: List(String),
    closing_delimiters: List(String),
    condition: fn(VXML) -> Bool,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(opening, closing) = core.opening_and_closing_delimiter_strings(param.1)
  Ok(InnerParam(param.0, opening, closing, param.2))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap(_, inner)
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(node: VXML, inner: InnerParam) -> Result(VXML, DesugaringError) {
  case node {
    V(_, tag, _, children) if tag == inner.target_tag -> {
      case inner.condition(node) {
        False -> Ok(node)
        True ->
          case children {
            [T(_, _) as t] -> Ok(V(..node, children: [strip(t, inner)]))
            _ ->
              Error(DesugaringError(
                node.blame,
                "expecting unique text child in target tag",
              ))
          }
      }
    }
    _ -> Ok(node)
  }
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

fn strip(t: VXML, inner: InnerParam) -> VXML {
  let assert T(_, lines) = t
  let lines = strip_opening_delimiter(lines, inner.opening_delimiters)
  let lines =
    strip_closing_delimiter(lines |> list.reverse, inner.closing_delimiters)
  let lines = lines |> list.reverse
  T(..t, lines: lines)
}

fn strip_opening_delimiter(
  lines: List(Line),
  prefixes: List(String),
) -> List(Line) {
  case lines {
    [] -> []
    [first, ..rest] ->
      case string.trim_start(first.content) {
        "" -> [first, ..strip_opening_delimiter(rest, prefixes)]
        content -> [
          Line(..first, content: remove_first_prefix_found(content, prefixes)),
          ..rest
        ]
      }
  }
}

fn strip_closing_delimiter(
  reversed_lines: List(Line),
  suffixes: List(String),
) -> List(Line) {
  case reversed_lines {
    [] -> []
    [first, ..rest] ->
      case string.trim_end(first.content) {
        "" -> [first, ..strip_closing_delimiter(rest, suffixes)]
        content -> [
          Line(..first, content: remove_first_suffix_found(content, suffixes)),
          ..rest
        ]
      }
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #("Z", [core.DoubleDollar], core.descendant_text_contains(_, "x")),
      source: "
                <> root
                  <> Z
                    <>
                      ''
                      '  $$x$$  '
                      ''
                  <> W
                    <>
                      '$$x$$'
                  <> Z
                    <>
                      '$$w$$'
                ",
      expected: "
                <> root
                  <> Z
                    <>
                      ''
                      'x'
                      ''
                  <> W
                    <>
                      '$$x$$'
                  <> Z
                    <>
                      '$$w$$'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
