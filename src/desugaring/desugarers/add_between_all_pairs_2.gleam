import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type VXML, V}

pub const name = "add_between_all_pairs_2"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Inserts an empty element between adjacent element
/// siblings when the left tag is in the first list and the
/// right tag is in the second; for efficiency, use the
/// smaller tag list as the second list.
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
    // Tags eligible for the left sibling.
    List(String),
    // Tags eligible for the right sibling.
    List(String),
    // Tag of the element inserted between them.
    String,
  )

type InnerParam {
  InnerParam(
    left_tags: List(String),
    right_tags: List(String),
    inserted_vxml: VXML,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(left_tags, right_tags, inserted_tag) = param
  InnerParam(
    left_tags,
    right_tags,
    V(authoring.blame(name, 51), inserted_tag, [], []),
  )
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
    [V(_, first_tag, _, _) as first, V(_, second_tag, _, _) as second, ..rest] ->
      case
        list.contains(inner.right_tags, second_tag)
        && list.contains(inner.left_tags, first_tag)
      {
        True -> {
          [first, inner.inserted_vxml, ..add_in_list([second, ..rest], inner)]
        }
        False -> [first, ..add_in_list([second, ..rest], inner)]
      }
    [first, ..rest] -> [first, ..add_in_list(rest, inner)]
    _ -> children
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #(["a", "b", "c"], ["D", "E"], "NEWGUY"),
      source: "
                <> root
                  <> D
                  <> a
                  <> b
                  <> D
                  <> E
                  <> a
                  <> c
                  <> c
                  <> D
      ",
      expected: "
                <> root
                  <> D
                  <> a
                  <> b
                  <> NEWGUY
                  <> D
                  <> E
                  <> a
                  <> c
                  <> c
                  <> NEWGUY
                  <> D
      ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
