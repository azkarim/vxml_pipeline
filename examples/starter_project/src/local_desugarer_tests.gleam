import gleam/io
import local_desugarers
import vxml_pipeline/testing

pub fn main() {
  case testing.test_desugarers(local_desugarers.assertive_tests, []) {
    Ok(_) -> io.println("All local desugarer tests passed.")
    Error(error) -> io.println(error)
  }
}
