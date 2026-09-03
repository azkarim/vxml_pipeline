import gleam/string
import vxml
import vxml_pipeline/core.{Desugarer, DesugaringError}
import vxml_pipeline/desugarers as ds

pub fn main() {
  rejects_missing_document_root()
  rejects_multiple_document_roots()
  rejects_an_unwrapped_document()
}

fn transform(source: String) {
  let assert Ok(source) =
    vxml.string_to_vxml(
      source,
      "writerly_handles_grand_wrapper_unwrap_test.vxml",
    )
  let Desugarer(transform:, ..) = ds.writerly_handles_grand_wrapper_unwrap()
  transform(source)
}

fn rejects_missing_document_root() {
  let assert Error(DesugaringError(_, message)) =
    transform("<> GrandWrapper\n  <> Handle")
  assert message == "GrandWrapper has no non-Handle root child"
}

fn rejects_multiple_document_roots() {
  let assert Error(DesugaringError(_, message)) =
    transform("<> GrandWrapper\n  <> first\n  <> second")
  assert string.contains(message, "2 non-Handle root children")
}

fn rejects_an_unwrapped_document() {
  let assert Error(DesugaringError(_, message)) = transform("<> root")
  assert message == "expected GrandWrapper at document root"
}
