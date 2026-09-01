import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/dict.{type Dict}
import gleam/list
import vxml.{type VXML, T, V}

pub const name = "append_class_to_child_if__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Appends configured classes to children of specified
/// parents when they satisfy the corresponding conditions.
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
      // Parent tag.
      String,
      // Class to append.
      String,
      // Condition applied to children.
      fn(VXML) -> Bool,
    ),
  )

type InnerParam =
  Dict(String, List(#(String, fn(VXML) -> Bool)))

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  param
  |> core.triples_to_aggregated_dict
  |> Ok
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    T(_, _) -> vxml
    V(_, tag, _, children) ->
      case dict.get(inner, tag) {
        Error(_) -> vxml
        Ok(classes_and_conditions) -> {
          V(
            ..vxml,
            children: core.v_map(children, update_child(
              _,
              classes_and_conditions,
            )),
          )
        }
      }
  }
}

fn update_child(
  node: VXML,
  classes_and_conditions: List(#(String, fn(VXML) -> Bool)),
) -> VXML {
  list.fold(classes_and_conditions, node, fn(acc, classes_and_condition) {
    core.v_append_classes_if(
      acc,
      classes_and_condition.0,
      classes_and_condition.1,
    )
  })
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: [#("Chapter", "main-column", core.is_v_and_tag_equals(_, "p"))],
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
      param: [#("container", "active", core.is_v_and_has_class(_, "highlight"))],
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
      param: [
        #("parent", "new", core.is_v_and_tag_equals(_, "child")),
        #("other", "different", core.is_v_and_has_class(_, "special")),
      ],
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
                      class=special different
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
