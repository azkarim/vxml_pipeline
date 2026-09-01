import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import vxml.{type VXML, T, V}

pub const name = "fold_children_into_text_if"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Replaces matching elements satisfying the predicate with
/// their children, joining boundary text nodes.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  #(
    // Element tag whose children may be folded.
    String,
    // Additional condition applied to the element.
    fn(VXML) -> Bool,
  )

type InnerParam {
  InnerParam(tag: String, condition: fn(VXML) -> Bool)
}

type TopOfStack {
  Nothing
  Hot(VXML)
  Cold(VXML)
}

type Stack =
  #(List(VXML), TopOfStack)

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(InnerParam(param.0, param.1))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNoErrorNodemap = nodemap(_, inner)
  nodemap |> n2t.one_to_one_no_error_nodemap_2_desugarer_transform
}

fn nodemap(node: VXML, inner: InnerParam) -> VXML {
  case node {
    V(_, _, _, children) -> {
      let children = accumulator(inner, #([], Nothing), children)
      V(..node, children: children)
    }
    _ -> node
  }
}

fn accumulator(
  inner: InnerParam,
  stack: Stack,
  remaining: List(VXML),
) -> List(VXML) {
  case remaining {
    [] ->
      case stack {
        #(previous, Nothing) -> previous |> list.reverse
        #(previous, Hot(t)) -> [t, ..previous] |> list.reverse
        #(previous, Cold(t)) -> [t, ..previous] |> list.reverse
      }
    [T(..) as first, ..rest] -> {
      let stack = smash_cold_t(stack, first)
      accumulator(inner, stack, rest)
    }
    [V(_, tag, _, children) as first, ..rest] -> {
      case tag == inner.tag && inner.condition(first) {
        False -> {
          let stack = smash_cold_v(stack, first)
          accumulator(inner, stack, rest)
        }
        True -> {
          let stack = smash_hot(stack, children)
          accumulator(inner, stack, rest)
        }
      }
    }
  }
}

fn smash_cold_t(stack: Stack, smashee: VXML) -> Stack {
  let assert T(..) = smashee
  let #(previous, t) = stack
  case t {
    Hot(t) -> {
      let smashee = core.t_t_last_to_first_concatenation(t, smashee)
      #(previous, Cold(smashee))
    }
    Cold(t) -> #([t, ..previous], Cold(smashee))
    Nothing -> #(previous, Cold(smashee))
  }
}

fn smash_cold_v(stack: Stack, smashee: VXML) -> Stack {
  let assert V(..) = smashee
  let #(previous, t) = stack
  case t {
    Hot(t) | Cold(t) -> #([smashee, t, ..previous], Nothing)
    Nothing -> #([smashee, ..previous], Nothing)
  }
}

fn smash_hot(stack: Stack, smashees: List(VXML)) -> Stack {
  let #(previous, t) = stack
  let #(previous, t) = case t, smashees {
    Hot(t), [T(..) as first, ..rest] | Cold(t), [T(..) as first, ..rest] -> {
      let t = core.t_t_last_to_first_concatenation(t, first)
      case rest {
        [] -> #(previous, t)
        _ -> core.pour_but_last(rest, [t, ..previous])
      }
    }
    Hot(t), _ | Cold(t), _ -> core.pour_but_last(smashees, [t, ..previous])
    Nothing, _ -> core.pour_but_last(smashees, previous)
  }
  case t {
    T(..) -> #(previous, Hot(t))
    _ -> #([t, ..previous], Nothing)
  }
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  testing.collection(name, assertive_tests_data(), constructor)
}
