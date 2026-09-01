import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/dict.{type Dict}
import gleam/list
import vxml.{type VXML, V}

pub const name = "add_before_but_not_before_first_of_kind__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Inserts each configured element with attributes
/// immediately before every matching element after its
/// first occurrence among the same parent's children.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer_with_stringified_param(
    name: name,
    param: param,
    stringified_param: core.list_param_stringifier(param),
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  List(
    #(
      // Tag before whose elements insertion occurs after its first occurrence.
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
  |> list.map(fn(p) {
    #(p.0, core.v_attrs_constructor(authoring.blame(name, 47), p.1, p.2))
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
    V(_, _, _, children) ->
      V(..vxml, children: add_in_list([], children, inner))
    _ -> vxml
  }
}

fn add_in_list(
  previous_tags: List(String),
  upcoming: List(VXML),
  inner: InnerParam,
) -> List(VXML) {
  case upcoming {
    [] -> []
    [V(_, tag, _, _) as first, ..rest] -> {
      case dict.get(inner, tag) {
        Error(_) -> [first, ..add_in_list(previous_tags, rest, inner)]
        Ok(v) -> {
          case list.contains(previous_tags, tag) {
            False -> [first, ..add_in_list([tag, ..previous_tags], rest, inner)]
            True -> [v, first, ..add_in_list(previous_tags, rest, inner)]
          }
        }
      }
    }
    [first, ..rest] -> [first, ..add_in_list(previous_tags, rest, inner)]
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
