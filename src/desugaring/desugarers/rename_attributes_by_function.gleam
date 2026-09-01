import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type Attr, type VXML, Attr, T, V}

pub const name = "rename_attributes_by_function"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Renames every attribute key using a supplied function.
pub fn constructor(param: Param) -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(param),
  )
}

type Param =
  fn(String) -> String

type InnerParam =
  Param

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap(_, inner)
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(vxml: VXML, inner: InnerParam) -> Result(VXML, DesugaringError) {
  case vxml {
    T(_, _) -> Ok(vxml)
    V(_, _, attrs, _) -> {
      Ok(V(..vxml, attrs: list.map(attrs, rename_attr_key(_, inner))))
    }
  }
}

fn rename_attr_key(attr: Attr, transform_fn: fn(String) -> String) -> Attr {
  Attr(..attr, key: transform_fn(attr.key))
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: core.kebab_case_to_camel_case,
      source: "
                <> div
                  data-test=value1
                  my-attr=value2
                  another-long-name=value3
                ",
      expected: "
                <> div
                  dataTest=value1
                  myAttr=value2
                  anotherLongName=value3
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
