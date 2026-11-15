#!/usr/bin/env python3
"""What Claude's answer was about, for Clawd: clawd-hook.sh runs this on Claude Code's Stop hook (its
JSON on stdin) and writes the word it prints into ~/.cache/clawd/activity.json as "kind".

    running   background work is still going (the hook's background_tasks), or the answer says so
    question  Claude can't go on without the user: a real question, or something only the user can do
              (a root command); an offer of a next step doesn't count
    stuck     the answer's first sentence says Claude couldn't get something to work
    fixed     the answer opens with a fix (or with the cause of a problem, after changing things)
    done      the turn changed things (edited files, or ran commands and opens with a result)
    found     research or an explanation: the turn read, searched or ran read-only commands
    chat      a short answer with no tools

The signals: which tools the turn used (from the transcript, since the person's last message), the
answer's first paragraph (where the outcome is stated) and its last two paragraphs (where questions
and offers go). Code blocks are left out. It never fails the hook: on any error it prints nothing.
"""
import json
import re
import sys
from pathlib import Path

EDITS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
LOOKS = {"Read", "Grep", "Glob", "LS", "WebSearch", "WebFetch", "NotebookRead"}

RUNNING = re.compile(r"\b(is|are) (still )?(running|going|in progress|underway)\b|\b(i'll|i will) (report|check back|"
                     r"let you know|update you)\b|\bwhen it (finishes|completes|is done|'s done)\b|\bshould take (about |around )?\d")
OFFER = re.compile(r"(^|[;:,(—–]\s*)(want me to|do you want me to|would you like me to|should i|shall i|i can (also|then)\b|if you('d| would)? like"
                   r"|happy to|let me know if|say the word|or i can)")
ASK = re.compile(r"\b(which (one|do you|would you)|do you (want|prefer|have)|would you (prefer|rather)|what do you "
                 r"(think|want|prefer)|can you|could you|please (run|check|confirm|try|restart|reboot|log|tell|send|paste|type|"
                 r"approve|open)|before i (go on|continue|start)|type `?!)")
# something only the user can do (a root command, a password), anywhere in the answer's ends
REQUEST = re.compile(r"\b(please run|tell me when|you('ll| will)? need to (run|type|enter|approve|restart|reboot|log|plug|install)|run (this|these|"
                     r"it|them) (in|from) your|in your own terminal|type `?!)")
# the first sentence says Claude couldn't get there
STUCK = re.compile(r"^(i|it|that|this|the \w+) (still )?(couldn't|could not|can't get|wasn't able to|failed to|didn't work|doesn't work|"
                   r"isn't working|won't (start|build|run|work))|\bstill (fails|failing|broken|doesn't work|not working)\b|\bno luck\b"
                   r"|\b(i'm|i am) stuck\b")
FIXED = re.compile(r"\b(fixed|the fix\b|fix(es)? (is|are) in\b|resolved|no longer|works now|working again|back (on|to normal)|repaired)\b")
CAUSE = re.compile(r"\b(the cause|caused by|culprit|root cause)\b")
RESULT = re.compile(r"\b(done|finished|complete|completed|is live|in place|installed|deployed|committed|pushed|published|set up|"
                    r"added|created|built|updated|wired|enabled|ready|removed|moved|renamed|applied|switched|works|passes|pass"
                    r"|now (has|have|is|are|shows?|uses?|runs?))\b")


def turn_tools(path):
    """The tools Claude used since the last prompt (the person's message, or a background task's notice)."""
    tools = []
    for raw in reversed(Path(path).read_bytes().splitlines()):
        if b'"type":"assistant"' not in raw and b'"type":"user"' not in raw:
            continue
        r = json.loads(raw)
        msg = r.get("message") or {}
        content = msg.get("content")
        if r.get("type") == "user":
            kind = (r.get("origin") or {}).get("kind")
            prompt = kind in ("human", "task-notification") or (kind is None and not r.get("isMeta") and (
                isinstance(content, str) or any(b.get("type") == "text" for b in content or [])))
            if prompt:
                break
        elif isinstance(content, list):
            tools += [b.get("name", "") for b in content if b.get("type") == "tool_use"]
    return tools


def sentences(paragraph):
    return [s for s in re.split(r"(?<=[.!?])\s+", paragraph.strip()) if s]


def classify(message, tools=(), background=()):
    if background:
        return "running"
    text = re.sub(r"`[^`\n]*`", "code", re.sub(r"```.*?```", "", message or "", flags=re.S))
    paras = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
    if not paras:
        return "chat"
    first = paras[0].lower()
    tail = [s.lower().strip(" *_`") for p in paras[-2:] for s in sentences(p)]
    edited = any(t in EDITS for t in tools)
    ran = "Bash" in tools
    looked = any(t in LOOKS or t.startswith("mcp__") for t in tools)
    busy = edited or ran or looked

    # still going, as the opening says ("nothing else is running" and "whether it's running" don't count)
    if any(not re.search(r"\b(nothing|no longer|not|whether|if)\b[^.;:]*$", first[:m.start()]) for m in RUNNING.finditer(first)):
        return "running"
    # a real question needs an answer before Claude can go on; an offer of a next step doesn't
    asked = any(s.endswith("?") and not OFFER.search(s) for s in tail)
    direct = any(ASK.search(s) and not OFFER.search(s) for s in tail)
    if asked or direct or REQUEST.search(first) or any(REQUEST.search(s) for s in tail):
        return "question"
    opening = (sentences(first) or [""])[0]
    if STUCK.search(opening) and not FIXED.search(opening):
        return "stuck"
    if FIXED.search(first) or ((edited or ran) and CAUSE.search(first)):
        return "fixed"
    if edited or (ran and RESULT.search(first)):
        return "done"
    if busy or len(text) > 600:
        return "found"
    return "chat"


def main():
    try:
        hook = json.load(sys.stdin)
        try:
            tools = turn_tools(hook.get("transcript_path") or "")
        except (OSError, ValueError):
            tools = []
        print(classify(hook.get("last_assistant_message") or "", tools, hook.get("background_tasks") or []))
    except Exception:                               # Clawd just doesn't learn anything this time
        pass


if __name__ == "__main__":
    main()
