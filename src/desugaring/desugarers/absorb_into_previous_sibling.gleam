import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type VXML, T, V}

pub const name = "absorb_into_previous_sibling"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Moves each uninterrupted run of elements of the
/// specified tags into the end of its preceding element
/// when that element's tag is not specified.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  List(String)

type InnerParam =
  Param

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(_, _, _, [first, second, ..rest]) ->
      V(..vxml, children: update_children([], first, [second, ..rest], inner))
    _ -> vxml
  }
}

fn update_children(
  already_processed: List(VXML),
  previous_sibling: VXML,
  remaining: List(VXML),
  inner: InnerParam,
) -> List(VXML) {
  case remaining {
    [] -> [previous_sibling, ..already_processed] |> list.reverse
    [T(_, _) as first, ..rest] ->
      update_children(
        [previous_sibling, ..already_processed],
        first,
        rest,
        inner,
      )
    [V(_, tag, _, _) as first, ..rest] ->
      case previous_sibling {
        T(_, _) ->
          update_children(
            [previous_sibling, ..already_processed],
            first,
            rest,
            inner,
          )
        V(_, prev_tag, _, _) ->
          case
            list.contains(inner, tag) && !{ list.contains(inner, prev_tag) }
          {
            False ->
              update_children(
                [previous_sibling, ..already_processed],
                first,
                rest,
                inner,
              )
            True ->
              update_children(
                already_processed,
                V(
                  ..previous_sibling,
                  children: list.append(previous_sibling.children, [first]),
                ),
                rest,
                inner,
              )
          }
      }
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: ["A", "B"],
      source: "
                <> Root
                  <> n1
                    <>
                      'text'
                  <> A
                  <> A
                  <> B
                  <> A
                  <> last
                ",
      expected: "
                <> Root
                  <> n1
                    <>
                      'text'
                    <> A
                    <> A
                    <> B
                    <> A
                  <> last
                ",
    ),
    testing.data(
      param: ["A", "B"],
      source: "
                <> Root
                  <> n1
                    <>
                      'text'
                  <> A
                  <> B
                  <> last
                  <> B
                  <> A
                ",
      expected: "
                <> Root
                  <> n1
                    <>
                      'text'
                    <> A
                    <> B
                  <> last
                    <> B
                    <> A
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
