import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/dict.{type Dict}
import gleam/list
import on
import vxml.{type VXML, T, V}

pub const name = "rename_if_child_of__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Applies multiple direct-child renaming rules.
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
      // Required parent tag.
      String,
    ),
  )

type InnerParam =
  Dict(String, Dict(String, String))

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  list.fold(
    param,
    dict.from_list([]),
    fn(
      acc: Dict(String, Dict(String, String)),
      incoming: #(String, String, String),
    ) {
      let #(old_name, new_name, parent_name) = incoming
      case dict.get(acc, parent_name) {
        Error(Nil) -> {
          dict.insert(acc, parent_name, dict.from_list([#(old_name, new_name)]))
        }
        Ok(existing_dict) -> {
          dict.insert(
            acc,
            parent_name,
            dict.insert(existing_dict, old_name, new_name),
          )
        }
      }
    },
  )
  |> Ok
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    T(_, _) -> vxml
    V(blame, tag, attrs, children) -> {
      use inner_dict <- on.error_ok(dict.get(inner, tag), fn(_) { vxml })

      let new_children =
        list.map(children, fn(child) {
          use child_blame, child_tag, child_attrs, grandchildren <- core.on_t_on_v(
            child,
            fn(_, _) { child },
          )
          case dict.get(inner_dict, child_tag) {
            Error(Nil) -> child
            Ok(new_name) -> V(child_blame, new_name, child_attrs, grandchildren)
          }
        })

      V(blame, tag, attrs, new_children)
    }
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
