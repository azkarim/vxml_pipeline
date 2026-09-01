import desugaring/core.{
  type DesugarerTransform, type DesugaringError, type DesugaringWarning,
  type TrafficLight, Continue, DesugaringError, GoBack,
}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string.{inspect as ins}
import vxml.{type VXML, T, V}

import on
import vxml/blame as bl

pub fn add_no_warnings(vxml: VXML) {
  #(vxml, [])
}

pub type NodeToNode =
  fn(VXML) -> Result(VXML, DesugaringError)

pub type NodeToNodeWithWarnings =
  fn(VXML) -> Result(#(VXML, List(DesugaringWarning)), DesugaringError)

pub type NodeToNil =
  fn(VXML) -> Result(Nil, DesugaringError)

pub fn node_to_node_2_desugarer_transform_without_walking(
  node_to_node: NodeToNode,
) {
  fn(vxml) {
    node_to_node(vxml)
    |> result.map(add_no_warnings)
  }
}

pub fn node_to_node_with_warnings_2_desugarer_transform_without_walking(
  node_to_node: NodeToNodeWithWarnings,
) {
  node_to_node
}

pub fn node_to_nil_2_desugarer_transform_without_walking(
  node_to_nil: NodeToNil,
) {
  fn(vxml) {
    use _ <- on.ok(node_to_nil(vxml))
    Ok(#(vxml, []))
  }
}

pub fn identity_transform(vxml: VXML) {
  Ok(#(vxml, []))
}

pub fn enter_exit_identity(
  vxml: VXML,
  state: state,
) -> Result(#(VXML, state), DesugaringError) {
  Ok(#(vxml, state))
}

pub fn enter_exit_keep_latest_state(
  vxml: VXML,
  _original_state: state,
  latest_state: state,
) -> Result(#(VXML, state), DesugaringError) {
  Ok(#(vxml, latest_state))
}

fn bad_tag_guard(
  tags: List(String),
  on_all_ok: fn() -> DesugarerTransform,
) -> DesugarerTransform {
  case list.find(tags, core.invalid_tag) {
    Ok(bad_tag) -> fn(_vxml) {
      Error(DesugaringError(bl.no_blame, "invalid tag: \"" <> bad_tag <> "\""))
    }
    Error(Nil) -> on_all_ok()
  }
}

fn get_root(vxmls: List(VXML)) -> Result(VXML, DesugaringError) {
  case vxmls {
    [root] -> Ok(root)
    [] ->
      Error(DesugaringError(
        bl.no_blame,
        "found 0 top-level nodes after desugaring",
      ))
    [_, second, ..] ->
      Error(DesugaringError(
        second.blame,
        "found " <> ins(list.length(vxmls)) <> " > 1 top-level nodes",
      ))
  }
}

fn get_root_option(vxml: Option(VXML)) -> Result(VXML, DesugaringError) {
  case vxml {
    Some(root) -> Ok(root)
    None ->
      Error(DesugaringError(
        bl.no_blame,
        "found 'None' top-level node after desugaring",
      ))
  }
}

// Nodemap names use the following term order:
//
// EarlyReturn | ""
// Fancy | ""
// OneToOne | OneToMany | OneToOption
// EnterExitStateful | Stateful | ""
// WithChildStates | ""
// NoError | ""
// WithWarnings | ""
// Nodemap
//
// EarlyReturn nodemaps can skip descent into a subtree. Fancy nodemaps receive
// ancestor and sibling context. EnterExitStateful nodemaps have hooks before
// and after child traversal. WithChildStates means that the exit hook receives
// the state returned by each child rather than only the latest state.
//
// Stateful visitors, which gather state without returning VXML, form a separate
// family and do not use the Nodemap suffix.

// ************************************************************
// OneToOneNoErrorNodemap
// ************************************************************

pub type OneToOneNoErrorNodemap =
  fn(VXML) -> VXML

// *** without forbidden ***

pub fn one_to_one_no_error_nodemap_walk(
  node: VXML,
  nodemap: OneToOneNoErrorNodemap,
) -> VXML {
  case node {
    T(_, _) -> nodemap(node)
    V(_, _, _, children) ->
      nodemap(
        V(
          ..node,
          children: list.map(children, one_to_one_no_error_nodemap_walk(
            _,
            nodemap,
          )),
        ),
      )
  }
}

pub fn one_to_one_no_error_nodemap_2_desugarer_transform(
  nodemap: OneToOneNoErrorNodemap,
) -> DesugarerTransform {
  fn(vxml) {
    one_to_one_no_error_nodemap_walk(vxml, nodemap)
    |> add_no_warnings
    |> Ok
  }
}

// *** with forbidden ***

fn one_to_one_no_error_nodemap_walk_with_forbidden(
  node: VXML,
  nodemap: OneToOneNoErrorNodemap,
  forbidden: List(String),
) -> VXML {
  case node {
    T(_, _) -> nodemap(node)
    V(_, tag, _, children) -> {
      case list.contains(forbidden, tag) {
        True -> node
        False ->
          nodemap(
            V(
              ..node,
              children: list.map(
                children,
                one_to_one_no_error_nodemap_walk_with_forbidden(
                  _,
                  nodemap,
                  forbidden,
                ),
              ),
            ),
          )
      }
    }
  }
}

pub fn one_to_one_no_error_nodemap_2_desugarer_transform_with_forbidden(
  nodemap: OneToOneNoErrorNodemap,
  forbidden: List(String),
) -> DesugarerTransform {
  use <- bad_tag_guard(forbidden)

  fn(vxml) {
    one_to_one_no_error_nodemap_walk_with_forbidden(vxml, nodemap, forbidden)
    |> add_no_warnings
    |> Ok
  }
}

// *** with forbidden, self_first ***

fn one_to_one_no_error_nodemap_walk_with_forbidden_self_first(
  node: VXML,
  nodemap: OneToOneNoErrorNodemap,
  forbidden: List(String),
) -> VXML {
  case node {
    T(_, _) -> nodemap(node)
    V(_, tag, _, _) ->
      case list.contains(forbidden, tag) {
        True -> node
        False -> {
          let assert V(_, _, _, children) as node = nodemap(node)
          let children =
            list.map(
              children,
              one_to_one_no_error_nodemap_walk_with_forbidden_self_first(
                _,
                nodemap,
                forbidden,
              ),
            )
          V(..node, children: children)
        }
      }
  }
}

pub fn one_to_one_no_error_nodemap_2_desugarer_transform_with_forbidden_self_first(
  nodemap: OneToOneNoErrorNodemap,
  forbidden: List(String),
) -> DesugarerTransform {
  use <- bad_tag_guard(forbidden)

  fn(vxml) {
    one_to_one_no_error_nodemap_walk_with_forbidden_self_first(
      vxml,
      nodemap,
      forbidden,
    )
    |> add_no_warnings
    |> Ok
  }
}

// ************************************************************
// OneToOneNoErrorWithWarningsNodemap
// ************************************************************

pub type OneToOneNoErrorWithWarningsNodemap =
  fn(VXML) -> #(VXML, List(DesugaringWarning))

// *** without forbidden ***

pub fn one_to_one_no_error_with_warnings_nodemap_walk(
  node: VXML,
  nodemap: OneToOneNoErrorWithWarningsNodemap,
) -> #(VXML, List(DesugaringWarning)) {
  case node {
    T(_, _) -> nodemap(node)
    V(_, _, _, children) -> {
      let #(children_warnings, children) =
        list.map_fold(children, [], fn(acc, child) {
          let #(child, warnings) =
            one_to_one_no_error_with_warnings_nodemap_walk(child, nodemap)
          let acc = core.pour(warnings, acc)
          #(acc, child)
        })
      let #(us, our_warnings) = nodemap(V(..node, children: children))
      #(us, core.pour(our_warnings, children_warnings))
    }
  }
}

pub fn one_to_one_no_error_with_warnings_nodemap_2_desugarer_transform(
  nodemap: OneToOneNoErrorWithWarningsNodemap,
) -> DesugarerTransform {
  fn(vxml) {
    one_to_one_no_error_with_warnings_nodemap_walk(vxml, nodemap)
    |> Ok
  }
}

// ************************************************************
// OneToOneNodemap
// ************************************************************

pub type OneToOneNodemap =
  fn(VXML) -> Result(VXML, DesugaringError)

// *** without forbidden ***

fn one_to_one_nodemap_walk(
  node: VXML,
  nodemap: OneToOneNodemap,
) -> Result(VXML, DesugaringError) {
  case node {
    T(_, _) -> nodemap(node)
    V(_, _, _, children) -> {
      use children <- on.ok(
        children |> list.try_map(one_to_one_nodemap_walk(_, nodemap)),
      )

      nodemap(V(..node, children: children))
    }
  }
}

pub fn one_to_one_nodemap_2_desugarer_transform(
  nodemap: OneToOneNodemap,
) -> DesugarerTransform {
  fn(vxml) {
    one_to_one_nodemap_walk(vxml, nodemap)
    |> result.map(add_no_warnings)
  }
}

// *** with forbidden ***

fn one_to_one_nodemap_walk_with_forbidden(
  node: VXML,
  nodemap: OneToOneNodemap,
  forbidden: List(String),
) -> Result(VXML, DesugaringError) {
  case node {
    T(_, _) -> nodemap(node)
    V(_, tag, _, children) ->
      case list.contains(forbidden, tag) {
        True -> Ok(node)
        False -> {
          use children <- on.ok(
            children
            |> list.try_map(one_to_one_nodemap_walk_with_forbidden(
              _,
              nodemap,
              forbidden,
            )),
          )
          nodemap(V(..node, children: children))
        }
      }
  }
}

pub fn one_to_one_nodemap_2_desugarer_transform_with_forbidden(
  nodemap: OneToOneNodemap,
  forbidden: List(String),
) -> DesugarerTransform {
  use <- bad_tag_guard(forbidden)

  fn(vxml) {
    one_to_one_nodemap_walk_with_forbidden(vxml, nodemap, forbidden)
    |> result.map(add_no_warnings)
  }
}

// ************************************************************
// OneToManyNoErrorNodemap
// ************************************************************

pub type OneToManyNoErrorNodemap =
  fn(VXML) -> List(VXML)

// *** without forbidden ***

pub fn one_to_many_no_error_nodemap_walk(
  node: VXML,
  nodemap: OneToManyNoErrorNodemap,
) -> List(VXML) {
  case node {
    T(_, _) -> nodemap(node)
    V(_, _, _, children) -> {
      // option 1:
      // let children =
      //   children
      //   |> list.flat_map(one_to_many_no_error_nodemap_walk(_, nodemap))
      // option 2:
      // let children =
      //   children
      // option 3:
      let children =
        list.fold(children, [], fn(acc, child) {
          core.pour(one_to_many_no_error_nodemap_walk(child, nodemap), acc)
        })
        |> list.reverse
      nodemap(V(..node, children: children))
    }
  }
}

pub fn one_to_many_no_error_nodemap_2_desugarer_transform(
  nodemap: OneToManyNoErrorNodemap,
) -> DesugarerTransform {
  fn(vxml) {
    one_to_many_no_error_nodemap_walk(vxml, nodemap)
    |> get_root
    |> result.map(add_no_warnings)
  }
}

// *** with forbidden ***

fn one_to_many_no_error_nodemap_walk_with_forbidden(
  node: VXML,
  nodemap: OneToManyNoErrorNodemap,
  forbidden: List(String),
) -> List(VXML) {
  case node {
    T(_, _) -> nodemap(node)
    V(_, tag, _, children) ->
      case list.contains(forbidden, tag) {
        True -> [node]
        False -> {
          let children =
            children
            |> list.map(one_to_many_no_error_nodemap_walk_with_forbidden(
              _,
              nodemap,
              forbidden,
            ))
            |> list.flatten
          nodemap(V(..node, children: children))
        }
      }
  }
}

pub fn one_to_many_no_error_nodemap_2_desugarer_transform_with_forbidden(
  nodemap: OneToManyNoErrorNodemap,
  forbidden: List(String),
) -> DesugarerTransform {
  use <- bad_tag_guard(forbidden)

  fn(vxml) {
    one_to_many_no_error_nodemap_walk_with_forbidden(vxml, nodemap, forbidden)
    |> get_root
    |> result.map(add_no_warnings)
  }
}

// ************************************************************
// OneToManyNoErrorWithWarningsNodemap
// ************************************************************

pub type OneToManyNoErrorWithWarningsNodemap =
  fn(VXML) -> #(List(VXML), List(DesugaringWarning))

// *** without forbidden ***

pub fn one_to_many_no_error_with_warnings_nodemap_walk(
  node: VXML,
  nodemap: OneToManyNoErrorWithWarningsNodemap,
) -> #(List(VXML), List(DesugaringWarning)) {
  case node {
    T(_, _) -> nodemap(node)
    V(_, _, _, children) -> {
      let #(children, warnings) =
        list.fold(children, #([], []), fn(acc, child) {
          let #(replacement, warnings) =
            one_to_many_no_error_with_warnings_nodemap_walk(child, nodemap)
          #(core.pour(replacement, acc.0), core.pour(warnings, acc.1))
        })
      let #(replacement, warnings2) =
        nodemap(V(..node, children: children |> list.reverse))
      #(replacement, core.pour(warnings2, warnings) |> list.reverse)
    }
  }
}

pub fn one_to_many_no_error_with_warnings_nodemap_2_desugarer_transform(
  nodemap: OneToManyNoErrorWithWarningsNodemap,
) -> DesugarerTransform {
  fn(vxml) {
    let #(replacement, warnings) =
      one_to_many_no_error_with_warnings_nodemap_walk(vxml, nodemap)
    use root <- on.ok(get_root(replacement))
    Ok(#(root, warnings))
  }
}

// ************************************************************
// OneToManyNodemap
// ************************************************************

pub type OneToManyNodemap =
  fn(VXML) -> Result(List(VXML), DesugaringError)

// *** without forbidden ***

fn one_to_many_nodemap_walk(
  node: VXML,
  nodemap: OneToManyNodemap,
) -> Result(List(VXML), DesugaringError) {
  case node {
    T(_, _) -> nodemap(node)
    V(_, _, _, children) -> {
      use children <- on.ok(
        children
        |> list.try_map(one_to_many_nodemap_walk(_, nodemap))
        |> result.map(list.flatten),
      )
      nodemap(V(..node, children: children))
    }
  }
}

pub fn one_to_many_nodemap_2_desugarer_transform(
  nodemap: OneToManyNodemap,
) -> DesugarerTransform {
  fn(vxml) {
    one_to_many_nodemap_walk(vxml, nodemap)
    |> on.ok(get_root)
    |> result.map(add_no_warnings)
  }
}

// *** with forbidden ***

fn one_to_many_nodemap_walk_with_forbidden(
  node: VXML,
  nodemap: OneToManyNodemap,
  forbidden: List(String),
) -> Result(List(VXML), DesugaringError) {
  case node {
    T(_, _) -> nodemap(node)
    V(_, tag, _, children) ->
      case list.contains(forbidden, tag) {
        True -> Ok([node])
        False -> {
          use children <- on.ok(
            children
            |> list.try_map(one_to_many_nodemap_walk_with_forbidden(
              _,
              nodemap,
              forbidden,
            ))
            |> result.map(list.flatten),
          )
          nodemap(V(..node, children: children))
        }
      }
  }
}

pub fn one_to_many_nodemap_2_desugarer_transform_with_forbidden(
  nodemap: OneToManyNodemap,
  forbidden: List(String),
) -> DesugarerTransform {
  use <- bad_tag_guard(forbidden)

  fn(vxml) {
    one_to_many_nodemap_walk_with_forbidden(vxml, nodemap, forbidden)
    |> on.ok(get_root)
    |> result.map(add_no_warnings)
  }
}

// ************************************************************
// FancyOneToOneNoErrorNodemap
// ************************************************************

pub type FancyOneToOneNoErrorNodemap =
  fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML)) -> VXML

fn fancy_one_to_one_no_error_nodemap_walk(
  node: VXML,
  ancestors: List(VXML),
  previous_siblings_before_mapping: List(VXML),
  previous_siblings_after_mapping: List(VXML),
  following_siblings_before_mapping: List(VXML),
  nodemap: FancyOneToOneNoErrorNodemap,
) -> VXML {
  case node {
    T(_, _) ->
      nodemap(
        node,
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
      )
    V(blame, tag, attrs, children) -> {
      let children_ancestors = [node, ..ancestors]
      let children =
        list.fold(children, #([], [], list.drop(children, 1)), fn(acc, child) {
          let mapped_child =
            fancy_one_to_one_no_error_nodemap_walk(
              child,
              children_ancestors,
              acc.0,
              acc.1,
              acc.2,
              nodemap,
            )
          #([child, ..acc.0], [mapped_child, ..acc.1], list.drop(acc.2, 1))
        })
        |> fn(acc) { acc.1 |> list.reverse }
      nodemap(
        V(blame, tag, attrs, children),
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
      )
    }
  }
}

