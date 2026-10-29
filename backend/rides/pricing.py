"""Fare maths — kept on the server, in one place, with `Decimal` money.

The app never sends a price. It sends the service and the duration, and renders
whatever the server calculates. That keeps a tampered client from inventing a
₹10 airport run.

Prototype pricing: a base fee plus an hourly rate, and a flat platform fee taken
from the completed fare. Surge, tolls, waiting time and night allowance are the
next step - they belong in this file and nowhere else.
"""

from decimal import Decimal, ROUND_HALF_UP

# Percent of the completed fare that DriveMate keeps.
PLATFORM_FEE_PERCENT = 18

# service key -> base (₹) and per-hour (₹). `min_hours` guards silly values.
SERVICE_PRICING: dict[str, dict[str, object]] = {
    'BOOK_NOW': {'label': 'Book now', 'base': 99, 'per_hour': 129, 'min_hours': 1},
    'HOURLY': {'label': 'Hourly', 'base': 99, 'per_hour': 119, 'min_hours': 2},
    'FULL_DAY': {'label': 'Full day', 'base': 199, 'per_hour': 109, 'min_hours': 8},
    'AIRPORT': {'label': 'Airport', 'base': 149, 'per_hour': 139, 'min_hours': 2},
    'OUTSTATION': {'label': 'Outstation', 'base': 249, 'per_hour': 149, 'min_hours': 6},
    'NIGHT': {'label': 'Night drive', 'base': 129, 'per_hour': 139, 'min_hours': 2},
    # Disabled until an administrator configures an explicit price.
    'GETAWAY': {'label': 'Outstation Getaways', 'base': 0, 'per_hour': 0, 'min_hours': 1},
    'EVENT': {'label': 'Wedding / Event Driver', 'base': 0, 'per_hour': 0, 'min_hours': 1},
}

MAX_HOURS = 14
GETAWAY_MAX_HOURS = 744
GETAWAY_MAX_DAYS = 31


def _rupees(value: Decimal) -> Decimal:
    return value.quantize(Decimal('1'), rounding=ROUND_HALF_UP)


def service_label(service: str) -> str:
    return str(SERVICE_PRICING.get(service, SERVICE_PRICING['BOOK_NOW'])['label'])


def clamp_hours(hours, maximum=MAX_HOURS) -> int:
    try:
        value = int(hours)
    except (TypeError, ValueError):
        value = 1
    return max(1, min(maximum, value))


def service_config(service: str) -> dict:
    """Read admin rates on every quote/booking, with old defaults as fallback."""
    from .models import ServiceRate
    key = service if service in SERVICE_PRICING else 'BOOK_NOW'
    config = dict(SERVICE_PRICING[key])
    row = ServiceRate.objects.filter(service=key).first()
    if row:
        config.update(base=row.base, per_hour=row.per_hour)
    return config


def estimate_fare(service: str, hours) -> Decimal:
    """Base + hourly rate for the requested duration."""
    config = service_config(service)
    duration = clamp_hours(hours, GETAWAY_MAX_HOURS if service == 'GETAWAY' else MAX_HOURS)
    minimum = int(config['min_hours'])  # type: ignore[arg-type]
    billable = max(duration, minimum)
    total = Decimal(int(config['base'])) + Decimal(int(config['per_hour'])) * billable  # type: ignore[arg-type]
    return _rupees(total)


def driver_payout(fare, fee_percent: int = PLATFORM_FEE_PERCENT) -> Decimal:
    """What the driver receives from a completed fare."""
    amount = Decimal(str(fare or 0))
    fee = (amount * Decimal(fee_percent) / Decimal(100)).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
    return (amount - fee).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)


def platform_fee(fare, fee_percent: int = PLATFORM_FEE_PERCENT) -> Decimal:
    amount = Decimal(str(fare or 0))
    return (amount * Decimal(fee_percent) / Decimal(100)).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)


def fare_breakdown(service: str, hours) -> dict:
    """Everything the booking screen needs to explain the number it shows."""
    config = service_config(service)
    duration = clamp_hours(hours, GETAWAY_MAX_HOURS if service == 'GETAWAY' else MAX_HOURS)
    minimum = int(config['min_hours'])  # type: ignore[arg-type]
    billable = max(duration, minimum)
    total = estimate_fare(service, duration)
    return {
        'service': service,
        'label': config['label'],
        'base': int(config['base']),  # type: ignore[arg-type]
        'per_hour': int(config['per_hour']),  # type: ignore[arg-type]
        'hours': duration,
        'billable_hours': billable,
        'minimum_hours': minimum,
        'estimated_fare': total,
        'platform_fee_percent': PLATFORM_FEE_PERCENT,
        'driver_payout': driver_payout(total),
    }
