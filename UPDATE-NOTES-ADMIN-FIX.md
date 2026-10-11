# Superuser creation fix

Extract/merge the included `backend/accounts/models.py` and migration `0004_alter_user_managers.py` into the existing project.

The custom user model removes `username`; Django's default `UserManager.create_superuser` still expects one. The included `DriveMateUserManager` creates superusers using the configured email + full name instead. Apply the state migration and retry:
```powershell
cd backend
python manage.py migrate
python manage.py createsuperuser
```
Enter email, full name, password and confirmation. The password prompt does not echo characters while typing; that's normal.

Also fix `python-dotenv could not parse statement starting at line 14`: in `backend/.env`, quote the sender label line exactly like this:
```dotenv
DEFAULT_FROM_EMAIL="DriveMate <support.driveemate@gmail.com>"
```
Do not paste/share the App Password. Restart Django after `.env` changes.
