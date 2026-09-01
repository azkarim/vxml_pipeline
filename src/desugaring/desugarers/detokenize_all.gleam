import desugaring/authoring
import desugaring/core.{type Desugarer, type DesugarerTransform}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type Line, type VXML, Attr, Line, T, V}
import vxml/blame.{type Blame}

pub const name = "detokenize_all"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Reconstructs text nodes from all token-marker element
/// sequences.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(),
  )
}

fn inner_param_to_transform() -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap
  nodemap
  |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform()
}

fn nodemap(vxml: VXML) -> VXML {
  case vxml {
    V(_, _, _, children) -> {
      let children = detokenize_in_list(children, [], [])
      V(..vxml, children: children)
    }
    _ -> vxml
  }
}

fn detokenize_in_list(
  children: List(VXML),
  accumulated_lines: List(Line),
  accumulated_nodes: List(VXML),
) -> List(VXML) {
  let append_word_to_accumlated_contents = fn(blame: Blame, word: String) -> List(
    Line,
  ) {
    case accumulated_lines {
      [first, ..rest] -> [Line(first.blame, first.content <> word), ..rest]
      _ -> [Line(blame, word)]
    }
  }

  case children {
    [] -> {
      let assert [] = accumulated_lines
      accumulated_nodes |> list.reverse |> core.last_to_first_concatenation
    }

    [first, ..rest] -> {
      case first {
        V(blame, "__StartTokenizedT", _, _) -> {
          let assert [] = accumulated_lines
          let accumulated_lines = [Line(blame, "")]
          detokenize_in_list(rest, accumulated_lines, accumulated_nodes)
        }

        V(blame, "__OneWord", attrs, _) -> {
          let assert [_, ..] = accumulated_lines
          let assert [Attr(_, "val", word)] = attrs
          let accumulated_lines =
            append_word_to_accumlated_contents(blame, word)
          detokenize_in_list(rest, accumulated_lines, accumulated_nodes)
        }

        V(blame, "__OneSpace", _, _) -> {
          let assert [_, ..] = accumulated_lines
          let accumulated_lines = append_word_to_accumlated_contents(blame, " ")
          detokenize_in_list(rest, accumulated_lines, accumulated_nodes)
        }

        V(blame, "__OneNewLine", _, _) -> {
          let assert [_, ..] = accumulated_lines
          let accumulated_lines = [Line(blame, ""), ..accumulated_lines]
          detokenize_in_list(rest, accumulated_lines, accumulated_nodes)
        }

        V(blame, "__EndTokenizedT", _, _) -> {
          let assert [_, ..] = accumulated_lines
          let accumulated_lines = append_word_to_accumlated_contents(blame, "")
          detokenize_in_list(rest, [], [
            T(blame, accumulated_lines |> list.reverse),
            ..accumulated_nodes
          ])
        }

        _ -> {
          let assert [] = accumulated_lines
          detokenize_in_list(rest, [], [first, ..accumulated_nodes])
        }
      }
    }
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataNoParam) {
  [
    testing.data_no_param(
      source: "
                <> testing
                  <> bb
                    <> __StartTokenizedT
                    <> __OneWord
                      val=first
                    <> __OneSpace
                    <> __OneWord
                      val=line
                    <> __OneNewLine
                    <> __OneWord
                      val=second
                    <> __OneSpace
                    <> __OneWord
                      val=line
                    <> __EndTokenizedT
                    <> inside
                      <>
                        'some text'
      ",
      expected: "
                <> testing
                  <> bb
                    <>
                      'first line'
                      'second line'

                    <> inside
                      <>
                        'some text'
      ",
    ),
    testing.data_no_param(
      source: "
                <> testing
                  <> bb
                    <> __StartTokenizedT
                    <> __OneWord
                      val=first
                    <> __OneSpace
                    <> __OneSpace
                    <> __OneWord
                      val=line
                    <> __EndTokenizedT
      ",
      expected: "
                <> testing
                  <> bb
                    <>
                      'first  line'
      ",
    ),
    testing.data_no_param(
      source: "
                <> testing
                  <> bb
                    <> __StartTokenizedT
                    <> __OneWord
                      val=first
                    <> __OneSpace
                    <> __OneNewLine
                    <> __OneSpace
                    <> __OneWord
                      val=line
                    <> __EndTokenizedT
      ",
      expected: "
                <> testing
                  <> bb
                    <>
                      'first '
                      ' line'
      ",
    ),
    testing.data_no_param(
      source: "
                <> testing
                  <> bb
                    <> __StartTokenizedT
                    <> __OneWord
                      val=
                    <> __OneNewLine
                    <> __OneWord
                      val=
                    <> __EndTokenizedT
      ",
      expected: "
                <> testing
                  <> bb
                    <>
                      ''
                      ''
      ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_no_param(name, assertive_tests_data(), constructor)
}
