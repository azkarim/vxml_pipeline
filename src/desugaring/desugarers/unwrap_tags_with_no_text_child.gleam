import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type VXML, T, V}

pub const name = "unwrap_tags_with_no_text_child"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Unwraps configured elements that have no direct text
/// children.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  // Tags to unwrap.
  List(String)

type InnerParam =
  Param

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToManyNoErrorNodemap = fn(vxml) { nodemap(vxml, inner) }
  n2t.one_to_many_no_error_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(vxml: VXML, inner: InnerParam) -> List(VXML) {
  case vxml {
    V(_, tag, _, children) -> {
      case list.contains(inner, tag), list.any(children, is_text) {
        True, False -> children
        _, _ -> [vxml]
      }
    }
    _ -> [vxml]
  }
}

fn is_text(vxml: VXML) {
  case vxml {
    T(..) -> True
    _ -> False
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: ["Wrapper"],
      source: "
                <> root
                  <> Wrapper
                    <> Child
                      <>
                        'nested text'
                ",
      expected: "
                <> root
                  <> Child
                    <>
                      'nested text'
                ",
    ),
    testing.data(
      param: ["Wrapper"],
      source: "
                <> root
                  <> Wrapper
                    <>
                      'direct text'
                    <> Child
                ",
      expected: "
                <> root
                  <> Wrapper
                    <>
                      'direct text'
                    <> Child
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
