import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/string
import vxml.{type VXML, Line, T, V}

pub const name = "prepend_text_node_if_fancy"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Prepends a text node when a contextual condition is
/// satisfied.
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
    // Target tag.
    String,
    // Text to prepend.
    String,
    // Contextual condition.
    core.ContextualVXMLCondition,
  )

type InnerParam =
  #(String, VXML, core.ContextualVXMLCondition)

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let blame = desugarer_blame(41)
  #(
    param.0,
    T(
      blame,
      param.1
        |> string.split("\n")
        |> list.map(Line(blame, _)),
    ),
    param.2,
  )
  |> Ok
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.FancyOneToOneNoErrorNodemap = fn(
    vxml,
    ancestors,
    previous_siblings_before_mapping,
    previous_siblings_after_mapping,
    following_siblings_before_mapping,
  ) {
    nodemap(
      vxml,
      ancestors,
      previous_siblings_before_mapping,
      previous_siblings_after_mapping,
      following_siblings_before_mapping,
      inner,
    )
  }
  nodemap
  |> n2t.fancy_one_to_one_no_error_nodemap_2_desugarer_transform
}

fn nodemap(
  vxml: VXML,
  ancestors: List(VXML),
  previous_siblings_before_mapping: List(VXML),
  previous_siblings_after_mapping: List(VXML),
  following_siblings_before_mapping: List(VXML),
  inner: InnerParam,
) -> VXML {
  case vxml {
    V(_, tag, _, children) if tag == inner.0 ->
      case
        inner.2(
          vxml,
          ancestors,
          previous_siblings_before_mapping,
          previous_siblings_after_mapping,
          following_siblings_before_mapping,
        )
      {
        True -> V(..vxml, children: [inner.1, ..children])
        False -> vxml
      }
    _ -> vxml
  }
}

fn desugarer_blame(line_no: Int) {
  authoring.blame(name, line_no)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
