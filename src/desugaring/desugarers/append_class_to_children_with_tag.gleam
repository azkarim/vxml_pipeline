import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/dict.{type Dict}
import gleam/list
import vxml.{type VXML, T, V}

pub const name = "append_class_to_children_with_tag"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Appends configured classes to children with the
/// corresponding tags.
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
      // Pairs of child tag and class to append.
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
        Ok(tags_and_classes_to_append) -> {
          Ok(
            V(
              ..vxml,
              children: core.v_map(children, update_child(
                _,
                tags_and_classes_to_append,
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
  tags_and_classes_to_append: List(#(String, String)),
) -> VXML {
  list.fold(
    tags_and_classes_to_append,
    node,
    fn(acc, tag_and_classes_to_append) {
      core.v_append_classes_if(
        acc,
        tag_and_classes_to_append.1,
        core.is_v_and_tag_equals(_, tag_and_classes_to_append.0),
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
      param: [#("Chapter", [#("p", "main-column")])],
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
      param: [#("container", [#("span", "highlight"), #("div", "block")])],
      source: "
                <> root
                  <> container
                    <> span
                      class=text
                    <> div
                      class=content
                    <> p
                      class=unchanged
                ",
      expected: "
                <> root
                  <> container
                    <> span
                      class=text highlight
                    <> div
                      class=content block
                    <> p
                      class=unchanged
                ",
    ),
    testing.data(
      param: [
        #("parent", [#("child", "new")]),
        #("other", [#("child", "different")]),
      ],
      source: "
                <> root
                  <> parent
                    <> child
                      class=original
                  <> other
                    <> child
                      class=base
                  <> parent
                    <> child
                ",
      expected: "
                <> root
                  <> parent
                    <> child
                      class=original new
                  <> other
                    <> child
                      class=base different
                  <> parent
                    <> child
                      class=new
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
