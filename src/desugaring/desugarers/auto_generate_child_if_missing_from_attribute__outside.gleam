import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue, GoBack,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/string
import on
import vxml.{type VXML, Line, T, V}
import vxml/blame as bl

pub const name = "auto_generate_child_if_missing_from_attribute__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Prepends a child populated from an attribute outside
/// forbidden subtrees when a matching parent has the
/// attribute but no child of the requested tag.
pub fn constructor(param: Param, outside: List(String)) -> Desugarer {
  authoring.desugarer_with_outside(
    name: name,
    param: param,
    outside: outside,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  #(
    // Parent tag.
    String,
    // Generated child tag.
    String,
    // Source attribute key.
    String,
  )

type InnerParam {
  InnerParam(
    parent_tag: String,
    child_tag: String,
    attr_key: String,
    content_offset: Int,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(param.0, param.1, param.2, string.length(param.2) + 1))
}

fn inner_param_to_transform(
  inner: InnerParam,
  outside: List(String),
) -> DesugarerTransform {
  let nodemap: n2t.EarlyReturnOneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.early_return_one_to_one_no_error_nodemap_2_desugarer_transform_with_forbidden(
    outside,
  )
}

fn nodemap(vxml: VXML, inner: InnerParam) -> #(VXML, TrafficLight) {
  case vxml {
    V(_, tag, _, _) if tag == inner.parent_tag -> {
      // return early if we have a child of tag child_tag == inner.child_tag:
      use <- on.nonempty_empty(
        core.v_children_with_tag(vxml, inner.child_tag),
        fn(_, _) { #(vxml, GoBack) },
      )

      // return early if we don't have a attr_key == inner.attr_key:
      use attr, _ <- on.empty_nonempty(
        core.v_attrs_with_key(vxml, inner.attr_key),
        fn() { #(vxml, GoBack) },
      )

      let b = bl.advance(attr.blame, inner.content_offset)

      #(
        V(..vxml, children: [
          V(authoring.blame(name, 84), inner.child_tag, [], [
            T(b, [Line(b, attr.val)]),
          ]),
          ..vxml.children
        ]),
        GoBack,
      )
    }
    _ -> #(vxml, Continue)
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataWithOutside(Param)) {
  []
}

pub fn assertive_tests() {
  testing.collection_with_outside(name, assertive_tests_data(), constructor)
}