pub fn fancy_one_to_one_no_error_nodemap_2_desugarer_transform(
  nodemap: FancyOneToOneNoErrorNodemap,
) -> DesugarerTransform {
  fn(vxml) {
    fancy_one_to_one_no_error_nodemap_walk(vxml, [], [], [], [], nodemap)
    |> add_no_warnings
    |> Ok
  }
}

// ************************************************************
// FancyOneToOneNodemap
// ************************************************************

pub type FancyOneToOneNodemap =
  fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML)) ->
    Result(VXML, DesugaringError)

fn fancy_one_to_one_nodemap_walk(
  node: VXML,
  ancestors: List(VXML),
  previous_siblings_before_mapping: List(VXML),
  previous_siblings_after_mapping: List(VXML),
  following_siblings_before_mapping: List(VXML),
  nodemap: FancyOneToOneNodemap,
) -> Result(VXML, DesugaringError) {
  case node {
    T(_, _) ->
      nodemap(
        node,
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
      )
    V(blame, tag, attrs, children) -> {
      let children_ancestors = [node, ..ancestors]
      use children <- on.ok(
        list.try_fold(
          children,
          #([], [], list.drop(children, 1)),
          fn(acc, child) {
            case
              fancy_one_to_one_nodemap_walk(
                child,
                children_ancestors,
                acc.0,
                acc.1,
                acc.2,
                nodemap,
              )
            {
              Error(e) -> Error(e)
              Ok(mapped_child) -> {
                Ok(#(
                  [child, ..acc.0],
                  [mapped_child, ..acc.1],
                  list.drop(acc.2, 1),
                ))
              }
            }
          },
        )
        |> result.map(fn(acc) { acc.1 |> list.reverse }),
      )
      nodemap(
        V(blame, tag, attrs, children),
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
      )
    }
  }
}

