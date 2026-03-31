///|
/// # Wiki Serving
///
/// Loads wiki pages from .indexion/wiki/ directory.
/// Builds a search index using the same embedding provider as digest.

///|
async fn load_wiki_pages(
  config : ServeConfig,
  provider : @dconfig.EmbeddingProvider,
) -> (@wiki.WikiData, @wiki.WikiSearchIndex?) {
  let wiki_dir = config.workspace_dir + "/.indexion/wiki"
  match @wiki.load_wiki(wiki_dir) {
    Some(data) => {
      @digest_cli.log_progress(
        "Wiki: " + data.pages.length().to_string() + " pages loaded.",
      )
      let search = @wiki.build_search_index(data.pages, provider) catch {
        _ => {
          @digest_cli.log_progress(
            "Wiki search: embedding failed, using TF-IDF fallback.",
          )
          @wiki.build_search_index(data.pages, @dconfig.TfIdf(256)) catch {
            _ => {
              @digest_cli.log_progress("Wiki search: failed to build index.")
              return (data, None)
            }
          }
        }
      }
      @digest_cli.log_progress(
        "Wiki search: " +
        search.sections.length().to_string() +
        " sections indexed.",
      )
      (data, Some(search))
    }
    None => {
      @digest_cli.log_progress(
        "Wiki: no .indexion/wiki/ found. Run `indexion plan wiki` to generate.",
      )
      (empty_wiki(), None)
    }
  }
}

///|
async fn handle_wiki_search(
  conn : @mhttp.ServerConnection,
  body_text : String,
  search_index : @wiki.WikiSearchIndex?,
  cors : Bool,
) -> Unit {
  match search_index {
    None => {
      send_json_error(conn, 404, "Wiki search index not available", cors)
      return
    }
    Some(idx) => {
      let json : Json = @json.parse(body_text) catch {
        _ => {
          send_json_error(conn, 400, "Invalid JSON body", cors)
          return
        }
      }
      let query = if json is { "query": String(q), .. } {
        q
      } else {
        send_json_error(conn, 400, "Missing 'query' field", cors)
        return
      }
      let top_k = if json is { "topK": Number(n, ..), .. } {
        n.to_int()
      } else {
        10
      }
      let hits = idx.search(query, top_k~)
      let results : Array[Json] = []
      for hit in hits {
        results.push(hit.to_json())
      }
      send_json_ok(conn, Json::array(results).stringify(), cors)
    }
  }
}

///|
fn empty_wiki() -> @wiki.WikiData {
  let placeholder = @wiki.WikiPage::new(
    id="overview",
    title="Wiki Not Generated",
    content="# Wiki Not Generated\n\nRun `indexion plan wiki` to generate a wiki structure, then have an agent write the pages.\n",
  )
  let pages : Map[String, @wiki.WikiPage] = {}
  pages["overview"] = placeholder
  let nav = @wiki.WikiNav::new(pages=[
    @wiki.WikiNavItem::new(id="overview", title="Overview"),
  ])
  @wiki.WikiData::new(nav~, pages~)
}
