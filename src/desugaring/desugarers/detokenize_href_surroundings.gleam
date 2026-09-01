import desugaring/authoring
import desugaring/core.{type Desugarer, type DesugarerTransform}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type Line, type VXML, Attr, Line, T, V}
import vxml/blame.{type Blame}

pub const name = "detokenize_href_surroundings"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Reconstructs text nodes from token-marker sequences inside
/// link surroundings.
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
    T(_, _) -> vxml
    V(_, _, attrs, children) -> {
      case core.attrs_have_key(attrs, "had_href_child") {
        False -> vxml
        True -> {
          let attrs = list.filter(attrs, fn(x) { x.key != "had_href_child" })
          let children = detokenize_children(children, [], [])
          V(..vxml, attrs: attrs, children: children)
        }
      }
    }
  }
}

fn detokenize_children(
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
          detokenize_children(rest, accumulated_lines, accumulated_nodes)
        }

        V(blame, "__OneWord", attrs, _) -> {
          let assert [_, ..] = accumulated_lines
          let assert [Attr(_, "val", word)] = attrs
          let accumulated_lines =
            append_word_to_accumlated_contents(blame, word)
          detokenize_children(rest, accumulated_lines, accumulated_nodes)
        }

        V(blame, "__OneSpace", _, _) -> {
          let assert [_, ..] = accumulated_lines
          let accumulated_lines = append_word_to_accumlated_contents(blame, " ")
          detokenize_children(rest, accumulated_lines, accumulated_nodes)
        }

        V(blame, "__OneNewLine", _, _) -> {
          let assert [_, ..] = accumulated_lines
          let accumulated_lines = [Line(blame, ""), ..accumulated_lines]
          detokenize_children(rest, accumulated_lines, accumulated_nodes)
        }

        V(blame, "__EndTokenizedT", _, _) -> {
          let assert [_, ..] = accumulated_lines
          let accumulated_lines = append_word_to_accumlated_contents(blame, "")
          detokenize_children(rest, [], [
            T(blame, accumulated_lines |> list.reverse),
            ..accumulated_nodes
          ])
        }

        T(_, _) -> {
          let assert [] = accumulated_lines
          detokenize_children(rest, [], [first, ..accumulated_nodes])
        }

        V(_, _, attrs, children) -> {
          let assert [] = accumulated_lines
          case core.attrs_have_key(attrs, "href") {
            False -> detokenize_children(rest, [], [first, ..accumulated_nodes])
            True -> {
              let children = detokenize_children(children, [], [])
              detokenize_children(rest, [], [
                V(..first, children: children),
                ..accumulated_nodes
              ])
            }
          }
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
                  had_href_child=true
                  <> bb
                    href=qq
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
                    href=qq
                    <>
                      'first  line'
      ",
    ),
    testing.data_no_param(
      source: "
                <> testing
                  had_href_child=true
                  <> bb
                    href=qq
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
                    href=qq
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
                  had_href_child=true
                  <> bb
                    href=qq
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
                    href=qq
                    <>
                      'first '
                      ' line'
      ",
    ),
    testing.data_no_param(
      source: "
                <> testing
                  had_href_child=true
                  <> bb
                    href=z
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
                    href=z
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
