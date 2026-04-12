def parse_config(filepath: str) -> dict:
    config = {}
    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            key, _, value = line.partition("=")
            config[key.strip()] = value.strip()
    return config

def format_duration(total_seconds: int) -> str:
    hours = total_seconds // 3600
    minutes = (total_seconds % 3600) // 60
    secs = total_seconds % 60
    return f"{hours:02d}:{minutes:02d}:{secs:02d}"

def make_slug(text: str) -> str:
    result = text.lower().strip()
    result = result.replace(" ", "-")
    return "".join(c for c in result if c.isalnum() or c == "-")
