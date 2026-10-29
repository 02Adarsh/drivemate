from .models import DirectUPIPayment


def payment_state(booking):
    record=DirectUPIPayment.objects.filter(booking_id=booking.pk).first()
    if booking.status=='COMPLETED' and booking.final_fare is not None and booking.final_fare==0:
        return {'payment_method':'NONE','payment_status':'NOT_REQUIRED','payment_received':True,'payment_label':'No payment due','payment_verification':'not_required','upi_payment':None}
    if booking.cash_received_at:
        return {'payment_method':'CASH','payment_status':'RECEIVED','payment_received':True,'payment_label':'Cash received (driver-confirmed)','payment_verification':'manual_driver','upi_payment':None}
    summary=None
    if record:
        summary={'id':str(record.pk),'status':record.status,'amount':str(record.amount),'currency':record.currency,
                 'receiver_upi_id':record.receiver_upi_id,'receiver_name':record.receiver_name,
                 'customer_reference':record.customer_reference,'bank_reference':record.bank_reference,
                 'confirmed_at':record.confirmed_at,'review_note':record.review_note}
    confirmed=bool(record and record.status=='CONFIRMED')
    return {'payment_method':'UPI_DIRECT' if record and record.status!='CANCELLED' else 'CASH',
            'payment_status':'DRIVER_CONFIRMED' if confirmed else 'AWAITING_DRIVER_CONFIRMATION' if record and record.status=='REPORTED' else 'DUE',
            'payment_received':confirmed,
            'payment_label':'UPI received (manually confirmed by driver)' if confirmed else 'UPI reported - waiting for driver bank check' if record and record.status=='REPORTED' else 'Payment not confirmed',
            'payment_verification':'manual_driver' if confirmed else 'none','upi_payment':summary}
