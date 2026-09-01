import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import either_or as eo
import gleam/list
import vxml.{type VXML, T, V}
import vxml/blame.{type Blame} as bl

fn param_to_inner_param(
  param: Param,
  outside: List(String),
) -> Result(InnerParam, DesugaringError) {
  case list.contains(outside, param.0) {
    True -> Ok(#(param.0, param.1, desugarer_blame(57)))
    False ->
      Error(DesugaringError(
        bl.no_blame,
        "the wrapper must be included either in the list of things not to be contained in in order to avoid infinite recursion",
      ))
  }
}

fn desugarer_blame(line_no: Int) {
  authoring.blame(name, line_no)
}

fn inner_param_to_transform(
  inner: InnerParam,
  outside: List(String),
) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform_with_forbidden_self_first(
    outside,
  )
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    T(_, _) -> vxml
    V(_, _, _, children) -> {
      let children =
        children
        |> eo.discriminate(is_forbidden(_, inner.1))
        |> eo.group_ors
        |> eo.map_resolve(fn(x) { x }, fn(consecutive_siblings) {
          V(
            inner.2,
            // Blame
            inner.0,
            // wrapper tag
            [],
            consecutive_siblings,
          )
        })
      V(..vxml, children: children)
    }
  }
}

type Param =
  #(
    // Wrapper element name.
    String,
    // Element names not to wrap.
    List(String),
  )

type InnerParam =
  #(String, List(String), Blame)

pub const name = "group_consecutive_children__outside"

fn is_forbidden(elem: VXML, forbidden: List(String)) {
  case elem {
    T(_, _) -> False
    V(_, tag, _, _) -> list.contains(forbidden, tag)
  }
}

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Wraps groups of consecutive allowed children, without
/// entering subtrees whose element names occur in `outside`.
pub fn constructor(param: Param, outside: List(String)) -> Desugarer {
  authoring.desugarer_with_outside(
    name: name,
    param: param,
    outside: outside,
    prepare: param_to_inner_param(_, outside),
    transform: inner_param_to_transform,
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataWithOutside(Param)) {
  [
    testing.data_with_outside(
      param: #("wrapper", ["A", "B"]),
      outside: ["B", "C", "wrapper"],
      source: "
                <> root
                  <> x
                  <> y
                  <> A
                  <> B
                    <> x
                    <> y
                  <> x
                  <> C
                    <> x
                    <> y
                ",
      expected: "
                <> root
                  <> wrapper
                    <> x
                    <> y
                  <> A
                  <> B
                    <> x
                    <> y
                  <> wrapper
                    <> x
                    <> C
                      <> x
                      <> y
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_with_outside(name, assertive_tests_data(), constructor)
}