pub fn fancy_one_to_one_nodemap_2_desugarer_transform(
  nodemap: FancyOneToOneNodemap,
) -> DesugarerTransform {
  fn(vxml) {
    fancy_one_to_one_nodemap_walk(vxml, [], [], [], [], nodemap)
    |> result.map(add_no_warnings)
  }
}

// *** with forbidden ***

fn fancy_one_to_one_nodemap_walk_with_forbidden(
  node: VXML,
  ancestors: List(VXML),
  previous_siblings_before_mapping: List(VXML),
  previous_siblings_after_mapping: List(VXML),
  following_siblings_before_mapping: List(VXML),
  nodemap: FancyOneToOneNodemap,
  forbidden: List(String),
) -> Result(VXML, DesugaringError) {
  case node {
    T(_, _) ->
      nodemap(
        node,
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
      )
    V(blame, tag, attrs, children) -> {
      use <- on.true_false(list.contains(forbidden, tag), fn() { Ok(node) })
      let children_ancestors = [node, ..ancestors]
      use children <- on.ok(
        list.try_fold(
          children,
          #([], [], list.drop(children, 1)),
          fn(acc, child) {
            case
              fancy_one_to_one_nodemap_walk_with_forbidden(
                child,
                children_ancestors,
                acc.0,
                acc.1,
                acc.2,
                nodemap,
                forbidden,
              )
            {
              Error(e) -> Error(e)
              Ok(mapped_child) -> {
                Ok(#(
                  [child, ..acc.0],
                  [mapped_child, ..acc.1],
                  list.drop(acc.2, 1),
                ))
              }
            }
          },
        )
        |> result.map(fn(acc) { acc.1 |> list.reverse }),
      )
      nodemap(
        V(blame, tag, attrs, children),
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
      )
    }
  }
}

pub fn fancy_one_to_one_nodemap_2_desugarer_transform_with_forbidden(
  nodemap: FancyOneToOneNodemap,
  forbidden: List(String),
) -> DesugarerTransform {
  fn(vxml) {
    fancy_one_to_one_nodemap_walk_with_forbidden(
      vxml,
      [],
      [],
      [],
      [],
      nodemap,
      forbidden,
    )
    |> result.map(add_no_warnings)
  }
}

// ************************************************************
// FancyOneToManyNoErrorNodemap
// ************************************************************

pub type FancyOneToManyNoErrorNodemap =
  fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML)) -> List(VXML)

fn fancy_one_to_many_no_error_nodemap_walk(
  node: VXML,
  ancestors: List(VXML),
  previous_siblings_before_mapping: List(VXML),
  previous_siblings_after_mapping: List(VXML),
  following_siblings_before_mapping: List(VXML),
  nodemap: FancyOneToManyNoErrorNodemap,
) -> List(VXML) {
  case node {
    T(_, _) ->
      nodemap(
        node,
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
      )
    V(_, _, _, children) -> {
      let children_ancestors = [node, ..ancestors]
      let children =
        list.fold(children, #([], [], list.drop(children, 1)), fn(acc, child) {
          let shat_children =
            fancy_one_to_many_no_error_nodemap_walk(
              child,
              children_ancestors,
              acc.0,
              acc.1,
              acc.2,
              nodemap,
            )
          #(
            [child, ..acc.0],
            core.pour(shat_children, acc.1),
            list.drop(acc.2, 1),
          )
        })
        |> fn(acc) { acc.1 |> list.reverse }
      nodemap(
        V(..node, children: children),
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
      )
    }
  }
}

pub fn fancy_one_to_many_no_error_nodemap_2_desugarer_transform(
  nodemap: FancyOneToManyNoErrorNodemap,
) -> DesugarerTransform {
  fn(root: VXML) {
    fancy_one_to_many_no_error_nodemap_walk(root, [], [], [], [], nodemap)
    |> get_root
    |> result.map(add_no_warnings)
  }
}

// ************************************************************
// FancyOneToManyNodemap
// ************************************************************

pub type FancyOneToManyNodemap =
  fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML)) ->
    Result(List(VXML), DesugaringError)

fn fancy_one_to_many_nodemap_walk(
  node: VXML,
  ancestors: List(VXML),
  previous_siblings_before_mapping: List(VXML),
  previous_siblings_after_mapping: List(VXML),
  following_siblings_before_mapping: List(VXML),
  nodemap: FancyOneToManyNodemap,
) -> Result(List(VXML), DesugaringError) {
  case node {
    T(_, _) ->
      nodemap(
        node,
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
      )
    V(_, _, _, children) -> {
      let children_ancestors = [node, ..ancestors]
      use children <- on.ok(
        list.try_fold(
          children,
          #([], [], list.drop(children, 1)),
          fn(acc, child) {
            case
              fancy_one_to_many_nodemap_walk(
                child,
                children_ancestors,
                acc.0,
                acc.1,
                acc.2,
                nodemap,
              )
            {
              Error(e) -> Error(e)
              Ok(shat_children) -> {
                Ok(#(
                  [child, ..acc.0],
                  core.pour(shat_children, acc.1),
                  list.drop(acc.2, 1),
                ))
              }
            }
          },
        )
        |> result.map(fn(acc) { acc.1 |> list.reverse }),
      )
      nodemap(
        V(..node, children: children),
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
      )
    }
  }
}

pub fn fancy_one_to_many_nodemap_2_desugarer_transform(
  nodemap: FancyOneToManyNodemap,
) -> DesugarerTransform {
  fn(root: VXML) {
    fancy_one_to_many_nodemap_walk(root, [], [], [], [], nodemap)
    |> on.ok(get_root)
    |> result.map(add_no_warnings)
  }
}

// ************************************************************
// OneToOneStatefulNodemap
// ************************************************************

pub type OneToOneStatefulNodemap(a) =
  fn(VXML, a) -> Result(#(VXML, a), DesugaringError)

fn one_to_one_stateful_nodemap_walk(
  state: a,
  node: VXML,
  nodemap: OneToOneStatefulNodemap(a),
) -> Result(#(VXML, a), DesugaringError) {
  case node {
    T(_, _) -> nodemap(node, state)
    V(_, _, _, children) -> {
      use #(children, state) <- on.ok(
        children
        |> core.try_map_fold(state, fn(acc, child) {
          one_to_one_stateful_nodemap_walk(acc, child, nodemap)
        }),
      )
      nodemap(V(..node, children: children), state)
    }
  }
}

