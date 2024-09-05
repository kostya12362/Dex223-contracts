import { Addressable } from "ethers";

export function compareToken(a: { target: string | Addressable }, b: { target: string | Addressable }): -1 | 1 {
  return a.target.toString().toLowerCase() < b.target.toString().toLowerCase() ? -1 : 1
}

export function sortedTokens(
  a: { target: string | Addressable },
  b: { target: string | Addressable }
): [typeof a, typeof b] | [typeof b, typeof a] {
  return compareToken(a, b) < 0 ? [a, b] : [b, a]
}
