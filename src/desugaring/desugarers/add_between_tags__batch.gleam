import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/dict.{type Dict}
import gleam/list
import gleam/pair
import vxml.{type VXML, Attr, V}

pub const name = "add_between_tags__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Inserts configured elements, with their attributes,
/// between adjacent element siblings whose tags match a
/// configured pair.
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
      // Tags of the adjacent siblings.
      #(String, String),
      // Tag of the element inserted between them.
      String,
      // Attributes of the inserted element.
      List(#(String, String)),
    ),
  )

type InnerParam =
  Dict(#(String, String), #(String, List(#(String, String))))

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  core.triples_to_dict(param)
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

fn add_in_list(children: List(VXML), inner: InnerParam) -> List(VXML) {
  case children {
    [V(_, first_tag, _, _) as first, V(_, second_tag, _, _) as second, ..rest] -> {
      case dict.get(inner, #(first_tag, second_tag)) {
        Error(Nil) -> [first, ..add_in_list([second, ..rest], inner)]
        Ok(#(new_element_tag, new_element_attrs)) -> {
          let blame = first.blame
          [
            first,
            V(
              blame,
              new_element_tag,
              list.map(new_element_attrs, fn(pair) {
                Attr(blame, pair |> pair.first, pair |> pair.second)
              }),
              [],
            ),
            ..add_in_list([second, ..rest], inner)
          ]
        }
      }
    }
    _ -> children
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
