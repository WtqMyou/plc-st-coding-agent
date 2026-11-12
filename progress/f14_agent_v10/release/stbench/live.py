"""Explicit live-experiment configuration. No models, provider, or budget defaults."""
from __future__ import annotations
import json
import math
import os
import re
import threading
from pathlib import Path
from .evaluation import atomic_json
from .providers.base import ProviderError, get_provider
_LEDGER_LOCKS={}


def validate_live_config(config: dict) -> None:
    if config.get("live_enabled") is not True:
        raise ProviderError("Live calls are disabled; specify models and approve a budget first")
    budget = config.get("budget_cny")
    if isinstance(budget, bool) or not isinstance(budget, (int, float)) or not math.isfinite(budget) or budget <= 0:
        raise ProviderError("A positive explicit budget_cny is required")
    models = config.get("models", [])
    if len(models) < 2:
        raise ProviderError("At least two explicitly selected real models are required")
    identities = set()
    labels=set()
    for m in models:
        for key in ("id", "provider", "model", "base_url", "api_key_env",
                    "input_cny_per_million", "output_cny_per_million"):
            if key not in m or m[key] in (None, ""):
                raise ProviderError("Missing live model field: " + key)
        if m["provider"] not in ("openai-compat", "anthropic"):
            raise ProviderError("Supported protocols: openai-compat or anthropic")
        if not isinstance(m["id"],str) or not re.fullmatch(r"[\w.-]+",m["id"]) or m["id"] in (".","..") or m["id"] in labels:
            raise ProviderError("Model labels must be unique safe directory names")
        labels.add(m["id"])
        if not m["base_url"].startswith("https://"):
            raise ProviderError("Live endpoint must use HTTPS")
        if str(m["model"]).lower() in ("mock", "default", "auto"):
            raise ProviderError("A concrete real model name is required")
        for rate in ("input_cny_per_million", "output_cny_per_million"):
            value=m[rate]
            if isinstance(value,bool) or not isinstance(value,(int,float)) or not math.isfinite(value) or value<0:
                raise ProviderError("Invalid explicit price: "+rate)
        identity=(m["base_url"],m["model"])
        if identity in identities:
            raise ProviderError("Model entries must be distinct; aliases require identity verification")
        identities.add(identity)


class Budget:
    """One shared durable ledger; failed requests retain their worst-case reservation."""
    def __init__(self, path: Path, limit: float):
        self.path, self.limit, self.lock = path, limit, _LEDGER_LOCKS.setdefault(str(path.resolve()),threading.Lock())
        self.state = json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {"spent_cny": 0., "events": []}
        if not isinstance(self.state.get("spent_cny"), (float,int)) or self.state["spent_cny"]<0:
            raise ProviderError("Corrupt budget ledger; refusing calls")

    def reserve(self, amount: float) -> int:
        with self.lock:
            if self.path.is_file():
                self.state=json.loads(self.path.read_text(encoding="utf-8"))
            if not math.isfinite(amount) or amount<0:
                raise ProviderError("Invalid budget reservation")
            if self.state["spent_cny"] + amount > self.limit:
                raise ProviderError("Budget exhausted; no request was sent")
            self.state["spent_cny"] += amount
            self.state["events"].append({"reserved_cny":amount, "status":"reserved"})
            atomic_json(self.path, self.state)
            return len(self.state["events"])-1

    def settle(self, index: int, actual: float):
        with self.lock:
            self.state=json.loads(self.path.read_text(encoding="utf-8"))
            e=self.state["events"][index]
            self.state["spent_cny"] += actual-e["reserved_cny"]
            e.update(status="settled",actual_cny=actual)
            atomic_json(self.path,self.state)


class BudgetedProvider:
    def __init__(self, inner, spec, budget):
        self.inner, self.spec, self.budget=inner,spec,budget
        self.model,self.name=inner.model,inner.name
    @property
    def timeout(self):
        return self.inner.timeout
    @timeout.setter
    def timeout(self,value):
        self.inner.timeout=value
    def generate(self,messages):
        # Conservative UTF-8 byte upper bound plus serialization overhead.
        input_upper=len(json.dumps(messages,ensure_ascii=False).encode("utf-8"))+4096
        upper=(input_upper*self.spec["input_cny_per_million"]+
               self.inner.max_tokens*self.spec["output_cny_per_million"])/1e6
        index=self.budget.reserve(upper)
        response=self.inner.generate(messages)
        if not isinstance((response.raw or {}).get("model"),str) or not response.raw["model"].strip():
            raise ProviderError("Missing actual model identity; worst-case budget reservation retained")
        usage=response.usage
        raw_usage=(response.raw or {}).get("usage",{})
        required=("input_tokens","output_tokens") if self.spec["provider"]=="anthropic" else ("prompt_tokens","completion_tokens")
        if not all(key in raw_usage for key in required) or "prompt_tokens" not in usage or "completion_tokens" not in usage:
            raise ProviderError("Missing usage; worst-case budget reservation retained")
        cost=(usage["prompt_tokens"]*self.spec["input_cny_per_million"]+
              usage["completion_tokens"]*self.spec["output_cny_per_million"])/1e6
        self.budget.settle(index,cost)
        response.cost_cny=cost
        return response


def configured_provider(config: dict, model_id: str, ledger: Path):
    validate_live_config(config)
    spec=next((m for m in config["models"] if m["id"]==model_id),None)
    if spec is None:
        raise ProviderError("Unknown explicitly configured model")
    key=os.environ.get(spec["api_key_env"],"")
    if not key:
        raise ProviderError("Missing credential environment variable: "+spec["api_key_env"])
    kwargs=dict(model=spec["model"],base_url=spec["base_url"].rstrip("/"),api_key=key,
                temperature=spec.get("temperature",0.),max_tokens=config.get("limits",{}).get("max_output_tokens",16384),
                max_retries=1,live_authorized=True)
    if spec["provider"]=="anthropic":
        from .providers.anthropic import AnthropicProvider
        inner=AnthropicProvider(**kwargs)
    else:
        from .providers.openai_compat import OpenAICompatProvider
        inner=OpenAICompatProvider(**kwargs)
    return BudgetedProvider(inner,spec,Budget(ledger,config["budget_cny"]))
