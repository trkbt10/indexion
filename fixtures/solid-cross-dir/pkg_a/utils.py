def parse_config(path: str) -> dict:
    result = {}
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            key, _, value = line.partition("=")
            result[key.strip()] = value.strip()
    return result

def format_duration(seconds: int) -> str:
    hours = seconds // 3600
    minutes = (seconds % 3600) // 60
    secs = seconds % 60
    return f"{hours:02d}:{minutes:02d}:{secs:02d}"

def slugify(text: str) -> str:
    result = text.lower().strip()
    result = result.replace(" ", "-")
    return "".join(c for c in result if c.isalnum() or c == "-")
