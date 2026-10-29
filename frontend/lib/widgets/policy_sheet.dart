import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/dm_theme.dart';

/// Draft policy text: obtain legal review and complete the retention process
/// before publishing. Keep this consistent with actual app behaviour.
class PolicyDoc {
  final String title;
  final List<String> points;
  const PolicyDoc(this.title, this.points);

  static const terms = PolicyDoc('Terms & Conditions', [
    'DriveMate connects customers who have their own vehicle with drivers. The vehicle is supplied by the customer; DriveMate does not provide a taxi or rental vehicle.',
    'You must provide accurate account and booking details, keep your login codes and password private, and use the service lawfully. You are responsible for activity on your account.',
    'Customers must ensure their vehicle is roadworthy and has the required registration, insurance and permissions. Drivers must hold a valid licence, follow traffic rules and drive safely.',
    'The app shows an estimated fare before booking. The fare depends on the selected service and duration; applicable offers and the final fare are shown in the app. Tolls, parking and other extras are not included in the estimate.',
    'A booking may be cancelled in the app while it is requested or accepted. For cancellation, payment disputes or refund requests, contact Help & Support. Requests are reviewed case by case; refunds are not automatic and depend on the circumstances and applicable law.',
    'For direct UPI, payment is sent to the driver using an external UPI app and the driver manually confirms receipt. Cash is recorded manually. DriveMate does not automatically verify UPI payments, collect the platform fee or transfer the calculated driver share.',
    'Check the recipient and payment status before paying. A payment report or QR scan is not proof of receipt. If a debit is pending or a payment is disputed, contact Help & Support rather than paying again immediately.',
    'DriveMate may review applications and restrict or suspend accounts for safety, inaccurate information, misuse or violation of these terms, subject to applicable law. The safety screen opens the phone dialer and does not automatically dispatch emergency services.',
    'For questions or complaints, signed-in users can use Account → Help & Support. These terms are subject to applicable law and do not remove rights that cannot legally be excluded.',
  ]);

  static const privacy = PolicyDoc('Privacy Policy', [
    'DriveMate collects information you provide to create and use an account, including your name, email, phone number, profile details, vehicle information, bookings, support requests and communications.',
    'Driver applications may include a profile photo, date of birth, address, driving licence details, identity documents, emergency contacts and training acknowledgements. Drivers who use direct UPI may also provide a UPI ID and QR image.',
    'The app may collect pickup and destination information, map searches and location data you choose to share for a trip. Location permissions can be managed in your device settings; some features may not work without them.',
    'We use this information to manage accounts, review driver applications, arrange trips, show fares and payment records, send account codes and notifications, respond to support requests, improve safety and meet applicable legal obligations.',
    'Relevant trip details may be shared with the assigned customer or driver. Authorised staff may access information for verification, support and administration. Email, hosting, storage and map providers may process information needed to provide their services; map searches may be sent to OpenStreetMap / Nominatim.',
    'Direct UPI payments are handled through your chosen UPI application and bank. Their privacy policies also apply. DriveMate does not collect your UPI PIN.',
    'DriveMate intends to retain account, trip and driver-document records for up to one year from the creation of each record, unless a longer period is required for a legal obligation, dispute, investigation or security need. Automatic deletion is not yet available and records may currently remain longer; use Help & Support to request a review or deletion.',
    'You can export some account data or deactivate your account in Privacy & security. Deactivation stops login but does not automatically erase records. To request access, correction or deletion, contact Help & Support while signed in; requests are reviewed subject to applicable law and necessary retention.',
    'We use access controls and other safeguards, but no system can guarantee absolute security. Do not share your password, account OTP or UPI PIN. We may update this policy as our practices change.',
  ]);

  static const backgroundCheck = PolicyDoc('Background verification consent', [
    'By giving consent, you allow DriveMate staff to review the identity and driving licence details and documents you submit for your driver application.',
    'The information is used to assess your application and may be retained and handled as described in the Privacy Policy. A document review does not guarantee a government, criminal-record or third-party background check.',
    'You must provide accurate, current documents. You can ask questions or request a review through Account → Help & Support. Withdrawing consent may affect our ability to process your application.',
  ]);
}

Future<void> showPolicySheet(BuildContext context, PolicyDoc doc) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: panel,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      maxChildSize: 0.9,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 30),
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                  color: hairline, borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(height: 20),
          Text(doc.title, style: dmHeading(size: 20)),
          const SizedBox(height: 14),
          ...doc.points.map(
            (point) => Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 10),
                    child: Icon(Icons.circle, size: 6, color: red),
                  ),
                  Expanded(child: Text(point, style: dmSubtitle(size: 13))),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A red, tappable text span that opens a policy sheet.
/// Using this keeps the `gestures` import out of every screen.
InlineSpan policySpan(String text, BuildContext context, PolicyDoc doc) {
  final recognizer = TapGestureRecognizer()
    ..onTap = () => showPolicySheet(context, doc);
  return TextSpan(
    text: text,
    style: const TextStyle(color: red, fontWeight: FontWeight.w600),
    recognizer: recognizer,
  );
}