pub fn one_to_one_stateful_nodemap_2_desugarer_transform(
  nodemap: OneToOneStatefulNodemap(a),
  initial_state: a,
) -> DesugarerTransform {
  fn(vxml) {
    case one_to_one_stateful_nodemap_walk(initial_state, vxml, nodemap) {
      Error(err) -> Error(err)
      Ok(#(new_vxml, _)) -> Ok(#(new_vxml, []))
    }
  }
}

// ************************************************************
// OneToOneEnterExitStatefulNoErrorNodemap
// ************************************************************

pub type OneToOneEnterExitStatefulNoErrorNodemap(a) {
  OneToOneEnterExitStatefulNoErrorNodemap(
    on_enter: fn(VXML, a) -> #(VXML, a),
    on_exit: fn(VXML, a, a) -> #(VXML, a),
    on_text: fn(VXML, a) -> #(VXML, a),
  )
}

fn one_to_one_enter_exit_stateful_no_error_nodemap_walk(
  original_state: a,
  node: VXML,
  nodemap: OneToOneEnterExitStatefulNoErrorNodemap(a),
) -> #(VXML, a) {
  case node {
    T(_, _) -> nodemap.on_text(node, original_state)
    V(_, _, _, _) -> {
      let assert #(V(_, _, _, children) as node, latest_state) =
        nodemap.on_enter(node, original_state)
      let #(latest_state, children) =
        list.map_fold(children, latest_state, fn(acc, child) {
          let #(vxml, state) =
            one_to_one_enter_exit_stateful_no_error_nodemap_walk(
              acc,
              child,
              nodemap,
            )
          #(state, vxml)
        })
      nodemap.on_exit(
        V(..node, children: children),
        original_state,
        latest_state,
      )
    }
  }
}

pub fn one_to_one_enter_exit_stateful_no_error_nodemap_2_desugarer_transform(
  nodemap: OneToOneEnterExitStatefulNoErrorNodemap(a),
  initial_state: a,
) -> DesugarerTransform {
  fn(vxml) {
    let #(vxml, _) =
      one_to_one_enter_exit_stateful_no_error_nodemap_walk(
        initial_state,
        vxml,
        nodemap,
      )
    Ok(#(vxml, []))
  }
}

// *** with forbidden ***

fn custom_map_folder(
  // (this function is to avoid some stupid '#(v, s) -> #(s, v)' inversion step
  // that would come with using the stdlib)
  remaining: List(a),
  state: b,
  map: fn(a, b) -> #(a, b),
  previous: List(a),
) -> #(List(a), b) {
  case remaining {
    [] -> #(previous |> list.reverse, state)
    [first, ..rest] -> {
      let #(first, state) = map(first, state)
      custom_map_folder(rest, state, map, [first, ..previous])
    }
  }
}

fn one_to_one_enter_exit_stateful_no_error_nodemap_walk_with_forbidden(
  original_state: a,
  node: VXML,
  nodemap: OneToOneEnterExitStatefulNoErrorNodemap(a),
  forbidden: List(String),
) -> #(VXML, a) {
  case node {
    T(_, _) -> nodemap.on_text(node, original_state)
    V(_, tag, _, _) -> {
      case list.contains(forbidden, tag) {
        True -> #(node, original_state)
        False -> {
          let assert #(V(_, _, _, children) as node, latest_state) =
            nodemap.on_enter(node, original_state)
          let #(children, latest_state) =
            custom_map_folder(
              children,
              latest_state,
              fn(child, state) {
                one_to_one_enter_exit_stateful_no_error_nodemap_walk_with_forbidden(
                  state,
                  child,
                  nodemap,
                  forbidden,
                )
              },
              [],
            )
          nodemap.on_exit(
            V(..node, children: children),
            original_state,
            latest_state,
          )
        }
      }
    }
  }
}

pub fn one_to_one_enter_exit_stateful_no_error_nodemap_2_desugarer_transform_with_forbidden(
  nodemap: OneToOneEnterExitStatefulNoErrorNodemap(a),
  initial_state: a,
  forbidden: List(String),
) -> DesugarerTransform {
  fn(vxml) {
    let #(vxml, _) =
      one_to_one_enter_exit_stateful_no_error_nodemap_walk_with_forbidden(
        initial_state,
        vxml,
        nodemap,
        forbidden,
      )
    Ok(#(vxml, []))
  }
}

// ************************************************************
// OneToOneEnterExitStatefulNodemap
// ************************************************************

pub type OneToOneEnterExitStatefulNodemap(a) {
  OneToOneEnterExitStatefulNodemap(
    on_enter: fn(VXML, a) -> Result(#(VXML, a), DesugaringError),
    on_exit: fn(VXML, a, a) -> Result(#(VXML, a), DesugaringError),
    on_text: fn(VXML, a) -> Result(#(VXML, a), DesugaringError),
  )
}

fn one_to_one_enter_exit_stateful_nodemap_walk(
  original_state: a,
  node: VXML,
  nodemap: OneToOneEnterExitStatefulNodemap(a),
) -> Result(#(VXML, a), DesugaringError) {
  case node {
    T(_, _) -> nodemap.on_text(node, original_state)
    V(_, _, _, _) -> {
      use #(node, latest_state) <- on.ok(nodemap.on_enter(node, original_state))
      let assert V(_, _, _, children) = node
      use #(children, latest_state) <- on.ok(
        core.try_map_fold(children, latest_state, fn(acc, child) {
          one_to_one_enter_exit_stateful_nodemap_walk(acc, child, nodemap)
        }),
      )
      nodemap.on_exit(
        node |> core.v_replace_children_with(children),
        original_state,
        latest_state,
      )
    }
  }
}

pub fn one_to_one_enter_exit_stateful_nodemap_2_desugarer_transform(
  nodemap: OneToOneEnterExitStatefulNodemap(a),
  initial_state: a,
) -> DesugarerTransform {
  fn(vxml) {
    use #(vxml, _) <- on.ok(one_to_one_enter_exit_stateful_nodemap_walk(
      initial_state,
      vxml,
      nodemap,
    ))
    Ok(#(vxml, []))
  }
}

// ************************************************************
// EarlyReturnOneToOneEnterExitStatefulNodemap
// ************************************************************

pub type EarlyReturnOneToOneEnterExitStatefulNodemap(a) {
  EarlyReturnOneToOneEnterExitStatefulNodemap(
    on_enter: fn(VXML, a) -> Result(#(VXML, a, TrafficLight), DesugaringError),
    on_exit: fn(VXML, a, a) -> Result(#(VXML, a), DesugaringError),
    on_text: fn(VXML, a) -> Result(#(VXML, a), DesugaringError),
  )
}

pub fn early_return_one_to_one_enter_exit_stateful_nodemap_walk(
  original_state: a,
  node: VXML,
  nodemap: EarlyReturnOneToOneEnterExitStatefulNodemap(a),
) -> Result(#(VXML, a), DesugaringError) {
  case node {
    T(_, _) -> nodemap.on_text(node, original_state)
    V(_, _, _, _) -> {
      use #(node, latest_state, traffic_light) <- on.ok(nodemap.on_enter(
        node,
        original_state,
      ))
      let assert V(_, _, _, children) = node
      use #(children, latest_state) <- on.ok(case traffic_light {
        GoBack -> Ok(#(children, latest_state))
        Continue -> {
          core.try_map_fold(children, latest_state, fn(acc, child) {
            early_return_one_to_one_enter_exit_stateful_nodemap_walk(
              acc,
              child,
              nodemap,
            )
          })
        }
      })
      nodemap.on_exit(
        node |> core.v_replace_children_with(children),
        original_state,
        latest_state,
      )
    }
  }
}

pub fn early_return_one_to_one_enter_exit_stateful_nodemap_2_desugarer_transform(
  nodemap: EarlyReturnOneToOneEnterExitStatefulNodemap(a),
  initial_state: a,
) -> DesugarerTransform {
  fn(vxml) {
    use #(vxml, _) <- on.ok(
      early_return_one_to_one_enter_exit_stateful_nodemap_walk(
        initial_state,
        vxml,
        nodemap,
      ),
    )
    Ok(#(vxml, []))
  }
}

// ************************************************************
// FancyOneToOneEnterExitStatefulNodemap(a)
// ************************************************************

pub type FancyOneToOneEnterExitStatefulNodemap(a) {
  FancyOneToOneEnterExitStatefulNodemap(
    on_enter: fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML), a) ->
      Result(#(VXML, a), DesugaringError),
    on_exit: fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML), a, a) ->
      Result(#(VXML, a), DesugaringError),
    on_text: fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML), a) ->
      Result(#(VXML, a), DesugaringError),
  )
}

