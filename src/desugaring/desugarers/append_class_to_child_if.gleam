import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import vxml.{type VXML, V}

pub const name = "append_class_to_child_if"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Appends a class to children of a specified parent when
/// they satisfy the supplied condition.
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
    // Class appended to matching children.
    String,
    // Condition applied to children.
    fn(VXML) -> Bool,
  )

type InnerParam {
  InnerParam(
    parent_tag: String,
    class_name: String,
    condition: fn(VXML) -> Bool,
  )
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(param.0, param.1, param.2))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(_, tag, _, children) if tag == inner.parent_tag ->
      V(
        ..vxml,
        children: core.v_map(children, core.v_append_classes_if(
          _,
          inner.class_name,
          inner.condition,
        )),
      )
    _ -> vxml
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #("Chapter", "main-column", core.is_v_and_tag_equals(_, "p")),
      source: "
                <> root
                  <> Chapter
                    <> p
                      class=existing
                    <> div
                      class=other
                    <> p
                      class=another
                  <> Section
                    <> p
                      class=should-not-change
                ",
      expected: "
                <> root
                  <> Chapter
                    <> p
                      class=existing main-column
                    <> div
                      class=other
                    <> p
                      class=another main-column
                  <> Section
                    <> p
                      class=should-not-change
                ",
    ),
    testing.data(
      param: #("container", "active", core.is_v_and_has_class(_, "highlight")),
      source: "
                <> root
                  <> container
                    <> span
                      class=highlight
                    <> span
                      class=normal
                    <> div
                      class=highlight bold
                ",
      expected: "
                <> root
                  <> container
                    <> span
                      class=highlight active
                    <> span
                      class=normal
                    <> div
                      class=highlight bold active
                ",
    ),
    testing.data(
      param: #("parent", "new", core.is_v_and_tag_equals(_, "child")),
      source: "
                <> root
                  <> parent
                    <> child
                      class=original
                    <> other
                      class=base
                  <> other
                    <> child
                      class=special
                ",
      expected: "
                <> root
                  <> parent
                    <> child
                      class=original new
                    <> other
                      class=base
                  <> other
                    <> child
                      class=special
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
