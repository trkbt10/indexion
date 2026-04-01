/**
 * @file Shared HttpClient instance for the wiki SPA.
 *
 * All pages import this instead of constructing URLs directly.
 * The base URL "/api" matches the dev-server proxy, production setup,
 * and static export (extensionless files at the same paths).
 */

import { createHttpClient } from "@indexion/api-client";

/** True when built with VITE_STATIC_MODE=true for static deployment. */
export const isStaticMode = import.meta.env.VITE_STATIC_MODE === "true";

export const client = createHttpClient("/api");
