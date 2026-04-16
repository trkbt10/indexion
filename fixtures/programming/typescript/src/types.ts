/** Common types for the user service. */

/** Unique identifier for a user. */
export type UserId = string;

/** Represents a user in the system. */
export interface User {
  id: UserId;
  name: string;
  email: string;
  role: UserRole;
  tags?: string[];
}

/** Role assigned to a user. */
export enum UserRole {
  Admin = "admin",
  Editor = "editor",
  Viewer = "viewer",
}

/** Options for querying users. */
export interface QueryOptions {
  limit?: number;
  offset?: number;
  role?: UserRole;
}

/** Result wrapper for paginated queries. */
export interface PagedResult<T> {
  items: T[];
  total: number;
  hasMore: boolean;
}

/** Event types emitted by the service. */
export type ServiceEvent =
  | { kind: "created"; user: User }
  | { kind: "deleted"; id: UserId };
