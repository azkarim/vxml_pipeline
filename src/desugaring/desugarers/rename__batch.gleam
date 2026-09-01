import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/dict.{type Dict}
import gleam/list
import on
import vxml.{V}
import vxml/blame as bl

pub const name = "rename__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Renames multiple element tags and rejects duplicate
/// source tags or invalid target tags.
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
      // Existing tag.
      String,
      // New tag.
      String,
    ),
  )

type InnerParam =
  Dict(String, String)

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  use _ <- on.ok(
    list.try_map(param, fn(pair) {
      case core.valid_tag(pair.1) {
        True -> Ok(Nil)
        False ->
          Error(DesugaringError(
            bl.no_blame,
            "invalid target tag name '" <> pair.1 <> "'",
          ))
      }
    }),
  )
  core.dict_from_list(param)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = fn(vxml) {
    case vxml {
      V(_, tag, _, _) ->
        case dict.get(inner, tag) {
          Error(_) -> vxml
          Ok(new_tag) -> V(..vxml, tag: new_tag)
        }
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
      param: [#("OldA", "NewA"), #("OldB", "NewB")],
      source: "
                <> root
                  <> OldA
                    <> OldB
                  <> Unchanged
                ",
      expected: "
                <> root
                  <> NewA
                    <> NewB
                  <> Unchanged
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
