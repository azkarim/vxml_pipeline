import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/string
import vxml.{type Line, type VXML, Line, T, V}

// word joiner character
const word_joiner = "&#8288;"

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.FancyOneToOneNoErrorNodemap = fn(
    vxml,
    _,
    previous,
    _,
    following,
  ) {
    nodemap(vxml, previous, following, inner)
  }
  nodemap
  |> n2t.fancy_one_to_one_no_error_nodemap_2_desugarer_transform
}

fn nodemap(
  vxml: VXML,
  prev_siblings: List(VXML),
  next_siblings: List(VXML),
  inner: InnerParam,
) -> VXML {
  case vxml {
    T(blame, lines) -> {
      let prev = list.first(prev_siblings)
      let next = list.first(next_siblings)

      let lines = case prev {
        Ok(V(_, tag, _, _)) ->
          case list.contains(inner, tag) {
            True -> edit_first_line(lines)
            False -> lines
          }
        _ -> lines
      }

      let lines = case next {
        Ok(V(_, tag, _, _)) ->
          case list.contains(inner, tag) {
            True -> edit_last_line(lines)
            False -> lines
          }
        _ -> lines
      }

      T(blame, lines)
    }
    _ -> vxml
  }
}

fn edit_first_line(lines: List(Line)) -> List(Line) {
  case lines {
    [] -> []
    [first, ..rest] -> {
      let content = first.content
      case content != "" && !string.starts_with(content, " ") {
        True -> [Line(..first, content: word_joiner <> content), ..rest]
        False -> [first, ..rest]
      }
    }
  }
}

fn edit_last_line(lines: List(Line)) -> List(Line) {
  case list.reverse(lines) {
    [] -> []
    [last, ..rest] -> {
      let content = last.content
      case content != "" && !string.ends_with(content, " ") {
        True -> [Line(..last, content: content <> word_joiner), ..rest]
        False -> [last, ..rest]
      }
    }
  }
  |> list.reverse
}

type Param =
  List(String)

type InnerParam =
  Param

pub const name = "insert_word_joiner_into_adjacent_text_nodes"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Inserts word-joiner characters into text adjacent to
/// configured elements when no separating whitespace exists.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: ["Math"],
      source: "
                <> div
                  <>
                    'a'
                  <> Math
                  <>
                    'b'
              ",
      expected: "
                <> div
                  <>
                    'a&#8288;'
                  <> Math
                  <>
                    '&#8288;b'
                ",
    ),
    testing.data(
      param: ["Math"],
      source: "
                <> div
                  <>
                    'a '
                  <> Math
                  <>
                    ' b'
              ",
      expected: "
                <> div
                  <>
                    'a '
                  <> Math
                  <>
                    ' b'
                ",
    ),
    testing.data(
      param: ["Math"],
      source: "
                <> div
                  <>
                    'a'
                    ''
                  <> Math
                  <>
                    ''
                    'b'
              ",
      expected: "
                <> div
                  <>
                    'a'
                    ''
                  <> Math
                  <>
                    ''
                    'b'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
