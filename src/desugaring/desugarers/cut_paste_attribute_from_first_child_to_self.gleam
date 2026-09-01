import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/option.{type Option, None, Some}
import on
import vxml.{type Attr, type VXML, V}

/// return option of
/// - attr with key `key`
/// - modified children (with removed attr)
pub const name = "cut_paste_attribute_from_first_child_to_self"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Moves a matching attribute from the first child of a
/// matching parent onto the parent.
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
    // Attribute key moved from the first child.
    String,
  )

type InnerParam {
  InnerParam(parent_tag: String, key: String)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(param.0, param.1))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap(_, inner)
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(vxml: VXML, inner: InnerParam) -> Result(VXML, DesugaringError) {
  case vxml {
    V(_, tag, _, children) if tag == inner.parent_tag -> {
      case check_first_child(children, inner.key) {
        None -> Ok(vxml)
        Some(#(att, children)) ->
          Ok(
            V(..vxml, attrs: list.append(vxml.attrs, [att]), children: children),
          )
      }
    }
    _ -> Ok(vxml)
  }
}

fn check_first_child(
  children: List(VXML),
  key: String,
) -> Option(#(Attr, List(VXML))) {
  use first, rest <- on.eager_empty_nonempty(children, None)
  use _, _, _, _ <- core.on_t_on_v(first, fn(_, _) { None })
  let assert V(_, _, attrs, _) = first
  use attr <- on.error_ok(list.find(attrs, fn(att) { att.key == key }), fn(_) {
    None
  })
  let first = V(..first, attrs: list.filter(attrs, fn(att) { att.key != key }))
  Some(#(attr, [first, ..rest]))
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #("figure", "src"),
      source: "
                <> root
                  <> figure
                    class=wide
                    <> image
                      src=photo.png
                      alt=Photo
                    <> caption
      ",
      expected: "
                <> root
                  <> figure
                    class=wide
                    src=photo.png
                    <> image
                      alt=Photo
                    <> caption
      ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
