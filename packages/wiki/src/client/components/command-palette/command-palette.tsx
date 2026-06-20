import {
  useState,
  useEffect,
  useRef,
  useCallback,
  useMemo,
  useSyncExternalStore,
} from "react";
import { useNavigate, useLocation } from "react-router";
import { Command } from "cmdk";
import { Search, FileCode2, BookOpen, Sparkles } from "lucide-react";
import { client, isStaticMode } from "../../lib/client.ts";
import { useCachedApiCall } from "../../lib/hooks.ts";
import { CacheKey } from "../../lib/api-cache.ts";
import {
  fetchGraph,
  fetchDigestIndex,
  fetchWikiNav,
  queryDigest,
  searchWiki,
  type CodeGraph,
  type DigestMatch,
  type WikiNav,
} from "@indexion/api-client";
import { useDict } from "../../i18n/index.ts";
import { cn } from "../../lib/utils.ts";

type Props = {
  readonly open: boolean;
  readonly onOpenChange: (open: boolean) => void;
};

// Matches server's WikiSearchHit: { section: WikiSection, score: number }
type WikiSearchHit = {
  readonly section: {
    readonly id: string;
    readonly title: string;
    readonly content: string;
    readonly page_id: string;
    readonly level: number;
  };
  readonly score: number;
};

type Scope = "wiki" | "explorer";

const DEBOUNCE_MS = 300;

const detectScope = (pathname: string): Scope =>
  pathname.startsWith("/wiki") ? "wiki" : "explorer";

// ── Search result store (module singleton) ───────────────

type SearchState = {
  readonly wikiResults: ReadonlyArray<WikiSearchHit>;
  readonly semanticResults: ReadonlyArray<DigestMatch>;
  readonly notice: string | null;
  readonly error: string | null;
};

const EMPTY_SEARCH: SearchState = {
  wikiResults: [],
  semanticResults: [],
  notice: null,
  error: null,
};
let searchState = EMPTY_SEARCH;
const searchListeners = new Set<() => void>();
let searchVersion = 0;
const WIKI_SEARCH_INDEX_UNAVAILABLE = "wiki search index not available";

function searchSubscribe(cb: () => void): () => void {
  searchListeners.add(cb);
  return () => searchListeners.delete(cb);
}

function searchGetSnapshot(): number {
  return searchVersion;
}

function updateSearch(next: Partial<SearchState>): void {
  searchState = { ...searchState, ...next };
  searchVersion++;
  for (const cb of searchListeners) {
    cb();
  }
}

function resetSearch(): void {
  searchState = EMPTY_SEARCH;
  searchVersion++;
  for (const cb of searchListeners) {
    cb();
  }
}

const isWikiSearchIndexUnavailable = (message: string): boolean =>
  message.toLowerCase().includes(WIKI_SEARCH_INDEX_UNAVAILABLE);

const errorMessage = (err: unknown): string =>
  err instanceof Error ? err.message : "Search failed.";

// ── Component ────────────────────────────────────────────

