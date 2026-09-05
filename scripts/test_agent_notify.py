import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, Mock


spec = importlib.util.spec_from_file_location("agent_notify", Path(__file__).with_name("agent-notify.py"))
notify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notify)


class AgentNotifyTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "transcript.jsonl"
        self.codex = {"type": "agent-turn-complete", "thread-id": "thread", "turn-id": "turn", "last-assistant-message": "Done"}
        self.claude = {"hook_event_name": "Stop", "session_id": "session", "last_assistant_message": "Done"}

    def write(self, rows):
        self.path.write_text("".join(json.dumps(row) + "\n" for row in rows))

    def codex_rows(self, source="cli", end="task_complete", turn="turn", reply="Done"):
        return [
            {"type": "session_meta", "payload": {"source": source}},
            {"type": "event_msg", "payload": {"type": "task_started", "turn_id": turn}},
            {"type": "event_msg", "payload": {"type": end, "turn_id": turn, "last_agent_message": reply}},
        ]

    def claude_rows(self, reason="end_turn", ended=True):
        rows = [{"type": "assistant", "sessionId": "session", "uuid": "reply-id", "message": {
            "stop_reason": reason, "content": [{"type": "text", "text": "Done"}],
        }}]
        if ended:
            rows.append({"type": "system", "subtype": "turn_duration"})
        return rows

    def test_codex_requires_actual_turn_completion(self):
        self.write(self.codex_rows())
        self.assertIsNotNone(notify.codex_completion(self.path, self.codex))
        for event in ("agent_message", "item_completed", "turn_aborted"):
            with self.subTest(event=event):
                self.write(self.codex_rows(end=event))
                self.assertIsNone(notify.codex_completion(self.path, self.codex))

    def test_codex_child_agents_and_noninteractive_jobs_are_silent(self):
        for source in ({"subagent": {"thread_spawn": {"parent_thread_id": "parent"}}}, "exec", "unknown"):
            self.write(self.codex_rows(source=source))
            self.assertIsNone(notify.codex_completion(self.path, self.codex))

    def test_codex_rejects_another_turn_or_intermediate_reply(self):
        for kwargs in ({"turn": "older-turn"}, {"reply": "Working on it"}, {"reply": None}):
            self.write(self.codex_rows(**kwargs))
            self.assertIsNone(notify.codex_completion(self.path, self.codex))

    def test_codex_new_work_cancels_finish(self):
        self.write(self.codex_rows() + [{"type": "event_msg", "payload": {"type": "task_started", "turn_id": "next"}}])
        self.assertIsNone(notify.codex_completion(self.path, self.codex))

    def test_codex_requires_valid_payload_to_find_transcript(self):
        for payload in ({}, {"type": "approval-requested"}, self.codex):
            self.assertIsNone(notify.codex_path(payload))

    def test_codex_finds_only_the_notified_thread(self):
        thread = "01a06fbb-5c34-73e1-907d-d938b18e0e9c"
        directory = Path(self.temp.name) / "sessions/2026/09/05"
        directory.mkdir(parents=True)
        rollout = directory / f"rollout-2026-09-05T13-02-25-{thread}.jsonl"
        rollout.touch()
        with patch.dict(notify.os.environ, {"CODEX_HOME": self.temp.name}):
            self.assertEqual(notify.codex_path({**self.codex, "thread-id": thread}), rollout)

    def test_torn_and_malformed_records_do_not_fake_completion(self):
        self.write(self.codex_rows(end="item_completed"))
        with self.path.open("a") as stream:
            stream.write('not json\n{"type":"event_msg","payload":{"type":"task_complete"')
        self.assertIsNone(notify.codex_completion(self.path, self.codex))

    def test_missing_or_invalid_notification_is_silent(self):
        for argv in (["script"], ["script", "codex", "turn-ended"], ["script", "codex", "[]"], ["script", "codex", "{}"]):
            with patch.object(notify.sys, "argv", argv), patch.object(notify, "play_once") as play:
                notify.main()
                play.assert_not_called()

    def test_claude_waits_until_stop_hooks_have_finished(self):
        self.write(self.claude_rows(ended=False))
        self.assertIsNone(notify.claude_completion(self.path, self.claude))
        self.write(self.claude_rows())
        self.assertIsNotNone(notify.claude_completion(self.path, self.claude))

    def test_claude_tool_calls_and_intermediate_output_are_silent(self):
        for reason in ("tool_use", "max_tokens", None):
            self.write(self.claude_rows(reason=reason))
            self.assertIsNone(notify.claude_completion(self.path, self.claude))

    def test_claude_continuation_cancels_finish(self):
        for row in ({"type": "user"}, {"type": "assistant", "message": {"stop_reason": "tool_use"}}):
            self.write(self.claude_rows() + [row])
            self.assertIsNone(notify.claude_completion(self.path, self.claude))

    def test_claude_children_and_mismatched_replies_are_silent(self):
        self.write(self.claude_rows())
        for extra in ({"agent_id": "child"}, {"session_id": "another"}, {"last_assistant_message": "Working"}):
            self.assertIsNone(notify.claude_completion(self.path, {**self.claude, **extra}))
        rows = self.claude_rows()
        rows[0]["isSidechain"] = True
        self.write(rows)
        self.assertIsNone(notify.claude_completion(self.path, self.claude))

    def test_final_after_stop_hook_continuation_still_notifies(self):
        # stop_hook_active means a previous hook continued work, not that THIS end is invalid.
        self.write(self.claude_rows())
        self.assertIsNotNone(notify.claude_completion(self.path, {**self.claude, "stop_hook_active": True}))

    def test_waiting_only_for_actionable_prompts(self):
        self.write(self.claude_rows(reason="tool_use", ended=False))
        for kind in ("idle_prompt", "agent_completed", "auth_success", "unknown"):
            self.assertIsNone(notify.claude_waiting(self.path, {**self.claude, "notification_type": kind}))
        for kind in notify.WAITING_TYPES:
            self.assertIsNotNone(notify.claude_waiting(self.path, {**self.claude, "notification_type": kind}))

    def test_confirmed_completion_does_not_wait(self):
        sleep = Mock()
        self.assertEqual(notify.confirmed_completion(lambda: "done", sleep), "done")
        sleep.assert_not_called()

    def test_retry_observes_completion_record_after_flush(self):
        self.write(self.codex_rows(end="item_completed"))
        sleep = Mock(side_effect=lambda _: self.write(self.codex_rows()))
        self.assertIsNotNone(notify.confirmed_completion(lambda: notify.codex_completion(self.path, self.codex), sleep))
        sleep.assert_called_once()

    def test_elapsed_time_alone_never_announces_completion(self):
        self.write(self.codex_rows(end="item_completed"))
        sleep = Mock()
        self.assertIsNone(notify.confirmed_completion(lambda: notify.codex_completion(self.path, self.codex), sleep))
        self.assertEqual(sleep.call_count, 5)

    def test_repeated_notification_plays_once_and_uses_correct_sound(self):
        with patch.object(Path, "home", return_value=Path(self.temp.name)), patch.object(notify.subprocess, "run", return_value=Mock(returncode=0)) as play:
            notify.play_once("completion-1", "finished")
            notify.play_once("completion-1", "finished")
            self.assertEqual(play.call_count, 1)
            self.assertEqual(play.call_args.args[0][-1], str(notify.SOUNDS["finished"]))
            notify.play_once("waiting-1", "waiting")
            self.assertEqual(play.call_count, 2)
            self.assertEqual(play.call_args.args[0][-1], str(notify.SOUNDS["waiting"]))

    def test_failed_play_can_retry(self):
        with patch.object(Path, "home", return_value=Path(self.temp.name)), patch.object(notify.subprocess, "run", return_value=Mock(returncode=1)) as play:
            notify.play_once("done", "finished")
            notify.play_once("done", "finished")
            self.assertEqual(play.call_count, 2)


if __name__ == "__main__":
    unittest.main()
