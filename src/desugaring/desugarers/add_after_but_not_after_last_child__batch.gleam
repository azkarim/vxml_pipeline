import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/dict.{type Dict}
import gleam/list
import vxml.{type VXML, V}

pub const name = "add_after_but_not_after_last_child__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Inserts the configured element with attributes after
/// each matching element, except when the matching element
/// is its parent's last child.
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
      // Tag after whose elements insertion occurs, except at the last child.
      String,
      // Tag of the inserted element.
      String,
      // Attributes of the inserted element.
      List(#(String, String)),
    ),
  )

type InnerParam =
  Dict(String, VXML)

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  param
  |> list.map(fn(triple) {
    #(
      triple.0,
      core.v_attrs_constructor(authoring.blame(name, 48), triple.1, triple.2),
    )
  })
  |> core.dict_from_list
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
    [V(_, tag, _, _) as first, second, ..rest] -> {
      case dict.get(inner, tag) {
        Error(Nil) -> [first, ..add_in_list([second, ..rest], inner)]
        Ok(v) -> [first, v, ..add_in_list([second, ..rest], inner)]
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
