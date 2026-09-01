import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type VXML, V}

pub const name = "unwrap_tags_with_no_text_descendant"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Unwraps configured elements that have no text
/// descendants.
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
  let nodemap: n2t.OneToManyNodemap = fn(vxml) { nodemap(vxml, inner) }
  n2t.one_to_many_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(
  vxml: VXML,
  inner: InnerParam,
) -> Result(List(VXML), DesugaringError) {
  case vxml {
    V(_, tag, _, children) ->
      case
        list.contains(inner, tag),
        list.any(children, is_text_or_has_text_descendant)
      {
        True, False -> Ok(children)
        _, _ -> Ok([vxml])
      }
    _ -> Ok([vxml])
  }
}

fn is_text_or_has_text_descendant(vxml: VXML) {
  core.is_t(vxml) || has_text_descendant(vxml)
}

fn has_text_descendant(vxml: VXML) {
  let assert V(_, _, _, children) = vxml
  list.any(children, core.is_t) || list.any(children, has_text_descendant)
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
                  <> Wrapper
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
                    <> Child
                      <> Grandchild
                ",
      expected: "
                <> root
                  <> Child
                    <> Grandchild
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
