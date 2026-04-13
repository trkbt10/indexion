/**
 * @file Public exports for @indexion/wiki components.
 *
 * Consumers (e.g. vscode-plugin) import from "@indexion/wiki/components"
 * to reuse wiki rendering without pulling in the full SPA router/layout.
 */

export { WikiContent } from "./client/pages/wiki/components/wiki-content.tsx";
export {
  WikiContentEnvProvider,
  useWikiContentEnv,
  type WikiContentEnv,
} from "./client/pages/wiki/components/wiki-content-context.tsx";
