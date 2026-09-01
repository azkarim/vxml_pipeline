import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import on
import vxml.{type VXML, V}

pub const name = "append"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Appends an element to every matching element, optionally
/// returning early from each matched subtree according to
/// the traffic-light argument.
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
    // Tag whose children receive the appended element.
    String,
    // Tag of the appended element.
    String,
    // Traversal behavior after appending.
    TrafficLight,
  )

type InnerParam {
  InnerParam(
    target_tag: String,
    appended_vxml: VXML,
    traffic_light: TrafficLight,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  use vxml <- on.ok(core.from_tag(authoring.blame(name, 48), param.1))
  Ok(InnerParam(param.0, vxml, param.2))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.EarlyReturnOneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.early_return_one_to_one_no_error_nodemap_2_desugarer_transform
}

fn nodemap(vxml: VXML, inner: InnerParam) -> #(VXML, TrafficLight) {
  case vxml {
    V(_, tag, _, children) if tag == inner.target_tag -> {
      #(
        V(..vxml, children: list.append(children, [inner.appended_vxml])),
        inner.traffic_light,
      )
    }
    _ -> #(vxml, Continue)
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #("section", "footer", Continue),
      source: "
                <> root
                  <> section
                    <> paragraph
                  <> aside
      ",
      expected: "
                <> root
                  <> section
                    <> paragraph
                    <> footer
                  <> aside
      ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
