import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import vxml.{V}
import vxml/blame as bl

pub const name = "rename_and_delete_children_if_has_singleton_class_attribute"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Renames matching elements and removes their class
/// attribute and children.
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
    // Existing tag.
    String,
    // Required singleton class.
    String,
    // New tag.
    String,
  )

type InnerParam =
  Param

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  case core.valid_tag(param.2) {
    True -> Ok(param)
    False ->
      Error(DesugaringError(
        bl.no_blame,
        "invalid target tag name '" <> param.2 <> "'",
      ))
  }
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = fn(vxml) {
    case vxml {
      V(_, tag, [singleton], _)
        if tag == inner.0 && singleton.key == "class" && singleton.val == inner.1
      -> V(..vxml, tag: inner.2, attrs: [], children: [])
      _ -> vxml
    }
  }
  n2t.one_to_one_no_error_nodemap_2_desugarer_transform(nodemap)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: #("Old", "discard", "New"),
      source: "
                <> root
                  <> Old
                    class=discard
                    <> Child
                  <> Old
                    class=keep
                    <> Child
                  <> Old
                    class=discard
                    extra=value
                    <> Child
                ",
      expected: "
                <> root
                  <> New
                  <> Old
                    class=keep
                    <> Child
                  <> Old
                    class=discard
                    extra=value
                    <> Child
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
