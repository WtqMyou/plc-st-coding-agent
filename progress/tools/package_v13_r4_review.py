"""Package the frozen r4 review materials, without changing the frozen version."""
import hashlib
import json
from pathlib import Path
import sys
import zipfile

REPO=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(REPO/'progress/v13_r4'))
import r4_revision as v


def main():
    v.verify_parent()
    manifest=json.loads((v.ROOT/'snapshot_manifest.json').read_text('utf-8'))
    for name,sha in {**manifest['files'],**manifest['evidence_sha256']}.items():
        assert v.digest((REPO/name).read_bytes())==sha,name
    names=['README.md','意见2采纳与核验.md','复审记录.md','复审材料.html']
    entries={name:(v.ROOT/name).read_bytes() for name in names}
    for p in v.problems():
        if p.pid not in v.CHANGED+v.FIVE:continue
        for platform in ('codesys','openplc'):
            name=f'adapted/{platform}/{p.pid}_{platform}.json'
            entries[name]=(v.ROOT/name).read_bytes()
        name=f'datasets/{p.source}/{p.pid}.json'
        entries[name]=(v.ROOT/name).read_bytes()
    entries['技术验收.json']=(REPO/'progress/evidence/v13_r4_20261108/acceptance.json').read_bytes()
    entries['先读这里.txt']=('刘晏铭：请先打开复审材料.html，按复审记录.md填写“通过／需修改／无法确认”、依据及实际日期。\n'
        '本包为r4，覆盖五道工业题及新增三题契约修订。全库35题583用例，包内提供八题的原工作JSON及双平台适配JSON。\n'
        '自动验收不能代替工艺结论；旧531例Word只作历史备查，不属于本包当前版本。\n'
        '请确认PI切换范围、三拍时间口径、阈值为算例、流量单位与复位上升沿。\n'
        '不要求连接PLC或调用模型。原始题与平台适配题的口径不可混用。\n').encode('utf-8')
    listing={name:dict(bytes=len(raw),sha256=v.digest(raw)) for name,raw in entries.items()}
    entries['文件校验.json']=(json.dumps(dict(version=v.VERSION,files=listing),ensure_ascii=False,indent=2)+'\n').encode()
    target=REPO/'progress/工艺复审_r4_刘晏铭_20261108.zip'
    assert not target.exists(),'Existing handout is immutable; use a new filename'
    with zipfile.ZipFile(target,'x',compression=zipfile.ZIP_DEFLATED) as archive:
        for name,raw in sorted(entries.items()):
            info=zipfile.ZipInfo(name,(2026,11,8,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED
            archive.writestr(info,raw)
    with zipfile.ZipFile(target) as archive:
        assert archive.testzip() is None
        assert set(archive.namelist())==set(entries)
        for name,raw in entries.items():assert archive.read(name)==raw
    out=REPO/'progress/evidence/v13_r4_handout_20261108/manifest.json'
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(dict(version=v.VERSION,zip=target.relative_to(REPO).as_posix(),
        zip_sha256=v.digest(target.read_bytes()),snapshot_sha256=v.digest((v.ROOT/'snapshot_manifest.json').read_bytes()),
        builder_sha256=v.digest(Path(__file__).read_bytes()),files=listing),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('PASS frozen review handout:',len(entries),'files; contents and CRC verified')


if __name__=='__main__':main()
