/**
 * Advanced TypeScript type puzzles — exercises generics, conditional types,
 * mapped types, template literal types, and type-level operators.
 */

/** Intersection type. */
export type Styled = { color: string } & { size: number };

/** Conditional type with infer. */
export type UnwrapPromise<T> = T extends Promise<infer U> ? U : T;

/** Mapped type with keyof. */
export type ReadonlyDeep<T> = {
  readonly [K in keyof T]: T[K];
};

/** Mapped type with modifier removal. */
export type RequiredAll<T> = {
  [K in keyof T]-?: T[K];
};

/** Generic constraint with extends. */
export interface Repository<T extends { id: string }> {
  findById(id: string): T | undefined;
  findAll(): T[];
}

/** Nested generics, defaults, and union. */
export type Result<T, E = Error> =
  | { ok: true; value: T }
  | { ok: false; error: E };

/** Function with complex generic constraints. */
export function merge<A extends object, B extends object>(a: A, b: B): A & B {
  return { ...a, ...b } as A & B;
}

/** Template literal type. */
export type EventName = `on${Capitalize<string>}`;

/** typeof in type position. */
export const ROLES = ["admin", "editor", "viewer"] as const;
export type RoleType = typeof ROLES[number];

/** satisfies usage. */
export const config = {
  host: "localhost",
  port: 3000,
} satisfies Record<string, unknown>;

/** Generic class with generic methods. */
export class Container<T> {
  private items: T[];

  constructor() {
    this.items = [];
  }

  add(item: T): void {
    this.items.push(item);
  }

  map<U>(fn: (item: T) => U): Container<U> {
    const result = new Container<U>();
    for (const item of this.items) {
      result.add(fn(item));
    }
    return result;
  }

  filter(pred: (item: T) => boolean): T[] {
    return this.items.filter(pred);
  }
}

/** Abstract class with generic. */
export abstract class BaseRepo<T extends { id: string }> {
  protected items: Map<string, T>;

  constructor() {
    this.items = new Map();
  }

  abstract validate(item: T): boolean;

  findById(id: string): T | undefined {
    return this.items.get(id);
  }

  save(item: T): void {
    this.items.set(item.id, item);
  }
}

/** Discriminated union. */
export type Shape =
  | { kind: "circle"; radius: number }
  | { kind: "rect"; width: number; height: number }
  | { kind: "triangle"; base: number; height: number };

/** Overloaded function signatures. */
export function parse(input: string): number;
export function parse(input: number): string;
export function parse(input: string | number): string | number {
  return typeof input === "string" ? parseInt(input) : input.toString();
}