fn fancy_one_to_one_enter_exit_stateful_nodemap_walk(
  original_state: a,
  node: VXML,
  ancestors: List(VXML),
  previous_siblings_before_mapping: List(VXML),
  previous_siblings_after_mapping: List(VXML),
  following_siblings_before_mapping: List(VXML),
  nodemap: FancyOneToOneEnterExitStatefulNodemap(a),
) -> Result(#(VXML, a), DesugaringError) {
  case node {
    T(_, _) ->
      nodemap.on_text(
        node,
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
        original_state,
      )
    V(_, _, _, _) -> {
      use #(node, latest_state) <- on.ok(nodemap.on_enter(
        node,
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
        original_state,
      ))
      let assert V(_, _, _, children) = node
      let children_ancestors = [node, ..ancestors]
      use #(children, latest_state) <- on.ok(
        list.try_fold(
          children,
          #([], [], list.drop(children, 1), latest_state),
          fn(acc, child) {
            use #(mapped_child, state) <- on.ok(
              fancy_one_to_one_enter_exit_stateful_nodemap_walk(
                acc.3,
                child,
                children_ancestors,
                acc.0,
                acc.1,
                acc.2,
                nodemap,
              ),
            )
            Ok(#(
              [child, ..acc.0],
              [mapped_child, ..acc.1],
              list.drop(acc.2, 1),
              state,
            ))
          },
        )
        |> result.map(fn(acc) { #(acc.1 |> list.reverse, acc.3) }),
      )
      let node = V(..node, children: children)
      nodemap.on_exit(
        node,
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
        original_state,
        latest_state,
      )
    }
  }
}

pub fn fancy_one_to_one_enter_exit_stateful_nodemap_2_desugarer_transform(
  nodemap: FancyOneToOneEnterExitStatefulNodemap(a),
  initial_state: a,
) -> DesugarerTransform {
  fn(vxml) {
    use #(vxml, _) <- on.ok(fancy_one_to_one_enter_exit_stateful_nodemap_walk(
      initial_state,
      vxml,
      [],
      [],
      [],
      [],
      nodemap,
    ))
    Ok(#(vxml, []))
  }
}

// ************************************************************
// FancyOneToOneEnterExitStatefulWithWarningsNodemap(a)
// ************************************************************

pub type FancyOneToOneEnterExitStatefulWithWarningsNodemap(a) {
  FancyOneToOneEnterExitStatefulWithWarningsNodemap(
    on_enter: fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML), a) ->
      Result(#(VXML, a, List(DesugaringWarning)), DesugaringError),
    on_exit: fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML), a, a) ->
      Result(#(VXML, a, List(DesugaringWarning)), DesugaringError),
    on_text: fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML), a) ->
      Result(#(VXML, a, List(DesugaringWarning)), DesugaringError),
  )
}

fn fancy_one_to_one_enter_exit_stateful_with_warnings_nodemap_walk(
  original_state: a,
  node: VXML,
  ancestors: List(VXML),
  previous_siblings_before_mapping: List(VXML),
  previous_siblings_after_mapping: List(VXML),
  following_siblings_before_mapping: List(VXML),
  nodemap: FancyOneToOneEnterExitStatefulWithWarningsNodemap(a),
) -> Result(#(VXML, a, List(DesugaringWarning)), DesugaringError) {
  case node {
    T(_, _) ->
      nodemap.on_text(
        node,
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
        original_state,
      )
    V(_, _, _, _) -> {
      use #(node, latest_state, warnings) <- on.ok(nodemap.on_enter(
        node,
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
        original_state,
      ))
      let assert V(_, _, _, children) = node
      let children_ancestors = [node, ..ancestors]
      use #(children, latest_state, children_warnings) <- on.ok(
        list.try_fold(
          children,
          #([], [], list.drop(children, 1), latest_state, warnings),
          fn(acc, child) {
            use #(mapped_child, state, ws) <- on.ok(
              fancy_one_to_one_enter_exit_stateful_with_warnings_nodemap_walk(
                acc.3,
                child,
                children_ancestors,
                acc.0,
                acc.1,
                acc.2,
                nodemap,
              ),
            )
            Ok(#(
              [child, ..acc.0],
              [mapped_child, ..acc.1],
              list.drop(acc.2, 1),
              state,
              core.pour(ws, acc.4),
            ))
          },
        )
        |> result.map(fn(acc) { #(acc.1 |> list.reverse, acc.3, acc.4) }),
      )
      let node = V(..node, children: children)
      use #(vxml, latest_state, after_warnings) <- on.ok(nodemap.on_exit(
        node,
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
        original_state,
        latest_state,
      ))
      Ok(#(vxml, latest_state, core.pour(after_warnings, children_warnings)))
    }
  }
}

pub fn fancy_one_to_one_enter_exit_stateful_with_warnings_nodemap_2_desugarer_transform(
  nodemap: FancyOneToOneEnterExitStatefulWithWarningsNodemap(a),
  initial_state: a,
) -> DesugarerTransform {
  fn(vxml) {
    use #(vxml, _, warnings) <- on.ok(
      fancy_one_to_one_enter_exit_stateful_with_warnings_nodemap_walk(
        initial_state,
        vxml,
        [],
        [],
        [],
        [],
        nodemap,
      ),
    )
    Ok(#(vxml, warnings))
  }
}

// ************************************************************
// EarlyReturnOneToOneEnterExitStatefulWithWarningsNodemap(a)
// ************************************************************

pub type EarlyReturnOneToOneEnterExitStatefulWithWarningsNodemap(a) {
  EarlyReturnOneToOneEnterExitStatefulWithWarningsNodemap(
    on_enter: fn(VXML, a) ->
      Result(#(VXML, a, List(DesugaringWarning), TrafficLight), DesugaringError),
    on_exit: fn(VXML, a, a) ->
      Result(#(VXML, a, List(DesugaringWarning)), DesugaringError),
    on_text: fn(VXML, a) ->
      Result(#(VXML, a, List(DesugaringWarning)), DesugaringError),
  )
}

fn early_return_one_to_one_enter_exit_stateful_with_warnings_nodemap_walk(
  original_state: a,
  node: VXML,
  nodemap: EarlyReturnOneToOneEnterExitStatefulWithWarningsNodemap(a),
) -> Result(#(VXML, a, List(DesugaringWarning)), DesugaringError) {
  case node {
    T(_, _) -> nodemap.on_text(node, original_state)
    V(_, _, _, _) -> {
      use #(node, latest_state, warnings, traffic_light) <- on.ok(
        nodemap.on_enter(node, original_state),
      )
      let assert V(_, _, _, children) = node
      use #(children, latest_state, children_warnings) <- on.ok(
        case traffic_light {
          GoBack -> Ok(#(children, latest_state, []))
          Continue -> {
            list.try_fold(
              children,
              #([], latest_state, warnings),
              fn(acc, child) {
                use #(mapped_child, state, ws) <- on.ok(
                  early_return_one_to_one_enter_exit_stateful_with_warnings_nodemap_walk(
                    acc.1,
                    child,
                    nodemap,
                  ),
                )
                Ok(#([mapped_child, ..acc.0], state, core.pour(ws, acc.2)))
              },
            )
            |> result.map(fn(acc) { #(acc.0 |> list.reverse, acc.1, acc.2) })
          }
        },
      )
      let node = V(..node, children: children)
      use #(node, latest_state, after_warnings) <- on.ok(nodemap.on_exit(
        node,
        original_state,
        latest_state,
      ))
      Ok(#(node, latest_state, core.pour(after_warnings, children_warnings)))
    }
  }
}

pub fn early_return_one_to_one_enter_exit_stateful_with_warnings_nodemap_2_desugarer_transform(
  nodemap: EarlyReturnOneToOneEnterExitStatefulWithWarningsNodemap(a),
  initial_state: a,
) -> DesugarerTransform {
  fn(vxml) {
    use #(vxml, _, warnings) <- on.ok(
      early_return_one_to_one_enter_exit_stateful_with_warnings_nodemap_walk(
        initial_state,
        vxml,
        nodemap,
      ),
    )
    Ok(#(vxml, warnings))
  }
}

// ************************************************************
// EarlyReturnFancyOneToOneEnterExitStatefulWithWarningsNodemap(a)
// ************************************************************

pub type EarlyReturnFancyOneToOneEnterExitStatefulWithWarningsNodemap(a) {
  EarlyReturnFancyOneToOneEnterExitStatefulWithWarningsNodemap(
    on_enter: fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML), a) ->
      Result(#(VXML, a, List(DesugaringWarning), TrafficLight), DesugaringError),
    on_exit: fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML), a, a) ->
      Result(#(VXML, a, List(DesugaringWarning)), DesugaringError),
    on_text: fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML), a) ->
      Result(#(VXML, a, List(DesugaringWarning)), DesugaringError),
  )
}

