import gleam/string
import vxml
import vxml_pipeline/core.{Desugarer, DesugaringError}
import vxml_pipeline/desugarers as ds

pub fn main() {
  rejects_missing_dictionary_fields()
  rejects_invalid_dictionary_names()
  rejects_invalid_dictionary_values()
  rejects_duplicate_dictionary_names()
  page_decorator_links_to_the_page()
}

fn transform(source: String) {
  let assert Ok(source) =
    vxml.string_to_vxml(
      source,
      "writerly_handles_grand_wrapper_substitute_test.vxml",
    )
  let Desugarer(transform:, ..) =
    ds.writerly_handles_grand_wrapper_substitute(
      #("path", "a", "a", [], [], ["a"], ["Math", "MathBlock"]),
    )
  transform(source)
}

fn assert_malformed(source: String, detail: String) {
  let assert Error(DesugaringError(_, message)) = transform(source)
  assert string.contains(message, detail)
}

fn handle(attributes: String) -> String {
  "<> GrandWrapper\n  <> Handle\n"
  <> attributes
  <> "\n  <> root\n    path=page.html"
}

fn rejects_missing_dictionary_fields() {
  assert_malformed(
    handle("    name=example"),
    "expected name, decorators, value",
  )
}

fn rejects_invalid_dictionary_names() {
  assert_malformed(
    handle(
      "    name=invalid/name\n    decorators=\n    value=<<value>>\n    id=id\n    path=page.html",
    ),
    "invalid name",
  )
}

fn rejects_invalid_dictionary_values() {
  assert_malformed(
    handle(
      "    name=example\n    decorators=\n    value=unwrapped\n    id=id\n    path=page.html",
    ),
    "value must have form",
  )
}

fn rejects_duplicate_dictionary_names() {
  assert_malformed(
    "<> GrandWrapper
  <> Handle
    name=example
    decorators=
    value=<<one>>
    id=one
    path=page.html
  <> Handle
    name=example
    decorators=
    value=<<two>>
    id=two
    path=page.html
  <> root
    path=page.html",
    "duplicate name",
  )
}

fn page_decorator_links_to_the_page() {
  let assert Ok(#(output, _warnings)) =
    transform(
      "<> GrandWrapper
  <> Handle
    name=example
    decorators=#page
    value=<<Example>>
    id=example-id
    path=other.html
  <> root
    path=here.html
    <> p
      <>
        'See >>example'",
    )
  let assert Ok(serialized) = vxml.vxml_to_string(output)
  assert string.contains(serialized, "href=other.html")
  assert !string.contains(serialized, "href=other.html#example-id")
}
