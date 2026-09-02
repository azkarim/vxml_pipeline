import gleam/list
import gleeunit/should
import vxml
import vxml_pipeline/core.{type Desugarer, Desugarer}
import vxml_pipeline/desugarers as ds

pub fn main() {
  complete_handle_lifecycle_test()
}

fn apply(vxml: vxml.VXML, desugarer: Desugarer) -> vxml.VXML {
  let Desugarer(transform:, ..) = desugarer
  let assert Ok(#(vxml, _warnings)) = transform(vxml)
  vxml
}

fn complete_handle_lifecycle_test() {
  let assert Ok([source]) =
    vxml.parse_string(
      "<> root
  path=chapter.html
  <> MathBlock
    <>
      'x=y eq:identity##<<>>##'
  <> p
    <>
      'See >>eq:identity'",
      "writerly_handles_integration_test.vxml",
      True,
    )

  let result =
    [
      ds.writerly_handles_materialize_mathjax_tags(#("MathBlock", "Equation 1")),
      ds.writerly_handles_generate_v_definitions_from_t_definitions(),
      ds.writerly_handles_add_ids(),
      ds.writerly_handles_grand_wrapper_generate_dictionary("path"),
      ds.writerly_handles_grand_wrapper_substitute(
        #("path", "a", "a", [], [], ["a"], ["Math", "MathBlock"]),
      ),
      ds.writerly_handles_grand_wrapper_warn_unused(["MathBlock"]),
      ds.writerly_handles_grand_wrapper_unwrap(),
    ]
    |> list.fold(source, apply)

  result
  |> vxml.vxml_to_string
  |> should.equal(Ok(
    "<> root
  path=chapter.html
  <> MathBlock
    id=_1_h.a.i_
    <>
      'x=y \\tag{Equation 1}'
  <> p
    <>
      'See '
    <> a
      href=#_1_h.a.i_
      <>
        'Equation 1'",
  ))
}
