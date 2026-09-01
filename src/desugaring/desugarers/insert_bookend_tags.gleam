import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/pair
import vxml.{type VXML, T, V}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  param
  |> core.triples_to_pairs
  |> Ok
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap(_, inner)
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(vxml: VXML, inner: InnerParam) -> Result(VXML, DesugaringError) {
  case vxml {
    V(blame, tag, attrs, children) -> {
      case list.find(inner, fn(pair) { pair |> pair.first == tag }) {
        Error(Nil) -> Ok(vxml)
        Ok(#(_, #(start_tag, end_tag))) -> {
          Ok(V(
            blame,
            tag,
            attrs,
            [
              [V(blame, start_tag, [], [])],
              children,
              [V(blame, end_tag, [], [])],
            ]
              |> list.flatten,
          ))
        }
      }
    }
    T(_, _) -> Ok(vxml)
  }
}

type Param =
  List(
    #(
      // Target element name.
      String,
      // Element name inserted at the start.
      String,
      // Element name inserted at the end.
      String,
    ),
  )

type InnerParam =
  List(#(String, #(String, String)))

pub const name = "insert_bookend_tags"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Inserts configured empty elements at the beginning and
/// end of each matching element.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
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
