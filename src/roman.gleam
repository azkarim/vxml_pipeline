import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string

@internal
pub type Numeral {
  I
  V
  X
  L
  C
  D
  M
}

fn numeral_value(numeral: Numeral) -> Int {
  case numeral {
    I -> 1
    V -> 5
    X -> 10
    L -> 50
    C -> 100
    D -> 500
    M -> 1000
  }
}

fn numeral_to_str(numeral: Numeral) -> String {
  case numeral {
    I -> "i"
    V -> "v"
    X -> "x"
    L -> "l"
    C -> "c"
    D -> "d"
    M -> "m"
  }
}

fn numeral_from_str(str: String) -> Option(Numeral) {
  case str {
    "i" -> Some(I)
    "v" -> Some(V)
    "x" -> Some(X)
    "l" -> Some(L)
    "c" -> Some(C)
    "d" -> Some(D)
    "m" -> Some(M)
    _ -> None
  }
}

@internal
pub type Roman =
  List(Numeral)

fn string_to_roman_recursive(chars: List(String)) -> Option(Roman) {
  case chars {
    [] -> Some([])
    [first, ..rest] -> {
      case numeral_from_str(first), string_to_roman_recursive(rest) {
        Some(num), Some(rest) -> Some([num, ..rest])
        _, _ -> None
      }
    }
  }
}

@internal
pub fn string_to_roman(input: String) -> Option(Roman) {
  let chars = string.split(input, "")
  string_to_roman_recursive(chars)
}

fn roman_to_int_recursive(
  reversed_values: List(Int),
  max: Int,
  total: Int,
) -> Int {
  case reversed_values {
    [] -> total
    [first, ..rest] -> {
      case first >= max {
        True -> {
          roman_to_int_recursive(rest, first, total + first)
        }
        False -> {
          roman_to_int_recursive(rest, max, total - first)
        }
      }
    }
  }
}

/// Converts roman ( list of numerals ) to int value
@internal
pub fn roman_to_int(roman: Roman) -> Int {
  roman
  |> list.map(fn(x) { numeral_value(x) })
  |> list.reverse()
  |> roman_to_int_recursive(0, 0)
}

fn append_primary(
  val: Int,
  primary: Numeral,
  numerals: List(Numeral),
) -> #(Int, List(Numeral)) {
  let primary_val = primary |> numeral_value()
  case val >= primary_val {
    True -> {
      let new_val = val - primary_val
      append_primary(new_val, primary, list.append(numerals, [primary]))
    }
    False -> #(val, numerals)
  }
}

fn loop_mappings(
  val: Int,
  mappings: List(#(Numeral, Numeral)),
  numerals: List(Numeral),
) -> #(Int, List(Numeral)) {
  case mappings {
    [] -> #(val, numerals)
    [#(secondary, primary), ..rest] -> {
      let #(new_val, numerals) = append_primary(val, primary, numerals)
      let diff = numeral_value(primary) - numeral_value(secondary)
      case val >= diff {
        True -> {
          let new_val = new_val - diff
          let numerals = list.append(numerals, [secondary, primary])
          loop_mappings(new_val, rest, numerals)
        }
        False -> loop_mappings(new_val, rest, numerals)
      }
    }
  }
}

fn dec_until_zero(val: Int, numerals: List(Numeral)) -> #(Int, List(Numeral)) {
  case val > 0 {
    True -> {
      dec_until_zero(val - 1, list.append(numerals, [I]))
    }
    False -> #(val, numerals)
  }
}

/// Converts int to roman ( list of numerals )
@internal
pub fn int_to_roman(val: Int) -> Option(Roman) {
  case int.compare(val, 0) {
    order.Gt -> {
      let mappings = [#(C, M), #(C, D), #(X, C), #(X, L), #(I, X), #(I, V)]
      let #(new_val, numerals) = loop_mappings(val, mappings, [])

      let #(_, numerals) = dec_until_zero(new_val, numerals)

      Some(numerals)
    }
    _ -> None
  }
}

@internal
pub fn roman_to_string(numerals: Roman) -> String {
  case numerals {
    [] -> ""
    [first, ..rest] -> {
      numeral_to_str(first) <> roman_to_string(rest)
    }
  }
}
