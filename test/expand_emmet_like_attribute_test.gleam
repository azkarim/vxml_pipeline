import gleam/string
import vxml
import vxml_pipeline/core.{Desugarer, DesugaringError}
import vxml_pipeline/desugarers as ds

pub fn main() {
  rejects_empty_shorthand_attribute_keys()
  rejects_invalid_shorthand_attribute_key()
  rejects_invalid_leading_value_attribute_key()
}

fn source() {
  let assert Ok(source) =
    vxml.string_to_vxml("<> root", "expand_emmet_like_attribute_test.vxml")
  source
}

fn assert_param_error(
  param: #(List(String), List(String), String),
  expected: String,
) {
  let Desugarer(transform:, ..) = ds.expand_emmet_like_attribute(param)
  let assert Error(DesugaringError(_, message)) = transform(source())
  assert string.contains(message, expected)
}

fn rejects_empty_shorthand_attribute_keys() {
  assert_param_error(#([], [], "language"), "cannot be empty")
}

fn rejects_invalid_shorthand_attribute_key() {
  assert_param_error(
    #([], ["invalid key"], "language"),
    "invalid VXML attribute key: 'invalid key'",
  )
}

fn rejects_invalid_leading_value_attribute_key() {
  assert_param_error(
    #([], ["info"], "invalid key"),
    "invalid VXML attribute key: 'invalid key'",
  )
}
