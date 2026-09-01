import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import vxml.{type VXML, V}

pub const name = "add_between"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Inserts an empty element of the specified tag between
/// each adjacent pair whose first and second elements have
/// the configured tags.
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
    // Tag of the first adjacent sibling.
    String,
    // Tag of the second adjacent sibling.
    String,
    // Tag of the element inserted between them.
    String,
  )

type InnerParam {
  InnerParam(first_tag: String, second_tag: String, inserted_vxml: VXML)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(first_tag, second_tag, inserted_tag) = param
  InnerParam(
    first_tag,
    second_tag,
    V(authoring.blame(name, 45), inserted_tag, [], []),
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
    [V(_, first_tag, _, _) as first, V(_, second_tag, _, _) as second, ..rest]
      if first_tag == inner.first_tag && second_tag == inner.second_tag
    -> {
      [first, inner.inserted_vxml, ..add_in_list([second, ..rest], inner)]
    }
    [first, ..rest] -> [first, ..add_in_list(rest, inner)]
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
