import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/dict.{type Dict}
import gleam/list
import gleam/option
import vxml.{type VXML, T, V}

pub const name = "surround_elements_by"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Places configured elements immediately before and after
/// matching elements.
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
    // Tags to surround.
    List(String),
    // Tag to insert before, or an empty string.
    String,
    // Tag to insert after, or an empty string.
    String,
  )

type InnerParam =
  Dict(String, #(String, String))

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let #(els, above, below) = param
  let inner_param =
    els
    |> list.map(fn(el) { #(el, #(above, below)) })
    |> dict.from_list
  Ok(inner_param)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.FancyOneToManyNodemap = fn(node, ancestors, _, _, _) {
    nodemap(node, ancestors, inner)
  }
  n2t.fancy_one_to_many_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(
  node: VXML,
  ancestors: List(VXML),
  inner: InnerParam,
) -> Result(List(VXML), DesugaringError) {
  case node {
    T(_, _) -> Ok([node])
    V(blame, tag, _, _) -> {
      case dict.get(inner, tag), ancestors {
        Error(Nil), _ -> Ok([node])
        _, [] -> Ok([node])
        Ok(#(above_tag, below_tag)), _ -> {
          let some_none_above = case above_tag {
            "" -> option.None
            _ ->
              option.Some(
                V(blame: blame, tag: above_tag, attrs: [], children: []),
              )
          }
          let some_none_below = case below_tag {
            "" -> option.None
            _ ->
              option.Some(
                V(blame: blame, tag: below_tag, attrs: [], children: []),
              )
          }
          case some_none_above, some_none_below {
            option.None, option.None -> Ok([node])
            option.None, option.Some(below) -> Ok([node, below])
            option.Some(above), option.None -> Ok([above, node])
            option.Some(above), option.Some(below) -> Ok([above, node, below])
          }
        }
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
