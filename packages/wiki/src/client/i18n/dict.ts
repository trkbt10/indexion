/**
 * @file i18n dictionary type — Single Source of Truth for all UI text keys.
 *
 * Every user-visible string in the wiki frontend MUST come from a Dict.
 * Dynamic strings that vary by count use function signatures so each
 * locale can handle pluralisation rules independently.
 */

import { createContext, useContext } from "react";

// ---------------------------------------------------------------------------
// Dict type
// ---------------------------------------------------------------------------

export type Dict = {
  // Navigation
  readonly nav_explorer: string;
  readonly nav_wiki: string;
  readonly nav_settings: string;
  readonly nav_search_tooltip: string;
  readonly nav_search_shortcut: string;

  // Command Palette
  readonly search_wiki_placeholder: string;
  readonly search_code_placeholder: string;
  readonly search_no_results: string;
  readonly search_wiki_unavailable: string;
  readonly search_group_wiki: string;
  readonly search_group_symbols: string;
  readonly search_group_purpose: string;
  readonly search_hint_navigate: string;
  readonly search_hint_open: string;
  readonly search_hint_close: string;

  // Explorer
  readonly explorer_view_tree: string;
  readonly explorer_view_table: string;
  readonly explorer_view_2d: string;
  readonly explorer_view_3d: string;
  readonly explorer_filter_placeholder: string;
  readonly explorer_stat_roots: string;
  readonly explorer_stat_files: string;
  readonly explorer_stat_symbols: string;

  // Table columns
  readonly col_name: string;
  readonly col_kind: string;
  readonly col_module: string;
  readonly col_depth: string;
  readonly col_in: string;
  readonly col_out: string;
  readonly col_doc: string;

  // Function detail
  readonly detail_summary: string;
  readonly detail_documentation: string;
  readonly detail_keywords: string;
  readonly detail_called_by: (count: number) => string;
  readonly detail_calls: (count: number) => string;
  readonly detail_depth: (n: number) => string;

  // Wiki
  readonly wiki_nav_heading: string;
  readonly wiki_toc_heading: string;
  readonly wiki_source_files: string;
  readonly wiki_pages_button: string;

  // Settings
  readonly settings_heading: string;
  readonly settings_server_config: string;
  readonly settings_index_stats: string;
  readonly settings_rebuild_title: string;
  readonly settings_rebuild_desc: string;
  readonly settings_rebuild_button: string;
  readonly settings_rebuilding: string;
  readonly settings_provider: string;
  readonly settings_dim: string;
  readonly settings_index_dir: string;
  readonly settings_symbols: (n: number) => string;
  readonly settings_modules: (n: number) => string;
  readonly settings_edges: (n: number) => string;
  readonly settings_rebuild_done: (n: number) => string;

  // Connection / Loading / Error
  readonly loading: string;
  readonly loading_wiki: string;
  readonly loading_page: string;
  readonly loading_graph: string;
  readonly connecting: string;
  readonly error_label: string;
  readonly error_connect_heading: string;
  readonly error_connect_message: string;
  readonly error_connect_hint: string;
  readonly error_retry: string;

  // Onboarding
  readonly onboarding_welcome: string;
  readonly onboarding_no_index: string;
  readonly onboarding_success: string;
  readonly onboarding_success_message: (n: number) => string;
  readonly onboarding_build_button: string;
  readonly onboarding_building: string;

  // Graph
  readonly graph_stats: (folders: number, deps: number) => string;
  readonly graph_detail: (
    files: number,
    symbols: number,
    fns: number,
  ) => string;
  readonly graph_subdirs: (n: number) => string;

  // Folder/File badges
  readonly badge_sym: (n: number) => string;
  readonly badge_files: (n: number) => string;

  // Color scheme
  readonly color_scheme_dark: string;
  readonly color_scheme_light: string;
  readonly color_scheme_system: string;
};

// ---------------------------------------------------------------------------
// React Context
// ---------------------------------------------------------------------------

export const DictContext = createContext<Dict | null>(null);

export const useDict = (): Dict => {
  const dict = useContext(DictContext);
  if (!dict) {
    throw new Error("useDict must be used within a DictContext.Provider");
  }
  return dict;
};
