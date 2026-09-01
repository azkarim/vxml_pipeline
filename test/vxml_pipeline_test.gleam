import command_line_parser_test
import delimited_syntax_test
import desugarers as desugarer_tests
import help_request_test
import line_wrap_test
import monitor_test
import public_facades_test
import renderer_integration_test
import tables_test
import tracking_display_test

pub fn main() {
  command_line_parser_test.main()
  delimited_syntax_test.main()
  desugarer_tests.main()
  help_request_test.main()
  line_wrap_test.main()
  monitor_test.main()
  public_facades_test.main()
  renderer_integration_test.main()
  tables_test.main()
  tracking_display_test.main()
}
