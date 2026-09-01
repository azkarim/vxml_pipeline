import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue, DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import vxml.{type VXML, T, V}
import vxml/blame as bl

pub const name = "wrap_children_custom"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Wraps all children of configured parents in a supplied
/// childless VXML wrapper.
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
    // Childless VXML wrapper.
    VXML,
    // Traversal behavior after wrapping.
    TrafficLight,
  )

type InnerParam =
  Param

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  case param.1 {
    V(_, _, _, []) -> Ok(param)
    V(..) ->
      Error(DesugaringError(bl.no_blame, "given wrapper already has children"))
    T(..) -> Error(DesugaringError(bl.no_blame, "expecting V-node as wrapper"))
  }
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.EarlyReturnOneToOneNoErrorNodemap = fn(vxml) {
    nodemap(vxml, inner)
  }
  nodemap
  |> n2t.early_return_one_to_one_no_error_nodemap_2_desugarer_transform
}

fn nodemap(vxml: VXML, inner: InnerParam) -> #(VXML, TrafficLight) {
  case vxml {
    V(_, tag, _, children) if tag == inner.0 -> {
      let wrapper = inner.1
      let assert V(..) = wrapper
      #(V(..vxml, children: [V(..wrapper, children: children)]), inner.2)
    }
    _ -> #(vxml, Continue)
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
