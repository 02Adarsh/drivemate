# V9.1 — driver receiving UPI + fare-prefilled QR (manual confirmation)

**App 1.7.1+9 / backend API 10.** This ZIP contains V9 plus this payment update. Install only the latest ZIP over the existing project.

## Important: what this mode can and cannot do

You selected **personal direct UPI / manual confirmation**, with receiving details in the **driver portal**.

Implemented:

- Driver saves their receiving UPI ID and uploads a matching receiving QR image.
- A new trip QR is generated from the **server final fare** and a snapshotted receiving ID.
- DriveMate has no customer amount-edit field. Uploaded QR old amounts/references and client-supplied amounts are ignored.
- The QR/UPI deep link **prefills the exact fare** in the external app.
- Customer payment reports stay unconfirmed. The assigned driver checks their own bank/UPI credit, amount and reference before manually recording receipt.

**Not guaranteed / not implemented:**

1. **An external UPI app may still allow editing.** Personal QR data cannot force every bank/UPI app to disable its edit controls. A merchant gateway with fixed-amount QR support is required for that guarantee.
2. **Scanning is not authorization or proof.** Payer confirms/authenticates in the UPI app. DriveMate does not collect a UPI PIN or automatically debit an account.
3. **No automatic bank/gateway verification.** QR scan, app return, screenshot and typed UTR cannot make the booking paid. The confirmation record explicitly says **manual driver confirmation**, not bank-verified.
4. **Personal QR is not single-use/expiring at the bank.** Old images can still be paid even after DriveMate closes/confirms the record. Never pay twice just because a screen was refreshed. Closing in this app is not bank cancellation/refund.
5. No automatic payout/refund, bank-feed access, arbitrary-UTR lookup or SMS scraping is added. Bank/app limits, receiver eligibility and network conditions can still reject a payment; DriveMate does not bypass them.

Do not describe this release as universally non-editable, automatic-debit or bank-verified. Those require a different approved merchant-provider integration, not just a personal UPI ID.

## 1. Update/run

Back up first. Stop old Flutter/backend processes, extract the latest ZIP into `C:\Users\adars\Downloads\updated_drivemate` and replace files. **Do not delete database, .env, uploads, signing keys or virtualenv.** They are not shipped in the ZIP.

New backend packages: QR encoding, image/QR decoding (`qrcode`, `zxing-cpp`, NumPy, Pillow). Backend **Python 3.12+** is required by the pinned NumPy version; your existing Python 3.12 environment is suitable. Tested here with Python 3.13.16.

### Terminal 1 — backend (one line, leave running)

```powershell
cd C:\Users\adars\Downloads\updated_drivemate; powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_backend.ps1
```

It installs requirements into the existing backend virtualenv, checks Django, applies the new `payments` migration and starts the API. Health must show `api_version: 10`. The new phone launcher refuses an old API 9 server. First install needs network access for the Python packages.

### Terminal 2 — phone rebuild

```powershell
cd C:\Users\adars\Downloads\updated_drivemate; powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_phone.ps1 -Usb
```

The ADB/USB safety checks are retained. Rebuild the app because the UPI intent visibility and new screens changed. No merchant API key is needed for **this manual mode**. Your existing SMTP settings remain private/preserved for receipts.

## 2. Driver: configure receiving details

Open **Account → Receiving UPI & QR** (also reachable from Payments on a driver account).

1. Enter your own receiving UPI ID.
2. Upload a clear receiving QR screenshot from gallery, or photograph a printed QR.
3. Standard **`upi://pay`** receiving QRs in JPG/PNG/WebP are supported. Web/payment-link/EMV-only QRs are not decoded by this flow; the server does not follow arbitrary URLs from an uploaded image.
4. If ID is blank on first upload, it can be extracted from a readable QR. If typed, it **must match** the decoded ID (case-normalized).
5. Confirm that the receiving account is yours and enter your **DriveMate password, not UPI PIN**.
6. Save. The server validates/decodes the image and strips metadata into a private PNG.

Limits: maximum 5 MB upload and 12 megapixels. Crop out unrelated QRs. A random photo or a QR for a different ID is rejected. A QR match does **not** prove bank ownership/name/KYC; the screen/API explicitly says so.

The uploaded image is a **reference**, not the payment QR. Its old amount, reference, merchant flags or callbacks are never reused. Fare QRs are newly generated with whitelisted `pa`, `pn`, `am`, `cu`, `tr`, `tn` fields.

Changing/pausing the receiving profile affects **new** requests. Existing trip requests retain their original payee snapshot, so an already-issued QR is never silently redirected. Check that old receiving account remains usable before changing details.

## 3. Customer/driver: QR payment after trip completion