export const CommandPalette = ({
  open,
  onOpenChange,
}: Props): React.JSX.Element => {
  const navigate = useNavigate();
  const location = useLocation();
  const d = useDict();
  const scope = detectScope(location.pathname);

  const [query, setQuery] = useState("");
  const debounceRef = useRef(0);

  // Data loading via app-level cache (no setState in effects)
  const graphState = useCachedApiCall(CacheKey.digest.graph, () =>
    fetchGraph(client),
  );
  const graph: CodeGraph | null =
    scope === "explorer" && graphState.status === "success"
      ? graphState.data
      : null;

  const digestState = useCachedApiCall(CacheKey.digest.index, () =>
    fetchDigestIndex(client),
  );
  const digestIndex =
    isStaticMode && scope === "explorer" && digestState.status === "success"
      ? digestState.data
      : null;

  const wikiNavState = useCachedApiCall(CacheKey.wiki.nav, () =>
    fetchWikiNav(client),
  );
  const wikiNav: WikiNav | null =
    isStaticMode && scope === "wiki" && wikiNavState.status === "success"
      ? wikiNavState.data
      : null;

  // Subscribe to search results store
  const version = useSyncExternalStore(
    searchSubscribe,
    searchGetSnapshot,
    searchGetSnapshot,
  );
  const { wikiResults, semanticResults, notice, error } = useMemo(() => {
    void version;
    return searchState;
  }, [version]);

  // Debounced search — side effect only, results go to external store
  useEffect(() => {
    if (!query.trim()) {
      resetSearch();
      return;
    }
    updateSearch({ notice: null, error: null });

    // Static mode: client-side search only
    if (isStaticMode) {
      const lower = query.toLowerCase();
      if (scope === "wiki" && wikiNav) {
        const flattenNav = (items: WikiNav["pages"]): WikiSearchHit[] => {
          const results: WikiSearchHit[] = [];
          for (const item of items) {
            if (item.title.toLowerCase().includes(lower)) {
              results.push({
                section: {
                  id: item.id,
                  title: item.title,
                  content: "",
                  page_id: item.id,
                  level: 1,
                },
                score: 1,
              });
            }
            if (item.children) {
              results.push(...flattenNav(item.children));
            }
          }
          return results;
        };
        updateSearch({
          wikiResults: flattenNav(wikiNav.pages).slice(0, 10),
          notice: null,
          error: null,
        });
      }
      if (scope === "explorer" && digestIndex) {
        const matches = digestIndex
          .filter(
            (fn) =>
              fn.name.toLowerCase().includes(lower) ||
              fn.module.toLowerCase().includes(lower),
          )
          .slice(0, 10)
          .map((fn) => ({
            name: fn.name,
            file: fn.module,
            score: 1,
            summary: fn.doc ?? fn.summary ?? "",
          }));
        updateSearch({ semanticResults: matches, notice: null, error: null });
      }
      return;
    }

    const id = ++debounceRef.current;
    const timeout = setTimeout(async () => {
      if (debounceRef.current !== id) {
        return;
      }

      try {
        if (scope === "wiki") {
          const wiki = await searchWiki(client, {
            query: query.trim(),
            topK: 10,
          });
          if (debounceRef.current !== id) {
            return;
          }
          if (wiki.ok) {
            updateSearch({
              wikiResults: wiki.data as ReadonlyArray<WikiSearchHit>,
              notice: null,
              error: null,
            });
          } else if (isWikiSearchIndexUnavailable(wiki.error)) {
            updateSearch({
              wikiResults: [],
              notice: d.search_wiki_unavailable,
              error: null,
            });
          } else {
            updateSearch({ wikiResults: [], notice: null, error: wiki.error });
          }
        } else {
          const semantic = await queryDigest(client, {
            purpose: query.trim(),
            topK: 10,
          });
          if (debounceRef.current !== id) {
            return;
          }
          if (semantic.ok) {
            updateSearch({
              semanticResults: semantic.data,
              notice: null,
              error: null,
            });
          } else {
            updateSearch({
              semanticResults: [],
              notice: null,
              error: semantic.error,
            });
          }
        }
      } catch (err) {
        if (debounceRef.current === id) {
          updateSearch({ notice: null, error: errorMessage(err) });
        }
      }
    }, DEBOUNCE_MS);
    return () => clearTimeout(timeout);
  }, [query, scope, wikiNav, digestIndex, d.search_wiki_unavailable]);

  // Reset search store when palette closes
  useEffect(() => {
    if (!open) {
      resetSearch();
    }
  }, [open]);

  const handleOpenChange = useCallback(
    (next: boolean) => {
      if (!next) {
        setQuery("");
      }
      onOpenChange(next);
    },
    [onOpenChange],
  );

  const go = useCallback(
    (path: string) => {
      handleOpenChange(false);
      navigate(path);
    },
    [navigate, handleOpenChange],
  );

  // Client-side symbol filter (explorer scope only)
  const symbolResults = useMemo(() => {
    if (scope !== "explorer" || !graph || !query.trim()) {
      return [];
    }
    const lower = query.toLowerCase();
    return Object.entries(graph.symbols)
      .filter(
        ([, sym]) =>
          sym.name.toLowerCase().includes(lower) ||
          sym.module.toLowerCase().includes(lower),
      )
      .slice(0, 12)
      .map(([id, sym]) => ({ id, ...sym }));
  }, [scope, graph, query]);

  const hasResults =
    symbolResults.length > 0 ||
    wikiResults.length > 0 ||
    semanticResults.length > 0;
  const statusMessage = error ?? notice;

  return (
    <Command.Dialog
      open={open}
      onOpenChange={handleOpenChange}
      label="Search"
      shouldFilter={false}
      className="fixed inset-0 z-50"
    >
      {/* Overlay */}
      <div
        className="fixed inset-0 bg-black/60 backdrop-blur-sm"
        onClick={() => onOpenChange(false)}
      />

      {/* Dialog */}
      <div className="fixed left-1/2 top-[15%] z-50 w-[calc(100%-2rem)] max-w-lg -translate-x-1/2 overflow-hidden rounded-lg border bg-background shadow-2xl">
        <div className="flex items-center gap-2 border-b px-3">
          <Search className="size-4 shrink-0 text-muted-foreground" />
          <Command.Input
            value={query}
            onValueChange={setQuery}
            placeholder={
              scope === "wiki"
                ? d.search_wiki_placeholder
                : d.search_code_placeholder
            }
            className="h-11 w-full bg-transparent text-sm text-foreground outline-none placeholder:text-muted-foreground"
          />
          <span className="shrink-0 rounded bg-muted px-1.5 py-0.5 text-[10px] text-muted-foreground">
            {scope === "wiki" ? d.nav_wiki : d.search_group_symbols}
          </span>
        </div>

        <Command.List className="max-h-80 overflow-y-auto p-1">
          {query.trim() && !hasResults && (
            <Command.Empty
              className={cn(
                "p-4 text-center text-sm",
                error ? "text-destructive" : "text-muted-foreground",
              )}
            >
              {statusMessage ?? d.search_no_results}
            </Command.Empty>
          )}

          {/* Wiki scope results */}
          {wikiResults.length > 0 && (
            <Command.Group heading={d.search_group_wiki}>
              <div className="px-1 py-1 text-xs font-semibold text-muted-foreground">
                {d.search_group_wiki}
              </div>
              {wikiResults.map((hit, i) => (
                <Command.Item
                  key={`wiki-${i}`}
                  value={`wiki-${i}`}
                  onSelect={() => go(`/wiki/${hit.section.page_id}`)}
                  className="flex cursor-pointer items-center gap-2 rounded-md px-2 py-1.5 text-sm text-foreground aria-selected:bg-accent"
                >
                  <BookOpen className="size-3.5 shrink-0 text-blue-400" />
                  <div className="min-w-0 flex-1">
                    <div className="truncate font-medium">
                      {hit.section.title || hit.section.page_id}
                    </div>
                    <div className="truncate text-xs text-muted-foreground">
                      {hit.section.page_id}
                    </div>
                  </div>
                  <span className="shrink-0 text-[10px] tabular-nums text-muted-foreground">
                    {Math.round(hit.score * 100)}%
                  </span>
                </Command.Item>
              ))}
            </Command.Group>
          )}

          {/* Explorer scope: symbols */}
          {symbolResults.length > 0 && (
            <Command.Group heading={d.search_group_symbols}>
              <div className="px-1 py-1 text-xs font-semibold text-muted-foreground">
                {d.search_group_symbols}
              </div>
              {symbolResults.map((sym) => (
                <Command.Item
                  key={sym.id}
                  value={`sym-${sym.id}`}
                  onSelect={() =>
                    go(`/?filter=${encodeURIComponent(sym.name)}`)
                  }
                  className="flex cursor-pointer items-center gap-2 rounded-md px-2 py-1.5 text-sm text-foreground aria-selected:bg-accent"
                >
                  <FileCode2 className="size-3.5 shrink-0 text-blue-400" />
                  <span className="truncate font-mono">{sym.name}</span>
                  <span className="ml-auto shrink-0 truncate text-xs text-muted-foreground">
                    {sym.module}
                  </span>
                </Command.Item>
              ))}
            </Command.Group>
          )}

          {/* Explorer scope: semantic */}
          {semanticResults.length > 0 && (
            <Command.Group heading={d.search_group_purpose}>
              <div className="px-1 py-1 text-xs font-semibold text-muted-foreground">
                {d.search_group_purpose}
              </div>
              {semanticResults.map((r, i) => (
                <Command.Item
                  key={`sem-${i}`}
                  value={`sem-${i}`}
                  onSelect={() => go(`/?filter=${encodeURIComponent(r.name)}`)}
                  className="flex cursor-pointer items-center gap-2 rounded-md px-2 py-1.5 text-sm text-foreground aria-selected:bg-accent"
                >
                  <Sparkles className="size-3.5 shrink-0 text-purple-400" />
                  <div className="min-w-0 flex-1">
                    <div className="truncate font-mono">{r.name}</div>
                    <div className="truncate text-xs text-muted-foreground">
                      {r.file}
                    </div>
                  </div>
                  <span className="shrink-0 text-[10px] tabular-nums text-muted-foreground">
                    {Math.round(r.score * 100)}%
                  </span>
                </Command.Item>
              ))}
            </Command.Group>
          )}
        </Command.List>

        <div className="flex items-center justify-between border-t px-3 py-1.5 text-xs text-muted-foreground">
          <span>{d.search_hint_navigate}</span>
          <span>{d.search_hint_open}</span>
          <span>{d.search_hint_close}</span>
        </div>
      </div>
    </Command.Dialog>
  );
};
