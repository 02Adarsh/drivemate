"""Read only UPI pay QRs; generate a NEW fare QR from whitelisted fields.

Uploaded amount/transaction/signature/callback fields are never reused. A
personal UPI URI can prefill a fare; it cannot force another app's UI or bank.
"""
import hashlib
import io
import re
from decimal import Decimal
from urllib.parse import parse_qs, urlencode, urlsplit, quote

from PIL import Image, ImageOps, UnidentifiedImageError
import numpy as np
import qrcode
import zxingcpp
from rest_framework.exceptions import ValidationError

VPA=re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]{1,255}@[A-Za-z][A-Za-z0-9]{1,63}$')


def normalize_upi(value):
    text=str(value or '').strip().lower()
    if len(text)>256 or not VPA.fullmatch(text):
        raise ValidationError({'upi_id':'Enter a valid receiving UPI ID, such as your-name@your-bank-handle.'})
    return text


def parse_upi(text):
    if len(text)>4096:return None
    try:
        uri=urlsplit(text.strip())
        if uri.scheme.lower()!='upi' or uri.netloc.lower()!='pay' or uri.path not in ('','/') or uri.fragment:return None
        fields=parse_qs(uri.query,keep_blank_values=True)
        if len(fields.get('pa',[]))!=1:return None
        vpa=normalize_upi(fields['pa'][0])
        if fields.get('cu') and fields['cu']!=['INR']:return None
        name=fields.get('pn',[''])[0].strip()[:120]
        return {'upi_id':vpa,'name_hint':name}
    except (ValueError,ValidationError):return None


def read_uploaded_qr(upload):
    if not upload or upload.size>5*1024*1024:raise ValidationError({'qr':'Upload a clear JPG/PNG/WebP QR image up to 5 MB.'})
    try:
        raw=upload.read();upload.seek(0)
        image=Image.open(io.BytesIO(raw))
        if image.format not in ['JPEG','PNG','WEBP'] or image.width*image.height>12000000:
            raise ValidationError({'qr':'Use JPG/PNG/WebP, maximum 12 megapixels.'})
        image=ImageOps.exif_transpose(image).convert('RGB')
        found=zxingcpp.read_barcodes(np.asarray(image))
        values=[value for barcode in found if (value:=parse_upi(barcode.text)) is not None]
        receivers={value['upi_id'] for value in values}
        if len(receivers)!=1:
            raise ValidationError({'qr':'A single clear UPI receiving QR is required. Crop out other QRs; web/payment-link QRs are not supported.'})
        decoded=values[0]
        image.thumbnail((1800,1800))
        cleaned=io.BytesIO();image.save(cleaned,format='PNG',optimize=True)
        content=cleaned.getvalue()
        return decoded,content,hashlib.sha256(content).hexdigest()
    except ValidationError:raise
    except (UnidentifiedImageError,OSError,ValueError,Image.DecompressionBombError):
        raise ValidationError({'qr':'This image could not be read. Upload a clear screenshot of your UPI receiving QR.'})
    except Exception:
        raise ValidationError({'qr':'QR decoding failed. Use a clear, cropped receiving UPI QR image.'})


def make_payload(upi_id,name,amount,reference,booking_id):
    number=Decimal(str(amount)).quantize(Decimal('0.01'))
    if number<=0:raise ValidationError({'detail':'There is no positive payment due.'})
    values={'pa':normalize_upi(upi_id),'pn':str(name).strip()[:120],'am':format(number,'.2f'),'cu':'INR',
            'tr':reference,'tn':f'DriveMate trip {booking_id}'}
    return 'upi://pay?'+urlencode(values,quote_via=quote)


def png(payload):
    qr=qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M,box_size=8,border=4)
    qr.add_data(payload);qr.make(fit=True)
    output=io.BytesIO();qr.make_image(fill_color='black',back_color='white').save(output,format='PNG')
    return output.getvalue()
