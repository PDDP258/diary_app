import json

from diary_mcp.store import Store, index_text


def test_index_text_splits_cjk_bigrams():
    tokens = index_text("今天天气好").split()
    assert "今天" in tokens
    assert "天天" in tokens
    assert "天气" in tokens


def test_index_text_keeps_latin_words():
    tokens = index_text("跑完 5km 之后").split()
    assert "5km" in tokens


def _backup():
    return {
        "diaries": [
            {
                "id": 1,
                "date": "2026-03-12",
                "title": "找工作",
                "content": "投了七份简历，只有一家回信，面试时问了很多算法题。",
                "mood_name": "焦虑",
                "is_favorite": 0,
            },
            {
                "id": 2,
                "date": "2026-03-15",
                "title": "面试通过",
                "content": "拿到 offer 了，回头看那几天焦虑有点多余。",
                "mood_name": "开心",
                "is_favorite": 1,
            },
            {
                "id": 3,
                "date": "2025-03-12",
                "title": "去年的今天",
                "content": "在准备考研，每天六点起。",
                "mood_name": "平静",
                "is_favorite": 0,
            },
        ],
        "tags": [{"id": "t1", "name": "求职"}],
        "diary_tags": [{"diary_id": 1, "tag_id": "t1"}],
    }


def test_replace_and_search(tmp_path):
    store = Store(tmp_path / "t.db")
    assert store.replace_all(_backup()) == 3

    hits = store.search("焦虑")
    ids = [h.id for h in hits]
    assert 1 in ids
    assert hits[0].date.startswith("2026")

    store.close()


def test_search_with_date_filter(tmp_path):
    store = Store(tmp_path / "t.db")
    store.replace_all(_backup())
    hits = store.search("今天", date_from="2025-01-01", date_to="2025-12-31")
    assert [h.id for h in hits] == [3]
    store.close()


def test_tags_are_joined(tmp_path):
    store = Store(tmp_path / "t.db")
    store.replace_all(_backup())
    assert store.read(1)["tags"] == "求职"
    store.close()


def test_stats_and_streak(tmp_path):
    store = Store(tmp_path / "t.db")
    store.replace_all(_backup())
    data = store.stats()
    assert data["count"] == 3
    assert data["days"] == 3
    assert data["moods"]["焦虑"] == 1
    assert data["streak"] == 1
    store.close()


def test_on_this_day(tmp_path):
    store = Store(tmp_path / "t.db")
    store.replace_all(_backup())
    rows = store.on_this_day("03-12")
    assert {r["id"] for r in rows} == {1, 3}
    store.close()


def test_on_this_day_excludes_today(tmp_path):
    """「往年的今天」不能把今天刚写的那篇算进去。

    2026-10-28 真实踩到：/diarytoday 把今天自己的日记当成「历史上的今天」发出来了，
    /diarybrief 也跟着说「往年的今天你在写…」。
    """
    store = Store(tmp_path / "t.db")
    store.replace_all(_backup())
    rows = store.on_this_day("03-12", exclude_date="2026-03-12")
    assert {r["id"] for r in rows} == {3}
    store.close()


def test_mood_falls_back_to_mood_id(tmp_path):
    """App 导出的 mood_name 经常是 null，只带 mood_id，必须回查 moods 表。

    否则以后用户在 App 里打了心情，云端索引里也会一律显示「未记录」。
    """
    backup = {
        "diaries": [
            {
                "id": 1,
                "date": "2026-03-12",
                "title": "",
                "content": "随便写点",
                "mood_id": 2,
                "mood_name": None,
            }
        ],
        "moods": [{"id": 2, "name": "平静"}],
    }
    store = Store(tmp_path / "t.db")
    store.replace_all(backup)
    assert store.stats()["moods"] == {"平静": 1}
    store.close()


def test_empty_query_returns_nothing(tmp_path):
    store = Store(tmp_path / "t.db")
    store.replace_all(_backup())
    assert store.search("") == []
    store.close()


def test_drafts(tmp_path):
    store = Store(tmp_path / "t.db")
    outbox = tmp_path / "outbox"
    path = store.write_draft(outbox, {"title": "t", "content": "c", "date": "2026-10-28"})
    assert path.exists()
    items = store.list_drafts(outbox)
    assert items[0]["content"] == "c"
    assert json.loads(path.read_text(encoding="utf-8"))["source"] == "mcp"
    store.close()
