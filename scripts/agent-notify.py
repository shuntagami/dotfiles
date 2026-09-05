#!/usr/bin/env python3
"""Own agent notification sounds, independently of the terminal application."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from uuid import UUID


ROOT = Path(__file__).resolve().parent.parent
SOUNDS = {
    "finished": ROOT / "static/turn-finished-chime.mp3",
    "waiting": ROOT / "static/waiting-chime.mp3",
}
WAITING_TYPES = {"permission_prompt", "elicitation_dialog", "elicitation_url_dialog"}
SETTLE_SECONDS = 2
VOLUME = "0.15"


def records(path):
    # Read a bounded tail: long-running conversations can be hundreds of MB.
    with path.open("rb") as stream:
        stream.seek(0, 2)
        offset = max(0, stream.tell() - 256 * 1024)
        stream.seek(offset)
        if offset:
            stream.readline()
        for line in stream:
            if not line.endswith(b"\n"):
                continue
            try:
                row = json.loads(line)
            except (ValueError, UnicodeError):
                continue
            if isinstance(row, dict):
                yield row


def codex_path(payload):
    if payload.get("type") != "agent-turn-complete" or not payload.get("turn-id"):
        return None
    try:
        thread = str(UUID(payload["thread-id"]))
    except (KeyError, ValueError, TypeError, AttributeError):
        return None
    home = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
    return next((home / "sessions").glob(f"*/*/*/rollout-*-{thread}.jsonl"), None)


def codex_completion(path, payload):
    with path.open() as stream:
        meta = json.loads(stream.readline())
    # Child agents inherit notify too. Their completion does not finish the main turn.
    if meta.get("type") != "session_meta" or meta.get("payload", {}).get("source") not in ("cli", "vscode"):
        return None
    boundary = None
    for row in records(path):
        event = row.get("payload", {})
        if row.get("type") == "event_msg" and event.get("type") in ("task_started", "task_complete", "turn_aborted"):
            boundary = event
    if not boundary or boundary.get("type") != "task_complete" or boundary.get("turn_id") != payload["turn-id"]:
        return None
    reply = boundary.get("last_agent_message")
    if not reply or reply != payload.get("last-assistant-message"):
        return None
    return f"codex:{payload['thread-id']}:{payload['turn-id']}"


def claude_completion(path, payload):
    if payload.get("hook_event_name") != "Stop" or payload.get("agent_id"):
        return None
    last = None
    ended = False
    for row in records(path):
        if row.get("isSidechain"):
            continue
        if row.get("type") in ("assistant", "user"):
            last = row
            ended = False
        elif row.get("type") == "system" and row.get("subtype") == "turn_duration":
            # Emitted after Stop hooks finish. A Stop hook can itself resume the agent.
            ended = True
    if not ended or not last or last.get("type") != "assistant":
        return None
    if last.get("sessionId") != payload.get("session_id"):
        return None
    message = last.get("message", {})
    if message.get("stop_reason") != "end_turn":
        return None
    content = message.get("content", [])
    if not isinstance(content, list) or any(item.get("type") == "tool_use" for item in content):
        return None
    reply = "\n".join(item.get("text", "") for item in content if item.get("type") == "text")
    if not reply or (payload.get("last_assistant_message") is not None and reply != payload["last_assistant_message"]):
        return None
    identity = last.get("uuid")
    return f"claude:{payload['session_id']}:{identity}" if identity else None


def settled_completion(read, sleep=time.sleep):
    # Legacy notify can precede the rollout flush; async Stop can precede turn_duration.
    # Retry briefly, then require the SAME completion after a quiet confirmation window.
    for _ in range(6):
        token = read()
        if token:
            sleep(SETTLE_SECONDS)
            return token if read() == token else None
        sleep(0.5)
    return None


def claude_waiting(path, payload):
    # idle_prompt is a reminder, often after an already announced finish, not a new block.
    if payload.get("notification_type") not in WAITING_TYPES or payload.get("agent_id"):
        return None
    last = None
    for row in records(path):
        if not row.get("isSidechain") and row.get("type") in ("assistant", "user"):
            last = row
    if not last or last.get("sessionId") != payload.get("session_id") or not last.get("uuid"):
        return None
    return f"waiting:{payload['session_id']}:{last['uuid']}:{payload['notification_type']}"


def play_once(token, kind):
    state = Path.home() / ".cache/agent-completion-chime"
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    # Atomic across duplicate notify processes; store no prompt or response text.
    marker = state / hashlib.sha256(token.encode()).hexdigest()
    try:
        fd = os.open(marker, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        return
    os.close(fd)
    try:
        result = subprocess.run(["afplay", "-v", VOLUME, str(SOUNDS[kind])], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode:
            marker.unlink(missing_ok=True)
    except OSError:
        marker.unlink(missing_ok=True)


def main():
    try:
        agent = sys.argv[1]
        payload = json.loads(sys.argv[-1] if agent == "codex" else sys.stdin.read())
        if not isinstance(payload, dict):
            return
        if agent == "codex":
            path = codex_path(payload)
            check = codex_completion
        elif agent == "claude" and payload.get("transcript_path"):
            path = Path(payload["transcript_path"]).expanduser()
            if payload.get("hook_event_name") == "Notification":
                token = claude_waiting(path, payload)
                if token:
                    play_once(token, "waiting")
                return
            check = claude_completion
        else:
            return
        if path:
            token = settled_completion(lambda: check(path, payload))
            if token:
                play_once(token, "finished")
    except (OSError, ValueError, KeyError, TypeError, AttributeError, IndexError):
        # Unknown/missing transcript data must never become a completion sound.
        return


if __name__ == "__main__":
    main()
