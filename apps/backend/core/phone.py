"""Phone-number shapes, in one place.

We store phones in E.164 (`+919494429963`) because that is what the SMS gateway
and the auth layer need. Several Indian vendor APIs — Payon's credit-score and
DigiLocker endpoints among them — instead demand the bare 10-digit subscriber
number and reject anything else with a validation error.

That conversion existed once per integration. Two copies of "what does this
vendor mean by a mobile number" is exactly the kind of thing that drifts: one
gets fixed for a formatting edge case and the other silently keeps failing, in a
different module, months later. It lives here now.
"""
from __future__ import annotations

import re


def msisdn10(mobile) -> str:
    """Reduce any input (E.164 '+91…', spaces, dashes) to the last 10 digits.

    Returns whatever digits are present when there are fewer than 10, rather than
    padding or raising: the caller is talking to a vendor that will reject a short
    number itself, with a better message than we could invent.
    """
    digits = re.sub(r"\D", "", str(mobile or ""))
    return digits[-10:] if len(digits) >= 10 else digits
