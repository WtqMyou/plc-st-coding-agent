"""Verification-only observers driven by public inputs, never candidate internals."""
import re

PREFIX = '__spec_'


def ipv4(current, previous=None, initial=False):
    text = str(current.get('iptext', ''))
    parts = text.split('.')
    valid = len(parts) == 4 and all(re.fullmatch(r'[0-9]+', p) and int(p) <= 255
                                  and (len(p) == 1 or p[0] != '0') for p in parts)
    value = 0
    if valid:
        for part in parts:
            value = value * 256 + int(part)
    ambiguous = (len(parts) == 4 and all(re.fullmatch(r"[0-9]+", p) and int(p) <= 255 for p in parts)
                 and any(len(p) > 1 and p.startswith("0") for p in parts))
    return dict(__spec_ip_scored=not ambiguous, __spec_ip_valid=bool(valid), __spec_ip_value=value,
                __spec_ip_segments=len(parts))


def process(current, previous=None, initial=False):
    """Observable conveyor contract; phase and sequence position belong to the checker."""
    before = previous or {}
    phase = int(before.get('__spec_phase', 0))
    index = int(before.get('__spec_index', 0))
    station = int(before.get('__spec_station', 1))
    target = int(before.get('__spec_target', 0))
    length = int(current.get('processlength', 0))
    sequence = current.get('processsequence', [])
    values = getattr(sequence, 'items', sequence)
    valid = (1 <= length <= 8 and isinstance(values, (list, tuple)) and len(values) >= length
             and values[length - 1] == 5 and all(2 <= v <= 4 for v in values[:length - 1]))
    # Once a fixture violates the route contract, its future state is no
    # longer implied by that contract. A new fixture starts a fresh observer.
    prefix_valid = True if initial else bool(valid and before.get('__spec_prefix_valid', True))
    complete_name = 'station' + str(station) + 'complete'
    complete = phase == 2 and bool(current.get(complete_name)) and not bool(before.get(complete_name))
    if not initial and prefix_valid:
        if phase == 0 and current.get('sensor1') and current.get('station1start') and not before.get('station1start'):
            index, station, target, phase = 1, 1, int(values[0]), 1
        if phase == 2 and complete:
            index += 1
            if index > length:
                phase = 0
            else:
                target, phase = int(values[index - 1]), 1
        if phase == 1 and current.get('sensor' + str(target)):
            station, phase = target, 0 if target == 5 else 2
    return dict(__spec_contract=bool(valid and prefix_valid), __spec_prefix_valid=prefix_valid,
                __spec_phase=phase, __spec_index=index,
                __spec_station=station, __spec_target=target, __spec_complete=bool(complete),
                __spec_idle=phase == 0, __spec_wait=phase == 2,
                __spec_right=phase == 1 and target > station,
                __spec_left=phase == 1 and target < station)


def observer_for(name):
    if name is None:
        return None
    if name == 'analog':
        from .analog_binding_check import observe
        return observe
    if name not in ('ipv4', 'process'):
        raise ValueError('Unknown verification observer')
    return {'ipv4': ipv4, 'process': process}[name]
