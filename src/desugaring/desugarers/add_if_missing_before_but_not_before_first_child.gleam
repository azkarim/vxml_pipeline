import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import vxml.{type VXML, V}

pub const name = "add_if_missing_before_but_not_before_first_child"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Inserts an element before each non-first matching child
/// unless the same inserted element is already immediately
/// before it.
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
    // Tag before which an element may be inserted.
    String,
    // Tag of the inserted element.
    String,
  )

type InnerParam {
  InnerParam(target_tag: String, inserted_vxml: VXML, inserted_tag: String)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  InnerParam(param.0, V(authoring.blame(name, 39), param.1, [], []), param.1)
  |> Ok
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(_, _, _, children) -> V(..vxml, children: add_in_list(children, inner))
    _ -> vxml
  }
}

fn add_in_list(vxmls: List(VXML), inner: InnerParam) -> List(VXML) {
  case vxmls {
    [first, V(_, tag, _, _) as second, ..rest] if tag == inner.target_tag -> {
      case first {
        V(_, t, _, _) if t == inner.inserted_tag -> [
          first,
          ..add_in_list([second, ..rest], inner)
        ]
        _ -> [
          first,
          inner.inserted_vxml,
          ..add_in_list([second, ..rest], inner)
        ]
      }
    }
    [first, second, ..rest] -> [first, ..add_in_list([second, ..rest], inner)]
    _ -> vxmls
  }
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
