"""OpenPLC v4.3.2 file format: textual IEC POUs plus project task configuration."""
from pathlib import Path
import json
import re
from .platforms import split_st


def write_candidate(project: Path, src: str):
    parts=split_st(src)
    folders={"FUNCTION_BLOCK":"function-blocks","FUNCTION":"functions","PROGRAM":"programs"}
    folder=project/"pous"/folders[parts["kind"]]
    folder.mkdir(parents=True,exist_ok=True)
    # Types are separate global declarations rather than hidden replacement logic.
    for text in parts["types"]:
        types=project/"dataTypes"
        types.mkdir(exist_ok=True)
        name=re.search(r"TYPE\s+(\w+)",text,re.I)[1]
        (types/(name+".dt")).write_text(text,encoding="utf-8")
    body=parts["declaration"]+"\n"+parts["implementation"]+"\nEND_"+parts["kind"]+"\n"
    (folder/(parts["name"]+".st")).write_text(body,encoding="utf-8")
    if parts["kind"]=="FUNCTION_BLOCK":
        # Instantiate generated FB so the platform checks the actual POU.
        # VAR_IN_OUT parameters require caller-owned storage even for build-only use.
        inouts=[]
        decl=parts["declaration"]
        for block in re.findall(r"\bVAR_IN_OUT\b(.*?)\bEND_VAR\b",decl,re.I|re.S):
            for match in re.finditer(r"(\w+)\s*:\s*([^;]+);",block):
                inouts.append((match[1],match[2].strip()))
        variables="\n".join("    arg_"+name+" : "+dtype+";" for name,dtype in inouts)
        arguments=", ".join(name+":=arg_"+name for name,_ in inouts)
        main="PROGRAM main\nVAR\n    instanceUnderTest : "+parts["name"]+";\n"+variables+"\nEND_VAR\ninstanceUnderTest("+arguments+");\nEND_PROGRAM\n"
        (project/"pous"/"programs"/"main.st").write_text(main,encoding="utf-8")
    elif parts["kind"]=="PROGRAM":
        config=json.loads((project/"project.json").read_text(encoding="utf-8"))
        config["data"]["configuration"]["resource"]["instances"][0]["program"]=parts["name"]
        (project/"project.json").write_text(json.dumps(config,indent=2),encoding="utf-8")
