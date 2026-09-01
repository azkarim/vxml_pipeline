import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type VXML, V}

pub const name = "expel_initial_last_backward_forward"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Moves matching leading and trailing children before and
/// after each configured parent element.
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
    // Parent tag.
    String,
    // Tags moved from the leading edge to before the parent.
    List(String),
    // Tags moved from the trailing edge to after the parent.
    List(String),
  )

type InnerParam {
  InnerParam(parent: String, leading: List(String), trailing: List(String))
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(param.0, param.1, param.2))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToManyNoErrorNodemap = nodemap(_, inner)
  nodemap |> n2t.one_to_many_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML, inner: InnerParam) -> List(VXML) {
  case vxml {
    V(_, tag, _, children) if tag == inner.parent -> {
      let #(prefix, children) =
        core.prefix_partition(children, core.is_v_and_tag_is_one_of(
          _,
          inner.leading,
        ))
      let #(children, suffix) =
        core.suffix_partition(children, core.is_v_and_tag_is_one_of(
          _,
          inner.trailing,
        ))
      [prefix, [V(..vxml, children: children)], suffix] |> list.flatten
    }
    _ -> [vxml]
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #("A", ["B"], ["C"]),
      source: "
                <> Root
                  <> n1
                  <> A
                    <> B
                    <> B
                    <>
                      'text1'
                    <>
                      'text2'
                    <> C
                    <> C
                  <> A
                  <> B
                  <> A
                ",
      expected: "
                <> Root
                  <> n1
                  <> B
                  <> B
                  <> A
                    <>
                      'text1'
                    <>
                      'text2'
                  <> C
                  <> C
                  <> A
                  <> B
                  <> A
                ",
    ),
    testing.data(
      param: #("A", ["B", "C"], ["B", "C"]),
      source: "
                <> Root
                  <> A
                    <> B
                    <> B
                    <> C
                    <> C
                    <> mid
                    <> B
                    <> B
                    <> B
                    <> C
                ",
      expected: "
                <> Root
                  <> B
                  <> B
                  <> C
                  <> C
                  <> A
                    <> mid
                  <> B
                  <> B
                  <> B
                  <> C
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
