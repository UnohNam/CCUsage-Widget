#!/usr/bin/env python3
"""플랜 한도(실제 남은 사용량) 수집기.

`claude -p "/usage"` 출력을 파싱한다. 한도 값은 서버가 주는 것이라
~/.claude/projects 의 JSONL 에는 없다. 호출에 약 4초 걸리므로 TTL 캐시를 둔다.
"""
import json, os, re, subprocess, time
from datetime import datetime

CACHE = os.path.expanduser("~/.claude/widgets/ccusage/limits-cache.json")
TTL = 300          # 5분
TIMEOUT = 25

# "Current session: 29% used · resets Sep 7 at 3:09am (Asia/Seoul)"
LINE = re.compile(
    r"^Current\s+(?P<scope>[^:]+):\s+(?P<pct><?\s*\d+)%\s+used\s*[·\-]\s*resets\s+(?P<reset>[^(]+?)\s*(?:\((?P<tz>[^)]+)\))?\s*$"
)


def parse_reset(text, now=None):
    """'Sep 7 at 3:09am' / 'Sep 13 at 6pm' -> epoch seconds (실패 시 None)."""
    now = now or datetime.now()
    text = text.strip().replace(" at ", " ")
    for fmt in ("%b %d %I:%M%p", "%b %d %I%p", "%b %d %H:%M"):
        try:
            # 연도를 명시해야 윤일 파싱과 경고 문제를 피한다.
            dt = datetime.strptime(f"{text} {now.year}", fmt + " %Y")
        except ValueError:
            continue
        # 연말 경계: 파싱 결과가 한참 과거면 내년으로 본다.
        if (now - dt).days > 180:
            dt = dt.replace(year=now.year + 1)
        return dt.timestamp()
    return None


def label_for(scope):
    s = scope.strip().lower()
    if s == "session":
        return "session", "세션"
    m = re.match(r"week\s*\((.+)\)", s)
    if m:
        inner = m.group(1)
        if "all" in inner:
            return "week", "주간 전체"
        return "week_model", "주간 " + m.group(1).strip().title()
    return s.replace(" ", "_"), scope.strip()


def parse(output):
    out = []
    for line in output.splitlines():
        m = LINE.match(line.strip())
        if not m:
            continue
        scope, label = label_for(m.group("scope"))
        pct = int(re.sub(r"\D", "", m.group("pct")) or 0)
        out.append({
            "scope": scope,
            "label": label,
            "used": pct,
            "reset": parse_reset(m.group("reset")),
            "reset_text": m.group("reset").strip(),
        })
    return out


def load_cache():
    try:
        with open(CACHE) as f:
            return json.load(f)
    except Exception:
        return None


def fetch(force=False):
    cached = load_cache()
    if not force and cached and time.time() - cached.get("fetched", 0) < TTL:
        return cached

    try:
        p = subprocess.run(["claude", "-p", "/usage"],
                           capture_output=True, text=True, timeout=TIMEOUT,
                           cwd=os.path.expanduser("~"))
        limits = parse(p.stdout)
    except Exception:
        limits = []

    if not limits:
        # 실패하면 마지막으로 성공한 값을 stale 표시와 함께 유지한다.
        if cached and cached.get("limits"):
            cached["stale"] = True
            return cached
        return {"fetched": time.time(), "limits": [], "stale": True}

    result = {"fetched": time.time(), "limits": limits, "stale": False}
    try:
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        tmp = CACHE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(result, f)
        os.replace(tmp, CACHE)
    except OSError:
        pass
    return result


if __name__ == "__main__":
    import sys
    json.dump(fetch(force="--force" in sys.argv), sys.stdout, ensure_ascii=False, indent=1)
    print()
