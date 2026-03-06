// Module A imports from B, which imports from A (circular)
import { helperB } from './b';

export function processA(x: number): number {
  return helperB(x) + 1;
}

export function helperA(x: number): number {
  return x * 2;
}
