import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/option.{type Option}
import vxml.{type VXML, Line, T, V}

fn turn_into_text_node(node: VXML, text: String) -> VXML {
  T(node.blame, [Line(node.blame, text)])
}

fn accumulator(
  tag_to_be_folded: String,
  replacement_text: String,
  already_processed: List(VXML),
  optional_last_t: Option(VXML),
  optional_last_v: Option(#(VXML, String)),
  remaining: List(VXML),
) -> List(VXML) {
  // *
  // - already_processed: previously processed children in
  //   reverse order (last stuff is first in the list)
  //
  // - optional_last_t is:
  //   * the node right before optional_last_v if
  //     optional_last_v != None
  //   * the last node before remaining if
  //     optional_last_v == None
  //
  // - optional_last_v is a possible previoux v-node that
  //   matched the dictionary; if it is not None, it is the
  //   immediately previous node to 'remaining'
  //
  // PURPOSE: this function should turn tags that appear
  //     in the tags2texts dictionary into text fragments
  //     that become the last/first line of the previous/next
  //     text nodes to the tag, if any, possibly resulting
  //     in the two text nodes on either side of the tag
  //     becoming joined into one text node (by glued via
  //     the tag text); if there are no adjacent text nodes,
  //     the tag becomes a new standalone text node
  // *
  case remaining {
    [] ->
      case optional_last_t {
        option.None -> {
          case optional_last_v {
            option.None ->
              // *
              // case N00: - no following node
              //           - no previous t node
              //           - no previous v node
              //
              // we reverse the list
              // *
              already_processed |> list.reverse
            option.Some(#(last_v, last_v_text)) ->
              // *
              // case N01: - no following node
              //           - no previous t node
              //           - there is a previous v node
              //
              // we turn the previous v node into a standalone text node
              // *
              [turn_into_text_node(last_v, last_v_text), ..already_processed]
              |> list.reverse
          }
        }
        option.Some(last_t) ->
          case optional_last_v {
            option.None ->
              // *
              // case N10: - no following node
              //           - there is a previous t node
              //           - no previous v node
              //
              // we add the t to already_processed, reverse the list
              // *
              [last_t, ..already_processed] |> list.reverse
            option.Some(#(_, replacement_text)) ->
              // *
              // case N11: - no following node
              //           - there is a previous t node
              //           - there is a previous v node
              //
              // we bundle the t & v, add to already_processed, reverse the list
              // *
              [
                core.t_end_insert_text(last_t, replacement_text),
                ..already_processed
              ]
              |> list.reverse
          }
      }
    [T(_, _) as first, ..rest] ->
      case optional_last_t {
        option.None ->
          case optional_last_v {
            option.None ->
              // *
              // case T00: - 'first' is a Text node
              //           - no previous t node
              //           - no previous v node
              //
              // we make 'first' the previous t node
              // *
              accumulator(
                tag_to_be_folded,
                replacement_text,
                already_processed,
                option.Some(first),
                option.None,
                rest,
              )
            option.Some(#(_, last_v_text)) ->
              // *
              // case T01: - 'first' is a Text node
              //           - no previous t node
              //           - there exists a previous v node
              //
              // we bundle the v & first, add to already_processed, reset v to None
              // *
              accumulator(
                tag_to_be_folded,
                replacement_text,
                already_processed,
                option.Some(core.t_start_insert_text(first, last_v_text)),
                option.None,
                rest,
              )
          }
        option.Some(last_t) -> {
          case optional_last_v {
            option.None ->
              // *
              // case T10: - 'first' is a Text node
              //           - there exists a previous t node
              //           - no previous v node
              //
              // we pass the previous t into already_processed and make 'first' the new optional_last_t
              // *
              accumulator(
                tag_to_be_folded,
                replacement_text,
                [last_t, ..already_processed],
                option.Some(first),
                option.None,
                rest,
              )
            option.Some(#(_, text)) -> {
              // *
              // case T11: - 'first' is a Text node
              //           - there exists a previous t node
              //           - there exists a previous v node
              //
              // we bundle t & v & first and etc
              // *
              accumulator(
                tag_to_be_folded,
                replacement_text,
                already_processed,
                option.Some(core.t_t_last_to_first_concatenation(
                  last_t,
                  core.t_start_insert_text(first, text),
                )),
                option.None,
                rest,
              )
            }
          }
        }
      }
    [V(_, tag, _, _) as first, ..rest] ->
      case optional_last_t {
        option.None -> {
          case optional_last_v {
            option.None ->
              case tag == tag_to_be_folded {
                False ->
                  // *
                  // case W00: - 'first' is non-matching V-node
                  //           - no previous t node
                  //           - no previous v node
                  //
                  // add 'first' to already_processed
                  // *
                  accumulator(
                    tag_to_be_folded,
                    replacement_text,
                    [first, ..already_processed],
                    option.None,
                    option.None,
                    rest,
                  )
                True ->
                  // *
                  // case M00: - 'first' is matching V-node
                  //           - no previous t node
                  //           - no previous v node
                  //
                  // make 'first' the optional_last_v
                  // *
                  accumulator(
                    tag_to_be_folded,
                    replacement_text,
                    already_processed,
                    option.None,
                    option.Some(#(first, replacement_text)),
                    rest,
                  )
              }
            option.Some(#(last_v, last_v_text)) ->
              case tag == tag_to_be_folded {
                False ->
                  // *
                  // case W01: - 'first' is non-matching V-node
                  //           - no previous t node
                  //           - there exists a previous v node
                  //
                  // standalone-bundle the previous v node & add first to already processed
                  // *
                  accumulator(
                    tag_to_be_folded,
                    replacement_text,
                    [
                      first,
                      turn_into_text_node(last_v, last_v_text),
                      ..already_processed
                    ],
                    option.None,
                    option.None,
                    rest,
                  )
                True ->
                  // *
                  // case M01: - 'first' is matching V-node
                  //           - no previous t node
                  //           - there exists a previous v node
                  //
                  // standalone-bundle the previous v node & make 'first' the optional_last_v
                  // *
                  accumulator(
                    tag_to_be_folded,
                    replacement_text,
                    already_processed,
                    option.Some(turn_into_text_node(last_v, last_v_text)),
                    option.Some(#(first, replacement_text)),
                    rest,
                  )
              }
          }
        }
        option.Some(last_t) ->
          case optional_last_v {
            option.None ->
              case tag == tag_to_be_folded {
                False ->
                  // *
                  // case W10: - 'first' is a non-matching V-node
                  //           - there exists a previous t node
                  //           - no previous v node
                  //
                  // add 'first' and previoux t node to already_processed
                  // *
                  accumulator(
                    tag_to_be_folded,
                    replacement_text,
                    [first, last_t, ..already_processed],
                    option.None,
                    option.None,
                    rest,
                  )
                True ->
                  // *
                  // case M10: - 'first' is a matching V-node
                  //           - there exists a previous t node
                  //           - no previous v node
                  //
                  // keep the previous t node, make 'first' the optional_last_v
                  // *
                  accumulator(
                    tag_to_be_folded,
                    replacement_text,
                    already_processed,
                    optional_last_t,
                    option.Some(#(first, replacement_text)),
                    rest,
                  )
              }
            option.Some(#(_, last_v_text)) ->
              case tag == tag_to_be_folded {
                False ->
                  // *
                  // case W11: - 'first' is a non-matching V-node
                  //           - there exists a previous t node
                  //           - there exists a previous v node
                  //
                  // fold t & v, put first & folder t/v into already_processed
                  // *
                  accumulator(
                    tag_to_be_folded,
                    replacement_text,
                    [
                      first,
                      core.t_end_insert_text(last_t, last_v_text),
                      ..already_processed
                    ],
                    option.None,
                    option.None,
                    rest,
                  )
                True ->
                  // *
                  // case M11: - 'first' is matching V-node
                  //           - there exists a previous t node
                  //           - there exists a previous v node
                  //
                  // fold t & v, put into already_processed, make v the new optional_last_v
                  // *
                  accumulator(
                    tag_to_be_folded,
                    replacement_text,
                    already_processed,
                    option.Some(core.t_end_insert_text(last_t, replacement_text)),
                    option.Some(#(first, replacement_text)),
                    rest,
                  )
              }
          }
      }
  }
}

fn nodemap(node: VXML, inner: InnerParam) -> Result(VXML, DesugaringError) {
  case node {
    T(_, _) -> Ok(node)
    V(blame, tag, attrs, children) -> {
      let new_children =
        accumulator(inner.0, inner.1, [], option.None, option.None, children)
      Ok(V(blame, tag, attrs, new_children))
    }
  }
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap(_, inner)
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param =
  #(
    // Element tag to replace.
    String,
    // Replacement text.
    String,
  )

type InnerParam =
  Param

pub const name = "fold_into_text"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Replaces matching elements with configured text, joining
/// it to adjacent text nodes.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
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
