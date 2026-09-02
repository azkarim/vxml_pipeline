import gleam/list
import vxml
import vxml_pipeline/core.{type Desugarer, Continue, Desugarer, DesugaringError}
import vxml_pipeline/desugarers as ds

pub fn main() {
  prepend_variants_validate_parameters()
  counters_substitute_validates_definitions_and_output_domains()
}

fn source(source: String) -> vxml.VXML {
  let assert Ok([vxml]) =
    vxml.parse_string(source, "counter_desugarers_test.vxml", True)
  vxml
}

fn error_message(desugarer: Desugarer, input: vxml.VXML) -> String {
  let Desugarer(transform:, ..) = desugarer
  let assert Error(DesugaringError(_, message)) = transform(input)
  message
}

fn prepend_variants_validate_parameters() {
  let input = source("<> root")

  assert error_message(
      ds.counters_prepend_incrementing_attribute(#(
        "bad tag",
        "Counter",
        Continue,
      )),
      input,
    )
    == "invalid target tag name 'bad tag'"
  assert error_message(
      ds.counters_prepend_incrementing_attribute(#("Item", "bad-name", Continue)),
      input,
    )
    == "counter name must contain only ASCII letters; found 'bad-name'"

  assert error_message(
      ds.counters_prepend_incrementing_attribute__outside(
        #("Item", "Counter", Continue),
        ["bad tag"],
      ),
      input,
    )
    == "invalid outside tag name 'bad tag'"
  assert error_message(
      ds.counters_prepend_incrementing_attribute__outside(
        #("bad tag", "Counter", Continue),
        [],
      ),
      input,
    )
    == "invalid target tag name 'bad tag'"
  assert error_message(
      ds.counters_prepend_incrementing_attribute__outside(
        #("Item", "bad-name", Continue),
        [],
      ),
      input,
    )
    == "counter name must contain only ASCII letters; found 'bad-name'"

  assert error_message(
      ds.counters_prepend_incrementing_attribute_if_fancy(#(
        "Item",
        "bad-name",
        fn(_, _, _, _, _) { True },
        Continue,
      )),
      input,
    )
    == "counter name must contain only ASCII letters; found 'bad-name'"
  assert error_message(
      ds.counters_prepend_incrementing_attribute_if_fancy(#(
        "bad tag",
        "Counter",
        fn(_, _, _, _, _) { True },
        Continue,
      )),
      input,
    )
    == "invalid target tag name 'bad tag'"
}

fn counters_substitute_validates_definitions_and_output_domains() {
  assert error_message(
      ds.counters_substitute(),
      source("<> root\n  counter=bad-name\n  <>\n    '::++bad-name'"),
    )
    == "counter name must contain only ASCII letters; found 'bad-name'"

  assert error_message(
      ds.counters_substitute(),
      source("<> root\n  counter=Counter_2"),
    )
    == "counter name must contain only ASCII letters; found 'Counter_2'"

  assert error_message(ds.counters_substitute(), source("<> root\n  counter="))
    == "counter must have a name"

  assert error_message(
      ds.counters_substitute(),
      source("<> root\n  counter=Counter start"),
    )
    == "counter starting value must be a number"

  assert error_message(
      ds.counters_substitute(),
      source("<> root\n  counter=Counter 0 step"),
    )
    == "counter step size must be a number"

  assert error_message(
      ds.counters_substitute(),
      source("<> root\n  counter=Counter 0 1 extra"),
    )
    == "extra arguments found after <counter_name> <starting_value> <step_value>"

  assert error_message(
      ds.counters_substitute(),
      source("<> root\n  <>\n    '::++Missing'"),
    )
    == "undefined counter: Missing"

  ["::++", "::--", "::øø", "..++", "..--", "..øø"]
  |> list.each(fn(expression) {
    assert error_message(
        ds.counters_substitute(),
        source("<> root\n  <>\n    '" <> expression <> "'"),
      )
      == "counter expression must have a name"
  })

  assert error_message(
      ds.counters_substitute(),
      source("<> root\n  counter-uppercase=Letters\n  <>\n    '::øøLetters'"),
    )
    == "alphabetic counters require a positive value; found 0"

  assert error_message(
      ds.counters_substitute(),
      source("<> root\n  counter-roman-lowercase=Roman\n  <>\n    '::øøRoman'"),
    )
    == "Roman counters cannot render value 0"

  assert error_message(
      ds.counters_substitute(),
      source("<> root\n  counter-unary=Marks * -1\n  <>\n    '::øøMarks'"),
    )
    == "unary counters cannot render negative values"
}
