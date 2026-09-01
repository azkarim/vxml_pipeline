import desugaring/authoring
import desugaring/core.{type Desugarer, type DesugarerTransform}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/option
import vxml.{type Attr, type VXML, Attr, T, V}
import writerly

pub const name = "format_writerly_commented_attributes"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Normalizes Writerly commented-attribute values to place
/// one space after their leading `!!` marker.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(),
  )
}

fn inner_param_to_transform() -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap
  nodemap |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform
}

fn nodemap(vxml: VXML) -> VXML {
  case vxml {
    T(_, _) -> vxml
    V(_, _, attrs, _) -> V(..vxml, attrs: list.map(attrs, format_attr))
  }
}

fn format_attr(attr: Attr) -> Attr {
  case writerly.is_commented_attribute_key(attr.key) {
    True -> {
      let spaces = case attr.val {
        "" -> 0
        _ -> 1
      }
      let assert option.Some(key) = writerly.commented_attribute_key(spaces)
      Attr(..attr, key: key)
    }
    False -> attr
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataNoParam) {
  [
    testing.data_no_param(
      source: "
                <> root
                  WriterlyCommentedAttribute0Spaces=foo
                  WriterlyCommentedAttribute0Spaces=
                  WriterlyCommentedAttribute3Spaces=
                  WriterlyCommentedAttribute2=ordinary
                ",
      expected: "
                <> root
                  WriterlyCommentedAttribute1Spaces=foo
                  WriterlyCommentedAttribute0Spaces=
                  WriterlyCommentedAttribute0Spaces=
                  WriterlyCommentedAttribute2=ordinary
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_no_param(name, assertive_tests_data(), constructor)
}
