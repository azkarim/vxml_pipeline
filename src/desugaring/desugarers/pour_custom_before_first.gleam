import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import vxml.{type VXML, V}

pub const name = "pour_custom_before_first"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Reverse-inserts nodes before the first matching child, or
/// at the end when none matches.
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
    // Nodes to insert in reverse order.
    List(VXML),
    // Child tag before which to insert.
    String,
    // Whether to return early after insertion.
    TrafficLight,
  )

type InnerParam {
  InnerParam(
    parent_tag: String,
    nodes: List(VXML),
    before_tag: String,
    traffic_light: TrafficLight,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(param.0, param.1, param.2, param.3))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.EarlyReturnOneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.early_return_one_to_one_no_error_nodemap_2_desugarer_transform
}

fn nodemap(vxml: VXML, inner: InnerParam) -> #(VXML, TrafficLight) {
  case vxml {
    V(_, tag, _, children) if tag == inner.parent_tag -> {
      #(
        V(
          ..vxml,
          children: core.pour_before_first_in_list(
            children,
            inner.nodes,
            inner.before_tag,
          ),
        ),
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
  let first = V(authoring.blame(name, 71), "first", [], [])
  let second = V(authoring.blame(name, 72), "second", [], [])

  [
    testing.data(
      param: #("section", [first, second], "marker", Continue),
      source: "
                <> root
                  <> section
                    <> before
                    <> marker
                    <> after
                ",
      expected: "
                <> root
                  <> section
                    <> before
                    <> second
                    <> first
                    <> marker
                    <> after
                ",
    ),
    testing.data(
      param: #("section", [first, second], "marker", Continue),
      source: "
                <> root
                  <> section
                    <> only_child
                ",
      expected: "
                <> root
                  <> section
                    <> only_child
                    <> second
                    <> first
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
