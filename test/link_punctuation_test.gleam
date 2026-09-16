import gleam/list
import vxml.{type VXML, Attr, Line, T, V}
import vxml/blame as bl
import vxml_pipeline/core.{type Desugarer}
import vxml_pipeline/desugarers as ds
import vxml_pipeline/link_tokenization

fn text(content: String) -> VXML {
  T(bl.no_blame, [Line(bl.no_blame, content)])
}

fn link(children: List(VXML)) -> VXML {
  V(
    bl.no_blame,
    "a",
    [
      Attr(bl.no_blame, "href", "chapter.html#equation"),
      Attr(bl.no_blame, "class", "reference"),
      Attr(bl.no_blame, "data-extra", "preserved"),
    ],
    children,
  )
}

fn root(children: List(VXML)) -> VXML {
  V(bl.no_blame, "p", [], children)
}

fn run(input: VXML, steps: List(Desugarer)) -> VXML {
  list.fold(steps, input, fn(tree, step) {
    let assert Ok(#(tree, [])) = step.transform(tree)
    tree
  })
}

fn same(actual: VXML, expected: VXML) {
  let assert Ok(actual) = vxml.vxml_to_string(actual)
  let assert Ok(expected) = vxml.vxml_to_string(expected)
  assert actual == expected
}

pub fn main() {
  // Punctuation on either side of words stays in its original order.
  assert link_tokenization.literal_tokens("don't—well-known).")
    == ["don", "'", "t", "—", "well", "-", "known", ")", "."]
  let punctuation = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~«»‘’“”–—…〈〉【】！？"
  let content = "word" <> punctuation <> "end  don't well-known\tend"
  let input =
    root([
      text(content),
      link([text(content)]),
      T(bl.no_blame, [Line(bl.no_blame, ""), Line(bl.no_blame, content)]),
    ])
  same(
    run(input, [
      ds.tokenize_href_surroundings(),
      ds.detokenize_href_surroundings(),
    ]),
    input,
  )
  same(
    run(input, [
      ds.rearrange_links__batch([
        #("absent <a href=0>_0_</a>", "<a href=0>absent _0_</a>"),
      ]),
    ]),
    input,
  )

  let pairs = [#("(<a href=0>_0_</a>)", "<a href=0>(_0_)</a>")]
  list.each(
    [".", ",", ";", ":", "!", "?", ").", "));", "—next", "…", "next", ""],
    fn(suffix) {
      let input = root([text("see ("), link([text("1")]), text(")" <> suffix)])
      let expected = root([text("see "), link([text("(1)")]), text(suffix)])
      same(run(input, [ds.rearrange_links__batch(pairs)]), expected)
      same(
        run(input, [
          ds.tokenize_href_surroundings(),
          ds.rearrange_links_4_pre_tokenized_src__batch(pairs),
          ds.detokenize_href_surroundings(),
        ]),
        expected,
      )
    },
  )

  // Nested delimiters move exactly one pair; rich link children survive.
  let bold = V(bl.no_blame, "b", [], [text("1")])
  let input = root([text("see (("), link([bold]), text(")).")])
  let expected =
    root([text("see ("), link([text("("), bold, text(")")]), text(").")])
  same(run(input, [ds.rearrange_links__batch(pairs)]), expected)
  same(
    run(input, [
      ds.tokenize_href_surroundings(),
      ds.rearrange_links_4_pre_tokenized_src__batch(pairs),
      ds.detokenize_href_surroundings(),
    ]),
    expected,
  )

  // Pattern literals and input text use identical boundaries, including
  // punctuation adjacent to a placeholder. Existing suffix rules still parse.
  let input = root([text("See (Theorem "), link([text("2.1")]), text(").")])
  let pairs = [
    #("(Theorem <a href=0>_0_</a>).", "<a href=0>(Theorem _0_)</a>."),
  ]
  let expected = root([text("See "), link([text("(Theorem 2.1)")]), text(".")])
  same(run(input, [ds.rearrange_links__batch(pairs)]), expected)
  same(
    run(input, [
      ds.tokenize_href_surroundings(),
      ds.rearrange_links_4_pre_tokenized_src__batch(pairs),
      ds.detokenize_href_surroundings(),
    ]),
    expected,
  )
}
