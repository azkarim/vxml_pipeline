import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue, GoBack,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/option
import vxml.{type Attr, type VXML, V}

pub const name = "cut_paste_attribute_from_self_to_child__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Moves the first matching parent attribute onto every
/// matching child outside forbidden subtrees.
pub fn constructor(param: Param, outside: List(String)) -> Desugarer {
  authoring.desugarer_with_outside(
    name: name,
    param: param,
    outside: outside,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  #(
    // Parent tag.
    String,
    // Child tag.
    String,
    // Attribute key to move.
    String,
  )

type InnerParam {
  InnerParam(parent_tag: String, child_tag: String, key: String)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(param.0, param.1, param.2))
}

fn inner_param_to_transform(
  inner: InnerParam,
  outside: List(String),
) -> DesugarerTransform {
  let nodemap: n2t.EarlyReturnOneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.early_return_one_to_one_no_error_nodemap_2_desugarer_transform_with_forbidden(
    outside,
  )
}

fn nodemap(vxml: VXML, inner: InnerParam) -> #(VXML, TrafficLight) {
  case vxml {
    V(_, tag, _, _) if tag == inner.parent_tag -> {
      case core.v_first_attr_with_key(vxml, inner.key) {
        option.None -> #(vxml, GoBack)
        option.Some(attr) -> #(
          V(
            ..vxml,
            attrs: vxml.attrs |> list.filter(fn(x) { x.key != inner.key }),
            children: vxml.children
              |> list.map(update_child(_, inner.child_tag, attr)),
          ),
          GoBack,
        )
      }
    }
    _ -> #(vxml, Continue)
  }
}

fn update_child(child: VXML, child_tag: String, attr: Attr) -> VXML {
  case child {
    V(_, tag, _, _) if tag == child_tag ->
      V(..child, attrs: list.append(child.attrs, [attr]))
    _ -> child
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataWithOutside(Param)) {
  []
}

pub fn assertive_tests() {
  testing.collection_with_outside(name, assertive_tests_data(), constructor)
}
