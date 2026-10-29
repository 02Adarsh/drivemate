"""Django settings for the DriveMate backend.

Development defaults work out of the box (SQLite + console email). Everything
that must change for production is read from the environment - see
`.env.example`. Secrets never live in this file.

NOTE: a blank value in `.env` (for example `DB_ENGINE=`) counts as
"not configured", not as an empty setting. The `env*` helpers below make sure a
blank line can never break the server.
"""

import os
from datetime import timedelta
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / '.env')


# ---------------------------------------------------------------------------
# Environment helpers - an empty string is treated as "use the default"
# ---------------------------------------------------------------------------

def env(name: str, default: str = '') -> str:
    value = os.getenv(name)
    return value if value is not None and value.strip() != '' else default


def env_int(name: str, default: int) -> int:
    try:
        return int(env(name, str(default)))
    except (TypeError, ValueError):
        return default


def env_bool(name: str, default: bool = False) -> bool:
    return env(name, 'true' if default else 'false').strip().lower() in ('1', 'true', 'yes', 'on')


def env_list(name: str, default: str = '') -> list:
    return [item.strip() for item in env(name, default).split(',') if item.strip()]


# --- Core -----------------------------------------------------------------
SECRET_KEY = env('DJANGO_SECRET_KEY', 'dev-only-change-me')
DEBUG = env_bool('DEBUG', True)
if not DEBUG and (len(SECRET_KEY) < 32 or SECRET_KEY.startswith(('dev-only','replace-'))):
    from django.core.exceptions import ImproperlyConfigured
    raise ImproperlyConfigured('Set a private, random DJANGO_SECRET_KEY of at least 32 characters before disabling DEBUG.')
ALLOWED_HOSTS = env_list('ALLOWED_HOSTS', 'localhost,127.0.0.1,10.0.2.2')

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'rest_framework',
    'corsheaders',
    'accounts',
    'rides',
    'hub',
    'payments',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'corsheaders.middleware.CorsMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'config.urls'
TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ]
        },
    }
]
WSGI_APPLICATION = 'config.wsgi.application'

# Enforce HTTPS and secure cookies in production. When terminating TLS at a
# trusted reverse proxy, enable TRUST_PROXY_HTTPS only if the proxy strips and
# overwrites X-Forwarded-Proto on every incoming request.
if not DEBUG:
    SECURE_SSL_REDIRECT = True
    SESSION_COOKIE_SECURE = True
    CSRF_COOKIE_SECURE = True
    SECURE_CONTENT_TYPE_NOSNIFF = True
    if env_bool('TRUST_PROXY_HTTPS', False):
        SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')


# --- Database -------------------------------------------------------------
# Development: SQLite (no configuration needed).
# Production (PostgreSQL example in .env):
#   DB_ENGINE=django.db.backends.postgresql
#   DB_NAME=drivemate  DB_USER=...  DB_PASSWORD=...  DB_HOST=...  DB_PORT=5432
DB_ENGINE = env('DB_ENGINE', 'django.db.backends.sqlite3')
DB_NAME = env('DB_NAME', str(BASE_DIR / 'db.sqlite3'))

if 'sqlite' in DB_ENGINE:
    DATABASES = {'default': {'ENGINE': DB_ENGINE, 'NAME': DB_NAME}}
else:
    DATABASES = {
        'default': {
            'ENGINE': DB_ENGINE,
            'NAME': DB_NAME,
            'USER': env('DB_USER'),
            'PASSWORD': env('DB_PASSWORD'),
            'HOST': env('DB_HOST', '127.0.0.1'),
            'PORT': env('DB_PORT', '5432'),
            'CONN_MAX_AGE': 60,
        }
    }

# Azure PostgreSQL requires TLS; opt in explicitly for cloud deployments.
if 'postgresql' in DB_ENGINE and env('DB_SSLMODE'):
    DATABASES['default']['OPTIONS'] = {'sslmode': env('DB_SSLMODE')}

AUTH_USER_MODEL = 'accounts.User'
AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator', 'OPTIONS': {'min_length': 8}},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]

LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'Asia/Kolkata'
USE_I18N = True
USE_TZ = True

STATIC_URL = 'static/'
DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# --- Private uploads ------------------------------------------------------
# Files are saved with private storage keys (never public URLs). In production
# point `STORAGES` at S3/R2/GCS and keep the same key layout.
MEDIA_ROOT = BASE_DIR / 'private_uploads'
FILE_UPLOAD_MAX_MEMORY_SIZE = 5 * 1024 * 1024   # 5 MB in memory, larger files spool to disk
DATA_UPLOAD_MAX_MEMORY_SIZE = 12 * 1024 * 1024  # allow 5 MB images + form fields

