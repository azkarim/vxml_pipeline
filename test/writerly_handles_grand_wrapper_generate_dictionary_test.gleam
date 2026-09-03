import gleam/string
import vxml
import vxml_pipeline/core.{Desugarer, DesugaringError}
import vxml_pipeline/desugarers as ds

pub fn main() {
  rejects_unwrapped_handle_value()
  rejects_invalid_handle_name()
}

fn rejects_unwrapped_handle_value() {
  let assert Ok(source) =
    vxml.string_to_vxml(
      "<> root
  path=./chapter.html
  <> Section
    handle=section:name unwrapped value
    id=section-id",
      "writerly_handles_grand_wrapper_generate_dictionary_test.vxml",
    )
  let Desugarer(transform:, ..) =
    ds.writerly_handles_grand_wrapper_generate_dictionary("path")
  let assert Error(DesugaringError(_, message)) = transform(source)
  assert string.contains(
    message,
    "handle attr must have form <name> or <name> <<value>>",
  )
}

fn rejects_invalid_handle_name() {
  let assert Ok(source) =
    vxml.string_to_vxml(
      "<> root
  path=./chapter.html
  <> Section
    handle=invalid/name <<value>>
    id=section-id",
      "writerly_handles_grand_wrapper_generate_dictionary_test.vxml",
    )
  let Desugarer(transform:, ..) =
    ds.writerly_handles_grand_wrapper_generate_dictionary("path")
  let assert Error(DesugaringError(_, message)) = transform(source)
  assert string.contains(
    message,
    "handle attr must have form <name> or <name> <<value>>",
  )
}
