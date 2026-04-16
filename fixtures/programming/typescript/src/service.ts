/**
 * User service — handles CRUD operations for users.
 */
import type { User, UserId, QueryOptions } from './types';
import { validateEmail, DEFAULT_PAGE_SIZE } from './utils';

/** In-memory user store. */
export class UserService {
  private users: Map<UserId, User>;

  constructor() {
    this.users = new Map();
  }

  /** Adds a new user after validating their email. */
  async addUser(user: User): Promise<void> {
    if (!validateEmail(user.email)) {
      throw new Error("Invalid email");
    }
    this.users.set(user.id, user);
  }

  /** Retrieves a user by ID. */
  getUser(id: UserId): User | undefined {
    return this.users.get(id);
  }

  /** Lists users with optional filtering. */
  listUsers(options?: QueryOptions): User[] {
    const limit = options?.limit ?? DEFAULT_PAGE_SIZE;
    const offset = options?.offset ?? 0;
    let result = Array.from(this.users.values());
    if (options?.role) {
      result = result.filter(u => u.role === options.role);
    }
    return result.slice(offset, offset + limit);
  }

  /** Deletes a user by ID. */
  deleteUser(id: UserId): boolean {
    return this.users.delete(id);
  }
}

/** Batch processor for user operations. */
export class BatchProcessor {
  static readonly MAX_BATCH_SIZE: number = 100;
  private readonly service: UserService;

  constructor(service: UserService) {
    this.service = service;
  }

  /** Process multiple users in one call. */
  async processAll(users: User[]): Promise<number> {
    let count = 0;
    for (const user of users) {
      await this.service.addUser(user);
      count++;
    }
    return count;
  }
}
