/**
 * @file Japanese dictionary.
 *
 * Falls back to en.ts for any missing key via resolveDict().
 */

import type { Dict } from "./dict.ts";

export const ja: Dict = {
  // Navigation
  nav_explorer: "\u30a8\u30af\u30b9\u30d7\u30ed\u30fc\u30e9\u30fc",
  nav_wiki: "Wiki",
  nav_settings: "\u8a2d\u5b9a",
  nav_search_tooltip: "\u691c\u7d22",
  nav_search_shortcut: "\u2318K",

  // Command Palette
  search_wiki_placeholder: "Wiki\u30da\u30fc\u30b8\u3092\u691c\u7d22\u2026",
  search_code_placeholder:
    "\u30b7\u30f3\u30dc\u30eb\u307e\u305f\u306f\u76ee\u7684\u3067\u691c\u7d22\u2026",
  search_no_results:
    "\u7d50\u679c\u304c\u898b\u3064\u304b\u308a\u307e\u305b\u3093\u3002",
  search_wiki_unavailable:
    "Wiki\u691c\u7d22\u306f\u307e\u3060\u4f7f\u3048\u307e\u305b\u3093\u3002Wiki\u30da\u30fc\u30b8\u306f\u95b2\u89a7\u3067\u304d\u307e\u3059\u3002",
  search_group_wiki: "Wiki\u30da\u30fc\u30b8",
  search_group_symbols: "\u30b7\u30f3\u30dc\u30eb",
  search_group_purpose: "\u76ee\u7684\u5225",
  search_hint_navigate: "\u2191\u2193 \u79fb\u52d5",
  search_hint_open: "\u21b5 \u958b\u304f",
  search_hint_close: "Esc \u9589\u3058\u308b",

  // Explorer
  explorer_view_tree: "\u30c4\u30ea\u30fc",
  explorer_view_table: "\u30c6\u30fc\u30d6\u30eb",
  explorer_view_2d: "2D\u30b0\u30e9\u30d5",
  explorer_view_3d: "3D\u30b0\u30e9\u30d5",
  explorer_filter_placeholder: "\u30d5\u30a3\u30eb\u30bf\u30fc\u2026",
  explorer_stat_roots: "\u30eb\u30fc\u30c8",
  explorer_stat_files: "\u30d5\u30a1\u30a4\u30eb",
  explorer_stat_symbols: "\u30b7\u30f3\u30dc\u30eb",

  // Table columns
  col_name: "\u540d\u524d",
  col_kind: "\u7a2e\u985e",
  col_module: "\u30e2\u30b8\u30e5\u30fc\u30eb",
  col_depth: "\u6df1\u3055",
  col_in: "\u5165",
  col_out: "\u51fa",
  col_doc: "\u30c9\u30ad\u30e5\u30e1\u30f3\u30c8",

  // Function detail
  detail_summary: "\u6982\u8981",
  detail_documentation: "\u30c9\u30ad\u30e5\u30e1\u30f3\u30c8",
  detail_keywords: "\u30ad\u30fc\u30ef\u30fc\u30c9",
  detail_called_by: (n) => `\u547c\u3073\u51fa\u3057\u5143 (${n})`,
  detail_calls: (n) => `\u547c\u3073\u51fa\u3057\u5148 (${n})`,
  detail_depth: (n) => `\u6df1\u3055 ${n}`,

  // Wiki
  wiki_nav_heading: "Wiki",
  wiki_toc_heading: "\u3053\u306e\u30da\u30fc\u30b8\u306e\u76ee\u6b21",
  wiki_source_files: "\u95a2\u9023\u30bd\u30fc\u30b9\u30d5\u30a1\u30a4\u30eb",
  wiki_pages_button: "\u30da\u30fc\u30b8",

  // Settings
  settings_heading: "\u8a2d\u5b9a",
  settings_server_config: "\u30b5\u30fc\u30d0\u30fc\u8a2d\u5b9a",
  settings_index_stats: "\u30a4\u30f3\u30c7\u30c3\u30af\u30b9\u7d71\u8a08",
  settings_rebuild_title:
    "\u30a4\u30f3\u30c7\u30c3\u30af\u30b9\u518d\u69cb\u7bc9",
  settings_rebuild_desc:
    "\u30bd\u30fc\u30b9\u30d5\u30a1\u30a4\u30eb\u3092\u518d\u89e3\u6790\u3057\u3001\u30b3\u30fc\u30c9\u30b0\u30e9\u30d5\u3092\u518d\u69cb\u7bc9\u3057\u3001\u691c\u7d22\u30a4\u30f3\u30c7\u30c3\u30af\u30b9\u3092\u66f4\u65b0\u3057\u307e\u3059\u3002",
  settings_rebuild_button: "\u518d\u69cb\u7bc9",
  settings_rebuilding: "\u518d\u69cb\u7bc9\u4e2d\u2026",
  settings_provider: "\u30d7\u30ed\u30d0\u30a4\u30c0\u30fc",
  settings_dim: "\u57cb\u3081\u8fbc\u307f\u6b21\u5143\u6570",
  settings_index_dir:
    "\u30a4\u30f3\u30c7\u30c3\u30af\u30b9\u30c7\u30a3\u30ec\u30af\u30c8\u30ea",
  settings_symbols: (n) => `${n} \u30b7\u30f3\u30dc\u30eb`,
  settings_modules: (n) => `${n} \u30e2\u30b8\u30e5\u30fc\u30eb`,
  settings_edges: (n) => `${n} \u30a8\u30c3\u30b8`,
  settings_rebuild_done: (n) =>
    `${n} \u95a2\u6570\u3092\u30a4\u30f3\u30c7\u30c3\u30af\u30b9\u6e08\u307f`,

  // Connection / Loading / Error
  loading: "\u8aad\u307f\u8fbc\u307f\u4e2d\u2026",
  loading_wiki: "Wiki\u3092\u8aad\u307f\u8fbc\u307f\u4e2d\u2026",
  loading_page: "\u30da\u30fc\u30b8\u3092\u8aad\u307f\u8fbc\u307f\u4e2d\u2026",
  loading_graph:
    "\u30b0\u30e9\u30d5\u30c7\u30fc\u30bf\u3092\u8aad\u307f\u8fbc\u307f\u4e2d\u2026",
  connecting: "\u30b5\u30fc\u30d0\u30fc\u306b\u63a5\u7d9a\u4e2d\u2026",
  error_label: "\u30a8\u30e9\u30fc",
  error_connect_heading:
    "\u30b5\u30fc\u30d0\u30fc\u306b\u63a5\u7d9a\u3067\u304d\u307e\u305b\u3093",
  error_connect_message: "",
  error_connect_hint: "indexion serve",
  error_retry: "\u518d\u8a66\u884c",

  // Onboarding
  onboarding_welcome: "indexion\u3078\u3088\u3046\u3053\u305d",
  onboarding_no_index:
    "\u30a4\u30f3\u30c7\u30c3\u30af\u30b9\u30c7\u30fc\u30bf\u304c\u898b\u3064\u304b\u308a\u307e\u305b\u3093\u3002\u30a4\u30f3\u30c7\u30c3\u30af\u30b9\u3092\u30d3\u30eb\u30c9\u3057\u3066\u3001\u30b3\u30fc\u30c9\u30d9\u30fc\u30b9\u306e\u69cb\u9020\u30fb\u30b7\u30f3\u30dc\u30eb\u30fb\u4f9d\u5b58\u95a2\u4fc2\u3092\u63a2\u7d22\u3057\u307e\u3057\u3087\u3046\u3002",
  onboarding_success:
    "\u30a4\u30f3\u30c7\u30c3\u30af\u30b9\u306e\u30d3\u30eb\u30c9\u306b\u6210\u529f",
  onboarding_success_message: (n) =>
    `${n} \u95a2\u6570\u3092\u30a4\u30f3\u30c7\u30c3\u30af\u30b9\u6e08\u307f\u3002\u30ea\u30ed\u30fc\u30c9\u4e2d\u2026`,
  onboarding_build_button:
    "\u30a4\u30f3\u30c7\u30c3\u30af\u30b9\u3092\u30d3\u30eb\u30c9",
  onboarding_building:
    "\u30a4\u30f3\u30c7\u30c3\u30af\u30b9\u3092\u30d3\u30eb\u30c9\u4e2d\u2026",

  // Graph
  graph_stats: (folders, deps) =>
    `${folders} \u30d5\u30a9\u30eb\u30c0\u30fc \u00b7 ${deps} \u4f9d\u5b58\u95a2\u4fc2`,
  graph_detail: (files, symbols, fns) =>
    `${files} \u30d5\u30a1\u30a4\u30eb \u00b7 ${symbols} \u30b7\u30f3\u30dc\u30eb \u00b7 ${fns} fn`,
  graph_subdirs: (n) => `${n} \u30b5\u30d6\u30c7\u30a3\u30ec\u30af\u30c8\u30ea`,

  // Folder/File badges
  badge_sym: (n) => `${n} sym`,
  badge_files: (n) => `${n} \u30d5\u30a1\u30a4\u30eb`,

  // Color scheme
  color_scheme_dark: "\u30c0\u30fc\u30af",
  color_scheme_light: "\u30e9\u30a4\u30c8",
  color_scheme_system: "\u30b7\u30b9\u30c6\u30e0",
};
