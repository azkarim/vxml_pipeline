import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import vxml.{type VXML, T, V}

pub const name = "add_between_tag_and_text_node"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Inserts an empty element of the specified tag between
/// each target element and an immediately following text
/// node.
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
    // Tag of the element immediately before the text node.
    String,
    // Tag of the element inserted between them.
    String,
  )

type InnerParam {
  InnerParam(target_tag: String, inserted_vxml: VXML)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(target_tag, inserted_tag) = param
  InnerParam(target_tag, V(authoring.blame(name, 40), inserted_tag, [], []))
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
    [V(_, tag, _, _) as first, T(..) as second, ..rest]
      if tag == inner.target_tag
    -> [first, inner.inserted_vxml, second, ..add_in_list(rest, inner)]
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
