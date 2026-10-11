# Patch — login with email or phone

Extract/merge these updated files into the existing DriveMate project.

Your pasted `LoginSerializer(identifier=...)` must be paired with a view that reads `validated_data['identifier']`; the previous view expected `email` and would error. This patch updates the API and Flutter request together.

- Register validates/normalizes phone input and rejects duplicate numbers.
- Login accepts either registered email or phone, normalizes spaces/dashes/parentheses in phone numbers, validates password and role.
- Flutter login field accepts email or phone and shows that label; signup still requires a valid email for email OTP, plus phone.

After extracting, restart Django:
```powershell
cd backend
python manage.py runserver 0.0.0.0:8000
```
No database migration is required for this patch. In Flutter, rebuild/relaunch the app:
```powershell
cd frontend
flutter pub get
flutter run -d ZA223BDMZP
```
