// Module D re-exports from C, creating another circular path
export { baseC as valueC } from './c';
export const valueD = 20;
