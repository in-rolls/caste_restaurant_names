import json

import adjudicate_matches as adjudication
import collect_restaurants as collector
import sample_frame


def test_nearby_preserves_first_capture_and_records_cap(monkeypatch):
    places = [
        {
            "id": str(i),
            "displayName": {"text": f"Cafe {i}"},
            "location": {"latitude": 12, "longitude": 77},
        }
        for i in range(20)
    ]

    class Response:
        def raise_for_status(self):
            pass

        def json(self):
            return {"places": places}

    calls = []

    def post(url, **kwargs):
        calls.append(kwargs)
        return Response()

    monkeypatch.setattr(collector.requests, "post", post)
    monkeypatch.setattr(collector.time, "sleep", lambda _: None)
    rows, meta = collector.collect_places_new_for_region(
        collector.Region("test", "Test", 12, 77, 1),
        api_key="test-key",
        languages=("en",),
        points=[(12, 77), (12.001, 77)],
    )
    assert len(rows) == 20
    assert {row["cell_idx"] for row in rows} == {0}
    assert meta["capped_queries"] == 2
    assert meta["errors"] == []
    assert calls[0]["json"]["rankPreference"] == "DISTANCE"


def test_nearby_failure_is_recorded(monkeypatch):
    def fail(*args, **kwargs):
        raise RuntimeError("test failure")

    monkeypatch.setattr(collector.requests, "post", fail)
    monkeypatch.setattr(collector.time, "sleep", lambda _: None)
    rows, meta = collector.collect_places_new_for_region(
        collector.Region("test", "Test", 12, 77, 1),
        api_key="test-key",
        languages=("en",),
        points=[(12, 77)],
    )
    assert rows == []
    assert len(meta["errors"]) == 1


def test_adjudication_resumes_and_retries_missing_answers(monkeypatch, tmp_path):
    out = tmp_path / "verdicts.jsonl"
    items = [
        {"item_id": f"B:{i}", "task": "screen_unmatched", "name": f"Cafe {i}"}
        for i in range(2)
    ]
    monkeypatch.setattr(
        adjudication,
        "ollama_chat",
        lambda _: {"answers": [{"id": 1, "caste_coded": False}]},
    )
    adjudication.run_batches(items, adjudication.PROMPT_B, "test", str(out), set())
    assert adjudication.load_done(str(out)) == {"B:0"}
    adjudication.run_batches(
        items, adjudication.PROMPT_B, "test", str(out), adjudication.load_done(str(out))
    )
    assert len([json.loads(line) for line in out.read_text().splitlines()]) == 2
    assert adjudication.load_done(str(out)) == {"B:0", "B:1"}


def test_frame_uses_archive_without_network(monkeypatch, tmp_path):
    import gzip

    path = tmp_path / "roads.json.gz"
    data = {
        "elements": [
            {"id": 1, "geometry": [{"lat": 12, "lon": 77}, {"lat": 12.001, "lon": 77}]}
        ]
    }
    with gzip.open(path, "wt") as stream:
        json.dump(data, stream)

    def fail(*args, **kwargs):
        raise AssertionError("Network call in archived-frame rebuild")

    monkeypatch.setattr(sample_frame.urllib.request, "urlopen", fail)
    loaded, query = sample_frame.fetch_roads([], path)
    assert loaded == data
    assert query is None
    assert len(sample_frame.build_segments(loaded)) == 1


def test_adjudication_rejects_malformed_verdict_and_deduplicates_in_run(
    monkeypatch, tmp_path
):
    out = tmp_path / "verdicts.jsonl"
    items = [{"item_id": "B:a", "task": "screen_unmatched", "name": "Cafe"}]
    done = set()
    monkeypatch.setattr(
        adjudication,
        "ollama_chat",
        lambda _: {"answers": [{"id": 1, "caste_coded": "false"}]},
    )
    adjudication.run_batches(items, adjudication.PROMPT_B, "test", str(out), done)
    assert not adjudication.load_done(str(out))
    monkeypatch.setattr(
        adjudication,
        "ollama_chat",
        lambda _: {"answers": [{"id": 1, "caste_coded": False}]},
    )
    adjudication.run_batches(items, adjudication.PROMPT_B, "test", str(out), done)
    adjudication.run_batches(
        items, adjudication.PROMPT_B, "another-region", str(out), done
    )
    assert len(out.read_text().splitlines()) == 1


def test_adjudication_failure_leaves_items_retryable(monkeypatch, tmp_path):
    out = tmp_path / "verdicts.jsonl"

    def fail(_):
        raise RuntimeError("unavailable")

    monkeypatch.setattr(adjudication, "ollama_chat", fail)
    adjudication.run_batches(
        [{"item_id": "B:a", "task": "screen_unmatched", "name": "Cafe"}],
        adjudication.PROMPT_B,
        "test",
        str(out),
        set(),
    )
    assert not adjudication.load_done(str(out))
