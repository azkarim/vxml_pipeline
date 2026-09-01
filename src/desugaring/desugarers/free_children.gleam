import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import either_or as eo
import vxml.{type VXML, V}

pub const name = "free_children"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️🏖️

/// Frees matching children from matching parents while
/// retaining intervening groups inside copies of the parent.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name:,
    param:,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  #(
    // Tag of the child to free from its parent.
    String,
    // Tag of the parent from which to free the child.
    String,
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
    V(blame, tag, attrs, children) if tag == inner.1 ->
      children
      |> eo.discriminate(core.is_v_and_tag_equals(_, inner.0))
      |> eo.group_ors
      |> eo.map_resolve(fn(x) { x }, fn(xs) { V(blame, tag, attrs, xs) })
    _ -> [vxml]
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
