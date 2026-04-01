import { useState, useEffect, useRef, useCallback } from "react";
import { useNavigate, useLocation } from "react-router";
import { Command } from "cmdk";
import { Search, FileCode2, BookOpen, Sparkles } from "lucide-react";
import { client, isStaticMode } from "../../lib/client.ts";
import { cachedFetch, CacheKey } from "../../lib/api-cache.ts";
import {
  fetchGraph,
  fetchDigestIndex,
  fetchWikiNav,
  queryDigest,
  searchWiki,
  type CodeGraph,
  type DigestMatch,
  type IndexedFunction,
  type WikiNav,
} from "@indexion/api-client";

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

export const CommandPalette = ({
  open,
  onOpenChange,
}: Props): React.JSX.Element => {
  const navigate = useNavigate();
  const location = useLocation();
  const scope = detectScope(location.pathname);

  const [query, setQuery] = useState("");
  const [graph, setGraph] = useState<CodeGraph | null>(null);
  const [digestIndex, setDigestIndex] = useState<ReadonlyArray<IndexedFunction> | null>(null);
  const [wikiNav, setWikiNav] = useState<WikiNav | null>(null);
  const [wikiResults, setWikiResults] = useState<ReadonlyArray<WikiSearchHit>>(
    [],
  );
  const [semanticResults, setSemanticResults] = useState<
    ReadonlyArray<DigestMatch>
  >([]);
  const debounceRef = useRef(0);

  // Load graph once for symbol search (explorer scope), via app-level cache
  useEffect(() => {
    if (!open || graph || scope !== "explorer") {
      return;
    }
    cachedFetch(CacheKey.digest.graph, () => fetchGraph(client)).then((r) => {
      if (r.ok) {
        setGraph(r.data);
      }
    });
  }, [open, graph, scope]);

  // In static mode, pre-load data for client-side search
  useEffect(() => {
    if (!open || !isStaticMode) return;
    if (scope === "explorer" && !digestIndex) {
      cachedFetch(CacheKey.digest.index, () => fetchDigestIndex(client)).then((r) => {
        if (r.ok) setDigestIndex(r.data);
      });
    }
    if (scope === "wiki" && !wikiNav) {
      cachedFetch(CacheKey.wiki.nav, () => fetchWikiNav(client)).then((r) => {
        if (r.ok) setWikiNav(r.data);
      });
    }
  }, [open, scope, digestIndex, wikiNav]);

  // Debounced searches — scoped, with static mode fallback
  useEffect(() => {
    if (!query.trim()) {
      setWikiResults([]);
      setSemanticResults([]);
      return;
    }

    // Static mode: client-side search only
    if (isStaticMode) {
      const lower = query.toLowerCase();
      if (scope === "wiki" && wikiNav) {
        const flattenNav = (items: WikiNav["pages"]): WikiSearchHit[] => {
          const results: WikiSearchHit[] = [];
          for (const item of items) {
            if (item.title.toLowerCase().includes(lower)) {
              results.push({
                section: { id: item.id, title: item.title, content: "", page_id: item.id, level: 1 },
                score: 1,
              });
            }
            if (item.children) {
              results.push(...flattenNav(item.children));
            }
          }
          return results;
        };
        setWikiResults(flattenNav(wikiNav.pages).slice(0, 10));
      } else if (scope === "explorer" && digestIndex) {
        const matches = digestIndex
          .filter((fn) => fn.name.toLowerCase().includes(lower) || fn.module.toLowerCase().includes(lower))
          .slice(0, 10)
          .map((fn) => ({ name: fn.name, file: fn.module, score: 1, summary: fn.doc ?? fn.summary ?? "" }));
        setSemanticResults(matches);
      }
      return;
    }

    const id = ++debounceRef.current;
    const timeout = setTimeout(async () => {
      if (debounceRef.current !== id) {
        return;
      }

      if (scope === "wiki") {
        // Wiki scope: only search wiki
        const wiki = await searchWiki(client, {
          query: query.trim(),
          topK: 10,
        });
        if (debounceRef.current !== id) {
          return;
        }
        if (wiki.ok) {
          setWikiResults(wiki.data as ReadonlyArray<WikiSearchHit>);
        }
      } else {
        // Explorer scope: symbol (client-side) + semantic (server)
        const semantic = await queryDigest(client, {
          purpose: query.trim(),
          topK: 10,
        });
        if (debounceRef.current !== id) {
          return;
        }
        if (semantic.ok) {
          setSemanticResults(semantic.data);
        }
      }
    }, DEBOUNCE_MS);
    return () => clearTimeout(timeout);
  }, [query, scope, wikiNav, digestIndex]);

  // Reset on close
  useEffect(() => {
    if (!open) {
      setQuery("");
      setWikiResults([]);
      setSemanticResults([]);
    }
  }, [open]);

  const go = useCallback(
    (path: string) => {
      onOpenChange(false);
      navigate(path);
    },
    [navigate, onOpenChange],
  );

  // Client-side symbol filter (explorer scope only)
  const symbolResults = (() => {
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
  })();

  const hasResults =
    symbolResults.length > 0 ||
    wikiResults.length > 0 ||
    semanticResults.length > 0;

  return (
    <Command.Dialog
      open={open}
      onOpenChange={onOpenChange}
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
                ? "Search wiki pages..."
                : "Search symbols or by purpose..."
            }
            className="h-11 w-full bg-transparent text-sm text-foreground outline-none placeholder:text-muted-foreground"
          />
          <span className="shrink-0 rounded bg-muted px-1.5 py-0.5 text-[10px] text-muted-foreground">
            {scope === "wiki" ? "Wiki" : "Code"}
          </span>
        </div>

        <Command.List className="max-h-80 overflow-y-auto p-1">
          {query.trim() && !hasResults && (
            <Command.Empty className="p-4 text-center text-sm text-muted-foreground">
              No results found.
            </Command.Empty>
          )}

          {/* Wiki scope results */}
          {wikiResults.length > 0 && (
            <Command.Group heading="Wiki Pages">
              <div className="px-1 py-1 text-xs font-semibold text-muted-foreground">
                Wiki Pages
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
            <Command.Group heading="Symbols">
              <div className="px-1 py-1 text-xs font-semibold text-muted-foreground">
                Symbols
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
            <Command.Group heading="By Purpose">
              <div className="px-1 py-1 text-xs font-semibold text-muted-foreground">
                By Purpose
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
          <span>↑↓ Navigate</span>
          <span>↵ Open</span>
          <span>Esc Close</span>
        </div>
      </div>
    </Command.Dialog>
  );
};
