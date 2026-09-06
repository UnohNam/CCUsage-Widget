#!/usr/bin/env python3
"""Codex CLI 사용 한도 수집기.

~/.codex/sessions/**/*.jsonl 에 API 응답의 rate_limits 가 그대로 기록된다.
CLI 를 호출할 필요 없이 가장 최근 기록을 읽으면 된다.

  primary   : window_minutes 300   → 5시간 세션 한도
  secondary : window_minutes 10080 → 주간 한도
"""
import json, os, re, glob, time

SESSIONS = os.path.expanduser("~/.codex/sessions")
TAIL_BYTES = 400_000     # 세션 파일 뒷부분만 읽는다
MAX_FILES = 8            # 최근 파일 몇 개까지 훑을지

RL = re.compile(r'"rate_limits"\s*:\s*(\{.*?\})\s*,\s*"(?:credits|individual_limit|plan_type)"', re.S)


def _tail(path, n=TAIL_BYTES):
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        size = f.tell()
        f.seek(max(0, size - n))
        return f.read().decode("utf-8", "replace")


def _extract(text):
    """마지막 rate_limits 객체를 꺼낸다. 중첩 괄호가 있어 수동으로 균형을 맞춘다."""
    idx = text.rfind('"rate_limits"')
    while idx != -1:
        start = text.find("{", idx)
        if start == -1:
            break
        depth, i = 0, start
        while i < len(text):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    try:
                        return json.loads(text[start:i + 1])
                    except Exception:
                        break
            i += 1
        idx = text.rfind('"rate_limits"', 0, idx)
    return None


def _window_label(minutes, scope):
    """창 길이에 맞는 라벨. 세션 창은 길이와 무관하게 '세션' 으로 통일한다."""
    if scope == "session":
        return "세션"
    if minutes is None:
        return "한도"
    if minutes >= 10000:
        return "주간 전체"
    if minutes >= 1440:
        return f"{minutes // 1440}일"
    if minutes >= 60:
        return f"{minutes // 60}시간"
    return f"{minutes}분"


def fetch():
    try:
        files = sorted(glob.glob(os.path.join(SESSIONS, "**", "*.jsonl"), recursive=True),
                       key=os.path.getmtime, reverse=True)
    except OSError:
        files = []

    for path in files[:MAX_FILES]:
        text = _tail(path)
        if '"rate_limits"' not in text:
            continue
        rl = _extract(text)
        if not rl:
            continue

        limits = []
        for key, scope in (("primary", "session"), ("secondary", "week")):
            w = rl.get(key)
            if not isinstance(w, dict) or w.get("used_percent") is None:
                continue
            limits.append({
                "scope": scope,
                "label": _window_label(w.get("window_minutes"), scope),
                "used": int(round(float(w["used_percent"]))),
                "reset": w.get("resets_at"),
            })
        if not limits:
            continue

        return {
            "ok": True,
            "fetched": os.path.getmtime(path),
            "plan": rl.get("plan_type"),
            "limits": limits,
            # 마지막 기록 시각이 오래됐으면 값이 낡았을 수 있다.
            "stale": time.time() - os.path.getmtime(path) > 6 * 3600,
        }

    return {"ok": False, "fetched": 0, "plan": None, "limits": [], "stale": True}


if __name__ == "__main__":
    import sys
    json.dump(fetch(), sys.stdout, ensure_ascii=False, indent=1)
    print()
