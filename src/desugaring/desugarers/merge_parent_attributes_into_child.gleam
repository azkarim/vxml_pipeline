import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import vxml.{type Attr, type VXML, T, V}

pub const name = "merge_parent_attributes_into_child"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Merges parent attributes into children for configured
/// parent-child tag pairs.
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
      // Parent tag.
      String,
      // Child tag.
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
      case
        result.all(
          list.map(children, fn(child) {
            case child {
              T(_, _) -> Ok(child)
              V(child_blame, child_tag, child_attrs, grandchildren) -> {
                case list.contains(inner, #(tag, child_tag)) {
                  False -> Ok(child)
                  True -> {
                    case merge_attrs(attrs, child_attrs) {
                      Ok(child_attrs) ->
                        Ok(V(child_blame, child_tag, child_attrs, grandchildren))
                      Error(d) -> Error(d)
                    }
                  }
                }
              }
            }
          }),
        )
      {
        Ok(new_children) -> Ok(V(blame, tag, attrs, new_children))
        Error(e) -> Error(e)
      }
    }
  }
}

fn merge_attrs(
  from: List(Attr),
  onto: List(Attr),
) -> Result(List(Attr), DesugaringError) {
  list.try_fold(from, onto, merge_one_attr)
}

fn merge_one_attr(
  attrs: List(Attr),
  to_merge: Attr,
) -> Result(List(Attr), DesugaringError) {
  case to_merge.key {
    "style" -> Ok(core.attrs_merge_styles(attrs, to_merge.blame, to_merge.val))
    "class" ->
      Ok(core.attrs_append_classes(attrs, to_merge.blame, to_merge.val))
    key ->
      case core.attrs_val_first_with_key(attrs, key) {
        Some(child_val) ->
          Error(DesugaringError(
            to_merge.blame,
            "attr of key '"
              <> key
              <> "' already exists in child (value '"
              <> to_merge.val
              <> "' in parent, '"
              <> child_val
              <> "' in child)",
          ))
        None -> Ok([to_merge, ..attrs])
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
