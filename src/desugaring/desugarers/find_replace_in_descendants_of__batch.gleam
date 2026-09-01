import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type VXML, T, V}

pub const name = "find_replace_in_descendants_of__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Applies configured literal replacements within text nodes
/// descended from their corresponding ancestor tags.
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
      // Ancestor tag.
      String,
      // Literal replacement pairs.
      List(#(String, String)),
    ),
  )

type InnerParam =
  Param

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.FancyOneToOneNoErrorNodemap = fn(
    vxml,
    ancestors,
    previous,
    next,
    processed,
  ) {
    nodemap(vxml, ancestors, previous, next, processed, inner)
  }
  n2t.fancy_one_to_one_no_error_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(
  vxml: VXML,
  ancestors: List(VXML),
  _: List(VXML),
  _: List(VXML),
  _: List(VXML),
  inner: InnerParam,
) -> VXML {
  case vxml {
    V(_, _, _, _) -> vxml
    T(_, _) -> {
      list.fold(inner, vxml, fn(v, tuple) -> VXML {
        let #(ancestor, list_pairs) = tuple
        case list.any(ancestors, fn(a) { core.v_get_tag(a) == ancestor }) {
          False -> v
          True -> core.t_find_replace__batch(vxml, list_pairs)
        }
      })
    }
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: [#("ancestor", [#("_FROM_", "_TO_")])],
      source: "
                <> root
                  <> B
                    <>
                      'hello _FROM_'
                      '_FROM__FROM_'
                  <> ancestor
                    <> B
                      <>
                        'hello _FROM_'
                        '_FROM__FROM_'
                ",
      expected: "
                <> root
                  <> B
                    <>
                      'hello _FROM_'
                      '_FROM__FROM_'
                  <> ancestor
                    <> B
                      <>
                        'hello _TO_'
                        '_TO__TO_'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