1. Complete the trip so the final fare is available. The start OTP flow is unchanged.
2. Customer or assigned driver opens **Trip details / Receipt → Pay / view UPI QR** or **Show fare QR / review UPI**.
3. Server calculates the amount from `Booking.final_fare`, not an editable/client amount. For example ₹575 produces `am=575.00`.
4. QR shows the receiving driver name/ID and exact fare. Check the actual recipient shown by the UPI app before authorization; the name in a QR is not independent bank validation.
5. Scan from another device, or tap **Open UPI app with this fare** on the same phone. Gallery QR scan may also work if the UPI app supports it. Share/save uses the phone share sheet.
6. Authorize payment in the UPI app. **If your account was debited, do not repeatedly scan/pay**—ask the driver to check credit.
7. Customer may choose **I paid → report reference** after their app shows success. This produces `REPORTED`, not paid/verified status.
8. Driver opens the request and checks their **own actual bank/UPI ledger**. Enter actual received amount and bank reference, acknowledge checking credit, then manually confirm.
9. A different amount is rejected and the booking remains unpaid. Typing a reference alone is never sufficient.
10. Receipt/activity updates to **UPI received — manually confirmed by driver**. Optional SMTP receipt is sent to the verified participant email. The record is not independent electronic bank proof or a GST invoice.

A driver can record an actual credit even when the payer paid outside the customer app and never submitted a report. The same manual bank-check/amount/reference requirements apply.

If credit cannot be found, driver rejects the report with a reason. Customer checks their payment status rather than blindly paying again. Use the linked payment-support ticket for pending/partial/wrong/duplicate transfers. No automatic refund is promised.

## 4. Switching to cash

An open/reported/confirmed UPI request blocks cash collection recording, to avoid two paid records.

- Resolve a reported payment first (driver review).
- Only an unreported/rejected request can be **closed in DriveMate**, after checking no payment was made/received.
- Then actual cash can be recorded separately.
- Closure cannot disable old QR screenshots at the bank. Do not use them or collect cash if a prior UPI debit/credit is still pending.
- A closed request is not silently recreated; use support if the payment method/recipient needs correction.

Already recorded cash blocks creating a new UPI request. Confirmed UPI blocks recording cash. Repeated opens/reports/confirmation are idempotent where appropriate; one confirmed bank reference cannot be reused for another trip.

## 5. Status meanings

| Status | Meaning |
|---|---|
| CREATED | Fare QR generated, no payment proof |
| REPORTED | Customer reported a reference; **unconfirmed** |
| REJECTED | Driver could not confirm; check bank/app before any retry |
| CONFIRMED | Assigned driver manually asserted exact credit received; **not bank/API verified** |
| CANCELLED | Closed in DriveMate only; not bank cancellation/refund |

All actions are participant/role-scoped. Only the customer reports; only the assigned driver reviews. Private profile QR files are owner-only. Generated trip QR and audit trail are visible only to that trip's customer/assigned driver. No public upload URL or API secret is exposed.

## 6. Operator/security notes

- Receiving-profile edits require authenticated driver, verified email, current password, own-account attestation and QR/ID match.
- Profile changes and payment state changes are audited. Amount/receiver snapshot is immutable once generated.
- Server verifies final fare again on payment actions. Unsupported/negative/zero-fare QR creation is rejected; zero-fare trips have no payment due.
- Global uniqueness of confirmed bank references and booking-level locking reduce duplicate/mixed cash/UPI records. These are application controls, **not independent checks with the banking network**.
- Do not trust a screenshot, notification sound, SMS text, customer-supplied reference or external app callback as verification.
- No code asks for/reads UPI PIN, bank passwords, account SMS inbox or another app's private data. Driver password is only their DriveMate login password.
- Keep HTTPS/strong secrets/storage/retention/operational policies from the V9 guide before using real financial/customer data. A human can make a false/mistaken manual confirmation; the application cannot guarantee bank facts without a provider.
- For strict bank-enforced fixed amount, single-use QR, authenticated payment webhooks/reconciliation and reliable refunds/settlements, onboard an approved merchant/payment provider (and linked drivers if direct settlement is required).

## 7. Verification

- Backend tests cover real QR generation/decode, uploaded mismatch rejection, role/ownership/privacy, immutable amount/payee snapshots, customer report vs confirmed receipt, exact actual amount, reference reuse, cash/UPI exclusivity, closure and idempotence.
- Flutter tests cover readonly amount/QR screen, UPI intent amount/receiver, no automatic paid state on app return, customer reporting, driver manual review, status polling and receiving setup.
- Full V9 regressions are retained. A new API-version boundary prevents the new UI using an old backend.
- No real UPI app/bank transfer or Windows phone deployment is performed by this sandbox. Platform calls are mocked; test QR IDs use an invalid handle. Validate with your own small, explicitly authorized test payment on the actual device only after checking the recipient, and reconcile in the driver's bank app.
