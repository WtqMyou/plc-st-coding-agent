"""Current-user Windows DPAPI credential loading; never log plaintext keys."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import shutil
import urllib.request
import urllib.error
import f14_study as base
from stbench.providers.base import ProviderError
from stbench.campaign import credentials

SECONDARY_ENV='F14_DMXAPI_SECONDARY_KEY'

def unseal(path):
    path=Path(path)
    if os.name!='nt' or not path.is_file():raise ProviderError('Current-user encrypted secondary credential is unavailable')
    shell=Path(shutil.which('pwsh') or 'C:/Users/27478/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe')
    if not shell.is_file():raise ProviderError('PowerShell 7 runtime is unavailable for DPAPI loading')
    # The shell command and argv contain the encrypted file path, never its plaintext key.
    script="$ErrorActionPreference='Stop'; $secure=ConvertTo-SecureString ([IO.File]::ReadAllText($args[0])); $pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure); try { [Console]::Out.Write([Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)); } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer); $secure.Dispose(); }"
    # -Command arguments are code-parsed by Windows PowerShell; pass the path via a task-specific environment variable instead.
    script=script.replace('$args[0]','$env:F14_SEALED_CREDENTIAL_PATH')
    result=subprocess.run([str(shell),'-NoProfile','-NonInteractive','-Command',script],capture_output=True,
        text=True,encoding='utf-8',env=dict(os.environ,F14_SEALED_CREDENTIAL_PATH=str(path)),timeout=20,
        creationflags=subprocess.CREATE_NO_WINDOW)
    if result.returncode or len(result.stdout.strip())<20:raise ProviderError('Secondary DPAPI credential could not be decrypted; no key output logged')
    return result.stdout.strip()

def load_credentials(cfg):
    credentials(cfg)
    primary=os.environ.get('DMXAPI_API_KEY','')
    secondary=unseal(cfg['credential_rotation']['secondary_dpapi_path'])
    if primary==secondary:raise ProviderError('Secondary key is identical to primary; refusing an ambiguous key rotation')
    os.environ[SECONDARY_ENV]=secondary
    return {slot:hashlib.sha256(value.encode()).hexdigest() for slot,value in (('primary',primary),('secondary',secondary))}

def catalog(cfg,slot):
    key=os.environ['DMXAPI_API_KEY' if slot=='primary' else SECONDARY_ENV]
    request=urllib.request.Request('https://www.dmxapi.cn/v1/models',headers={'Authorization':'Bearer '+key})
    try:
        with urllib.request.urlopen(request,timeout=30) as reply:data=json.load(reply)
    except urllib.error.HTTPError as exc:raise ProviderError('Read-only '+slot+' model catalog HTTP '+str(exc.code)) from None
    except (OSError,ValueError) as exc:raise ProviderError('Read-only '+slot+' model catalog '+type(exc).__name__) from None
    names={m.get('id') for m in data.get('data',[]) if isinstance(m,dict)}
    selected={m['model']:m['model'] in names for m in cfg['models']}
    if not all(selected.values()):raise ProviderError('Required models missing for '+slot+' credential; no paid request sent')
    return dict(credential_batch=slot,authenticated=True,endpoint='https://www.dmxapi.cn/v1',selected_models=selected,generation_requests=0)

def provider_factory(spec,budget,**kwargs):
    from full_r8b_transport import MeteredProvider
    selected=dict(spec,api_key_env='DMXAPI_API_KEY' if budget.active_batch=='primary' else SECONDARY_ENV)
    return MeteredProvider(selected,budget,**kwargs)
