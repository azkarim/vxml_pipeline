import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/string
import on
import splitter as sp
import vxml.{type Line, type VXML, Line, T, V}
import vxml/blame.{type Blame} as bl

pub const name = "markdown_link_closing_handrolled_splitter__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Splits closing Markdown-link syntax into VXML outside
/// configured subtrees.
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
  String

type InnerParam =
  Param

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(
  inner: InnerParam,
  outside: List(String),
) -> DesugarerTransform {
  let nodemap: n2t.OneToManyNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.one_to_many_no_error_nodemap_2_desugarer_transform_with_forbidden(
    outside,
  )
}

fn nodemap(vxml: VXML, inner: InnerParam) -> List(VXML) {
  case vxml {
    V(_, _, _, _) -> [vxml]
    T(_, lines) ->
      lines
      |> list.flat_map(line_map(_, inner))
      |> core.plain_concatenation_in_list
  }
}

fn desugarer_blame(line_no: Int) {
  authoring.blame(name, line_no)
}

fn t_1_line(b: Blame, c: String) -> VXML {
  T(b, [Line(b, c)])
}

fn get_to_zero(
  current: Int,
  cumulated: String,
  remaining: String,
) -> Result(#(String, String), Nil) {
  use <- on.true_false(current == 0, fn() { Ok(#(cumulated, remaining)) })
  assert current > 0
  let splitter = sp.new([")", "("])
  let #(before, there, after) = sp.split(splitter, remaining)
  case there {
    "" -> Error(Nil)
    ")" -> get_to_zero(current - 1, cumulated <> before <> there, after)
    "(" -> get_to_zero(current + 1, cumulated <> before <> there, after)
    _ -> panic
  }
}

fn line_map(l: Line, inner: InnerParam) -> List(VXML) {
  let blame = l.blame
  let early_return = [T(blame, [l])]

  use #(before, original_after) <- on.error_ok(
    string.split_once(l.content, "]("),
    fn(_) { early_return },
  )

  use #(maybe_href, after) <- on.error_ok(
    string.split_once(original_after, ")"),
    fn(_) { early_return },
  )

  use _ <- on.ok_error(string.split_once(maybe_href, " "), fn(pair) {
    let #(href_bef, href_af) = pair
    let continue_with_bef = before <> "](" <> href_bef <> " "
    let continue_with_af = href_af <> ")" <> after
    let assert [first, ..rest] =
      line_map(
        Line(
          bl.advance(blame, string.length(continue_with_bef)),
          continue_with_af,
        ),
        inner,
      )
    case first {
      T(_, lines) -> {
        let assert [first, ..more] = lines
        [
          T(blame, [Line(blame, continue_with_bef <> first.content), ..more]),
          ..rest
        ]
      }
      V(..) -> [t_1_line(blame, continue_with_bef), ..rest]
    }
  })

  // try for cheap success:
  use <- on.false_true(string.contains(maybe_href, "("), fn() {
    [
      t_1_line(blame, before),
      V(
        bl.advance(blame, string.length(before) + 2),
        inner,
        [vxml.Attr(desugarer_blame(132), "href", maybe_href)],
        [],
      ),
      ..line_map(
        Line(
          bl.advance(
            blame,
            string.length(before) + string.length(maybe_href) + 3,
          ),
          after,
        ),
        inner,
      )
    ]
  })

  // do complete homework:
  case get_to_zero(1, "", original_after) {
    Ok(#(href, after)) -> {
      let href = string.drop_end(href, 1)
      [
        t_1_line(blame, before),
        V(
          bl.advance(blame, string.length(before) + 2),
          inner,
          [vxml.Attr(desugarer_blame(157), "href", href)],
          [],
        ),
        ..line_map(
          Line(
            bl.advance(blame, string.length(before) + string.length(href) + 3),
            after,
          ),
          inner,
        )
      ]
    }
    Error(_) -> {
      let continue_with_bef = before <> "]("
      let continue_with_af = original_after
      let assert [first, ..rest] =
        line_map(
          Line(
            bl.advance(blame, string.length(continue_with_bef)),
            continue_with_af,
          ),
          inner,
        )
      case first {
        T(_, lines) -> {
          let assert [first, ..more] = lines
          [
            T(blame, [Line(blame, continue_with_bef <> first.content), ..more]),
            ..rest
          ]
        }
        V(..) -> [t_1_line(blame, continue_with_bef), ..rest]
      }
    }
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
