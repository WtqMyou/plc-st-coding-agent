"""Save a reviewable complete text patch against the preserved v1.1 source."""
import difflib
import hashlib
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from stbench.evaluation import atomic_json


def main():
    base=ROOT.parent/"交付包_stbench_v1.1_20261026"/"stbench"
    if not base.is_dir():raise FileNotFoundError("Preserved v1.1 source is required to create the revision patch")
    changes=[];patch=[]
    names=set()
    for root in (base,ROOT):
        for folder in ("stbench","datasets","tests","scripts","docs"):
            for p in (root/folder).rglob("*"):
                if p.is_file() and p.suffix in (".py",".st",".json",".md",".mmd",".txt"):
                    names.add(p.relative_to(root).as_posix())
        for name in ("README.md","requirements.txt","config.example.json",".gitignore"):
            if (root/name).is_file():names.add(name)
    for name in sorted(names):
        a,b=base/name,ROOT/name
        old=a.read_bytes() if a.is_file() else b""
        new=b.read_bytes() if b.is_file() else b""
        if old==new:continue
        changes.append(dict(path=name,old_sha256=hashlib.sha256(old).hexdigest() if a.is_file() else None,
                            new_sha256=hashlib.sha256(new).hexdigest() if b.is_file() else None))
        patch.extend(difflib.unified_diff(old.decode("utf-8-sig").splitlines(True),
            new.decode("utf-8-sig").splitlines(True),fromfile="v1.1/"+name,tofile="v2.0/"+name))
    target=ROOT/"evidence"/"revisions"
    target.mkdir(parents=True,exist_ok=True)
    patch=[line if line.endswith("\n") else line+"\n\\ No newline at end of file\n" for line in patch]
    (target/"v1.1_to_v2.0.patch").write_text("".join(patch),encoding="utf-8")
    atomic_json(target/"changes.json",dict(base=str(base),changes=changes))
    print("Recorded",len(changes),"changed or new text files")


if __name__=="__main__":main()
