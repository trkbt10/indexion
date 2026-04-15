///|
/// Wiki branding configuration from `.indexion.toml` or `.indexion.json`.
/// Controls title, logo, color scheme, and per-mode color overrides
/// for the wiki frontend served by `indexion serve`.

///|
/// Color overrides for a single color scheme (dark or light).
/// All fields are optional — unset values fall back to built-in presets
/// on the frontend side.
pub struct WikiColorConfig {
  background : String?
  foreground : String?
  primary : String?
  accent : String?
} derive(Eq, Debug)

///|
pub fn WikiColorConfig::empty() -> WikiColorConfig {
  { background: None, foreground: None, primary: None, accent: None }
}

///|
/// Parse key-value in [wiki.colors.dark] or [wiki.colors.light] section.
pub fn parse_wiki_color_key(
  config : WikiColorConfig,
  key : String,
  value : String,
) -> WikiColorConfig {
  let v = trim_quotes(value)
  if v.length() == 0 {
    return config
  }
  match key {
    "background" => { ..config, background: Some(v) }
    "foreground" => { ..config, foreground: Some(v) }
    "primary" => { ..config, primary: Some(v) }
    "accent" => { ..config, accent: Some(v) }
    _ => config
  }
}

///|
/// Merge two WikiColorConfigs. Primary takes precedence.
pub fn merge_wiki_color_configs(
  primary : WikiColorConfig,
  fallback : WikiColorConfig,
) -> WikiColorConfig {
  {
    background: or_opt(primary.background, fallback.background),
    foreground: or_opt(primary.foreground, fallback.foreground),
    primary: or_opt(primary.primary, fallback.primary),
    accent: or_opt(primary.accent, fallback.accent),
  }
}

///|
/// Convert WikiColorConfig to JSON object.
pub fn WikiColorConfig::to_json(self : WikiColorConfig) -> Json {
  let obj : Map[String, Json] = {}
  obj.set(
    "background",
    match self.background {
      Some(v) => v.to_json()
      None => Json::null()
    },
  )
  obj.set(
    "foreground",
    match self.foreground {
      Some(v) => v.to_json()
      None => Json::null()
    },
  )
  obj.set(
    "primary",
    match self.primary {
      Some(v) => v.to_json()
      None => Json::null()
    },
  )
  obj.set(
    "accent",
    match self.accent {
      Some(v) => v.to_json()
      None => Json::null()
    },
  )
  Json::object(obj)
}

///|
/// Wiki branding configuration.
pub struct WikiFileConfig {
  title : String?
  logo_url : String?
  logo_alt : String?
  default_color_scheme : String?
  locale : String?
  colors_dark : WikiColorConfig
  colors_light : WikiColorConfig
} derive(Eq, Debug)

///|
pub fn WikiFileConfig::empty() -> WikiFileConfig {
  {
    title: None,
    logo_url: None,
    logo_alt: None,
    default_color_scheme: None,
    locale: None,
    colors_dark: WikiColorConfig::empty(),
    colors_light: WikiColorConfig::empty(),
  }
}

///|
/// Parse key-value in [wiki] section (flat keys only).
pub fn parse_wiki_section_key(
  config : WikiFileConfig,
  key : String,
  value : String,
) -> WikiFileConfig {
  let v = trim_quotes(value)
  if v.length() == 0 {
    return config
  }
  match key {
    "title" => { ..config, title: Some(v) }
    "logo_url" => { ..config, logo_url: Some(v) }
    "logo_alt" => { ..config, logo_alt: Some(v) }
    "default_color_scheme" => { ..config, default_color_scheme: Some(v) }
    "locale" => { ..config, locale: Some(v) }
    _ => config
  }
}

///|
/// Merge two WikiFileConfigs. Primary takes precedence.
pub fn merge_wiki_configs(
  primary : WikiFileConfig,
  fallback : WikiFileConfig,
) -> WikiFileConfig {
  {
    title: or_opt(primary.title, fallback.title),
    logo_url: or_opt(primary.logo_url, fallback.logo_url),
    logo_alt: or_opt(primary.logo_alt, fallback.logo_alt),
    default_color_scheme: or_opt(
      primary.default_color_scheme,
      fallback.default_color_scheme,
    ),
    locale: or_opt(primary.locale, fallback.locale),
    colors_dark: merge_wiki_color_configs(
      primary.colors_dark,
      fallback.colors_dark,
    ),
    colors_light: merge_wiki_color_configs(
      primary.colors_light,
      fallback.colors_light,
    ),
  }
}

///|
/// Resolve logo_url: relative paths are prefixed with the wiki assets
/// API endpoint so the browser can fetch them from the serve handler.
/// Absolute URLs (http://, https://) and root-relative paths (/) are kept as-is.
fn resolve_logo_url(url : String) -> String {
  if url.has_prefix("http://") ||
    url.has_prefix("https://") ||
    url.has_prefix("/") {
    url
  } else {
    "/api/wiki/assets/" + url
  }
}

