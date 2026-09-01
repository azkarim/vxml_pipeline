import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/string
import vxml.{type VXML, T, V}

pub const name = "check_proper_tokenization"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Validates internal token structure wherever an element
/// or one of its children has an href attribute.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(),
  )
}

fn inner_param_to_transform() -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(vxml: VXML) -> Result(VXML, DesugaringError) {
  case vxml {
    T(_, _) -> Ok(vxml)
    V(_, _, _, children) ->
      case has_href(vxml) || list.any(children, is_v_and_has_href) {
        False ->
          case list.any(children, is_v_and_has_tag_starting_with(_, "__")) {
            True ->
              Error(core.DesugaringError(vxml.blame, "found tokenization error"))
            False -> Ok(vxml)
          }
        True ->
          case remaining_properly_tokenized(False, children) {
            True -> Ok(vxml)
            False ->
              Error(core.DesugaringError(vxml.blame, "found tokenization error"))
          }
      }
  }
}

fn remaining_properly_tokenized(
  in_text_mode: Bool,
  remaining: List(VXML),
) -> Bool {
  case remaining {
    [] -> !in_text_mode
    [T(_, _), ..] -> False
    [V(_, "__StartTokenizedT", _, _), ..rest] ->
      case in_text_mode {
        True -> False
        False -> remaining_properly_tokenized(True, rest)
      }
    [V(_, "__EndTokenizedT", _, _), ..rest] ->
      case in_text_mode {
        False -> False
        True -> remaining_properly_tokenized(False, rest)
      }
    [_, ..rest] -> remaining_properly_tokenized(in_text_mode, rest)
  }
}

fn has_href(vxml: VXML) -> Bool {
  core.v_has_attr_with_key(vxml, "href")
}

fn is_v_and_has_href(vxml: VXML) -> Bool {
  core.is_v_and_has_attr_with_key(vxml, "href")
}

fn is_v_and_has_tag_starting_with(vxml: VXML, prefix: String) -> Bool {
  case vxml {
    T(_, _) -> False
    V(_, tag, _, _) -> string.starts_with(tag, prefix)
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataNoParam) {
  []
}

pub fn assertive_tests() {
  testing.collection_no_param(name, assertive_tests_data(), constructor)
}
