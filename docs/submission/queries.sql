-- SQLite / PostgreSQL. Analytics values are theoretical, not settled money.
-- Join: each driver with their own document statuses.
SELECT u.full_name, u.email, d.document_type, d.review_status, d.rejection_reason
FROM accounts_driverdocument d
JOIN accounts_driverprofile p ON p.id = d.driver_id
JOIN accounts_user u ON u.id = p.user_id
ORDER BY u.email, d.document_type;

-- Analytics view (created by rides migration 0005).
SELECT service, COUNT(*) AS completed_rides, SUM(final_fare) AS fare_total,
       SUM(calculated_platform_fee) AS calculated_fees,
       SUM(calculated_driver_share) AS calculated_driver_shares
FROM rides_completed_analytics GROUP BY service;

-- Inspect database trigger audit. Actor is recorded separately by Django admin log.
SELECT rate_id, old_base, new_base, old_per_hour, new_per_hour, changed_at
FROM rides_rate_change_audit ORDER BY changed_at DESC;

-- Transaction demonstration, deliberately rolled back; not a production update.
BEGIN;
UPDATE rides_servicerate SET per_hour = per_hour + 1 WHERE service = 'HOURLY';
SELECT service, base, per_hour FROM rides_servicerate WHERE service = 'HOURLY';
ROLLBACK;
