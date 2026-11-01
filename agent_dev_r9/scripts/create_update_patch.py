"""Save the complete v2.0 -> v2.1 source delta from the preserved delivery ZIP."""
import difflib
import hashlib
import json
import zipfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]


def main():
    base = ROOT.parent / "成员2_Agent前期交接包_v2.0_20261027.zip"
    folders = {"stbench", "datasets", "scripts", "tests", "docs"}
    suffixes = {".py", ".st", ".json", ".md", ".mmd", ".txt"}
    def selected(name):
        path = Path(name)
        return ((path.parts[0] in folders and path.suffix in suffixes) or len(path.parts)==1) and "__pycache__" not in path.parts
    with zipfile.ZipFile(base) as z:
        old = {n[len("agent_dev/"):]:z.read(n) for n in z.namelist()
               if n.startswith("agent_dev/") and not n.endswith("/") and selected(n[len("agent_dev/"):])
               and Path(n).name != "MANIFEST_v2.json"}
    new = {p.relative_to(ROOT).as_posix():p.read_bytes() for p in ROOT.rglob("*") if p.is_file()
           and selected(p.relative_to(ROOT).as_posix()) and p.name not in ("MANIFEST_v2.json", "config.local.json", ".env")}
    rows, patch = [], []
    for name in sorted(old.keys() | new.keys()):
        a, b = old.get(name,b""), new.get(name,b"")
        if a == b:continue
        rows.append(dict(path=name, before_sha256=hashlib.sha256(a).hexdigest() if name in old else None,
                         after_sha256=hashlib.sha256(b).hexdigest() if name in new else None))
        for line in difflib.unified_diff(a.decode("utf-8-sig").splitlines(True), b.decode("utf-8-sig").splitlines(True),
                                        fromfile="v2.0/"+name, tofile="v2.1/"+name):
            patch.append(line if line.endswith("\n") else line+"\n\\ No newline at end of file\n")
    out = ROOT / "evidence/revisions"
    (out / "v2.0_to_v2.1.patch").write_text("".join(patch), encoding="utf-8")
    (out / "changes_v2.1.json").write_text(json.dumps(dict(base_package=base.name,
        base_sha256=hashlib.sha256(base.read_bytes()).hexdigest(), changes=rows), ensure_ascii=False, indent=2), encoding="utf-8")
    print("Recorded",len(rows),"changed/new text files against v2.0")


if __name__ == "__main__":main()
