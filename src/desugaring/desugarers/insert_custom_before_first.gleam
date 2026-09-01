import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import vxml.{type VXML, V}

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
    V(_, tag, _, children) if tag == inner.target_tag -> {
      #(
        V(
          ..vxml,
          children: core.insert_child_before_first_in_list(
            children,
            inner.child,
            inner.before_tag,
          ),
        ),
        inner.traffic_light,
      )
    }
    _ -> #(vxml, Continue)
  }
}

type Param =
  #(
    // Target element name.
    String,
    // VXML child to insert.
    VXML,
    // Element before which to insert, or append if absent.
    String,
    // Whether traversal returns early after insertion.
    TrafficLight,
  )

type InnerParam {
  InnerParam(
    target_tag: String,
    child: VXML,
    before_tag: String,
    traffic_light: TrafficLight,
  )
}

pub const name = "insert_custom_before_first"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// For a given tag, adds a custom child to all nodes
/// of that tag at the first position right before
/// tags of another given string, or else as the last
/// child if no such other tag is found.
///
/// Early-returns after operating on a node depending
/// on the value of the last argument.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
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
