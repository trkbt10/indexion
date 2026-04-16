/** Utility functions for validation and formatting. */

/**
 * Validates an email address.
 */
export function validateEmail(email: string): boolean {
  return email.includes("@") && email.includes(".");
}

/**
 * Formats a user's display name.
 */
export function formatDisplayName(name: string, role: string): string {
  return name + " (" + role + ")";
}

/** Generates a unique ID. */
export function generateId(): string {
  return Math.random().toString(36).substring(2);
}

/** Default page size for queries. */
export const DEFAULT_PAGE_SIZE: number = 20;

/** Maximum username length. */
export const MAX_NAME_LENGTH: number = 100;
