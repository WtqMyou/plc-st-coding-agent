"""Derive discrete-time thresholds from public language without loading benchmark test data."""
from decimal import Decimal,ROUND_FLOOR,ROUND_CEILING
import re
PATTERN=re.compile(r'\b(?P<op>more than|exceeds?|at least|reaches?)\b(?P<context>[^\n.]{0,220}?)(?P<number>\d+(?:\.\d+)?)\s*(?P<unit>milliseconds?|seconds?|minutes?|ms|s|min)\b',re.I)


def derive(public_text,quantum_ms=1):
    quantum=Decimal(str(quantum_ms))
    if quantum<=0:raise ValueError('Time quantum must be positive')
    rows=[]
    for match in PATTERN.finditer(public_text):
        unit=match['unit'].lower();scale=1 if unit.startswith('mill') or unit=='ms' else 60000 if unit.startswith('min') else 1000
        duration=Decimal(match['number'])*scale
        strict=match['op'].lower() in ('more than','exceed','exceeds')
        ticks=duration/quantum
        first=((ticks.to_integral_value(rounding=ROUND_FLOOR)+1) if strict else ticks.to_integral_value(rounding=ROUND_CEILING))*quantum
        numeric=lambda value:int(value) if value==value.to_integral_value() else float(value)
        rows.append(dict(public_excerpt=match.group(0),comparison='>' if strict else '>=',duration_ms=numeric(duration),
            time_quantum_ms=numeric(quantum),first_satisfying_tick_ms=numeric(first),
            derivation='floor(duration/quantum)+1 ticks' if strict else 'ceil(duration/quantum) ticks',
            timer_fact='TON.Q is elapsed >= PT; previous-scan Q delays by a whole scan, not one representable time quantum'))
    return rows
