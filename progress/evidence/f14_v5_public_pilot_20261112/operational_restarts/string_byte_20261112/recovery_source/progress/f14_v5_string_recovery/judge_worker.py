"""Isolated V5 judge extension. Frozen original source and candidate text are untouched."""
import importlib.util
from pathlib import Path
import sys
ORIGINAL=Path(__file__).resolve().parent.parent/'f14_agent_v5'
sys.path.insert(0,str(ORIGINAL))
sys.path.insert(0,str(ORIGINAL/'release'))
from conversion_patch import install
install()
spec=importlib.util.spec_from_file_location('frozen_v5_worker',ORIGINAL/'judge_worker.py')
worker=importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)
if __name__=='__main__':worker.main()

