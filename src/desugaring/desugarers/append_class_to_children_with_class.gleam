import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/dict.{type Dict}
import gleam/list
import vxml.{type VXML, T, V}

pub const name = "append_class_to_children_with_class"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Appends configured classes to children that already have
/// the corresponding classes.
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
      // Pairs of existing class and class to append.
      List(#(String, String)),
    ),
  )

type InnerParam =
  Dict(String, List(#(String, String)))

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  core.dict_from_list(param)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap(_, inner)
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(vxml: VXML, inner: InnerParam) -> Result(VXML, DesugaringError) {
  case vxml {
    T(_, _) -> Ok(vxml)
    V(_, tag, _, children) -> {
      case dict.get(inner, tag) {
        Error(Nil) -> Ok(vxml)
        Ok(targets_and_classes_to_append) -> {
          Ok(
            V(
              ..vxml,
              children: core.v_map(children, update_child(
                _,
                targets_and_classes_to_append,
              )),
            ),
          )
        }
      }
    }
  }
}

fn update_child(
  node: VXML,
  targets_and_classes_to_append: List(#(String, String)),
) -> VXML {
  list.fold(
    targets_and_classes_to_append,
    node,
    fn(acc, target_and_classes_to_append) {
      core.v_append_classes_if(
        acc,
        target_and_classes_to_append.1,
        core.is_v_and_has_class(_, target_and_classes_to_append.0),
      )
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: [#("Chapter", [#("well", "out")])],
      source: "
                <> root
                  <> Chapter
                    <> div
                      class=well
                    <> div
                      class=other
                    <> p
                      class=well
                  <> Section
                    <> div
                      class=well
                ",
      expected: "
                <> root
                  <> Chapter
                    <> div
                      class=well out
                    <> div
                      class=other
                    <> p
                      class=well out
                  <> Section
                    <> div
                      class=well
                ",
    ),
    testing.data(
      param: [#("container", [#("highlight", "active")])],
      source: "
                <> root
                  <> container
                    <> span
                      class=highlight
                    <> span
                      class=highlight bold
                    <> div
                      class=normal
                ",
      expected: "
                <> root
                  <> container
                    <> span
                      class=highlight active
                    <> span
                      class=highlight bold active
                    <> div
                      class=normal
                ",
    ),
    testing.data(
      param: [
        #("parent", [#("target", "new")]),
        #("other", [#("different", "added")]),
      ],
      source: "
                <> root
                  <> parent
                    <> child
                      class=target
                  <> other
                    <> child
                      class=different
                ",
      expected: "
                <> root
                  <> parent
                    <> child
                      class=target new
                  <> other
                    <> child
                      class=different added
                ",
    ),
    testing.data(
      param: [#("Chapter", [#("well", "out"), #("highlight", "active")])],
      source: "
                <> root
                  <> Chapter
                    <> div
                      class=well highlight
                    <> div
                      class=important
                    <> div
                      class=other
                ",
      expected: "
                <> root
                  <> Chapter
                    <> div
                      class=well highlight out active
                    <> div
                      class=important
                    <> div
                      class=other
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
