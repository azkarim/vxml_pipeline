import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/dict.{type Dict}
import gleam/list
import vxml.{type Attr, type VXML, Attr, T, V}

pub const name = "append_attribute__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Appends every configured key-value attribute to elements
/// of its configured tag; a tag may occur repeatedly and
/// receives all associated attributes.
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
      // Tag whose elements receive the attribute.
      String,
      // Attribute key.
      String,
      // Attribute value.
      String,
    ),
  )

type InnerParam =
  Dict(String, List(Attr))

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  param
  |> list.map(fn(t) { #(t.0, Attr(authoring.blame(name, 46), t.1, t.2)) })
  |> core.aggregate_on_first
  |> Ok
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  n2t.one_to_one_no_error_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    T(_, _) -> vxml
    V(blame, tag, attrs, children) -> {
      case dict.get(inner, tag) {
        Ok(new_attrs) -> {
          V(blame, tag, list.flatten([attrs, new_attrs]), children)
        }
        Error(Nil) -> vxml
      }
    }
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
