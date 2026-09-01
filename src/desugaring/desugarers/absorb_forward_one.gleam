import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type VXML, T, V}

pub const name = "absorb_forward_one"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Moves each element of the absorbed tag into the end of
/// the immediately preceding element of the absorber tag.
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
    // Tag whose element absorbs an adjacent sibling.
    String,
    // Tag absorbed from immediately after the absorbing element.
    String,
  )

type InnerParam {
  InnerParam(absorber_tag: String, absorbed_tag: String)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(absorber_tag, absorbed_tag) = param
  Ok(InnerParam(absorber_tag, absorbed_tag))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(_, _, _, children) ->
      V(..vxml, children: update_children(children, inner))
    _ -> vxml
  }
}

fn update_children(children: List(VXML), inner: InnerParam) -> List(VXML) {
  case children {
    [] -> []
    [one] -> [one]
    [T(..) as first, ..rest] -> [first, ..update_children(rest, inner)]
    [V(..) as first, ..rest] if first.tag != inner.absorber_tag -> [
      first,
      ..update_children(rest, inner)
    ]
    [V(..) as first, T(..) as second, ..rest] -> [
      first,
      second,
      ..update_children(rest, inner)
    ]
    [V(..) as first, V(..) as second, ..rest]
      if second.tag != inner.absorbed_tag
    -> [first, ..update_children([second, ..rest], inner)]
    [V(..) as first, V(..) as second, ..rest] -> {
      assert first.tag == inner.absorber_tag
      assert second.tag == inner.absorbed_tag
      [
        V(..first, children: list.append(first.children, [second])),
        ..update_children(rest, inner)
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
      param: #("A", "B"),
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
      param: #("A", "B"),
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
    testing.data(
      param: #("A", "B"),
      source: "
                <> Root
                  <> n1
                    <>
                      'text'
                  <> A
                  <> B
                  <> B
                  <> A
                  <> last
                  <> B
                  <> B
                  <> B
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
                  <> B
                  <> A
                  <> last
                  <> B
                  <> B
                  <> B
                  <> B
                  <> A
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
