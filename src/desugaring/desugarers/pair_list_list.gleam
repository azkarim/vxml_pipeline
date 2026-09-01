import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/option.{type Option}
import gleam/string.{inspect as ins}
import vxml.{type VXML, T, V}
import vxml/blame.{type Blame, Src} as bl

pub const name = "pair_list_list"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Pairs corresponding opening and closing element types
/// inside an enclosing element.
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
    // Opening tags.
    List(String),
    // Closing tags.
    List(String),
    // Enclosing tag.
    String,
  )

type InnerParam =
  Param

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(node: VXML, inner: InnerParam) -> VXML {
  let #(opening, closing, enclosing) = inner
  case node {
    T(_, _) -> node
    V(blame, tag, attrs, children) -> {
      let new_children =
        accumulator(opening, closing, enclosing, [], option.None, [], children)
      V(blame, tag, attrs, new_children)
    }
  }
}

fn accumulator(
  opening: List(String),
  closing: List(String),
  enclosing: String,
  already_processed: List(VXML),
  last_opening: Option(VXML),
  after_last_opening: List(VXML),
  remaining: List(VXML),
) -> List(VXML) {
  case remaining {
    [] ->
      case last_opening {
        option.None -> {
          let assert [] = after_last_opening
          already_processed |> list.reverse
        }
        option.Some(dude) -> {
          list.flatten([after_last_opening, [dude, ..already_processed]])
          |> list.reverse
        }
      }
    [T(_, _) as first, ..rest] ->
      case last_opening {
        option.None -> {
          // *
          // absorb the T-node into already_processed
          // *
          let assert [] = after_last_opening
          accumulator(
            opening,
            closing,
            enclosing,
            [first, ..already_processed],
            option.None,
            [],
            rest,
          )
        }
        option.Some(_) ->
          // *
          // absorb the T-node into after_last_opening
          // *
          accumulator(
            opening,
            closing,
            enclosing,
            already_processed,
            last_opening,
            [first, ..after_last_opening],
            rest,
          )
      }
    [V(_, tag, _, _) as first, ..rest] ->
      case list.contains(opening, tag), list.contains(closing, tag) {
        False, False ->
          // *
          // treat the V-node like the T-node above
          // *
          case last_opening {
            option.None -> {
              // *
              // absorb the V-node into already_processed
              // *
              let assert [] = after_last_opening
              accumulator(
                opening,
                closing,
                enclosing,
                [first, ..already_processed],
                option.None,
                [],
                rest,
              )
            }
            option.Some(_) ->
              // *
              // absorb the V-node into after_last_opening
              // *
              accumulator(
                opening,
                closing,
                enclosing,
                already_processed,
                last_opening,
                [first, ..after_last_opening],
                rest,
              )
          }
        True, False ->
          case last_opening {
            option.None -> {
              // *
              // we make the V-node the new value of last_opening
              // *
              let assert [] = after_last_opening
              accumulator(
                opening,
                closing,
                enclosing,
                already_processed,
                option.Some(first),
                [],
                rest,
              )
            }
            option.Some(dude) ->
              // *
              // we discard the previous last_opening and his followers and make the V-node the new value of last_opening
              // *
              accumulator(
                opening,
                closing,
                enclosing,
                list.flatten([after_last_opening, [dude, ..already_processed]]),
                option.Some(first),
                [],
                rest,
              )
          }
        False, True ->
          case last_opening {
            option.None -> {
              // *
              // we absorb the V-node into already_processed
              // *
              let assert [] = after_last_opening
              accumulator(
                opening,
                closing,
                enclosing,
                [first, ..already_processed],
                option.None,
                [],
                rest,
              )
            }
            option.Some(dude) ->
              // *
              // we do a pairing
              // *
              accumulator(
                opening,
                closing,
                enclosing,
                [
                  V(
                    dude.blame
                      |> bl.append_comment(pairing_msg(dude.blame, first.blame)),
                    enclosing,
                    [],
                    after_last_opening |> list.reverse,
                  ),
                  ..already_processed
                ],
                option.None,
                [],
                rest,
              )
          }
        True, True ->
          case last_opening {
            option.None -> {
              // *
              // we make the V-node the new value of last_opening
              // *
              let assert [] = after_last_opening
              accumulator(
                opening,
                closing,
                enclosing,
                already_processed,
                option.Some(first),
                [],
                rest,
              )
            }
            option.Some(dude) ->
              // *
              // we do a pairing
              // *
              accumulator(
                opening,
                closing,
                enclosing,
                [
                  V(
                    dude.blame
                      |> bl.append_comment(pairing_msg(dude.blame, first.blame)),
                    enclosing,
                    [],
                    after_last_opening |> list.reverse,
                  ),
                  ..already_processed
                ],
                option.None,
                [],
                rest,
              )
          }
      }
  }
}

fn pairing_msg(local: Blame, remote: Blame) -> String {
  case local, remote {
    Src(_, l, _, _, _), Src(_, r, _, _, _) if l == r ->
      "paired with --:" <> ins(remote.line_no) <> ":" <> ins(remote.char_no)
    _, _ -> "p.w. " <> bl.blame_digest(remote)
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
