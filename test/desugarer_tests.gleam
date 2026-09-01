import argv
import gleam/io
import vxml_pipeline/desugarers
import vxml_pipeline/testing

pub fn main() {
  io.println("")
  let args = argv.load().arguments
  case testing.test_desugarers(desugarers.assertive_tests, args) {
    Ok(Nil) -> Nil
    Error(message) -> panic as message
  }
}
