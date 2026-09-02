import command_line_parser_test
import counter_desugarers_test
import delimited_syntax_test
import desugarer_tests
import expand_emmet_like_attribute_test
import help_request_test
import line_wrap_test
import monitor_test
import public_facades_test
import renderer_integration_test
import tables_test
import tracking_display_test
import writerly_handles_grand_wrapper_generate_dictionary_test
import writerly_handles_grand_wrapper_substitute_test
import writerly_handles_integration_test
import writerly_handles_set_value_test

pub fn main() {
  command_line_parser_test.main()
  counter_desugarers_test.main()
  delimited_syntax_test.main()
  desugarer_tests.main()
  expand_emmet_like_attribute_test.main()
  help_request_test.main()
  writerly_handles_grand_wrapper_generate_dictionary_test.main()
  writerly_handles_grand_wrapper_substitute_test.main()
  writerly_handles_integration_test.main()
  writerly_handles_set_value_test.main()
  line_wrap_test.main()
  monitor_test.main()
  public_facades_test.main()
  renderer_integration_test.main()
  tables_test.main()
  tracking_display_test.main()
}
