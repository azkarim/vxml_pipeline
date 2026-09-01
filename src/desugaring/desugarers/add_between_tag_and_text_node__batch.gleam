import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/dict.{type Dict}
import gleam/list
import vxml.{type VXML, T, V}

pub const name = "add_between_tag_and_text_node__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Inserts each configured element, with its attributes,
/// between an element of the configured tag and an
/// immediately following text node.
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
      // Tag before which the new element is inserted.
      String,
      // Tag of the new element.
      String,
      // Attributes of the new element.
      List(#(String, String)),
    ),
  )

type InnerParam =
  Dict(String, VXML)

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  param
  |> list.map(fn(p) {
    #(p.0, core.v_attrs_constructor(authoring.blame(name, 46), p.1, p.2))
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

fn add_in_list(children: List(VXML), inner: InnerParam) -> List(VXML) {
  case children {
    [V(_, first_tag, _, _) as first, T(_, _) as second, ..rest] -> {
      case dict.get(inner, first_tag) {
        Error(Nil) -> [first, ..add_in_list([second, ..rest], inner)]
        Ok(v) -> [first, v, second, ..add_in_list(rest, inner)]
      }
    }
    [first, ..rest] -> [first, ..add_in_list(rest, inner)]
    [] -> []
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
