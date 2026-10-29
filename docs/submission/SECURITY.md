# One-page threat model & security checklist

**Assets:** passwords/tokens, personal identity documents, location/booking data, UPI identifiers, fare configuration and payment records. **Actors:** customers, drivers, staff, attackers, hosting and payment providers. **Trust boundaries:** mobile/browser → API; staff → admin; API → database/private storage/email; user → external UPI app.

| Threat | Mitigation in code / remaining action |
|---|---|
| Stolen session or staff impersonation | JWT/session auth, Django permissions and `IsAdminUser`; enforce HTTPS, short sessions and MFA for staff at deployment; MFA not implemented. |
| Cross-user document disclosure | Private storage keys and staff-authenticated download endpoint; validate real private Azure container/network policy. Minimize retention and access. |
| SQL injection / XSS | Django ORM parameterizes ordinary queries; DRF validates inputs and Django templates escape by default. Review any raw SQL and Flutter/web rendering; no independent penetration test. |
| Password/token or cloud-secret exposure | Django password hashing, env configuration, `.env` ignored. Review tracked backup and git history; rotate any exposed secrets. Development default key is insecure. |
| Fare tampering / unapproved money transfer | Server calculates fares and 18% share; rate editing is staff admin-only, DB audit trigger stores old/new prices. Existing direct UPI pays driver full amount; it does not settle platform fee. Reconciliation and gateway verification are missing. |
| Race conditions / duplicated booking | Database constraints and atomic booking operations; test PostgreSQL concurrency and retries. |
| Data loss / unauthorized cloud access | Backups, restore exercises, network firewall and least privilege are deployment responsibilities, not verified here. |

## Checklist
- [x] Password hashing through Django auth (do not store plaintext passwords).
- [x] Role/staff-scoped APIs and Django admin permissions exist; authorization must be reviewed for each new endpoint.
- [x] Production settings enforce HTTPS redirect and secure cookies when DEBUG=false; certificate/proxy not deployed or tested.
- [x] Real secrets expected from environment; `.env` ignored. Existing tracked backup needs review.
- [x] Server-side validation and ORM are used; uploads have size/type checks. This is not proof all XSS/SQLi paths are secure.
- [x] Activity evidence: booking events, latest document reviewer/time, payment audit, Django admin log and database rate trigger. Coverage is partial, not immutable or centralized.
- [ ] Azure database firewall/private networking configured and screenshot captured.
- [ ] Azure PostgreSQL and private Blob deployed, backups tested, and secrets secured with a secret manager.
- [ ] Real Power BI report built and evidence captured.
- [ ] Independent security testing, centralized monitoring, retention policy, staff MFA and disaster recovery verified.
- [ ] Approved payment provider, webhooks and real 18%/82% settlement tested and reconciled.
