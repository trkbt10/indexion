/**
 * @file English dictionary — SoT for all user-facing strings.
 *
 * Every key in Dict MUST have a value here. Other locales fall back to
 * this dictionary for any missing key.
 */

import type { Dict } from "./dict.ts";

export const en: Dict = {
  // Navigation
  nav_explorer: "Explorer",
  nav_wiki: "Wiki",
  nav_settings: "Settings",
  nav_search_tooltip: "Search",
  nav_search_shortcut: "\u2318K",

  // Command Palette
  search_wiki_placeholder: "Search wiki pages\u2026",
  search_code_placeholder: "Search symbols or by purpose\u2026",
  search_no_results: "No results found.",
  search_wiki_unavailable:
    "Wiki search is not available yet. The wiki pages are still browsable.",
  search_group_wiki: "Wiki Pages",
  search_group_symbols: "Symbols",
  search_group_purpose: "By Purpose",
  search_hint_navigate: "\u2191\u2193 Navigate",
  search_hint_open: "\u21b5 Open",
  search_hint_close: "Esc Close",

  // Explorer
  explorer_view_tree: "Tree",
  explorer_view_table: "Table",
  explorer_view_2d: "2D Graph",
  explorer_view_3d: "3D Graph",
  explorer_filter_placeholder: "Filter\u2026",
  explorer_stat_roots: "roots",
  explorer_stat_files: "files",
  explorer_stat_symbols: "symbols",

  // Table columns
  col_name: "Name",
  col_kind: "Kind",
  col_module: "Module",
  col_depth: "Depth",
  col_in: "In",
  col_out: "Out",
  col_doc: "Doc",

  // Function detail
  detail_summary: "Summary",
  detail_documentation: "Documentation",
  detail_keywords: "Keywords",
  detail_called_by: (n) => `Called by (${n})`,
  detail_calls: (n) => `Calls (${n})`,
  detail_depth: (n) => `depth ${n}`,

  // Wiki
  wiki_nav_heading: "Wiki",
  wiki_toc_heading: "On this page",
  wiki_source_files: "Relevant source files",
  wiki_pages_button: "Pages",

  // Settings
  settings_heading: "Settings",
  settings_server_config: "Server Configuration",
  settings_index_stats: "Index Statistics",
  settings_rebuild_title: "Rebuild Index",
  settings_rebuild_desc:
    "Re-analyze source files, rebuild the code graph, and update the search index.",
  settings_rebuild_button: "Rebuild",
  settings_rebuilding: "Rebuilding\u2026",
  settings_provider: "Provider",
  settings_dim: "Embedding Dim",
  settings_index_dir: "Index Directory",
  settings_symbols: (n) => `${n} symbols`,
  settings_modules: (n) => `${n} modules`,
  settings_edges: (n) => `${n} edges`,
  settings_rebuild_done: (n) => `${n} functions indexed`,

  // Connection / Loading / Error
  loading: "Loading\u2026",
  loading_wiki: "Loading wiki\u2026",
  loading_page: "Loading page\u2026",
  loading_graph: "Loading graph data\u2026",
  connecting: "Connecting to server\u2026",
  error_label: "Error",
  error_connect_heading: "Cannot connect to server",
  error_connect_message: "Make sure ",
  error_connect_hint: "indexion serve",
  error_retry: "Retry",

  // Onboarding
  onboarding_welcome: "Welcome to indexion",
  onboarding_no_index:
    "No index data found. Build the index to explore your codebase\u2019s structure, symbols, and dependencies.",
  onboarding_success: "Index built successfully",
  onboarding_success_message: (n) => `${n} functions indexed. Reloading\u2026`,
  onboarding_build_button: "Build Index",
  onboarding_building: "Building index\u2026",

  // Graph
  graph_stats: (folders, deps) =>
    `${folders} folders \u00b7 ${deps} dependencies`,
  graph_detail: (files, symbols, fns) =>
    `${files} files \u00b7 ${symbols} symbols \u00b7 ${fns} fn`,
  graph_subdirs: (n) => `${n} subdirectories`,

  // Folder/File badges
  badge_sym: (n) => `${n} sym`,
  badge_files: (n) => `${n} files`,

  // Color scheme
  color_scheme_dark: "Dark",
  color_scheme_light: "Light",
  color_scheme_system: "System",
};
