"""Keeps TASKS_ii_windows.md honest. The source of truth per task is a file
docs/seguimiento/<ID>.md (starts with "### ID: <ID>" and has a line "**Estado:** <STATE>");
`sync` renders them into section 15 of TASKS_ii_windows.md and sets the marks in the index table,
so nothing is edited twice by hand.

    python tasks_status.py sync      rebuild section 15 and the index marks from docs/seguimiento/
    python tasks_status.py show      count per state

Index row marks: [ ] TODO, [~] EN_CURSO / IMPLEMENTADA_SIN_VALIDAR_WINDOWS, [x] VERIFICADA /
YA_RESUELTA, [-] BLOQUEADA / DESCARTADA_CON_MOTIVO.
"""
import glob
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TASKS = os.path.join(ROOT, "TASKS_ii_windows.md")
FOLDER = os.path.join(ROOT, "docs", "seguimiento")
MARKS = {
    "TODO": " ", "EN_CURSO": "~", "IMPLEMENTADA_SIN_VALIDAR_WINDOWS": "~",
    "VERIFICADA": "x", "YA_RESUELTA": "x", "BLOQUEADA": "-", "DESCARTADA_CON_MOTIVO": "-",
}
LOG_HEADER = "## 15. Registro de ejecución"
ROW = re.compile(r"^\| \[.\] (\S+) \| (\S+) \|", re.M)


def read(path):
    return open(path, encoding="utf-8", newline="").read().replace("\r\n", "\n")


def sync():
    text = read(TASKS)
    index_order = [m.group(2) for m in ROW.finditer(text)]
    entries = {}
    for path in sorted(glob.glob(os.path.join(FOLDER, "*.md"))):
        body = read(path).strip("\n")
        m = re.match(r"### ID: (\S+)", body)
        if not m:
            sys.exit(f"{path}: must start with '### ID: <id>'")
        entries[m.group(1)] = body
    unknown = set(entries) - set(index_order)
    if unknown:
        sys.exit(f"entries for ids that are not in the index: {sorted(unknown)}")
    intro_path = os.path.join(FOLDER, "_intro.txt")
    intro = read(intro_path).strip("\n") if os.path.exists(intro_path) else ""

    rendered = []
    for task_id in index_order:
        if task_id not in entries:
            continue
        body = entries[task_id]
        state = re.search(r"\*\*Estado:\*\* (\w+)", body)
        if not state or state.group(1) not in MARKS:
            sys.exit(f"{task_id}: missing or unknown '**Estado:**'")
        row = re.compile(r"^\| \[.\] \S+ \| " + re.escape(task_id) + r" \|", re.M)
        text = row.sub(f"| [{MARKS[state.group(1)]}] {state.group(1)} | {task_id} |", text, count=1)
        rendered.append(body)

    head = text.split(LOG_HEADER, 1)[0].rstrip("\n")
    parts = [head, LOG_HEADER]
    if intro:
        parts.append(intro)
    parts.extend(rendered)
    open(TASKS, "w", encoding="utf-8", newline="").write("\n\n".join(parts) + "\n")
    print(f"synced {len(rendered)} entries")


def show():
    counts = {}
    for m in ROW.finditer(read(TASKS)):
        counts.setdefault(m.group(1), []).append(m.group(2))
    for state, ids in counts.items():
        print(f"{state}: {len(ids)}" + (f"  {' '.join(ids)}" if state != "TODO" else ""))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "sync":
        sync()
    elif cmd == "show":
        show()
    else:
        sys.exit(__doc__)
