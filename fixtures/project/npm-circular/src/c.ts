// Module C: self-referential module (imports itself indirectly via re-export)
import { valueC } from './d';

export const baseC = 10;
export const computedC = valueC + baseC;