fn early_return_fancy_one_to_one_enter_exit_stateful_with_warnings_nodemap_walk(
  original_state: a,
  node: VXML,
  ancestors: List(VXML),
  previous_siblings_before_mapping: List(VXML),
  previous_siblings_after_mapping: List(VXML),
  following_siblings_before_mapping: List(VXML),
  nodemap: EarlyReturnFancyOneToOneEnterExitStatefulWithWarningsNodemap(a),
) -> Result(#(VXML, a, List(DesugaringWarning)), DesugaringError) {
  case node {
    T(_, _) ->
      nodemap.on_text(
        node,
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
        original_state,
      )
    V(_, _, _, _) -> {
      use #(node, latest_state, warnings, traffic_light) <- on.ok(
        nodemap.on_enter(
          node,
          ancestors,
          previous_siblings_before_mapping,
          previous_siblings_after_mapping,
          following_siblings_before_mapping,
          original_state,
        ),
      )
      let assert V(_, _, _, children) = node
      use #(children, latest_state, children_warnings) <- on.ok(
        case traffic_light {
          Continue -> {
            let children_ancestors = [node, ..ancestors]
            list.try_fold(
              children,
              #([], [], list.drop(children, 1), latest_state, warnings),
              fn(acc, child) {
                use #(mapped_child, state, ws) <- on.ok(
                  early_return_fancy_one_to_one_enter_exit_stateful_with_warnings_nodemap_walk(
                    acc.3,
                    child,
                    children_ancestors,
                    acc.0,
                    acc.1,
                    acc.2,
                    nodemap,
                  ),
                )
                Ok(#(
                  [child, ..acc.0],
                  [mapped_child, ..acc.1],
                  list.drop(acc.2, 1),
                  state,
                  core.pour(ws, acc.4),
                ))
              },
            )
            |> result.map(fn(acc) { #(acc.1 |> list.reverse, acc.3, acc.4) })
          }
          GoBack -> Ok(#(children, latest_state, []))
        },
      )
      let node = V(..node, children: children)
      use #(node, latest_state, after_warnings) <- on.ok(nodemap.on_exit(
        node,
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
        original_state,
        latest_state,
      ))
      Ok(#(node, latest_state, core.pour(after_warnings, children_warnings)))
    }
  }
}

pub fn early_return_fancy_one_to_one_enter_exit_stateful_with_warnings_nodemap_2_desugarer_transform(
  nodemap: EarlyReturnFancyOneToOneEnterExitStatefulWithWarningsNodemap(a),
  initial_state: a,
) -> DesugarerTransform {
  fn(vxml) {
    use #(vxml, _, warnings) <- on.ok(
      early_return_fancy_one_to_one_enter_exit_stateful_with_warnings_nodemap_walk(
        initial_state,
        vxml,
        [],
        [],
        [],
        [],
        nodemap,
      ),
    )
    Ok(#(vxml, warnings))
  }
}

// ************************************************************
// EarlyReturnOneToOptionEnterExitStatefulWithChildStatesNoErrorNodemap(a)
// ************************************************************

// WithChildStates means that on_exit receives the list of all child states,
// rather than only the state returned by the last child.

pub type EarlyReturnOneToOptionEnterExitStatefulWithChildStatesNoErrorNodemap(a) {
  EarlyReturnOneToOptionEnterExitStatefulWithChildStatesNoErrorNodemap(
    on_enter: fn(VXML, a) -> #(Option(VXML), a, TrafficLight),
    on_exit: fn(VXML, a, List(a)) -> #(Option(VXML), a),
    on_text: fn(VXML, a) -> #(Option(VXML), a),
  )
}

fn early_return_one_to_option_enter_exit_stateful_with_child_states_no_error_nodemap_walk(
  original_state: a,
  node: VXML,
  nodemap: EarlyReturnOneToOptionEnterExitStatefulWithChildStatesNoErrorNodemap(
    a,
  ),
) -> #(Option(VXML), a) {
  case node {
    T(..) -> nodemap.on_text(node, original_state)
    V(..) -> {
      let #(node, parent_state, traffic_light) =
        nodemap.on_enter(node, original_state)
      use <- on.true_false(traffic_light == GoBack, fn() {
        #(node, parent_state)
      })
      use node <- on.none_some(node, fn() { #(None, parent_state) })
      let assert V(_, _, _, children) = node
      let #(children_states, children) =
        children
        |> list.fold(#([], []), fn(acc, child) {
          let #(option_child, child_state) =
            early_return_one_to_option_enter_exit_stateful_with_child_states_no_error_nodemap_walk(
              parent_state,
              child,
              nodemap,
            )
          case option_child {
            None -> acc
            Some(x) -> #([child_state, ..acc.0], [x, ..acc.1])
          }
        })
      let node = V(..node, children: children |> list.reverse)
      nodemap.on_exit(node, original_state, children_states)
    }
  }
}

pub fn early_return_one_to_option_enter_exit_stateful_with_child_states_no_error_nodemap_2_desugarer_transform(
  nodemap: EarlyReturnOneToOptionEnterExitStatefulWithChildStatesNoErrorNodemap(
    a,
  ),
  initial_state: a,
) -> DesugarerTransform {
  fn(vxml) {
    let #(vxml, _) =
      early_return_one_to_option_enter_exit_stateful_with_child_states_no_error_nodemap_walk(
        initial_state,
        vxml,
        nodemap,
      )
    vxml
    |> get_root_option
    |> result.map(add_no_warnings)
  }
}

// ************************************************************
// EarlyReturnFancyOneToOptionEnterExitStatefulWithWarningsNodemap(a)
// ************************************************************

pub type EarlyReturnFancyOneToOptionEnterExitStatefulWithWarningsNodemap(a) {
  EarlyReturnFancyOneToOptionEnterExitStatefulWithWarningsNodemap(
    on_enter: fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML), a) ->
      Result(
        #(Option(VXML), a, List(DesugaringWarning), TrafficLight),
        DesugaringError,
      ),
    on_exit: fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML), a, a) ->
      Result(#(Option(VXML), a, List(DesugaringWarning)), DesugaringError),
    on_text: fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML), a) ->
      Result(#(Option(VXML), a, List(DesugaringWarning)), DesugaringError),
  )
}

fn early_return_fancy_one_to_option_enter_exit_stateful_with_warnings_nodemap_walk(
  original_state: a,
  node: VXML,
  ancestors: List(VXML),
  previous_siblings_before_mapping: List(VXML),
  previous_siblings_after_mapping: List(VXML),
  following_siblings_before_mapping: List(VXML),
  nodemap: EarlyReturnFancyOneToOptionEnterExitStatefulWithWarningsNodemap(a),
) -> Result(#(Option(VXML), a, List(DesugaringWarning)), DesugaringError) {
  case node {
    T(_, _) ->
      nodemap.on_text(
        node,
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
        original_state,
      )
    V(_, _, _, _) -> {
      use #(node, latest_state, warnings, traffic_light) <- on.ok(
        nodemap.on_enter(
          node,
          ancestors,
          previous_siblings_before_mapping,
          previous_siblings_after_mapping,
          following_siblings_before_mapping,
          original_state,
        ),
      )
      use node <- on.none_some(node, fn() {
        Ok(#(None, latest_state, warnings))
      })
      let assert V(_, _, _, children) = node
      use #(children, latest_state, children_warnings) <- on.ok(
        case traffic_light {
          Continue -> {
            let children_ancestors = [node, ..ancestors]
            list.try_fold(
              children,
              #([], [], list.drop(children, 1), latest_state, warnings),
              fn(acc, child) {
                use #(mapped_child, state, ws) <- on.ok(
                  early_return_fancy_one_to_option_enter_exit_stateful_with_warnings_nodemap_walk(
                    acc.3,
                    child,
                    children_ancestors,
                    acc.0,
                    acc.1,
                    acc.2,
                    nodemap,
                  ),
                )
                let renovated_siblings = case mapped_child {
                  None -> acc.1
                  Some(x) -> [x, ..acc.1]
                }
                Ok(#(
                  [child, ..acc.0],
                  renovated_siblings,
                  list.drop(acc.2, 1),
                  state,
                  core.pour(ws, acc.4),
                ))
              },
            )
            |> result.map(fn(acc) { #(acc.1 |> list.reverse, acc.3, acc.4) })
          }
          GoBack -> Ok(#(children, latest_state, []))
        },
      )
      let node = V(..node, children: children)
      use #(node, latest_state, after_warnings) <- on.ok(nodemap.on_exit(
        node,
        ancestors,
        previous_siblings_before_mapping,
        previous_siblings_after_mapping,
        following_siblings_before_mapping,
        original_state,
        latest_state,
      ))
      Ok(#(node, latest_state, core.pour(after_warnings, children_warnings)))
    }
  }
}

