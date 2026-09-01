import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option}
import vxml.{type VXML, Line, T, V}

fn turn_into_text_node(node: VXML, text: String) -> VXML {
  let blame = node.blame
  T(blame, [Line(blame, text)])
}

fn accumulator(
  tags2texts: Dict(String, String),
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
                tags2texts,
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
                tags2texts,
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
                tags2texts,
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
                tags2texts,
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
              case dict.get(tags2texts, tag) {
                Error(Nil) ->
                  // *
                  // case W00: - 'first' is non-matching V-node
                  //           - no previous t node
                  //           - no previous v node
                  //
                  // add 'first' to already_processed
                  // *
                  accumulator(
                    tags2texts,
                    [first, ..already_processed],
                    option.None,
                    option.None,
                    rest,
                  )
                Ok(text) ->
                  // *
                  // case M00: - 'first' is matching V-node
                  //           - no previous t node
                  //           - no previous v node
                  //
                  // make 'first' the optional_last_v
                  // *
                  accumulator(
                    tags2texts,
                    already_processed,
                    option.None,
                    option.Some(#(first, text)),
                    rest,
                  )
              }
            option.Some(#(last_v, last_v_text)) ->
              case dict.get(tags2texts, tag) {
                Error(Nil) ->
                  // *
                  // case W01: - 'first' is non-matching V-node
                  //           - no previous t node
                  //           - there exists a previous v node
                  //
                  // standalone-bundle the previous v node & add first to already processed
                  // *
                  accumulator(
                    tags2texts,
                    [
                      first,
                      turn_into_text_node(last_v, last_v_text),
                      ..already_processed
                    ],
                    option.None,
                    option.None,
                    rest,
                  )
                Ok(text) ->
                  // *
                  // case M01: - 'first' is matching V-node
                  //           - no previous t node
                  //           - there exists a previous v node
                  //
                  // standalone-bundle the previous v node & make 'first' the optional_last_v
                  // *
                  accumulator(
                    tags2texts,
                    already_processed,
                    option.Some(turn_into_text_node(last_v, last_v_text)),
                    option.Some(#(first, text)),
                    rest,
                  )
              }
          }
        }
        option.Some(last_t) ->
          case optional_last_v {
            option.None ->
              case dict.get(tags2texts, tag) {
                Error(Nil) ->
                  // *
                  // case W10: - 'first' is a non-matching V-node
                  //           - there exists a previous t node
                  //           - no previous v node
                  //
                  // add 'first' and previoux t node to already_processed
                  // *
                  accumulator(
                    tags2texts,
                    [first, last_t, ..already_processed],
                    option.None,
                    option.None,
                    rest,
                  )
                Ok(text) ->
                  // *
                  // case M10: - 'first' is a matching V-node
                  //           - there exists a previous t node
                  //           - no previous v node
                  //
                  // keep the previous t node, make 'first' the optional_last_v
                  // *
                  accumulator(
                    tags2texts,
                    already_processed,
                    optional_last_t,
                    option.Some(#(first, text)),
                    rest,
                  )
              }
            option.Some(#(_, last_v_text)) ->
              case dict.get(tags2texts, tag) {
                Error(Nil) ->
                  // *
                  // case W11: - 'first' is a non-matching V-node
                  //           - there exists a previous t node
                  //           - there exists a previous v node
                  //
                  // fold t & v, put first & folder t/v into already_processed
                  // *
                  accumulator(
                    tags2texts,
                    [
                      first,
                      core.t_end_insert_text(last_t, last_v_text),
                      ..already_processed
                    ],
                    option.None,
                    option.None,
                    rest,
                  )
                Ok(text) ->
                  // *
                  // case M11: - 'first' is matching V-node
                  //           - there exists a previous t node
                  //           - there exists a previous v node
                  //
                  // fold t & v, put into already_processed, make v the new optional_last_v
                  // *
                  accumulator(
                    tags2texts,
                    already_processed,
                    option.Some(core.t_end_insert_text(last_t, text)),
                    option.Some(#(first, text)),
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
        accumulator(inner, [], option.None, option.None, children)
      Ok(V(blame, tag, attrs, new_children))
    }
  }
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap(_, inner)
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  core.dict_from_list(param)
}

type Param =
  List(
    #(
      // Tag name to replace.
      String,
      // Replacement text to use.
      String,
    ),
  )

type InnerParam =
  Dict(String, String)

pub const name = "fold_into_text__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Replaces configured elements with text glued to the
/// surrounding text nodes, discarding their contents and attrs.
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
