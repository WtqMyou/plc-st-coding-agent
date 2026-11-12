from .cli import main
from .providers.base import ProviderError
import sys
try:
    raise SystemExit(main())
except ProviderError as exc:
    print(str(exc),file=sys.stderr)
    raise SystemExit(2)
