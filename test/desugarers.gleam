import argv
import desugaring/desugarers
import desugaring/testing
import gleam/io

pub fn main() {
  io.println("")
  let args = argv.load().arguments
  case testing.test_desugarers(desugarers.assertive_tests, args) {
    Ok(Nil) -> Nil
    Error(message) -> panic as message
  }
}
