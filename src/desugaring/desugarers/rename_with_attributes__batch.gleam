import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/dict.{type Dict}
import gleam/list
import vxml.{type VXML, T, V}

pub const name = "rename_with_attributes__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Renames multiple element types and appends configured
/// attributes.
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
      // Existing tag.
      String,
      // New tag.
      String,
      // Attributes to append.
      List(#(String, String)),
    ),
  )

type InnerParam =
  Dict(String, #(String, List(vxml.Attr)))

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let inner_param =
    param
    |> list.map(fn(renaming: #(String, String, List(#(String, String)))) {
      let #(old_tag, new_tag, attrs) = renaming
      let attrs_converted =
        list.map(attrs, fn(attr) {
          let #(key, value) = attr
          vxml.Attr(desugarer_blame(50), key, value)
        })
      #(old_tag, #(new_tag, attrs_converted))
    })
    |> dict.from_list
  Ok(inner_param)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap(_, inner)
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(vxml: VXML, inner: InnerParam) -> Result(VXML, DesugaringError) {
  case vxml {
    T(_, _) -> Ok(vxml)
    V(blame, tag, attrs, children) -> {
      case dict.get(inner, tag) {
        Error(Nil) -> Ok(vxml)
        Ok(new_tag_info) -> {
          let #(new_tag, new_attrs) = new_tag_info
          let new_attrs = list.append(attrs, new_attrs)
          Ok(V(blame, new_tag, new_attrs, children))
        }
      }
    }
  }
}

fn desugarer_blame(line_no: Int) {
  authoring.blame(name, line_no)
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
