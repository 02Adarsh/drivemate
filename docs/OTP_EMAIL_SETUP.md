# OTP: how to send the verification code to the user's real email

Right now the code is **not emailed**. Why: with no SMTP settings, Django falls
back to the *console* email backend, which simply prints the message in the
terminal where `runserver` is running:

```
Content-Type: text/plain; charset="utf-8"
Subject: Your DriveMate verification code
From: DriveMate <no-reply@drivemate.local>
To: driver@example.com

Your DriveMate verification code is 472913. It expires in 10 minutes.
```

That behaviour is deliberate for development (no secrets, no spam, instant).
This guide turns it into real email delivery. Nothing in the Flutter app has to
change — the app already says "check your inbox".

---

## How the code path works

```
Flutter app  →  POST /api/auth/register/        (backend/accounts/views.py)
                     ↓
                issue_otp(user)                 ← the ONLY place OTPs are created
                     ↓
                django.core.mail.send_mail(...) → EMAIL_BACKEND from settings
                     ↓
      console backend (development)  OR  SMTP backend (configured)
```

`backend/config/settings.py` picks the backend automatically:

```python
EMAIL_BACKEND = 'django.core.mail.backends.smtp.EmailBackend'
    if EMAIL_HOST and EMAIL_HOST_USER and EMAIL_HOST_PASSWORD
    else 'django.core.mail.backends.console.EmailBackend'
```

So: fill three values in `backend/.env`, restart the server, and codes start
arriving in real inboxes. That is the whole switch.

---

## Option A — Gmail SMTP (fastest way to see a real email today)

Good for testing with your own address. Not recommended as the final setup for
a public app (Gmail caps ~500 recipients/day and can throttle).

1. In the Google account you want to send from, turn on **2-Step Verification**
   (required before app passwords appear).
2. Go to <https://myaccount.google.com/apppasswords> → create an app password
   named `DriveMate`. Google shows a 16-character password like `abcd efgh ijkl mnop`.
3. Put this in `backend/.env` (keep the spaces out of the password):

```env
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_USE_TLS=true
EMAIL_HOST_USER=yourgmail@gmail.com
EMAIL_HOST_PASSWORD=your16characterapppassword
DEFAULT_FROM_EMAIL="DriveMate <yourgmail@gmail.com>"
```

4. Restart the backend (`CTRL+C`, then `python manage.py runserver 0.0.0.0:8000`).
5. Sign up in the app with an email you can open → the code shows up in the inbox
   (check Spam the first time).

> Never use your normal Google password. `EMAIL_HOST_PASSWORD` is an app
> password, and `.env` is never committed (it is already in `.gitignore`).

---

## Option B — a transactional email provider (recommended for launch)

Providers built for app email give you delivery logs, bounce handling and much
higher limits. Any of these work with the SMTP settings already in `.env`:

| Provider | Free tier (typical) | Notes |
|---|---|---|
| **Brevo** (ex-Sendinblue) | ~300 emails/day | simple SMTP, good for India |
| **SendGrid** | ~100/day | well documented |
| **Amazon SES** | pay per email, very cheap | starts in *sandbox*: you must request production access, and verify the sending domain |
| **Resend** | small free tier | modern, API + SMTP |
| **Zoho Mail / Google Workspace** | paid mailbox | best if you want `support@yourdomain.com` |

Example (Amazon SES, Mumbai region) — copy into `backend/.env`:

```env
EMAIL_HOST=email-smtp.ap-south-1.amazonaws.com
EMAIL_PORT=587
EMAIL_USE_TLS=true
EMAIL_HOST_USER=AKIA...your-SMTP-username
EMAIL_HOST_PASSWORD=your-SMTP-password
DEFAULT_FROM_EMAIL="DriveMate <no-reply@yourdomain.com>"
```

Two things that decide whether mail actually lands in the inbox:

1. **Verify the sending domain** with the provider, then add their DNS records:
   * **SPF** (`TXT`, allows the provider to send for you),
   * **DKIM** (signature that proves the mail is really yours),
   * **DMARC** (`TXT`, policy + reports — start with `p=none`).
2. Send from a **domain address** (`no-reply@yourdomain.com`), not a free
   Gmail address, once you are live. Free-address senders get filtered more.

---

## Step 3 — test the email without touching the app

```bash
cd backend
python manage.py shell
```

```python
from django.core.mail import send_mail
send_mail(
    'DriveMate SMTP test',
    'If you can read this, real email delivery works.',
    None,                      # uses DEFAULT_FROM_EMAIL
    ['you@example.com'],       # <- your address
    fail_silently=False,       # so errors are visible
)
```

Nothing raised + mail in the inbox = configured correctly. Common failures:

| Error | Meaning |
|---|---|
| `SMTPAuthenticationError 535` | wrong app password / username, or 2FA is off (Gmail) |
| `ConnectionRefused / timed out` | port blocked by a firewall or ISP; try port `465` with `EMAIL_USE_TLS=false` and `EMAIL_USE_SSL` support, or the provider's alternate port |
| Mail arrives in Spam | add SPF/DKIM/DMARC, or send from a verified domain |
| `SMTPSenderRefused` | the `From` address is not allowed by the provider — it must be a verified sender/domain |

---

## Step 4 — production checklist for OTP

* Keep `OTP_EXPIRY_MINUTES=10` and `OTP_MAX_ATTEMPTS=5` (already enforced by the
  API, and the code is stored **hashed**, never in plain text).
* Never log or email the code in production — the console backend must stay off;
  it only activates when `EMAIL_HOST` is empty.
* Rate-limit resends (`/api/auth/resend-otp/`) — the endpoint already refuses to
  issue a new code for an already verified email, and Django's anon throttle
  applies. For launch, add a per-address cooldown (for example 60 seconds) in
  `issue_otp()`.
* Want **SMS OTP** later? `issue_otp()` in `backend/accounts/views.py` is the one
  place that generates and sends codes; add an `SmsService` (MSG91, Twilio, AWS
  SNS) next to the `send_mail` call and send both. Keep the same hashed-code
  table so nothing else changes.

---

## Optional — see the code in the Django admin while testing

With the console backend you can also read pending codes in the admin site:
`/admin/accounts/emailotp/` lists the created codes (hashed) with expiry and
attempt counts. Handy to confirm delivery timing without opening the mailbox.
