import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/option.{type Option, None, Some}
import vxml.{type VXML, Line, T, V}

pub const name = "bridge_whitespace_single_space"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Merges consecutive matching siblings separated only by
/// whitespace, reducing nonempty intervening whitespace to
/// one space.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  String

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

fn nodemap(vxml: VXML, inner: InnerParam) -> VXML {
  case vxml {
    T(_, _) -> vxml
    V(_, _, _, children) -> {
      let children = accumulator(inner, [], None, [], children)
      V(..vxml, children: children)
    }
  }
}

fn accumulator(
  inner: String,
  already_processed: List(VXML),
  last_dude: Option(VXML),
  whitespace: List(VXML),
  remaining: List(VXML),
) -> List(VXML) {
  case remaining {
    [] -> {
      case last_dude {
        None -> {
          assert [] == whitespace
          already_processed |> list.reverse
        }
        Some(dude) -> {
          list.append(whitespace, [dude, ..already_processed])
          |> list.reverse
        }
      }
    }

    [T(_, _) as first, ..rest] -> {
      case last_dude {
        None -> {
          // *
          // absorb the T-node into already_processed
          // *
          assert [] == whitespace
          accumulator(inner, [first, ..already_processed], None, [], rest)
        }
        Some(dude) ->
          case core.lines_are_whitespace(first.lines) {
            False -> {
              // *
              // flush whitespace & dude, start over
              // *
              accumulator(
                inner,
                case whitespace {
                  [] -> [first, dude, ..already_processed]
                  [one] -> [first, one, dude, ..already_processed]
                  _ -> [
                    first,
                    ..list.append(whitespace, [dude, ..already_processed])
                  ]
                },
                None,
                [],
                rest,
              )
            }
            True -> {
              // *
              // add to whitespace
              // *
              accumulator(
                inner,
                already_processed,
                last_dude,
                [first, ..whitespace],
                rest,
              )
            }
          }
      }
    }

    [V(_, tag, _, _) as first, ..rest] if tag != inner -> {
      case last_dude {
        None -> {
          // *
          // absorb the V-node into already_processed
          // *
          assert [] == whitespace
          accumulator(inner, [first, ..already_processed], None, [], rest)
        }
        Some(dude) -> {
          // *
          // flush whitespace & dude, start over
          // *
          accumulator(
            inner,
            case whitespace {
              [] -> [first, dude, ..already_processed]
              [one] -> [first, one, dude, ..already_processed]
              _ -> [
                first,
                ..list.append(whitespace, [dude, ..already_processed])
              ]
            },
            None,
            [],
            rest,
          )
        }
      }
    }

    [V(_, tag, _, c2) as first, ..rest] -> {
      assert tag == inner
      case last_dude {
        None -> {
          // *
          // let last_dude = Some(first)
          // *
          assert [] == whitespace
          accumulator(inner, already_processed, Some(first), [], rest)
        }
        Some(dude) -> {
          // *
          // bridge dude -> first
          // *
          let assert V(_, _, _, c1) = dude
          let #(c1_last_lines, c1_others_reversed) = case c1 |> list.reverse {
            [T(..) as last, ..rest] -> #(last.lines, rest)
            anything_else -> #([], anything_else)
          }
          let #(c2_first_lines, c2_others) = case c2 {
            [T(..) as first, ..rest] -> #(first.lines, rest)
            _ -> #([], c2)
          }
          let any_space_or_newline =
            list.any(whitespace, fn(w) {
              let assert T(_, lines) = w
              case lines {
                [] -> panic
                [one] -> one.content != ""
                _ -> True
              }
            })
          let whitespace = case any_space_or_newline {
            True -> [[Line(authoring.blame(name, 185), " ")]]
            False -> []
          }
          let all_lists =
            list.flatten([[c1_last_lines], whitespace, [c2_first_lines]])
            |> list.filter(fn(x) { x != [] })
          let bridge_lines = case all_lists {
            [] -> []
            _ -> core.last_to_first_concatenation_in_list_list_lines(all_lists)
          }
          let children = case bridge_lines {
            [] -> core.pour(c1_others_reversed, c2_others)
            _ -> {
              let bridge_child = T(authoring.blame(name, 198), bridge_lines)
              core.pour([bridge_child, ..c1_others_reversed], c2_others)
            }
          }
          accumulator(
            inner,
            already_processed,
            Some(V(..dude, children: children)),
            [],
            rest,
          )
        }
      }
    }
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  [
    testing.data(
      param: "b",
      source: "
                <> root
                  <> b
                    <>
                      'hello1'
                  <> b
                    <>
                      'hello2'
                ",
      expected: "
                <> root
                  <> b
                    <>
                      'hello1hello2'
                ",
    ),
    testing.data(
      param: "b",
      source: "
                <> root
                  <> b
                    <>
                      'hello1'
                  <>
                    ''
                  <> b
                    <>
                      'hello2'
                ",
      expected: "
                <> root
                  <> b
                    <>
                      'hello1hello2'
                ",
    ),
    testing.data(
      param: "b",
      source: "
                <> root
                  <> b
                    <>
                      'hello1'
                  <>
                    ' '
                  <> b
                    <>
                      'hello2'
                ",
      expected: "
                <> root
                  <> b
                    <>
                      'hello1 hello2'
                ",
    ),
    testing.data(
      param: "b",
      source: "
                <> root
                  <> b
                    <>
                      'hello1'
                      'hello2'
                  <>
                    ''
                    ''
                  <> b
                    <>
                      'hello3'
                      'hello4'
                ",
      expected: "
                <> root
                  <> b
                    <>
                      'hello1'
                      'hello2 hello3'
                      'hello4'
                ",
    ),
    testing.data(
      param: "b",
      source: "
                <> root
                  <> b
                    <>
                      'hello1'
                      'hello2'
                    <> i
                      <>
                        'hey1'
                  <>
                    ''
                    ''
                  <> b
                    <> i
                      <>
                        'hey2'
                    <>
                      'hello3'
                      'hello4'
                ",
      expected: "
                <> root
                  <> b
                    <>
                      'hello1'
                      'hello2'
                    <> i
                      <>
                        'hey1'
                    <>
                      ' '
                    <> i
                      <>
                        'hey2'
                    <>
                      'hello3'
                      'hello4'
                ",
    ),
    testing.data(
      param: "b",
      source: "
                <> root
                  <> b
                    <>
                      'hello1'
                      'hello2'
                  <>
                    ''
                    'caramel'
                  <> b
                    <>
                      'hello3'
                      'hello4'
                ",
      expected: "
                <> root
                  <> b
                    <>
                      'hello1'
                      'hello2'
                  <>
                    ''
                    'caramel'
                  <> b
                    <>
                      'hello3'
                      'hello4'
                ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
