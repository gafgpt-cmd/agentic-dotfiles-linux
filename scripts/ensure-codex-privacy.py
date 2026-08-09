#!/usr/bin/env python3
from __future__ import annotations

import os
import stat
import tempfile
from pathlib import Path

import tomlkit


def table(document: tomlkit.TOMLDocument, name: str):
    value = document.get(name)
    if value is None:
        value = tomlkit.table()
        document[name] = value
    if not hasattr(value, "__setitem__"):
        raise SystemExit(f"Codex config [{name}] is not a TOML table")
    return value


def main() -> None:
    home = Path(os.environ["HOME"]).expanduser().resolve()
    codex_home = Path(os.environ.get("CODEX_HOME", home / ".codex")).expanduser()
    if not codex_home.is_absolute():
        raise SystemExit("CODEX_HOME must be an absolute path")

    codex_home.mkdir(mode=0o700, parents=True, exist_ok=True)
    config_path = codex_home / "config.toml"
    if config_path.is_symlink():
        raise SystemExit(f"refusing to replace symlinked Codex config: {config_path}")

    if config_path.exists():
        original = config_path.read_text(encoding="utf-8")
        mode = stat.S_IMODE(config_path.stat().st_mode)
        document = tomlkit.parse(original)
    else:
        original = ""
        mode = 0o600
        document = tomlkit.document()

    analytics = table(document, "analytics")
    analytics["enabled"] = False

    otel = table(document, "otel")
    otel["exporter"] = "none"
    otel["trace_exporter"] = "none"
    otel["metrics_exporter"] = "none"
    otel["log_user_prompt"] = False

    rendered = tomlkit.dumps(document)
    if rendered == original:
        return

    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=codex_home,
        prefix=".config.toml.",
        delete=False,
    ) as temporary:
        temporary.write(rendered)
        temporary.flush()
        os.fsync(temporary.fileno())
        temporary_path = Path(temporary.name)

    temporary_path.chmod(mode)
    os.replace(temporary_path, config_path)


if __name__ == "__main__":
    main()
