import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type Line, type VXML, Line, T, V}

pub const name = "insert_on_own_line_start_end"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Inserts configured text on its own boundary lines,
/// reusing existing empty boundary lines when available.
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
    // Target element name.
    String,
    #(
      // Line content inserted at the start.
      String,
      // Line content inserted at the end.
      String,
    ),
  )

type InnerParam =
  #(String, Line, Line)

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(#(
    param.0,
    Line(desugarer_blame(44), param.1.0),
    Line(desugarer_blame(45), param.1.1),
  ))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  n2t.one_to_one_no_error_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(_, tag, _, _) if tag == inner.0 ->
      vxml
      |> insert_at_start(inner.1)
      |> insert_at_end(inner.2)
    _ -> vxml
  }
}

fn insert_at_start(vxml: VXML, line: Line) -> VXML {
  let assert V(blame, _, _, children) = vxml
  let children = case children {
    [T(t_blame, [first, ..rest]), ..other_children] if first.content == "" -> [
      T(t_blame, [line, ..rest]),
      ..other_children
    ]
    [T(..) as first, ..rest] -> [core.t_start_insert_line(first, line), ..rest]
    _ -> [T(blame, [line]), ..children]
  }
  V(..vxml, children: children)
}

fn insert_at_end(vxml: VXML, line: Line) -> VXML {
  let assert V(blame, _, _, children) = vxml
  let reversed_children = children |> list.reverse
  let reversed_children = case reversed_children {
    [T(t_blame, lines), ..other_children] ->
      case lines |> list.reverse {
        [last, ..rest] if last.content == "" -> [
          T(t_blame, [line, ..rest] |> list.reverse),
          ..other_children
        ]
        _ -> [core.t_end_insert_line(T(t_blame, lines), line), ..other_children]
      }
    _ -> [T(blame, [line]), ..reversed_children]
  }
  V(..vxml, children: reversed_children |> list.reverse)
}

fn desugarer_blame(line_no: Int) {
  authoring.blame(name, line_no)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #("MathBlock", #("\\[", "\\]")),
      source: "
                <> root
                  <> MathBlock
                    <>
                      'x + y'
                ",
      expected: "
                <> root
                  <> MathBlock
                    <>
                      '\\['
                      'x + y'
                      '\\]'
                ",
    ),
    testing.data(
      param: #("MathBlock", #("\\[", "\\]")),
      source: "
                <> root
                  <> MathBlock
                    <>
                      ''
                      'x + y'
                      ''
                ",
      expected: "
                <> root
                  <> MathBlock
                    <>
                      '\\['
                      'x + y'
                      '\\]'
                ",
    ),
    testing.data(
      param: #("MathBlock", #("\\[", "\\]")),
      source: "
                <> root
                  <> MathBlock
                    <>
                      ''
                ",
      expected: "
                <> root
                  <> MathBlock
                    <>
                      '\\['
                      '\\]'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
