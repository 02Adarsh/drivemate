import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/dm_theme.dart';
import 'dm_buttons.dart';

/// Placeholder legal text.
///
/// IMPORTANT: these are structured placeholders, not legal advice. Every policy
/// must be written and reviewed by a qualified professional for the country and
/// state the service operates in before the app is published.
class PolicyDoc {
  final String title;
  final List<String> points;
  const PolicyDoc(this.title, this.points);

  static const terms = PolicyDoc('Terms & Conditions', [
    'DriveMate connects customers who own a vehicle with verified professional drivers.',
    'The vehicle always belongs to the customer. DriveMate does not provide vehicles.',
    'The customer is responsible for maintaining valid vehicle registration, insurance and roadworthiness.',
    'The driver is responsible for driving safely and following traffic law.',
    'Cancellation, waiting, extension and overtime rules apply as shown on the booking screen.',
    '[Placeholder] Final terms of service must be reviewed for your launch jurisdiction.',
  ]);

  static const privacy = PolicyDoc('Privacy Policy', [
    'We collect contact details, location, documents and trip records needed to run the service.',
    'Driver documents are stored privately and are visible only to authorised verification staff.',
    'Location is shared only with the assigned customer, the assigned driver and authorised admins.',
    'Phone numbers are shared only when a party chooses to use the call button.',
    '[Placeholder] A data-retention and privacy policy must be reviewed for your launch jurisdiction.',
  ]);

  static const backgroundCheck = PolicyDoc('Background verification consent', [
    'You agree that we may verify the identity and driving documents you upload.',
    'You agree that document data may be checked with the issuing authority where legally permitted.',
    'You understand that providing false documents leads to rejection or suspension.',
    '[Placeholder] The exact verification scope must follow local law and your operating policy.',
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
          const SizedBox(height: 6),
          const DmInfoBox(
            icon: Icons.gavel_outlined,
            text:
                'These documents are placeholders for development. Have them reviewed by a legal professional for your jurisdiction before publishing.',
            color: warning,
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
