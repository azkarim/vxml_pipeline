import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/int
import gleam/list
import vxml.{type Attr, type VXML, Attr, T, V}

pub const name = "convert_int_attributes_to_float"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Converts matching integer-valued attributes to float-
/// valued strings.
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
      // Element tag; an empty string matches every tag.
      String,
      // Attribute key; an empty string matches every key.
      String,
    ),
  )

type InnerParam =
  Param

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap(_, inner)
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(vxml: VXML, inner: InnerParam) -> Result(VXML, DesugaringError) {
  case vxml {
    T(_, _) -> Ok(vxml)
    V(blame, tag, attrs, children) -> {
      Ok(V(blame, tag, update_attrs(tag, attrs, inner), children))
    }
  }
}

fn update_attrs(
  tag: String,
  attrs: List(Attr),
  inner: InnerParam,
) -> List(Attr) {
  list.fold(
    over: inner,
    from: attrs,
    with: fn(current_attrs: List(Attr), tag_attr_name_pair: #(String, String)) -> List(
      Attr,
    ) {
      let #(tag_name, attr_name) = tag_attr_name_pair
      case tag_name == "" || tag_name == tag {
        False -> current_attrs
        True -> {
          list.map(current_attrs, fn(attr: Attr) -> Attr {
            let Attr(blame, key, value) = attr
            case attr_name == "" || attr_name == key {
              False -> attr
              True -> {
                case int.parse(value) {
                  Error(_) -> attr
                  Ok(z) -> Attr(blame, key, int.to_string(z) <> ".0")
                }
              }
            }
          })
        }
      }
    },
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: [#("point", "x")],
      source: "
                <> root
                  <> point
                    x=-3
                    y=4
                  <> other
                    x=5
      ",
      expected: "
                <> root
                  <> point
                    x=-3.0
                    y=4
                  <> other
                    x=5
      ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
