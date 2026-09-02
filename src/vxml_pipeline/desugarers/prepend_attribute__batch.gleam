import gleam/list
import gleam/result
import on
import vxml.{type Attr, type VXML, Attr, V}
import vxml/blame as bl
import vxml_pipeline/authoring
import vxml_pipeline/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

pub const name = "prepend_attribute__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Prepends each configured attribute to every element of its
/// configured tag. Repeated target tags are allowed and receive
/// every associated attribute in list order.
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
      // Target tag.
      String,
      // Attribute key.
      String,
      // Attribute value.
      String,
    ),
  )

type InnerParam =
  List(#(String, Attr))

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  list.try_map(param, fn(item) {
    use <- on.false_true(core.valid_tag(item.0), fn() {
      Error(DesugaringError(
        bl.no_blame,
        "invalid target tag name '" <> item.0 <> "'",
      ))
    })
    use <- on.false_true(result.is_ok(vxml.validate_key(item.1)), fn() {
      Error(DesugaringError(
        bl.no_blame,
        "invalid attribute key '" <> item.1 <> "'",
      ))
    })
    Ok(#(item.0, Attr(authoring.blame(name, 61), item.1, item.2)))
  })
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  n2t.one_to_one_no_error_nodemap_2_desugarer_transform(nodemap)
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    V(_, tag, attrs, _) -> {
      let new_attrs =
        inner
        |> list.filter(fn(pair) { pair.0 == tag })
        |> list.map(fn(pair) { pair.1 })

      case new_attrs {
        [] -> vxml
        _ -> V(..vxml, attrs: list.append(new_attrs, attrs))
      }
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
      param: [
        #("section", "first", "one"),
        #("aside", "kind", "note"),
        #("section", "second", "two"),
      ],
      source: "
                  <> root
                    <> section
                      old=three
                      <> section
                    <> aside
                ",
      expected: "
                  <> root
                    <> section
                      first=one
                      second=two
                      old=three
                      <> section
                        first=one
                        second=two
                    <> aside
                      kind=note
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
