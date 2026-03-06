// Module B imports from A, creating a circular dependency
import { helperA } from './a';

export function processB(x: number): number {
  return helperA(x) - 1;
}

export function helperB(x: number): number {
  return x / 2;
}
