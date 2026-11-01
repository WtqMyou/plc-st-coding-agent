"""Interpret legacy control-stop entries without changing their raw evidence."""
from dataclasses import replace


def is_unissued_pause(attempt):
    return (attempt.provider_error == 'Campaign halted: Paused by user for laptop relocation'
            and not attempt.code and not attempt.actual_model and not attempt.prompt_tokens
            and not attempt.completion_tokens and not attempt.cost_cny)


def accounting_record(record):
    issued = [a for a in record.attempts if not is_unissued_pause(a)]
    return replace(record, attempts=issued), len(record.attempts) - len(issued)
