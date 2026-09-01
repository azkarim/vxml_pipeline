import desugaring/authoring
import desugaring/core
import desugaring/testing
import vxml.{type VXML}
import vxml/blame.{Des}

const name = "client_identity"

fn transform(_: Nil) -> core.DesugarerTransform {
  fn(vxml: VXML) { Ok(#(vxml, [])) }
}

fn constructor(_: Nil) {
  authoring.desugarer(name:, param: Nil, prepare: Ok, transform:)
}

pub fn main() {
  let collection =
    testing.collection(
      name,
      [testing.data(Nil, "<> root", "<> root")],
      constructor,
    )
  let results = testing.run([collection])
  assert testing.all_passed(results)
  let assert Des([], desugarer_name, 12) = authoring.blame(name, 12)
  assert desugarer_name == name
}