///|
/// Convert WikiFileConfig to JSON for the /api/config branding response.
pub fn WikiFileConfig::to_branding_json(self : WikiFileConfig) -> Json {
  let obj : Map[String, Json] = {}
  obj.set(
    "title",
    match self.title {
      Some(v) => v.to_json()
      None => Json::null()
    },
  )
  obj.set(
    "defaultColorScheme",
    match self.default_color_scheme {
      Some(v) => v.to_json()
      None => Json::null()
    },
  )
  obj.set(
    "locale",
    match self.locale {
      Some(v) => v.to_json()
      None => Json::null()
    },
  )
  obj.set(
    "logoUrl",
    match self.logo_url {
      Some(v) => resolve_logo_url(v).to_json()
      None => Json::null()
    },
  )
  obj.set(
    "logoAlt",
    match self.logo_alt {
      Some(v) => v.to_json()
      None => Json::null()
    },
  )
  let colors : Map[String, Json] = {}
  colors.set("dark", self.colors_dark.to_json())
  colors.set("light", self.colors_light.to_json())
  obj.set("colors", Json::object(colors))
  Json::object(obj)
}

///|
/// Load WikiFileConfig from JSON root object.
pub fn load_wiki_from_json_root(root : Map[String, Json]) -> WikiFileConfig {
  let wiki_json = match root.get("wiki") {
    Some(value) => value
    None => return WikiFileConfig::empty()
  }
  let wiki_obj : Map[String, Json] = @json.from_json(wiki_json) catch {
    _ => return WikiFileConfig::empty()
  }
  let mut config = WikiFileConfig::empty()
  match wiki_obj.get("title") {
    Some(value) =>
      match parse_json_string(value) {
        Some(v) => if v.length() > 0 { config = { ..config, title: Some(v) } }
        None => ()
      }
    None => ()
  }
  match wiki_obj.get("logo_url") {
    Some(value) =>
      match parse_json_string(value) {
        Some(v) =>
          if v.length() > 0 {
            config = { ..config, logo_url: Some(v) }
          }
        None => ()
      }
    None => ()
  }
  match wiki_obj.get("logo_alt") {
    Some(value) =>
      match parse_json_string(value) {
        Some(v) =>
          if v.length() > 0 {
            config = { ..config, logo_alt: Some(v) }
          }
        None => ()
      }
    None => ()
  }
  match wiki_obj.get("default_color_scheme") {
    Some(value) =>
      match parse_json_string(value) {
        Some(v) =>
          if v.length() > 0 {
            config = { ..config, default_color_scheme: Some(v) }
          }
        None => ()
      }
    None => ()
  }
  match wiki_obj.get("locale") {
    Some(value) =>
      match parse_json_string(value) {
        Some(v) => if v.length() > 0 { config = { ..config, locale: Some(v) } }
        None => ()
      }
    None => ()
  }
  // Parse colors.dark and colors.light
  match wiki_obj.get("colors") {
    Some(colors_json) => {
      let colors_obj : Map[String, Json] = @json.from_json(colors_json) catch {
        _ => return config
      }
      match colors_obj.get("dark") {
        Some(dark_json) =>
          config = {
            ..config,
            colors_dark: load_wiki_color_from_json(dark_json),
          }
        None => ()
      }
      match colors_obj.get("light") {
        Some(light_json) =>
          config = {
            ..config,
            colors_light: load_wiki_color_from_json(light_json),
          }
        None => ()
      }
    }
    None => ()
  }
  config
}

///|
/// Load WikiColorConfig from a JSON value.
fn load_wiki_color_from_json(value : Json) -> WikiColorConfig {
  let obj : Map[String, Json] = @json.from_json(value) catch {
    _ => return WikiColorConfig::empty()
  }
  let mut config = WikiColorConfig::empty()
  match obj.get("background") {
    Some(v) =>
      match parse_json_string(v) {
        Some(s) =>
          if s.length() > 0 {
            config = { ..config, background: Some(s) }
          }
        None => ()
      }
    None => ()
  }
  match obj.get("foreground") {
    Some(v) =>
      match parse_json_string(v) {
        Some(s) =>
          if s.length() > 0 {
            config = { ..config, foreground: Some(s) }
          }
        None => ()
      }
    None => ()
  }
  match obj.get("primary") {
    Some(v) =>
      match parse_json_string(v) {
        Some(s) => if s.length() > 0 { config = { ..config, primary: Some(s) } }
        None => ()
      }
    None => ()
  }
  match obj.get("accent") {
    Some(v) =>
      match parse_json_string(v) {
        Some(s) => if s.length() > 0 { config = { ..config, accent: Some(s) } }
        None => ()
      }
    None => ()
  }
  config
}

///|
/// Load merged wiki config from project + global config files.
pub fn load_effective_wiki_config(
  project_config_path : String,
) -> WikiFileConfig {
  let project = load_project_config(project_config_path)
  if project.inherit_global {
    let global = load_global_config()
    merge_wiki_configs(project.wiki, global.wiki)
  } else {
    project.wiki
  }
}
