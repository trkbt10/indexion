/**
 * @file Wiki-specific data fetching hooks.
 */

import { useApiCall } from "../../../lib/hooks.ts";
import { client } from "../../../lib/client.ts";
import { fetchWikiNav, fetchWikiPage } from "@indexion/api-client";

export const useWikiNav = () =>
  useApiCall((signal) => fetchWikiNav(client, signal));

export const useWikiPage = (pageId: string | undefined) =>
  useApiCall(
    pageId ? (signal) => fetchWikiPage(client, pageId, signal) : null,
    [pageId],
  );