# Optional private Azure Blob container. Application endpoints still authorize
# downloads; never enable anonymous container access. Install requirements-cloud.txt.
if env_bool('USE_AZURE_BLOB', False):
    from django.core.exceptions import ImproperlyConfigured
    if not env('AZURE_CONNECTION_STRING') or not env('AZURE_CONTAINER'):
        raise ImproperlyConfigured('Set AZURE_CONNECTION_STRING and AZURE_CONTAINER for Blob storage.')
    STORAGES = {
        'default': {'BACKEND': 'storages.backends.azure_storage.AzureStorage', 'OPTIONS': {
            'connection_string': env('AZURE_CONNECTION_STRING'),
            'azure_container': env('AZURE_CONTAINER'),
            'azure_ssl': True,
            'overwrite_files': False,
        }},
        'staticfiles': {'BACKEND': 'django.contrib.staticfiles.storage.StaticFilesStorage'},
    }


# --- CORS / API -----------------------------------------------------------
CORS_ALLOW_ALL_ORIGINS = DEBUG
CORS_ALLOWED_ORIGINS = env_list('CORS_ALLOWED_ORIGINS')

REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': (
        'rest_framework_simplejwt.authentication.JWTAuthentication',
        'rest_framework.authentication.SessionAuthentication',
    ),
    'DEFAULT_THROTTLE_CLASSES': ['rest_framework.throttling.AnonRateThrottle'],
    'DEFAULT_THROTTLE_RATES': {'anon': env('ANON_THROTTLE', '60/minute'), 'otp': '5/minute', 'map': '12/minute', 'trip_start': '10/minute', 'payment':'24/minute'},
}
SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(minutes=env_int('ACCESS_TOKEN_MINUTES', 60)),
    'REFRESH_TOKEN_LIFETIME': timedelta(days=env_int('REFRESH_TOKEN_DAYS', 7)),
    'CHECK_REVOKE_TOKEN': True,
}

# --- Email / OTP ----------------------------------------------------------
EMAIL_TIMEOUT = 12
EMAIL_HOST = env('EMAIL_HOST')
EMAIL_PORT = env_int('EMAIL_PORT', 587)
EMAIL_USE_TLS = env_bool('EMAIL_USE_TLS', True)
EMAIL_HOST_USER = env('EMAIL_HOST_USER')
EMAIL_HOST_PASSWORD = env('EMAIL_HOST_PASSWORD')
EMAIL_BACKEND = (
    'django.core.mail.backends.smtp.EmailBackend'
    if EMAIL_HOST and EMAIL_HOST_USER and EMAIL_HOST_PASSWORD
    else 'django.core.mail.backends.console.EmailBackend'
)
DEFAULT_FROM_EMAIL = env('DEFAULT_FROM_EMAIL', EMAIL_HOST_USER or 'DriveMate <no-reply@drivemate.local>')
OTP_EXPIRY_MINUTES = env_int('OTP_EXPIRY_MINUTES', 10)
OTP_MAX_ATTEMPTS = env_int('OTP_MAX_ATTEMPTS', 5)

# --- Driver verification policy ------------------------------------------
# Change these per service area instead of editing code.
DRIVER_REQUIRED_DOCUMENTS = tuple(
    env_list('DRIVER_REQUIRED_DOCUMENTS', 'LICENCE_FRONT,LICENCE_BACK,IDENTITY')
)
DRIVER_OPTIONAL_DOCUMENTS = tuple(env_list('DRIVER_OPTIONAL_DOCUMENTS', 'ADDRESS_PROOF'))
DRIVER_REQUIRED_TRAINING = tuple(
    env_list('DRIVER_REQUIRED_TRAINING', 'SAFE_DRIVING,CUSTOMER_SERVICE,VEHICLE_INSPECTION')
)

# DEVELOPMENT ONLY. When true (and DEBUG=true) an application that reaches
# PENDING_REVIEW is approved automatically so the flow can be tested without an
# admin. This must stay false for any real deployment.
AUTO_APPROVE_DRIVERS_IN_DEV = env_bool('AUTO_APPROVE_DRIVERS_IN_DEV', False) and DEBUG

# --- Logging --------------------------------------------------------------
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {'simple': {'format': '[{asctime}] {levelname} {name}: {message}', 'style': '{'}},
    'handlers': {'console': {'class': 'logging.StreamHandler', 'formatter': 'simple'}},
    'loggers': {'accounts': {'handlers': ['console'], 'level': env('LOG_LEVEL', 'INFO'), 'propagate': False}},
}

# Identify user-triggered OpenStreetMap lookups (never autocomplete/bulk scan).
GEOCODING_USER_AGENT = env('GEOCODING_USER_AGENT', 'DriveMate/1.7 (https://github.com/02Adarsh/drivemate)')
