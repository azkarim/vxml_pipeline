import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import vxml.{type VXML, V}

pub const name = "add_before_but_not_before_first_of_kind"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Inserts an empty element of the specified tag
/// immediately before every target element after the first
/// target among the same parent's children.
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
    // Tag before whose elements insertion occurs after its first occurrence.
    String,
    // Tag of the inserted element.
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
    V(_, _, _, children) ->
      V(..vxml, children: add_in_list(False, children, inner))
    _ -> vxml
  }
}

fn add_in_list(
  seen_da_tag_yet: Bool,
  upcoming: List(VXML),
  inner: InnerParam,
) -> List(VXML) {
  case upcoming {
    [] -> []
    [V(_, tag, _, _) as first, ..rest] if tag == inner.target_tag -> {
      case seen_da_tag_yet {
        True -> [inner.inserted_vxml, first, ..add_in_list(True, rest, inner)]
        False -> [first, ..add_in_list(True, rest, inner)]
      }
    }
    [first, ..rest] -> [first, ..add_in_list(seen_da_tag_yet, rest, inner)]
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