pub fn early_return_fancy_one_to_option_enter_exit_stateful_with_warnings_nodemap_2_desugarer_transform(
  nodemap: EarlyReturnFancyOneToOptionEnterExitStatefulWithWarningsNodemap(a),
  initial_state: a,
) -> DesugarerTransform {
  fn(vxml) {
    use #(vxml, _, warnings) <- on.ok(
      early_return_fancy_one_to_option_enter_exit_stateful_with_warnings_nodemap_walk(
        initial_state,
        vxml,
        [],
        [],
        [],
        [],
        nodemap,
      ),
    )
    case vxml {
      Some(vxml) -> Ok(#(vxml, warnings))
      None ->
        Error(DesugaringError(
          bl.no_blame,
          "fancy-one-to-option desugarer returned None root",
        ))
    }
  }
}

// ************************************************************
// OneToManyEnterExitStatefulNodemap
// ************************************************************

pub type OneToManyEnterExitStatefulNodemap(a) {
  OneToManyEnterExitStatefulNodemap(
    on_enter: fn(VXML, a) -> Result(#(VXML, a), DesugaringError),
    on_exit: fn(VXML, a, a) -> Result(#(List(VXML), a), DesugaringError),
    on_text: fn(VXML, a) -> Result(#(List(VXML), a), DesugaringError),
  )
}

fn one_to_many_enter_exit_stateful_nodemap_walk(
  original_state: a,
  node: VXML,
  nodemap: OneToManyEnterExitStatefulNodemap(a),
) -> Result(#(List(VXML), a), DesugaringError) {
  case node {
    V(_, _, _, _) -> {
      use #(node, latest_state) <- on.ok(nodemap.on_enter(node, original_state))
      let assert V(_, _, _, children) = node
      use #(children, latest_state) <- on.ok(
        children
        |> list.try_fold(#([], latest_state), fn(acc, child) {
          use #(shat_children, latest_state) <- on.ok(
            one_to_many_enter_exit_stateful_nodemap_walk(acc.1, child, nodemap),
          )
          Ok(#(core.pour(shat_children, acc.0), latest_state))
        })
        |> result.map(fn(acc) { #(acc.0 |> list.reverse, acc.1) }),
      )
      nodemap.on_exit(
        node |> core.v_replace_children_with(children),
        original_state,
        latest_state,
      )
    }
    T(_, _) -> nodemap.on_text(node, original_state)
  }
}

pub fn one_to_many_enter_exit_stateful_nodemap_2_desugarer_transform(
  nodemap: OneToManyEnterExitStatefulNodemap(a),
  initial_state: a,
) -> DesugarerTransform {
  fn(vxml) {
    one_to_many_enter_exit_stateful_nodemap_walk(initial_state, vxml, nodemap)
    |> result.map(fn(pair) { pair.0 })
    |> on.ok(get_root)
    |> result.map(add_no_warnings)
  }
}

// ************************************************************
// OneToManyEnterExitStatefulWithWarningsNodemap
// ************************************************************

pub type OneToManyEnterExitStatefulWithWarningsNodemap(a) {
  OneToManyEnterExitStatefulWithWarningsNodemap(
    on_enter: fn(VXML, a) ->
      Result(#(VXML, a, List(DesugaringWarning)), DesugaringError),
    on_exit: fn(VXML, a, a) ->
      Result(#(List(VXML), a, List(DesugaringWarning)), DesugaringError),
    on_text: fn(VXML, a) ->
      Result(#(List(VXML), a, List(DesugaringWarning)), DesugaringError),
  )
}

fn one_to_many_enter_exit_stateful_with_warnings_nodemap_walk(
  collected_warnings: List(DesugaringWarning),
  original_state: a,
  node: VXML,
  nodemap: OneToManyEnterExitStatefulWithWarningsNodemap(a),
) -> Result(#(List(VXML), a, List(DesugaringWarning)), DesugaringError) {
  case node {
    V(_, _, _, _) -> {
      use #(node, latest_state, warnings) <- on.ok(nodemap.on_enter(
        node,
        original_state,
      ))
      let collected_warnings = core.pour(warnings, collected_warnings)
      let assert V(_, _, _, children) = node
      use #(children, latest_state, collected_warnings) <- on.ok(
        children
        |> list.try_fold(
          #([], latest_state, collected_warnings),
          fn(acc, child) {
            use #(shat_children, latest_state, collected_warnings) <- on.ok(
              one_to_many_enter_exit_stateful_with_warnings_nodemap_walk(
                acc.2,
                acc.1,
                child,
                nodemap,
              ),
            )
            Ok(#(
              core.pour(shat_children, acc.0),
              latest_state,
              collected_warnings,
            ))
          },
        )
        |> result.map(fn(acc) { #(acc.0 |> list.reverse, acc.1, acc.2) }),
      )
      use #(node, latest_state, warnings) <- on.ok(nodemap.on_exit(
        node |> core.v_replace_children_with(children),
        original_state,
        latest_state,
      ))
      Ok(#(node, latest_state, core.pour(warnings, collected_warnings)))
    }
    T(_, _) -> {
      use #(vxml, latest_state, warnings) <- on.ok(nodemap.on_text(
        node,
        original_state,
      ))

      Ok(#(vxml, latest_state, core.pour(warnings, collected_warnings)))
    }
  }
}

pub fn one_to_many_enter_exit_stateful_with_warnings_nodemap_2_desugarer_transform(
  nodemap: OneToManyEnterExitStatefulWithWarningsNodemap(a),
  initial_state: a,
) -> DesugarerTransform {
  fn(vxml) {
    use #(vxmls, _, warnings) <- on.ok(
      one_to_many_enter_exit_stateful_with_warnings_nodemap_walk(
        [],
        initial_state,
        vxml,
        nodemap,
      ),
    )
    use vxml <- on.ok(get_root(vxmls))
    Ok(#(vxml, warnings |> list.reverse))
  }
}

// ************************************************************
// EarlyReturnOneToOneNoErrorNodemap
// ************************************************************

pub type EarlyReturnOneToOneNoErrorNodemap =
  fn(VXML) -> #(VXML, TrafficLight)

fn early_return_one_to_one_no_error_nodemap_walk(
  node: VXML,
  nodemap: EarlyReturnOneToOneNoErrorNodemap,
) -> VXML {
  let #(node, signal) = nodemap(node)
  case node, signal {
    V(_, _, _, children), Continue -> {
      let children =
        children
        |> list.map(early_return_one_to_one_no_error_nodemap_walk(_, nodemap))
      V(..node, children: children)
    }
    _, _ -> node
  }
}

pub fn early_return_one_to_one_no_error_nodemap_2_desugarer_transform(
  nodemap: EarlyReturnOneToOneNoErrorNodemap,
) -> DesugarerTransform {
  fn(vxml) {
    early_return_one_to_one_no_error_nodemap_walk(vxml, nodemap)
    |> add_no_warnings
    |> Ok
  }
}

// *** with forbidden ***

fn early_return_one_to_one_no_error_nodemap_walk_with_forbidden(
  node: VXML,
  nodemap: EarlyReturnOneToOneNoErrorNodemap,
  forbidden: List(String),
) -> VXML {
  use <- on.eager_true_false(core.is_v_and_tag_is_one_of(node, forbidden), node)
  let #(node, signal) = nodemap(node)
  case node, signal {
    V(_, _, _, children), Continue -> {
      let children =
        children
        |> list.map(
          early_return_one_to_one_no_error_nodemap_walk_with_forbidden(
            _,
            nodemap,
            forbidden,
          ),
        )
      V(..node, children: children)
    }
    _, _ -> node
  }
}

pub fn early_return_one_to_one_no_error_nodemap_2_desugarer_transform_with_forbidden(
  nodemap: EarlyReturnOneToOneNoErrorNodemap,
  forbidden: List(String),
) -> DesugarerTransform {
  use <- bad_tag_guard(forbidden)

  fn(vxml) {
    early_return_one_to_one_no_error_nodemap_walk_with_forbidden(
      vxml,
      nodemap,
      forbidden,
    )
    |> add_no_warnings
    |> Ok
  }
}

// ************************************************************
// EarlyReturnFancyOneToOneNoErrorNodemap
// ************************************************************

pub type EarlyReturnFancyOneToOneNoErrorNodemap =
  fn(VXML, List(VXML), List(VXML), List(VXML), List(VXML)) ->
    #(VXML, TrafficLight)

fn early_return_fancy_one_to_one_no_error_nodemap_walk(
  node: VXML,
  ancestors: List(VXML),
  previous_siblings_before_mapping: List(VXML),
  previous_siblings_after_mapping: List(VXML),
  following_siblings_before_mapping: List(VXML),
  nodemap: EarlyReturnFancyOneToOneNoErrorNodemap,
) -> VXML {
  let #(node, signal) =
    nodemap(
      node,
      ancestors,
      previous_siblings_before_mapping,
      previous_siblings_after_mapping,
      following_siblings_before_mapping,
    )
  case node, signal {
    V(_, _, _, children), Continue -> {
      let children_ancestors = [node, ..ancestors]
      let children =
        list.fold(children, #([], [], list.drop(children, 1)), fn(acc, child) {
          let mapped_child =
            early_return_fancy_one_to_one_no_error_nodemap_walk(
              child,
              children_ancestors,
              acc.0,
              acc.1,
              acc.2,
              nodemap,
            )
          #([child, ..acc.0], [mapped_child, ..acc.1], list.drop(acc.2, 1))
        })
        |> fn(acc) { acc.1 |> list.reverse }
      V(..node, children: children)
    }
    _, _ -> node
  }
}

