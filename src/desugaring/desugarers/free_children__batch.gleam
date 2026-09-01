import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import either_or as eo
import gleam/list
import vxml.{type VXML, T, V}

pub const name = "free_children__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️🏖️

/// Frees configured children from configured parents while
/// retaining intervening groups inside copies of each parent.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name:,
    param:,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  List(
    #(
      // Tag of a child to free from its parent.
      String,
      // Tag of the parent from which to free the child.
      String,
    ),
  )

type InnerParam =
  Param

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToManyNoErrorNodemap = nodemap(_, inner)
  n2t.one_to_many_no_error_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(vxml: VXML, inner: InnerParam) -> List(VXML) {
  case vxml {
    V(blame, tag, attrs, children) ->
      children
      |> eo.discriminate(child_must_escape(_, tag, inner))
      |> eo.group_ors
      |> eo.map_resolve(fn(x) { x }, fn(xs) { V(blame, tag, attrs, xs) })
    _ -> [vxml]
  }
}

fn child_must_escape(child: VXML, parent: String, inner: InnerParam) -> Bool {
  case child {
    T(_, _) -> False
    V(_, child, _, _) -> list.contains(inner, #(child, parent))
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
