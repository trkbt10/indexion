// Circular import test: index -> a -> b -> a (circular)
export { processA } from './a';
export { processB } from './b';
