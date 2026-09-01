import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/option.{type Option}
import gleam/string
import vxml.{type VXML, Line, T, V}

fn accumulator(
  inner: InnerParam,
  already_processed: List(VXML),
  optional_last_t: Option(VXML),
  optional_last_v: Option(VXML),
  remaining: List(VXML),
) -> List(VXML) {
  let blame = authoring.blame(name, 18)
  let ze_t = fn(node: VXML) -> VXML {
    let lines =
      inner.1(node)
      |> string.split("\n")
      |> list.map(fn(s) { Line(blame, s) })
    T(blame, lines)
  }

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
  // - optional_last_v is a possible previous v-node that
  //   matched the dictionary; if it is not None, it is the
  //   immediately previous node to 'remaining'
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
            option.Some(last_v) -> {
              // *
              // case N01: - no following node
              //           - no previous t node
              //           - there is a previous v node
              //
              // we turn the previous v node into a standalone text node
              // *
              [ze_t(last_v), ..already_processed] |> list.reverse
            }
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
            option.Some(last_v) -> {
              // *
              // case N11: - no following node
              //           - there is a previous t node
              //           - there is a previous v node
              //
              // we bundle the t & v, add to already_processed, reverse the list
              // *
              [
                core.t_t_last_to_first_concatenation(last_t, ze_t(last_v)),
                ..already_processed
              ]
              |> list.reverse
            }
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
                inner,
                already_processed,
                option.Some(first),
                option.None,
                rest,
              )
            option.Some(last_v) -> {
              // *
              // case T01: - 'first' is a Text node
              //           - no previous t node
              //           - there exists a previous v node
              //
              // we bundle the v & first, add to already_processed, reset v to None
              // *
              accumulator(
                inner,
                already_processed,
                option.Some(core.t_t_last_to_first_concatenation(
                  ze_t(last_v),
                  first,
                )),
                option.None,
                rest,
              )
            }
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
                inner,
                [last_t, ..already_processed],
                option.Some(first),
                option.None,
                rest,
              )
            option.Some(last_v) -> {
              // *
              // case T11: - 'first' is a Text node
              //           - there exists a previous t node
              //           - there exists a previous v node
              //
              // we bundle t & v & first and etc
              // *
              accumulator(
                inner,
                already_processed,
                option.Some(core.t_t_last_to_first_concatenation(
                  last_t,
                  core.t_t_last_to_first_concatenation(ze_t(last_v), first),
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
              case tag == inner.0 {
                False ->
                  // *
                  // case W00: - 'first' is non-matching V-node
                  //           - no previous t node
                  //           - no previous v node
                  //
                  // add 'first' to already_processed
                  // *
                  accumulator(
                    inner,
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
                    inner,
                    already_processed,
                    option.None,
                    option.Some(first),
                    rest,
                  )
              }
            option.Some(last_v) ->
              case tag == inner.0 {
                False -> {
                  // *
                  // case W01: - 'first' is non-matching V-node
                  //           - no previous t node
                  //           - there exists a previous v node
                  //
                  // standalone-bundle the previous v node & add first to already processed
                  // *
                  accumulator(
                    inner,
                    [first, ze_t(last_v), ..already_processed],
                    option.None,
                    option.None,
                    rest,
                  )
                }
                True -> {
                  // *
                  // case M01: - 'first' is matching V-node
                  //           - no previous t node
                  //           - there exists a previous v node
                  //
                  // standalone-bundle the previous v node & make 'first' the optional_last_v
                  // *
                  accumulator(
                    inner,
                    already_processed,
                    option.Some(ze_t(last_v)),
                    option.Some(first),
                    rest,
                  )
                }
              }
          }
        }
        option.Some(last_t) ->
          case optional_last_v {
            option.None ->
              case tag == inner.0 {
                False ->
                  // *
                  // case W10: - 'first' is a non-matching V-node
                  //           - there exists a previous t node
                  //           - no previous v node
                  //
                  // add 'first' and previous t node to already_processed
                  // *
                  accumulator(
                    inner,
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
                    inner,
                    already_processed,
                    optional_last_t,
                    option.Some(first),
                    rest,
                  )
              }
            option.Some(last_v) ->
              case tag == inner.0 {
                False -> {
                  // *
                  // case W11: - 'first' is a non-matching V-node
                  //           - there exists a previous t node
                  //           - there exists a previous v node
                  //
                  // fold t & v, put first & folded t/v into already_processed
                  // *
                  accumulator(
                    inner,
                    [
                      first,
                      core.t_t_last_to_first_concatenation(last_t, ze_t(last_v)),
                      ..already_processed
                    ],
                    option.None,
                    option.None,
                    rest,
                  )
                }
                True -> {
                  // *
                  // case M11: - 'first' is matching V-node
                  //           - there exists a previous t node
                  //           - there exists a previous v node
                  //
                  // fold t & v, put into already_processed, make v the new optional_last_v
                  // *
                  accumulator(
                    inner,
                    already_processed,
                    option.Some(core.t_t_last_to_first_concatenation(
                      last_t,
                      ze_t(last_v),
                    )),
                    option.Some(first),
                    rest,
                  )
                }
              }
          }
      }
  }
}

fn nodemap(node: VXML, inner: InnerParam) -> VXML {
  case node {
    T(_, _) -> node
    V(_, _, _, children) -> {
      let children = accumulator(inner, [], option.None, option.None, children)
      V(..node, children: children)
    }
  }
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  n2t.one_to_one_no_error_nodemap_2_desugarer_transform(nodemap)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

type Param =
  #(String, fn(VXML) -> String)

type InnerParam =
  Param

pub const name = "fold_custom_into_text"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Replaces matching elements with computed text, joining
/// the result to adjacent text nodes.
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
