"""Retry transient Windows file sharing conflicts, never a model request."""
import json
import os
from pathlib import Path
import shutil
import time
import uuid

def file_operation(operation,*,seconds=6):
    deadline=time.monotonic()+seconds
    while True:
        try:return operation()
        except PermissionError:
            if time.monotonic()>=deadline:raise
            time.sleep(.05)

def atomic_json(path,value):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    temporary=path.with_name(path.name+'.'+uuid.uuid4().hex+'.tmp')
    data=json.dumps(value,ensure_ascii=False,indent=2).encode('utf-8')
    file_operation(lambda:temporary.write_bytes(data))
    file_operation(lambda:os.replace(temporary,path))

def copyfile(source,destination):
    return file_operation(lambda:shutil.copyfile(source,destination))
