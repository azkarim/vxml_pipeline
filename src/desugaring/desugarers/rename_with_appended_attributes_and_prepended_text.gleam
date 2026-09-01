import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/dict.{type Dict}
import gleam/list
import vxml.{type VXML, Line, T, V}

pub const name = "rename_with_appended_attributes_and_prepended_text"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Renames configured elements, appends attributes, and
/// prepends a text child.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  List(
    #(
      // Existing tag.
      String,
      // New tag.
      String,
      // Text to prepend.
      String,
      // Attributes to append.
      List(#(String, String)),
    ),
  )

type InnerParam =
  Dict(String, #(String, String, List(vxml.Attr)))

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let inner_param =
    param
    |> list.map(
      fn(renaming: #(String, String, String, List(#(String, String)))) {
        let #(old_tag, new_tag, text, attrs) = renaming
        let attrs_converted =
          list.map(attrs, fn(attr) {
            let #(key, value) = attr
            vxml.Attr(desugarer_blame(53), key, value)
          })
        #(old_tag, #(new_tag, text, attrs_converted))
      },
    )
    |> dict.from_list
  Ok(inner_param)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap(_, inner)
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(vxml: VXML, inner: InnerParam) -> Result(VXML, DesugaringError) {
  case vxml {
    T(_, _) -> Ok(vxml)
    V(blame, tag, attrs, children) -> {
      case dict.get(inner, tag) {
        Error(Nil) -> Ok(vxml)
        Ok(#(new_tag, text, new_attrs)) -> {
          let text_node = T(blame, [Line(blame, text)])
          let attrs = list.append(attrs, new_attrs)
          Ok(V(blame, new_tag, attrs, [text_node, ..children]))
        }
      }
    }
  }
}

fn desugarer_blame(line_no: Int) {
  authoring.blame(name, line_no)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: [#("QED", "span", "\\(\\square\\)", [#("class", "qed")])],
      source: "
                <> root
                  <> QED
                ",
      expected: "
                <> root
                  <> span
                    class=qed
                    <>
                      '\\(\\square\\)'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
