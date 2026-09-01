import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type VXML, Attr, V}

pub const name = "append_attribute_if_child_of"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Appends an attribute to matching children of a specified
/// parent without replacing an existing attribute of the
/// same key.
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
    // Child tag.
    String,
    // Parent tag.
    String,
    // Attribute key.
    String,
    // Attribute value.
    String,
  )

type InnerParam {
  InnerParam(child_tag: String, parent_tag: String, key: String, value: String)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(param.0, param.1, param.2, param.3))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(_, parent_tag, _, children) if parent_tag == inner.parent_tag -> {
      let children = list.map(children, child_mapper(_, inner))
      V(..vxml, children: children)
    }
    _ -> vxml
  }
}

fn child_mapper(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(_, child_tag, attrs, _) if child_tag == inner.child_tag -> {
      let old_keys = core.keys(attrs)
      let attrs = case list.contains(old_keys, inner.key) {
        True -> attrs
        False ->
          list.append(attrs, [
            Attr(authoring.blame(name, 71), inner.key, inner.value),
          ])
      }
      V(..vxml, attrs: attrs)
    }
    _ -> vxml
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #("B", "parent", "key1", "val1"),
      source: "
                <> root
                  <> B
                    <> parent
                  <> parent
                    <> B
                  <> parent
                    <> B
                      key1=val2
                ",
      expected: "
                <> root
                  <> B
                    <> parent
                  <> parent
                    <> B
                      key1=val1
                  <> parent
                    <> B
                      key1=val2
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
