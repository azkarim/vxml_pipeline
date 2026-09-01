import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import on
import vxml.{type VXML, V}

pub const name = "auto_generate_child_if_missing_from_first_descendant_of_type"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Prepends a child copied from the first matching
/// descendant when a matching parent has no child of the
/// requested tag.
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
    // Parent tag.
    String,
    // Generated child tag.
    String,
    // Descendant tag whose first occurrence is copied.
    String,
  )

type InnerParam {
  InnerParam(parent_tag: String, child_tag: String, descendant_tag: String)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(param.0, param.1, param.2))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap(_, inner)
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(vxml: VXML, inner: InnerParam) -> Result(VXML, DesugaringError) {
  case vxml {
    V(_, tag, _, _) if tag == inner.parent_tag -> {
      // return early if we have a child of tag inner.child_tag:
      use <- on.nonempty_empty(
        core.v_children_with_tag(vxml, inner.child_tag),
        fn(_, _) { Ok(vxml) },
      )

      // return early if we don't have a descendant of tag inner.descendant_tag:
      use descendant, _ <- on.empty_nonempty(
        core.descendants_with_tag(vxml, inner.descendant_tag),
        fn() { Ok(vxml) },
      )

      let assert V(_, _, _, _) = descendant

      Ok(
        V(..vxml, children: [
          V(..descendant, tag: inner.child_tag),
          ..vxml.children
        ]),
      )
    }

    _ -> Ok(vxml)
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