pub fn early_return_fancy_one_to_one_no_error_nodemap_2_desugarer_transform(
  nodemap: EarlyReturnFancyOneToOneNoErrorNodemap,
) -> DesugarerTransform {
  fn(vxml) {
    early_return_fancy_one_to_one_no_error_nodemap_walk(
      vxml,
      [],
      [],
      [],
      [],
      nodemap,
    )
    |> add_no_warnings
    |> Ok
  }
}

// ************************************************************
// EarlyReturnOneToOneNodemap
// ************************************************************

pub type EarlyReturnOneToOneNodemap =
  fn(VXML) -> Result(#(VXML, TrafficLight), DesugaringError)

pub fn early_return_one_to_one_nodemap_walk(
  node: VXML,
  nodemap: EarlyReturnOneToOneNodemap,
) -> Result(VXML, DesugaringError) {
  use #(node, signal) <- on.ok(nodemap(node))
  case node, signal {
    V(_, _, _, children), Continue -> {
      use children <- on.ok(
        list.try_map(children, early_return_one_to_one_nodemap_walk(_, nodemap)),
      )
      Ok(V(..node, children: children))
    }
    _, _ -> Ok(node)
  }
}

pub fn early_return_one_to_one_nodemap_2_desugarer_transform(
  nodemap: EarlyReturnOneToOneNodemap,
) -> DesugarerTransform {
  fn(vxml) {
    early_return_one_to_one_nodemap_walk(vxml, nodemap)
    |> result.map(add_no_warnings)
  }
}

// ************************************************************
// EarlyReturnOneToManyNoErrorNodemap
// ************************************************************

pub type EarlyReturnOneToManyNoErrorNodemap =
  fn(VXML) -> #(List(VXML), TrafficLight)

// *** without forbidden ***

fn early_return_one_to_many_no_error_nodemap_walk(
  node: VXML,
  nodemap: EarlyReturnOneToManyNoErrorNodemap,
) -> List(VXML) {
  let #(nodes, signal) = nodemap(node)
  case nodes, signal {
    _, GoBack -> nodes
    [], Continue -> nodes
    [T(_, _)], Continue -> nodes
    [V(_, _, _, children) as node], Continue -> {
      let children =
        children
        |> list.map(early_return_one_to_many_no_error_nodemap_walk(_, nodemap))
        |> list.flatten
      [V(..node, children: children)]
    }
    _, Continue -> {
      // right now we don't like to see EarlyReturn nodemap
      // replacing itself by > 1 node and asking
      // us to continue at child level ()
      panic as "EarlyReturn recursive_application asked to Continue after node spit itself"
    }
  }
}

pub fn early_return_one_to_many_no_error_nodemap_2_desugarer_transform(
  nodemap: EarlyReturnOneToManyNoErrorNodemap,
) -> DesugarerTransform {
  fn(vxml) {
    early_return_one_to_many_no_error_nodemap_walk(vxml, nodemap)
    |> get_root
    |> result.map(add_no_warnings)
  }
}

// *** with forbidden ***

fn early_return_one_to_many_no_error_nodemap_walk_with_forbidden(
  node: VXML,
  nodemap: EarlyReturnOneToManyNoErrorNodemap,
  forbidden: List(String),
) -> List(VXML) {
  use <- on.true_false(core.is_v_and_tag_is_one_of(node, forbidden), fn() {
    [node]
  })
  let #(nodes, signal) = nodemap(node)
  case nodes, signal {
    _, GoBack -> nodes
    [], Continue -> nodes
    [T(_, _)], Continue -> nodes
    [V(_, _, _, children) as node], Continue -> {
      let children =
        children
        |> list.map(
          early_return_one_to_many_no_error_nodemap_walk_with_forbidden(
            _,
            nodemap,
            forbidden,
          ),
        )
        |> list.flatten
      [V(..node, children: children)]
    }
    _, Continue -> {
      // right now we're not super in love with EarlyReturn (or more
      // generally self_first) nodemap replacing itself by > 1 node
      // and asking us to continue at child level
      panic as "EarlyReturnOneToManyNoErrorNodemap asked to Continue after node multiplied itself"
    }
  }
}

pub fn early_return_one_to_many_no_error_nodemap_2_desugarer_transform_with_forbidden(
  nodemap: EarlyReturnOneToManyNoErrorNodemap,
  forbidden: List(String),
) -> DesugarerTransform {
  use <- bad_tag_guard(forbidden)

  fn(vxml) {
    early_return_one_to_many_no_error_nodemap_walk_with_forbidden(
      vxml,
      nodemap,
      forbidden,
    )
    |> get_root
    |> result.map(add_no_warnings)
  }
}

// ************************************************************
// StatefulNoErrorVisitor
// ************************************************************

pub type StatefulNoErrorVisitor(a) =
  fn(VXML, a) -> a

pub fn stateful_no_error_visit(
  vxml: VXML,
  state: state,
  visitor: StatefulNoErrorVisitor(state),
) -> state {
  case vxml {
    T(..) -> visitor(vxml, state)
    V(_, _, _, children) -> {
      list.fold(children, state, fn(state, child) {
        stateful_no_error_visit(child, state, visitor)
      })
      |> visitor(vxml, _)
    }
  }
}

// ************************************************************
// EarlyReturnStatefulVisitor
// ************************************************************

pub type EarlyReturnStatefulVisitor(a) =
  fn(VXML, a) -> Result(#(a, TrafficLight), DesugaringError)

pub fn early_return_stateful_visit(
  vxml: VXML,
  state: state,
  visitor: EarlyReturnStatefulVisitor(state),
) -> Result(state, DesugaringError) {
  use #(state, traffic_light) <- on.ok(visitor(vxml, state))
  case traffic_light, vxml {
    Continue, V(_, _, _, children) -> {
      list.try_fold(children, state, fn(state, child) {
        early_return_stateful_visit(child, state, visitor)
      })
    }
    _, _ -> Ok(state)
  }
}
