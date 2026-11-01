"""Import the reviewed upstream delta without replacing the repaired Agent engine.

Idempotent for the imported files; originals and the v2.0 archive stay untouched.
"""
from pathlib import Path
import hashlib
import json
import shutil
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
UPDATE = ROOT.parent / "组员二次更新"
UPSTREAM = UPDATE / "upstream_v1.2" / "交付包_stbench_v1.2_20261027"
NEW_IDS = ["self-hard-05", "self-hard-06", "self-hard-07", "self-medium-05", "self-medium-06"]


def main():
    if (ROOT / "evidence" / "upstream_v1.2_import.json").exists():
        raise SystemExit("v1.2 already imported; local reviewed corrections will not be overwritten")
    paths = ["datasets/selfmade_new5.py", "datasets/public/public-easy-02.json"]
    for pid in NEW_IDS:
        paths += [f"datasets/selfmade/{pid}.json", f"datasets/selfmade/tests/{pid}.reference.st"]
    rows = []
    for name in paths:
        src, dst = UPSTREAM / "stbench" / name, ROOT / name
        before = hashlib.sha256(dst.read_bytes()).hexdigest() if dst.exists() else None
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
        rows.append(dict(path=name, previous_sha256=before, upstream_sha256=hashlib.sha256(src.read_bytes()).hexdigest()))
    docs = ROOT / "docs" / "upstream_v1.2"
    docs.mkdir(parents=True, exist_ok=True)
    for name in ("00_先读我.md", "CHANGELOG_v1.2_前后差异.md", "dataset_freeze_v1.2.json"):
        shutil.copyfile(UPSTREAM / name, docs / name)
    shutil.copyfile(UPDATE / "流程工业自建题库_五题评审草案.md", docs / "流程工业自建题库_五题评审草案.md")
    with zipfile.ZipFile(UPDATE / "组员消息.docx") as z:
        tree = ET.fromstring(z.read("word/document.xml"))
    ns = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
    paragraphs = ["".join(t.text or "" for t in p.findall(".//w:t", ns)) for p in tree.findall(".//w:p", ns)]
    (docs / "组员消息摘录.md").write_text("# 原始消息摘录\n\n" + "\n\n".join(filter(None, paragraphs)) + "\n", encoding="utf-8")
    files = []
    for p in sorted(UPDATE.iterdir()):
        if p.is_file():
            files.append(dict(path=p.name, bytes=p.stat().st_size, sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
    out = ROOT / "evidence" / "upstream_v1.2_import.json"
    out.write_text(json.dumps(dict(date="2026-10-30", sources=files, imported=rows,
        policy="Add five tasks; preserve v2 Agent and old repaired references; independently revalidate upstream claims"),
        ensure_ascii=False, indent=2), encoding="utf-8")
    print("Imported", len(rows), "files; preserved existing Agent and reference repairs")


if __name__ == "__main__":
    main()
