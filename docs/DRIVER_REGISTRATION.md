# Driver registration — the five-step flow

Every driver on DriveMate goes through the same five steps. The **backend**
decides whether a step is finished; the app only shows the result.

```
STEP 1  Create account            name · email · mobile · password
STEP 2  Personal profile          photo · DOB · address · city · emergency contact · languages
STEP 3  Driving details           licence no. · expiry · experience · transmission · vehicle types
STEP 4  Documents & consent       licence front + back · identity proof · consents · training
STEP 5  Admin verification        PENDING_REVIEW → UNDER_REVIEW → APPROVED / REJECTED
```

## Step 1 — Create account

| Field | Rules |
|---|---|
| Full name | at least 2 characters, must contain a letter |
| Email address | unique, verified with a 6-digit code |
| Mobile number | 8–15 digits, unique, normalised to digits (and a leading `+`) |
| Password | at least 8 characters, mixed letters and numbers, Django password validators |
| Confirm password | must match |

The account is created with role `CUSTOMER` or `DRIVER` **by the server**.
`ADMIN` can never be created through public signup — the API rejects it.
After signup the app opens the OTP screen and the driver continues to step 2.

## Step 2 — Personal profile

All fields are required before step 3 unlocks:

* profile photo (uploaded to private storage),
* date of birth — the server checks the minimum age (18 by default),
* current address,
* city *(service area is optional but recommended)*,
* emergency contact name and number,
* languages known (chips in the app, stored as a comma separated list).

## Step 3 — Driving details

* licence number,
* licence expiry (must be in the future),
* driving experience in years (1–60),
* **at least one transmission** (Manual / Automatic),
* **at least one vehicle type** (Sedan / SUV / Luxury),
* optional capabilities: Highway, Night driving, Outstation.

These capability flags are what the future matching engine will filter on: an
automatic SUV booking can only be offered to a driver who selected both.

## Step 4 — Documents, consent and training

Documents (all stored privately, never in a public URL):

| Type | Required | Notes |
|---|---|---|
| `LICENCE_FRONT` | yes | front of the driving licence |
| `LICENCE_BACK` | yes | back of the driving licence |
| `IDENTITY` | yes | government photo ID |
| `ADDRESS_PROOF` | no | speeds up verification |

Consents (all three required):

1. background verification consent,
2. Terms & Conditions,
3. declaration that the details and documents are true.

Training: three modules must be completed (`SAFE_DRIVING`,
`CUSTOMER_SERVICE`, `VEHICLE_INSPECTION`) before the application can be
submitted. The text inside each module is a **placeholder** until the real
training material exists.

Upload limits: 5 MB per file, JPG / PNG / WebP / PDF.

## Step 5 — Admin verification

Statuses stored in `DriverProfile.verification_status`:

| Status | Meaning |
|---|---|
| `INCOMPLETE` | one or more steps still missing |
| `PENDING_REVIEW` | every step complete, waiting in the queue |
| `UNDER_REVIEW` | an admin is checking the documents |
| `APPROVED` | required checks complete — the driver may later go online |
| `REJECTED` | needs fixes; the reason is shown in the app; the driver can resubmit |
| `SUSPENDED` | temporarily blocked by an admin |
| `INACTIVE` | account is not active |

**Important:** `APPROVED` and *online* are different things. Approval only means
the application passed review. Availability and booking eligibility need the
extra checks that come with the matching phase.

### How an admin reviews applications

Option A — Django admin (available today):

```
/admin/accounts/driverprofile/      filter by status, open a profile, inspect documents
/admin/accounts/driverdocument/     per-document approve/reject
```

Actions available on the profile list: *Mark UNDER_REVIEW*, *Approve*,
*Reject*, *Suspend*, *Re-activate*. An application can only be approved when
every required step is complete — the same rule is enforced by the API.

Option B — staff API (for the future admin dashboard):

```
GET  /api/auth/admin/drivers/?status=PENDING_REVIEW
GET  /api/auth/admin/drivers/<user_id>/application/
POST /api/auth/admin/drivers/<user_id>/review/   {"action":"approve"}
POST /api/auth/admin/documents/<document_id>/review/  {"action":"reject","reason":"..."}
```

Both routes require a staff account (`is_staff`), and every decision records
`reviewed_by`, `reviewed_at` and `rejection_reason`.

### Testing without an admin

Set `AUTO_APPROVE_DRIVERS_IN_DEV=true` in `backend/.env` (only works while
`DEBUG=true`). A complete application is then approved automatically and marked
as a development shortcut. Keep this flag off for anything real.

## What is intentionally NOT in this build

Going online, receiving booking requests, live GPS, earnings, payouts and the
in-app admin dashboard belong to the booking/matching phases. The driver
dashboard says so on screen instead of showing invented numbers.
