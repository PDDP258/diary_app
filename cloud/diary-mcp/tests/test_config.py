"""配置路径解析：相对 -c 也必须落成绝对路径。

踩过：麦麦把 MCP 子进程起在任意工作目录，`-c config.toml` 时
`Path("config.toml").parent` 是 `.`，`data/diary.db` 就会解析到那个目录，
索引读不到，工具全部返回空。
"""

from __future__ import annotations

from pathlib import Path

from diary_mcp.config import load_config


def test_relative_config_resolves_to_absolute(tmp_path: Path, monkeypatch) -> None:
    (tmp_path / "config.toml").write_text(
        '[storage]\ndb_path = "data/diary.db"\n', encoding="utf-8"
    )
    deeper = tmp_path / "deeper"
    deeper.mkdir()
    monkeypatch.chdir(deeper)

    cfg = load_config("../config.toml")

    db = cfg.path(cfg.storage.db_path)
    assert db.is_absolute()
    assert db == tmp_path / "data" / "diary.db"


def test_absolute_config_keeps_sibling_data(tmp_path: Path) -> None:
    config = tmp_path / "config.toml"
    config.write_text('[storage]\ndb_path = "data/diary.db"\n', encoding="utf-8")

    cfg = load_config(config)
    assert cfg.path(cfg.storage.db_path) == tmp_path / "data" / "diary.db"


def test_missing_config_falls_back_to_package_dir(tmp_path: Path) -> None:
    cfg = load_config(tmp_path / "nope.toml")
    db = cfg.path(cfg.storage.db_path)
    assert db.is_absolute()
    assert db.parent.name == "data"
