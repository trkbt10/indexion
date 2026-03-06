import { merge, cloneDeep } from 'lodash';

export function deepMerge<T extends object>(target: T, source: Partial<T>): T {
  return merge(cloneDeep(target), source);
}

export function createId(): string {
  return Math.random().toString(36).slice(2);
}
