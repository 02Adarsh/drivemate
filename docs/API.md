# DriveMate API (current build)

Base URL: `http://<your-server>:8000/api/`

Authentication: JWT (`Authorization: Bearer <access>`), except where marked
public. Roles: `CUSTOMER`, `DRIVER`, `ADMIN` (staff only for `/admin/...`).

## Authentication — `/api/auth/`

| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | `register/` | public | Create account (`CUSTOMER` or `DRIVER` only) |
| POST | `verify-otp/` | public | Verify the 6-digit email code; returns tokens |
| POST | `resend-otp/` | public | Send a new code |
| POST | `login/` | public | `identifier` (email or phone) + password + role |
| GET | `me/` | any | Current user (+ driver progress) |
| POST | `password/reset/request/` | public | Email a reset code |
| POST | `password/reset/confirm/` | public | Set the new password |

`register/` body:
```json
{"full_name":"Adarsh Kumar","email":"a@example.com","phone":"+919000000000",
 "password":"Secret123","confirm_password":"Secret123","role":"DRIVER"}
```

Login/OTP responses contain:
```json
{"access":"...","refresh":"...",
 "user":{"id":1,"name":"...","email":"...","phone":"...","role":"DRIVER",
         "email_verified":true,"profile_complete":true,
         "driver_documents_complete":false,"next_step":"DOCUMENTS"},
 "driver":{"verification_status":"INCOMPLETE","next_step":"DOCUMENTS", "...":"..."}}
```

`next_step` is calculated on the server and is what the app uses to decide
where to send the person: `PERSONAL_PROFILE`, `DRIVING_DETAILS`, `DOCUMENTS`,
`UNDER_REVIEW`, `FIX_AND_RESUBMIT`, `SUSPENDED`, `DASHBOARD`.

## Profile — `/api/auth/`

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `profile/` | any | Read profile (+ progress for drivers) |
| PUT | `profile/` | any | Save a step; send `"step":"PERSONAL"`, `"DRIVING"` or `"PROFILE"` |
| POST | `profile/photo/` | any | Profile photo (multipart, `file`) |

Sending a `step` makes the API verify the **whole** step. If something is
missing it answers `400` with a readable list:

```json
{"detail":"Complete every field before continuing.",
 "missing_fields":["Profile photo","Emergency contact number"]}
```

Drivers cannot jump ahead: `step: DRIVING` before step 2 is complete returns
`400`. Documents cannot be uploaded before steps 2 and 3 are done.

## Driver application — `/api/auth/driver/`

| Method | Path | Purpose |
|---|---|---|
| GET | `application/` | Steps, documents, training, consents, review info |
| POST | `documents/` | Upload a document (multipart: `file`, `document_type`, optional `document_number`, `expires_at`) |
| POST | `consents/` | Save the three required consents |
| GET | `training/` | Training checklist |
| POST | `training/<MODULE>/complete/` | Mark a module complete |
| GET/POST | `emergency-contacts/` | List / add extra emergency contacts |
| DELETE | `emergency-contacts/<id>/` | Remove one |

`document_type` must be one of `LICENCE_FRONT`, `LICENCE_BACK`, `IDENTITY`,
`ADDRESS_PROOF`. Upload limits: 5 MB, JPG/PNG/WebP/PDF.

## Admin / staff — `/api/auth/admin/` (staff only)

| Method | Path | Purpose |
|---|---|---|
| GET | `drivers/?status=&search=` | Verification queue |
| GET | `drivers/<user_id>/application/` | Full application detail |
| POST | `drivers/<user_id>/review/` | `{"action":"approve\|reject\|suspend\|reactivate\|inactive\|under_review\|pending_review","reason":"..."}` |
| GET | `documents/<document_id>/download/` | Private file download |
| POST | `documents/<document_id>/review/` | Approve/reject one document |

Rules enforced by the server:

* only staff can call these routes,
* an incomplete application cannot be approved,
* `reject` and `suspend` require a reason,
* every decision stores who decided and when.

## Error format

| Status | Meaning |
|---|---|
| 400 | validation problem (`detail`, `missing_fields`, or field errors) |
| 401 | wrong credentials / expired session |
| 403 | wrong role, unverified email, or not staff |
| 404 | not found |
| 429 | too many attempts (OTP) or throttled |

## Planned next (not implemented yet)

Booking creation, 500 m driver matching with radius expansion, driver
availability, request/accept, live GPS over WebSockets, trip timer, inspections,
payments, receipts, ratings, disputes, notifications and the admin dashboard.
The models and services for those phases are described in the project brief and
will be added incrementally so nothing is faked.
