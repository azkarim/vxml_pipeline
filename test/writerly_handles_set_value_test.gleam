import vxml
import vxml_pipeline/core.{type Desugarer, Continue, Desugarer, DesugaringError}
import vxml_pipeline/desugarers as ds

pub fn main() {
  all_value_setters_reject_malformed_handle_attributes()
}

fn source() {
  let assert Ok(source) =
    vxml.string_to_vxml(
      "<> root\n  <> Target\n    handle=invalid/name",
      "writerly_handles_set_value_test.vxml",
    )
  source
}

fn assert_malformed(desugarer: Desugarer) {
  let Desugarer(transform:, ..) = desugarer
  let assert Error(DesugaringError(_, message)) = transform(source())
  assert message
    == "handle attr must have form <name> or <name> <<value>>; found: “invalid/name”"
}

fn all_value_setters_reject_malformed_handle_attributes() {
  assert_malformed(
    ds.writerly_handles_set_value(#("Target", "value", Continue)),
  )
  assert_malformed(
    ds.writerly_handles_set_value__outside(#("Target", "value", Continue), []),
  )
  assert_malformed(
    ds.writerly_handles_set_value_if_has_ancestor_else(#(
      "Target",
      "Ancestor",
      "inside",
      "outside",
    )),
  )
}
