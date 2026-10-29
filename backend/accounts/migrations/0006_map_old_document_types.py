"""Data migration: the old single 'LICENSE' document becomes 'LICENCE_FRONT'.

Phase 1 stored one licence document with document_type="LICENSE". From the
driver registration flow onwards we store licence front and back separately
(plus identity proof and an optional address proof), so old rows are mapped
forward instead of being lost.
"""

from django.db import migrations


def forwards(apps, schema_editor):
    DriverDocument = apps.get_model('accounts', 'DriverDocument')
    for document in DriverDocument.objects.filter(document_type='LICENSE'):
        already_has_front = DriverDocument.objects.filter(
            driver_id=document.driver_id, document_type='LICENCE_FRONT'
        ).exists()
        if already_has_front:
            # A newer front image exists: keep it and drop the old duplicate row.
            document.delete()
        else:
            document.document_type = 'LICENCE_FRONT'
            document.save(update_fields=['document_type'])


def backwards(apps, schema_editor):
    DriverDocument = apps.get_model('accounts', 'DriverDocument')
    DriverDocument.objects.filter(document_type='LICENCE_FRONT').update(document_type='LICENSE')


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0005_driveremergencycontact_drivertraining_and_more'),
    ]

    operations = [
        migrations.RunPython(forwards, backwards),
    ]
