import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError, DesugaringError,
}
import desugaring/nodemaps_2_transform as n2t
import desugaring/testing
import gleam/list
import gleam/string.{inspect as ins}
import on
import vxml.{type VXML, T, V}

pub const name = "fold_contents_into_text__batch"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Replaces elements with configured tags by their sole text
/// child, joining it to adjacent text nodes.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  List(String)

type InnerParam =
  Param

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param)
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  let nodemap: n2t.OneToOneNodemap = nodemap(_, inner)
  nodemap |> n2t.one_to_one_nodemap_2_desugarer_transform
}

type TopOfStack {
  Nothing
  Hot(VXML)
  Cold(VXML)
}

type Stack =
  #(List(VXML), TopOfStack)

fn nodemap(node: VXML, inner: InnerParam) -> Result(VXML, DesugaringError) {
  case node {
    V(_, _, _, children) -> {
      use children <- on.ok(accumulator(inner, #([], Nothing), children))
      Ok(V(..node, children: children))
    }
    _ -> Ok(node)
  }
}

fn accumulator(
  inner: InnerParam,
  stack: Stack,
  remaining: List(VXML),
) -> Result(List(VXML), DesugaringError) {
  case remaining {
    [] ->
      case stack {
        #(previous, Nothing) -> previous |> list.reverse |> Ok
        #(previous, Hot(t)) -> [t, ..previous] |> list.reverse |> Ok
        #(previous, Cold(t)) -> [t, ..previous] |> list.reverse |> Ok
      }
    [T(..) as first, ..rest] -> {
      let stack = smash_cold_t(stack, first)
      accumulator(inner, stack, rest)
    }
    [V(_, tag, _, children) as first, ..rest] -> {
      case list.contains(inner, tag) {
        False -> {
          let stack = smash_cold_v(stack, first)
          accumulator(inner, stack, rest)
        }
        True -> {
          use t <- on.ok(case children {
            [T(..) as one] -> Ok(one)
            _ ->
              Error(DesugaringError(
                first.blame,
                "found "
                  <> ins(list.length(children))
                  <> " ≠ 1 child or non-T nodes",
              ))
          })
          let stack = smash_hot_t(stack, t)
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

fn smash_hot_t(stack: Stack, smashee: VXML) -> Stack {
  let assert T(..) = smashee
  let #(previous, t) = stack
  case t {
    Hot(t) | Cold(t) -> {
      let smashee = core.t_t_last_to_first_concatenation(t, smashee)
      #(previous, Hot(smashee))
    }
    Nothing -> #(previous, Hot(smashee))
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
