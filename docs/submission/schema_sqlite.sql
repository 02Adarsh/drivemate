-- SQLite schema export after Django migrations. For an EMPTY database only.
-- Canonical cross-database schema is backend/*/migrations; run manage.py migrate.
-- Existing databases must be upgraded using migrations, not this file.
PRAGMA foreign_keys=ON;

-- table: accounts_customerprofile
CREATE TABLE "accounts_customerprofile" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "address" varchar(250) NOT NULL, "city" varchar(100) NOT NULL, "emergency_contact_name" varchar(120) NOT NULL, "emergency_contact_phone" varchar(20) NOT NULL, "profile_complete" bool NOT NULL, "updated_at" datetime NOT NULL, "user_id" bigint NOT NULL UNIQUE REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED, "pincode" varchar(10) NOT NULL, "state" varchar(100) NOT NULL);

-- table: accounts_driverdocument
CREATE TABLE "accounts_driverdocument" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "document_type" varchar(20) NOT NULL, "private_storage_key" varchar(500) NOT NULL, "expires_at" date NULL, "review_status" varchar(12) NOT NULL, "rejection_reason" varchar(500) NOT NULL, "uploaded_at" datetime NOT NULL, "reviewed_at" datetime NULL, "driver_id" bigint NOT NULL REFERENCES "accounts_driverprofile" ("id") DEFERRABLE INITIALLY DEFERRED, "reviewed_by_id" bigint NULL REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED, "document_number" varchar(80) NOT NULL, "updated_at" datetime NOT NULL);

-- table: accounts_driveremergencycontact
CREATE TABLE "accounts_driveremergencycontact" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "name" varchar(120) NOT NULL, "relationship" varchar(60) NOT NULL, "phone" varchar(20) NOT NULL, "is_primary" bool NOT NULL, "created_at" datetime NOT NULL, "driver_id" bigint NOT NULL REFERENCES "accounts_driverprofile" ("id") DEFERRABLE INITIALLY DEFERRED);

-- table: accounts_driverprofile
CREATE TABLE "accounts_driverprofile" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "date_of_birth" date NULL, "address" varchar(250) NOT NULL, "city" varchar(100) NOT NULL, "emergency_contact_name" varchar(120) NOT NULL, "emergency_contact_phone" varchar(20) NOT NULL, "languages" varchar(250) NOT NULL, "introduction" varchar(500) NOT NULL, "licence_number" varchar(80) NOT NULL, "licence_expiry" date NULL, "experience_years" smallint unsigned NOT NULL CHECK ("experience_years" >= 0), "manual_transmission" bool NOT NULL, "automatic_transmission" bool NOT NULL, "sedan" bool NOT NULL, "suv" bool NOT NULL, "luxury" bool NOT NULL, "highway" bool NOT NULL, "night_driving" bool NOT NULL, "outstation" bool NOT NULL, "verification_status" varchar(20) NOT NULL, "profile_complete" bool NOT NULL, "submitted_at" datetime NULL, "updated_at" datetime NOT NULL, "user_id" bigint NOT NULL UNIQUE REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED, "approved_at" datetime NULL, "consent_background_check" bool NOT NULL, "consent_data_accuracy" bool NOT NULL, "consent_terms" bool NOT NULL, "consents_accepted_at" datetime NULL, "rejection_reason" varchar(500) NOT NULL, "reviewed_at" datetime NULL, "reviewed_by_id" bigint NULL REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED, "service_area" varchar(120) NOT NULL, "pincode" varchar(10) NOT NULL, "state" varchar(100) NOT NULL, "available_since" datetime NULL, "is_available" bool NOT NULL);

-- table: accounts_drivertraining
CREATE TABLE "accounts_drivertraining" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "module" varchar(32) NOT NULL, "status" varchar(12) NOT NULL, "completed_at" datetime NULL, "updated_at" datetime NOT NULL, "driver_id" bigint NOT NULL REFERENCES "accounts_driverprofile" ("id") DEFERRABLE INITIALLY DEFERRED);

-- table: accounts_emailotp
CREATE TABLE "accounts_emailotp" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "code_hash" varchar(128) NOT NULL, "expires_at" datetime NOT NULL, "attempts" smallint unsigned NOT NULL CHECK ("attempts" >= 0), "created_at" datetime NOT NULL, "consumed_at" datetime NULL, "user_id" bigint NOT NULL REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED, "purpose" varchar(20) NOT NULL);

-- table: accounts_user
CREATE TABLE "accounts_user" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "password" varchar(128) NOT NULL, "last_login" datetime NULL, "is_superuser" bool NOT NULL, "first_name" varchar(150) NOT NULL, "last_name" varchar(150) NOT NULL, "is_staff" bool NOT NULL, "is_active" bool NOT NULL, "date_joined" datetime NOT NULL, "email" varchar(254) NOT NULL UNIQUE, "full_name" varchar(120) NOT NULL, "role" varchar(12) NOT NULL, "email_verified" bool NOT NULL, "phone" varchar(20) NOT NULL, "profile_photo_key" varchar(500) NOT NULL, "last_seen_at" datetime NULL);

-- table: accounts_user_groups
CREATE TABLE "accounts_user_groups" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "user_id" bigint NOT NULL REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED, "group_id" integer NOT NULL REFERENCES "auth_group" ("id") DEFERRABLE INITIALLY DEFERRED);

-- table: accounts_user_user_permissions
CREATE TABLE "accounts_user_user_permissions" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "user_id" bigint NOT NULL REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED, "permission_id" integer NOT NULL REFERENCES "auth_permission" ("id") DEFERRABLE INITIALLY DEFERRED);

-- table: auth_group
CREATE TABLE "auth_group" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "name" varchar(150) NOT NULL UNIQUE);

-- table: auth_group_permissions
CREATE TABLE "auth_group_permissions" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "group_id" integer NOT NULL REFERENCES "auth_group" ("id") DEFERRABLE INITIALLY DEFERRED, "permission_id" integer NOT NULL REFERENCES "auth_permission" ("id") DEFERRABLE INITIALLY DEFERRED);

-- table: auth_permission
CREATE TABLE "auth_permission" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "content_type_id" integer NOT NULL REFERENCES "django_content_type" ("id") DEFERRABLE INITIALLY DEFERRED, "codename" varchar(100) NOT NULL, "name" varchar(255) NOT NULL);

-- table: django_admin_log
CREATE TABLE "django_admin_log" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "object_id" text NULL, "object_repr" varchar(200) NOT NULL, "action_flag" smallint unsigned NOT NULL CHECK ("action_flag" >= 0), "change_message" text NOT NULL, "content_type_id" integer NULL REFERENCES "django_content_type" ("id") DEFERRABLE INITIALLY DEFERRED, "user_id" bigint NOT NULL REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED, "action_time" datetime NOT NULL);

-- table: django_content_type
CREATE TABLE "django_content_type" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "app_label" varchar(100) NOT NULL, "model" varchar(100) NOT NULL);

-- table: django_session
CREATE TABLE "django_session" ("session_key" varchar(40) NOT NULL PRIMARY KEY, "session_data" text NOT NULL, "expire_date" datetime NOT NULL);

-- table: hub_businessprofile
CREATE TABLE "hub_businessprofile" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "company" varchar(120) NOT NULL, "department" varchar(80) NOT NULL, "employee_id" varchar(60) NOT NULL, "created_at" datetime NOT NULL, "owner_id" bigint NOT NULL REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED);

-- table: hub_claimedpromo
CREATE TABLE "hub_claimedpromo" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "created_at" datetime NOT NULL, "used_booking_id" bigint NULL UNIQUE REFERENCES "rides_booking" ("id") DEFERRABLE INITIALLY DEFERRED, "user_id" bigint NOT NULL REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED, "promo_id" bigint NOT NULL REFERENCES "hub_promocode" ("id") DEFERRABLE INITIALLY DEFERRED, CONSTRAINT "one_promo_per_customer" UNIQUE ("user_id", "promo_id"));

-- table: hub_contact
CREATE TABLE "hub_contact" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "name" varchar(120) NOT NULL, "phone" varchar(20) NOT NULL, "relationship" varchar(40) NOT NULL, "emergency" bool NOT NULL, "created_at" datetime NOT NULL, "owner_id" bigint NOT NULL REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED);

-- table: hub_emailchange
CREATE TABLE "hub_emailchange" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "email" varchar(254) NOT NULL, "code_hash" varchar(128) NOT NULL, "expires_at" datetime NOT NULL, "attempts" smallint unsigned NOT NULL CHECK ("attempts" >= 0), "created_at" datetime NOT NULL, "user_id" bigint NOT NULL UNIQUE REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED);

-- table: hub_preferences
CREATE TABLE "hub_preferences" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "language" varchar(2) NOT NULL, "theme" varchar(8) NOT NULL, "trip_updates" bool NOT NULL, "email_receipts" bool NOT NULL, "marketing" bool NOT NULL, "large_text" bool NOT NULL, "invite_code" varchar(12) NOT NULL UNIQUE, "referred_by_id" bigint NULL REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED, "user_id" bigint NOT NULL UNIQUE REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED);

-- table: hub_promocode
CREATE TABLE "hub_promocode" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "code" varchar(32) NOT NULL UNIQUE, "description" varchar(240) NOT NULL, "amount" decimal NOT NULL, "active" bool NOT NULL, "expires_at" datetime NULL, "max_redemptions" integer unsigned NOT NULL CHECK ("max_redemptions" >= 0));

-- table: hub_savedplace
CREATE TABLE "hub_savedplace" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "label" varchar(60) NOT NULL, "address" varchar(240) NOT NULL, "latitude" decimal NOT NULL, "longitude" decimal NOT NULL, "kind" varchar(8) NOT NULL, "created_at" datetime NOT NULL, "owner_id" bigint NOT NULL REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED);

-- table: hub_supportmessage
CREATE TABLE "hub_supportmessage" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "text" varchar(2000) NOT NULL, "created_at" datetime NOT NULL, "author_id" bigint NULL REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED, "ticket_id" bigint NOT NULL REFERENCES "hub_supportticket" ("id") DEFERRABLE INITIALLY DEFERRED);

-- table: hub_supportticket
CREATE TABLE "hub_supportticket" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "category" varchar(24) NOT NULL, "subject" varchar(120) NOT NULL, "description" varchar(2000) NOT NULL, "status" varchar(12) NOT NULL, "created_at" datetime NOT NULL, "updated_at" datetime NOT NULL, "booking_id" bigint NULL REFERENCES "rides_booking" ("id") DEFERRABLE INITIALLY DEFERRED, "owner_id" bigint NOT NULL REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED);

-- table: payments_directupipayment
CREATE TABLE "payments_directupipayment" ("id" char(32) NOT NULL PRIMARY KEY, "receiver_upi_id" varchar(256) NOT NULL, "receiver_name" varchar(120) NOT NULL, "profile_version" integer unsigned NOT NULL CHECK ("profile_version" >= 0), "amount" decimal NOT NULL, "currency" varchar(3) NOT NULL, "qr_payload" text NOT NULL, "reference" varchar(48) NOT NULL UNIQUE, "status" varchar(12) NOT NULL, "customer_reference" varchar(64) NOT NULL, "reported_at" datetime NULL, "bank_reference" varchar(64) NOT NULL, "received_amount" decimal NULL, "confirmed_at" datetime NULL, "reviewed_at" datetime NULL, "review_note" varchar(500) NOT NULL, "created_at" datetime NOT NULL, "updated_at" datetime NOT NULL, "booking_id" bigint NOT NULL UNIQUE REFERENCES "rides_booking" ("id") DEFERRABLE INITIALLY DEFERRED, "driver_id" bigint NOT NULL REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED);

-- table: payments_driverupichange
CREATE TABLE "payments_driverupichange" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "previous_upi_id" varchar(256) NOT NULL, "new_upi_id" varchar(256) NOT NULL, "profile_version" integer unsigned NOT NULL CHECK ("profile_version" >= 0), "qr_sha256" varchar(64) NOT NULL, "created_at" datetime NOT NULL, "driver_id" bigint NOT NULL REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED);

-- table: payments_driverupiprofile
CREATE TABLE "payments_driverupiprofile" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "upi_id" varchar(256) NOT NULL, "payee_name" varchar(120) NOT NULL, "uploaded_payee_hint" varchar(120) NOT NULL, "qr_storage_key" varchar(500) NOT NULL, "qr_sha256" varchar(64) NOT NULL, "active" bool NOT NULL, "version" integer unsigned NOT NULL CHECK ("version" >= 0), "ownership_attested_at" datetime NOT NULL, "updated_at" datetime NOT NULL, "driver_id" bigint NOT NULL UNIQUE REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED);

-- table: payments_paymentaudit
CREATE TABLE "payments_paymentaudit" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "action" varchar(32) NOT NULL, "note" varchar(500) NOT NULL, "created_at" datetime NOT NULL, "actor_id" bigint NULL REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED, "payment_id" char(32) NOT NULL REFERENCES "payments_directupipayment" ("id") DEFERRABLE INITIALLY DEFERRED);

-- table: rides_booking
CREATE TABLE "rides_booking" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "service" varchar(12) NOT NULL, "scheduled_at" datetime NULL, "duration_hours" smallint unsigned NOT NULL CHECK ("duration_hours" >= 0), "pickup" varchar(240) NOT NULL, "drop_address" varchar(240) NOT NULL, "notes" varchar(500) NOT NULL, "estimated_fare" decimal NOT NULL, "final_fare" decimal NULL, "platform_fee_percent" smallint unsigned NOT NULL CHECK ("platform_fee_percent" >= 0), "status" varchar(12) NOT NULL, "cancel_reason" varchar(240) NOT NULL, "created_at" datetime NOT NULL, "updated_at" datetime NOT NULL, "accepted_at" datetime NULL, "started_at" datetime NULL, "completed_at" datetime NULL, "cancelled_at" datetime NULL, "customer_id" bigint NOT NULL REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED, "driver_id" bigint NULL REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED, "vehicle_id" bigint NULL REFERENCES "rides_vehicle" ("id") DEFERRABLE INITIALLY DEFERRED, "request_key" varchar(64) NOT NULL, "vehicle_snapshot" text NOT NULL CHECK ((JSON_VALID("vehicle_snapshot") OR "vehicle_snapshot" IS NULL)), "business_label" varchar(120) NOT NULL, "cash_received_at" datetime NULL, "discount_amount" decimal NOT NULL, "driver_latitude" decimal NULL, "driver_longitude" decimal NULL, "drop_latitude" decimal NULL, "drop_longitude" decimal NULL, "location_updated_at" datetime NULL, "otp_verified_at" datetime NULL, "passenger_name" varchar(120) NOT NULL, "passenger_phone" varchar(20) NOT NULL, "pickup_latitude" decimal NULL, "pickup_longitude" decimal NULL, "promo_code" varchar(32) NOT NULL);

-- table: rides_bookingdecline
CREATE TABLE "rides_bookingdecline" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "created_at" datetime NOT NULL, "booking_id" bigint NOT NULL REFERENCES "rides_booking" ("id") DEFERRABLE INITIALLY DEFERRED, "driver_id" bigint NOT NULL REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED, CONSTRAINT "booking_decline_unique" UNIQUE ("booking_id", "driver_id"));

-- table: rides_bookingevent
CREATE TABLE "rides_bookingevent" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "kind" varchar(12) NOT NULL, "note" varchar(240) NOT NULL, "created_at" datetime NOT NULL, "booking_id" bigint NOT NULL REFERENCES "rides_booking" ("id") DEFERRABLE INITIALLY DEFERRED, "created_by_id" bigint NULL REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED);

-- table: rides_notification
CREATE TABLE "rides_notification" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "title" varchar(120) NOT NULL, "body" varchar(400) NOT NULL, "kind" varchar(24) NOT NULL, "read_at" datetime NULL, "created_at" datetime NOT NULL, "booking_id" bigint NULL REFERENCES "rides_booking" ("id") DEFERRABLE INITIALLY DEFERRED, "user_id" bigint NOT NULL REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED);

-- table: rides_rate_change_audit
CREATE TABLE rides_rate_change_audit (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rate_id BIGINT NOT NULL REFERENCES rides_servicerate(id),
        old_base INTEGER NOT NULL, new_base INTEGER NOT NULL,
        old_per_hour INTEGER NOT NULL, new_per_hour INTEGER NOT NULL,
        changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

-- table: rides_servicerate
CREATE TABLE "rides_servicerate" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "service" varchar(12) NOT NULL UNIQUE, "base" integer unsigned NOT NULL CHECK ("base" >= 0), "per_hour" integer unsigned NOT NULL CHECK ("per_hour" >= 0), "updated_at" datetime NOT NULL, CONSTRAINT "rate_base_max" CHECK ("base" <= 1000000), CONSTRAINT "rate_hour_max" CHECK ("per_hour" <= 100000));

-- table: rides_triprating
CREATE TABLE "rides_triprating" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "score" smallint unsigned NOT NULL CHECK ("score" >= 0), "comment" varchar(500) NOT NULL, "created_at" datetime NOT NULL, "author_id" bigint NOT NULL REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED, "booking_id" bigint NOT NULL REFERENCES "rides_booking" ("id") DEFERRABLE INITIALLY DEFERRED, CONSTRAINT "one_rating_per_trip_author" UNIQUE ("booking_id", "author_id"));

-- table: rides_tripstartcode
CREATE TABLE "rides_tripstartcode" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "code_hash" varchar(128) NOT NULL, "code_ciphertext" text NOT NULL, "expires_at" datetime NOT NULL, "attempts" smallint unsigned NOT NULL CHECK ("attempts" >= 0), "locked_until" datetime NULL, "consumed_at" datetime NULL, "email_sent" bool NOT NULL, "created_at" datetime NOT NULL, "booking_id" bigint NOT NULL UNIQUE REFERENCES "rides_booking" ("id") DEFERRABLE INITIALLY DEFERRED);

-- table: rides_vehicle
CREATE TABLE "rides_vehicle" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT, "make" varchar(60) NOT NULL, "model" varchar(60) NOT NULL, "registration" varchar(16) NOT NULL, "fuel" varchar(10) NOT NULL, "transmission" varchar(10) NOT NULL, "seats" smallint unsigned NOT NULL CHECK ("seats" >= 0), "is_default" bool NOT NULL, "created_at" datetime NOT NULL, "updated_at" datetime NOT NULL, "owner_id" bigint NOT NULL REFERENCES "accounts_user" ("id") DEFERRABLE INITIALLY DEFERRED, CONSTRAINT "vehicle_unique_per_owner" UNIQUE ("owner_id", "registration"));

-- index: accounts_driverdocument_driver_id_b85f7e50
CREATE INDEX "accounts_driverdocument_driver_id_b85f7e50" ON "accounts_driverdocument" ("driver_id");

-- index: accounts_driverdocument_driver_id_document_type_421625a7_uniq
CREATE UNIQUE INDEX "accounts_driverdocument_driver_id_document_type_421625a7_uniq" ON "accounts_driverdocument" ("driver_id", "document_type");

-- index: accounts_driverdocument_reviewed_by_id_c7f4efad
CREATE INDEX "accounts_driverdocument_reviewed_by_id_c7f4efad" ON "accounts_driverdocument" ("reviewed_by_id");

-- index: accounts_driveremergencycontact_driver_id_2f9d0e01
CREATE INDEX "accounts_driveremergencycontact_driver_id_2f9d0e01" ON "accounts_driveremergencycontact" ("driver_id");

-- index: accounts_driverprofile_reviewed_by_id_9d2f5746
CREATE INDEX "accounts_driverprofile_reviewed_by_id_9d2f5746" ON "accounts_driverprofile" ("reviewed_by_id");

-- index: accounts_drivertraining_driver_id_d514c9ee
CREATE INDEX "accounts_drivertraining_driver_id_d514c9ee" ON "accounts_drivertraining" ("driver_id");

-- index: accounts_drivertraining_driver_id_module_38731c19_uniq
CREATE UNIQUE INDEX "accounts_drivertraining_driver_id_module_38731c19_uniq" ON "accounts_drivertraining" ("driver_id", "module");

-- index: accounts_emailotp_user_id_137ae83b
CREATE INDEX "accounts_emailotp_user_id_137ae83b" ON "accounts_emailotp" ("user_id");

-- index: accounts_user_groups_group_id_bd11a704
CREATE INDEX "accounts_user_groups_group_id_bd11a704" ON "accounts_user_groups" ("group_id");

-- index: accounts_user_groups_user_id_52b62117
CREATE INDEX "accounts_user_groups_user_id_52b62117" ON "accounts_user_groups" ("user_id");

-- index: accounts_user_groups_user_id_group_id_59c0b32f_uniq
CREATE UNIQUE INDEX "accounts_user_groups_user_id_group_id_59c0b32f_uniq" ON "accounts_user_groups" ("user_id", "group_id");

-- index: accounts_user_user_permissions_permission_id_113bb443
CREATE INDEX "accounts_user_user_permissions_permission_id_113bb443" ON "accounts_user_user_permissions" ("permission_id");

-- index: accounts_user_user_permissions_user_id_e4f0a161
CREATE INDEX "accounts_user_user_permissions_user_id_e4f0a161" ON "accounts_user_user_permissions" ("user_id");

-- index: accounts_user_user_permissions_user_id_permission_id_2ab516c2_uniq
CREATE UNIQUE INDEX "accounts_user_user_permissions_user_id_permission_id_2ab516c2_uniq" ON "accounts_user_user_permissions" ("user_id", "permission_id");

-- index: auth_group_permissions_group_id_b120cbf9
CREATE INDEX "auth_group_permissions_group_id_b120cbf9" ON "auth_group_permissions" ("group_id");

-- index: auth_group_permissions_group_id_permission_id_0cd325b0_uniq
CREATE UNIQUE INDEX "auth_group_permissions_group_id_permission_id_0cd325b0_uniq" ON "auth_group_permissions" ("group_id", "permission_id");

-- index: auth_group_permissions_permission_id_84c5c92e
CREATE INDEX "auth_group_permissions_permission_id_84c5c92e" ON "auth_group_permissions" ("permission_id");

-- index: auth_permission_content_type_id_2f476e4b
CREATE INDEX "auth_permission_content_type_id_2f476e4b" ON "auth_permission" ("content_type_id");

-- index: auth_permission_content_type_id_codename_01ab375a_uniq
CREATE UNIQUE INDEX "auth_permission_content_type_id_codename_01ab375a_uniq" ON "auth_permission" ("content_type_id", "codename");

-- index: booking_customer_idx
CREATE INDEX "booking_customer_idx" ON "rides_booking" ("customer_id", "created_at" DESC);

-- index: booking_driver_idx
CREATE INDEX "booking_driver_idx" ON "rides_booking" ("driver_id", "created_at" DESC);

-- index: booking_one_live_customer
CREATE UNIQUE INDEX "booking_one_live_customer" ON "rides_booking" ("customer_id") WHERE "status" IN ('REQUESTED', 'ACCEPTED', 'ONGOING');

-- index: booking_one_live_driver
CREATE UNIQUE INDEX "booking_one_live_driver" ON "rides_booking" ("driver_id") WHERE ("driver_id" IS NOT NULL AND "status" IN ('ACCEPTED', 'ONGOING'));

-- index: booking_status_idx
CREATE INDEX "booking_status_idx" ON "rides_booking" ("status", "created_at" DESC);

-- index: booking_unique_request_key
CREATE UNIQUE INDEX "booking_unique_request_key" ON "rides_booking" ("customer_id", "request_key") WHERE NOT ("request_key" = '');

-- index: django_admin_log_content_type_id_c4bce8eb
CREATE INDEX "django_admin_log_content_type_id_c4bce8eb" ON "django_admin_log" ("content_type_id");

-- index: django_admin_log_user_id_c564eba6
CREATE INDEX "django_admin_log_user_id_c564eba6" ON "django_admin_log" ("user_id");

-- index: django_content_type_app_label_model_76bd3d3b_uniq
CREATE UNIQUE INDEX "django_content_type_app_label_model_76bd3d3b_uniq" ON "django_content_type" ("app_label", "model");

-- index: django_session_expire_date_a5c62663
CREATE INDEX "django_session_expire_date_a5c62663" ON "django_session" ("expire_date");

-- index: doc_expiry_idx
CREATE INDEX "doc_expiry_idx" ON "accounts_driverdocument" ("expires_at");

-- index: doc_type_review_idx
CREATE INDEX "doc_type_review_idx" ON "accounts_driverdocument" ("document_type", "review_status");

-- index: driver_city_idx
CREATE INDEX "driver_city_idx" ON "accounts_driverprofile" ("city");

-- index: driver_state_idx
CREATE INDEX "driver_state_idx" ON "accounts_driverprofile" ("state");

-- index: driver_status_idx
CREATE INDEX "driver_status_idx" ON "accounts_driverprofile" ("verification_status");

-- index: emergency_driver_idx
CREATE INDEX "emergency_driver_idx" ON "accounts_driveremergencycontact" ("driver_id");

-- index: hub_businessprofile_owner_id_81e93fe5
CREATE INDEX "hub_businessprofile_owner_id_81e93fe5" ON "hub_businessprofile" ("owner_id");

-- index: hub_claimedpromo_promo_id_634279f6
CREATE INDEX "hub_claimedpromo_promo_id_634279f6" ON "hub_claimedpromo" ("promo_id");

-- index: hub_claimedpromo_user_id_c06881ec
CREATE INDEX "hub_claimedpromo_user_id_c06881ec" ON "hub_claimedpromo" ("user_id");

-- index: hub_contact_owner_id_005a84bf
CREATE INDEX "hub_contact_owner_id_005a84bf" ON "hub_contact" ("owner_id");

-- index: hub_preferences_referred_by_id_9dadfca7
CREATE INDEX "hub_preferences_referred_by_id_9dadfca7" ON "hub_preferences" ("referred_by_id");

-- index: hub_savedplace_owner_id_f66d0068
CREATE INDEX "hub_savedplace_owner_id_f66d0068" ON "hub_savedplace" ("owner_id");

-- index: hub_supportmessage_author_id_092069bd
CREATE INDEX "hub_supportmessage_author_id_092069bd" ON "hub_supportmessage" ("author_id");

-- index: hub_supportmessage_ticket_id_914758f0
CREATE INDEX "hub_supportmessage_ticket_id_914758f0" ON "hub_supportmessage" ("ticket_id");

-- index: hub_supportticket_booking_id_2ef1d8fc
CREATE INDEX "hub_supportticket_booking_id_2ef1d8fc" ON "hub_supportticket" ("booking_id");

-- index: hub_supportticket_owner_id_73f628f2
CREATE INDEX "hub_supportticket_owner_id_73f628f2" ON "hub_supportticket" ("owner_id");

-- index: notification_user_idx
CREATE INDEX "notification_user_idx" ON "rides_notification" ("user_id", "created_at" DESC);

-- index: otp_user_consumed_idx
CREATE INDEX "otp_user_consumed_idx" ON "accounts_emailotp" ("user_id", "consumed_at");

-- index: payments_directupipayment_driver_id_d14a50ef
CREATE INDEX "payments_directupipayment_driver_id_d14a50ef" ON "payments_directupipayment" ("driver_id");

-- index: payments_driverupichange_driver_id_2cda29f2
CREATE INDEX "payments_driverupichange_driver_id_2cda29f2" ON "payments_driverupichange" ("driver_id");

-- index: payments_paymentaudit_actor_id_fb178f22
CREATE INDEX "payments_paymentaudit_actor_id_fb178f22" ON "payments_paymentaudit" ("actor_id");

-- index: payments_paymentaudit_payment_id_4594298d
CREATE INDEX "payments_paymentaudit_payment_id_4594298d" ON "payments_paymentaudit" ("payment_id");

-- index: rides_booking_customer_id_eaee840f
CREATE INDEX "rides_booking_customer_id_eaee840f" ON "rides_booking" ("customer_id");

-- index: rides_booking_driver_id_80b20d35
CREATE INDEX "rides_booking_driver_id_80b20d35" ON "rides_booking" ("driver_id");

-- index: rides_booking_vehicle_id_cd426682
CREATE INDEX "rides_booking_vehicle_id_cd426682" ON "rides_booking" ("vehicle_id");

-- index: rides_bookingdecline_booking_id_a981f71d
CREATE INDEX "rides_bookingdecline_booking_id_a981f71d" ON "rides_bookingdecline" ("booking_id");

-- index: rides_bookingdecline_driver_id_fedcd3cb
CREATE INDEX "rides_bookingdecline_driver_id_fedcd3cb" ON "rides_bookingdecline" ("driver_id");

-- index: rides_bookingevent_booking_id_542e9220
CREATE INDEX "rides_bookingevent_booking_id_542e9220" ON "rides_bookingevent" ("booking_id");

-- index: rides_bookingevent_created_by_id_8dbbfa13
CREATE INDEX "rides_bookingevent_created_by_id_8dbbfa13" ON "rides_bookingevent" ("created_by_id");

-- index: rides_notification_booking_id_26d3c988
CREATE INDEX "rides_notification_booking_id_26d3c988" ON "rides_notification" ("booking_id");

-- index: rides_notification_user_id_6fcde4fb
CREATE INDEX "rides_notification_user_id_6fcde4fb" ON "rides_notification" ("user_id");

-- index: rides_triprating_author_id_49d92727
CREATE INDEX "rides_triprating_author_id_49d92727" ON "rides_triprating" ("author_id");

-- index: rides_triprating_booking_id_42dceb61
CREATE INDEX "rides_triprating_booking_id_42dceb61" ON "rides_triprating" ("booking_id");

-- index: rides_vehicle_owner_id_a272699d
CREATE INDEX "rides_vehicle_owner_id_a272699d" ON "rides_vehicle" ("owner_id");

-- index: training_driver_status_idx
CREATE INDEX "training_driver_status_idx" ON "accounts_drivertraining" ("driver_id", "status");

-- index: unique_confirmed_upi_bank_ref
CREATE UNIQUE INDEX "unique_confirmed_upi_bank_ref" ON "payments_directupipayment" ("bank_reference") WHERE ("status" = 'CONFIRMED' AND NOT ("bank_reference" = ''));

-- index: user_phone_idx
CREATE INDEX "user_phone_idx" ON "accounts_user" ("phone");

-- index: user_role_idx
CREATE INDEX "user_role_idx" ON "accounts_user" ("role");

-- index: vehicle_one_default
CREATE UNIQUE INDEX "vehicle_one_default" ON "rides_vehicle" ("owner_id") WHERE "is_default";

-- view: rides_completed_analytics
CREATE VIEW rides_completed_analytics AS
        SELECT id AS booking_id, customer_id, driver_id, service, completed_at,
               final_fare, platform_fee_percent,
               ROUND(final_fare * platform_fee_percent / 100.0, 2) AS calculated_platform_fee,
               ROUND(final_fare - ROUND(final_fare * platform_fee_percent / 100.0, 2), 2) AS calculated_driver_share
        FROM rides_booking WHERE status = 'COMPLETED' AND final_fare IS NOT NULL;

-- trigger: rides_rate_audit_update
CREATE TRIGGER rides_rate_audit_update AFTER UPDATE OF base, per_hour ON rides_servicerate
            WHEN OLD.base <> NEW.base OR OLD.per_hour <> NEW.per_hour BEGIN
              INSERT INTO rides_rate_change_audit(rate_id, old_base, new_base, old_per_hour, new_per_hour)
              VALUES(OLD.id, OLD.base, NEW.base, OLD.per_hour, NEW.per_hour);
            END;

