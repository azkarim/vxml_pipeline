import gleam/string
import vxml
import vxml_pipeline/core.{Desugarer, DesugaringError}
import vxml_pipeline/desugarers as ds

pub fn main() {
  rejects_missing_dictionary_fields()
  rejects_invalid_dictionary_names()
  rejects_invalid_dictionary_pages()
  rejects_invalid_dictionary_values()
  rejects_duplicate_dictionary_names()
}

fn transform(source: String) {
  let assert Ok([source]) =
    vxml.parse_string(
      source,
      "writerly_handles_grand_wrapper_substitute_test.vxml",
      True,
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
  assert_malformed(handle("    name=example"), "expected name, page, value")
}

fn rejects_invalid_dictionary_names() {
  assert_malformed(
    handle(
      "    name=invalid/name\n    page=false\n    value=<<value>>\n    id=id\n    path=page.html",
    ),
    "invalid name",
  )
}

fn rejects_invalid_dictionary_pages() {
  assert_malformed(
    handle(
      "    name=example\n    page=perhaps\n    value=<<value>>\n    id=id\n    path=page.html",
    ),
    "page must be",
  )
}

fn rejects_invalid_dictionary_values() {
  assert_malformed(
    handle(
      "    name=example\n    page=false\n    value=unwrapped\n    id=id\n    path=page.html",
    ),
    "value must have form",
  )
}

fn rejects_duplicate_dictionary_names() {
  assert_malformed(
    "<> GrandWrapper
  <> Handle
    name=example
    page=false
    value=<<one>>
    id=one
    path=page.html
  <> Handle
    name=example
    page=false
    value=<<two>>
    id=two
    path=page.html
  <> root
    path=page.html",
    "duplicate name",
  )
}
