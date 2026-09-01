import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/dict.{type Dict}
import gleam/list
import gleam/string
import vxml.{type VXML, Line, T, V}
import vxml/blame.{type Blame}

pub const name = "prepend_append_to_text_children_of"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Adds configured text before and after every text child
/// of matching elements.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  List(
    #(
      // Text to prepend.
      String,
      // Text to append.
      String,
      // Parent tag.
      String,
    ),
  )

type InnerParam =
  Dict(String, #(VXML, VXML))

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  param
  |> list.map(fn(tuple) {
    let #(t1, t2, tag) = tuple
    let contents1 = string.split(t1, "\n")
    let contents2 = string.split(t2, "\n")
    let v1 =
      T(
        desugarer_blame(52),
        list.map(contents1, fn(content) { Line(desugarer_blame(53), content) }),
      )
    let v2 =
      T(
        desugarer_blame(57),
        list.map(contents2, fn(content) { Line(desugarer_blame(58), content) }),
      )
    #(tag, #(v1, v2))
  })
  |> dict.from_list
  |> Ok
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap(_, inner)
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(vxml: VXML, inner: InnerParam) -> Result(VXML, DesugaringError) {
  case vxml {
    T(_, _) -> Ok(vxml)
    V(blame, tag, attrs, children) -> {
      case dict.get(inner, tag) {
        Error(Nil) -> Ok(vxml)
        Ok(#(v1, v2)) -> {
          let new_children =
            list.map(children, fn(child) {
              case child {
                V(_, _, _, _) -> child
                T(blame, _) -> {
                  substitute_blames_in(v1, blame)
                  |> last_line_concatenate_with_first_line(child)
                  |> last_line_concatenate_with_first_line(substitute_blames_in(
                    v2,
                    blame,
                  ))
                }
              }
            })
          Ok(V(blame, tag, attrs, new_children))
        }
      }
    }
  }
}

fn substitute_blames_in(vxml: VXML, new_blame: Blame) -> VXML {
  let assert T(_, lines) = vxml
  T(new_blame, list.map(lines, fn(line) { Line(new_blame, line.content) }))
}

fn last_line_concatenate_with_first_line(node1: VXML, node2: VXML) -> VXML {
  let assert T(blame1, lines1) = node1
  let assert T(_, lines2) = node2

  let assert [Line(blame_last, content_last), ..other_lines1] =
    lines1 |> list.reverse
  let assert [Line(_, content_first), ..other_lines2] = lines2

  T(
    blame1,
    list.flatten([
      other_lines1 |> list.reverse,
      [Line(blame_last, content_last <> content_first)],
      other_lines2,
    ]),
  )
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
      param: [#("before ", " after", "section")],
      source: "
                <> root
                  <> section
                    <>
                      'first line'
                      'last line'
                    <> child
                  <> aside
                    <>
                      'unchanged'
                ",
      expected: "
                <> root
                  <> section
                    <>
                      'before first line'
                      'last line after'
                    <> child
                  <> aside
                    <>
                      'unchanged'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
