import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/auth_service.dart';
import '../services/navigation.dart';
import '../theme/dm_theme.dart';
import '../widgets/dm_buttons.dart';
import '../widgets/dm_feedback.dart';
import '../widgets/dm_fields.dart';
import '../widgets/dm_screen.dart';
import '../widgets/policy_sheet.dart';
import '../widgets/step_progress.dart';
import 'driver_application_status_screen.dart';
import 'driver_driving_details_screen.dart';

/// DRIVER REGISTRATION - STEP 4 of 5: documents, consent and training.
///
/// Required documents depend on the backend policy (`DRIVER_REQUIRED_DOCUMENTS`):
/// licence front, licence back and identity proof. Address proof is optional.
/// Nothing is public: files are uploaded to private storage and only
/// verification staff can open them.
class DriverDocumentsScreen extends StatefulWidget {
  final String name;
  const DriverDocumentsScreen({super.key, required this.name});

  @override
  State<DriverDocumentsScreen> createState() => _DriverDocumentsScreenState();
}

class _DocumentSpec {
  final String type;
  final String label;
  final String hint;
  final bool required;
  final IconData icon;

  const _DocumentSpec({
    required this.type,
    required this.label,
    required this.hint,
    required this.required,
    this.icon = Icons.description_outlined,
  });
}

final List<_DocumentSpec> _documents = [
  const _DocumentSpec(
    type: 'LICENCE_FRONT',
    label: 'Driving licence - front',
    hint: 'Photograph the front of your licence clearly.',
    required: true,
    icon: Icons.badge_outlined,
  ),
  const _DocumentSpec(
    type: 'LICENCE_BACK',
    label: 'Driving licence - back',
    hint: 'Include the back side with its details visible.',
    required: true,
    icon: Icons.credit_card_outlined,
  ),
  const _DocumentSpec(
    type: 'IDENTITY',
    label: 'Identity proof',
    hint: 'Government photo ID as accepted by the verification policy.',
    required: true,
    icon: Icons.fingerprint_outlined,
  ),
  const _DocumentSpec(
    type: 'ADDRESS_PROOF',
    label: 'Address proof (optional)',
    hint: 'Helps speed up verification if your address is not on the ID.',
    required: false,
    icon: Icons.home_work_outlined,
  ),
];

class _DriverDocumentsScreenState extends State<DriverDocumentsScreen> {
  final _picker = ImagePicker();

  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  String? _licenceNumber;
  String? _licenceExpiry;

  /// document_type -> uploaded document record from the server
  final Map<String, Map<String, dynamic>> _uploaded = const {};
  final Map<String, Map<String, dynamic>> _training = const {};
  final Set<String> _busyDocuments = const {};

  bool _consentBackgroundCheck = false;
  bool _consentTerms = false;
  bool _consentAccuracy = false;
  bool _savedConsents = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final profile = await AuthService.getProfile();
      final profileData =
          (profile['profile'] as Map?)?.cast<String, dynamic>() ?? {};
      _licenceNumber = (profileData['licence_number'] ?? '').toString();
      _licenceExpiry = (profileData['licence_expiry'] ?? '').toString();

      final application = await AuthService.driverApplication();
      final documents = (application['documents'] as List?) ?? [];
      final training = (application['training'] as List?) ?? [];
      final consents =
          (application['consents'] as Map?)?.cast<String, dynamic>() ?? {};

      _uploaded
        ..clear()
        ..addEntries(documents.map((doc) {
          final map = (doc as Map).cast<String, dynamic>();
          return MapEntry(map['document_type'].toString(), map);
        }));
      _training
        ..clear()
        ..addEntries(training.map((module) {
          final map = (module as Map).cast<String, dynamic>();
          return MapEntry(map['module'].toString(), map);
        }));
      _consentBackgroundCheck = consents['consent_background_check'] == true;
      _consentTerms = consents['consent_terms'] == true;
      _consentAccuracy = consents['consent_data_accuracy'] == true;
      _savedConsents =
          _consentBackgroundCheck && _consentTerms && _consentAccuracy;
    } on ApiException catch (error) {
      _loadError = error.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ------------------------------------------------------------- upload flow

  Future<void> _pickFor(_DocumentSpec spec, {required bool asFile}) async {
    try {
      if (asFile) {
        final picked = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
        );
        final path = picked?.path;
        if (path != null) await _upload(spec, path);
        return;
      }
      final file = await _picker.pickImage(
          source: ImageSource.gallery, maxWidth: 1800, imageQuality: 85);
      if (file != null) await _upload(spec, file.path);
    } catch (_) {
      if (mounted) {
        showDmMessage(context, 'Could not select that file.', error: true);
      }
    }
  }

  void _chooseSource(_DocumentSpec spec) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: red),
              title: const Text('Take a photo'),
              onTap: () async {
                Navigator.pop(context);
                final file = await _picker.pickImage(
                    source: ImageSource.camera,
                    maxWidth: 1800,
                    imageQuality: 85);
                if (file != null) await _upload(spec, file.path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: red),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickFor(spec, asFile: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined, color: red),
              title: const Text('Choose a PDF / file'),
              onTap: () {
                Navigator.pop(context);
                _pickFor(spec, asFile: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _upload(_DocumentSpec spec, String path) async {
    setState(() => _busyDocuments.add(spec.type));
    try {
      final result = await AuthService.uploadDriverDocument(
        path: path,
        documentType: spec.type,
        documentNumber: spec.type.startsWith('LICENCE') ? _licenceNumber : null,
        expiresAt: spec.type.startsWith('LICENCE') ? _licenceExpiry : null,
      );
      final document = (result['document'] as Map?)?.cast<String, dynamic>();
      if (document != null) {
        setState(() => _uploaded[spec.type] = document);
      }
      if (!mounted) return;
      showDmMessage(context, '${spec.label} uploaded privately.');
    } on ApiException catch (error) {
      if (mounted) showDmMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _busyDocuments.remove(spec.type));
    }
  }

  // ------------------------------------------------------------- other steps

  Future<void> _openTraining(String module) async {
    final data = _training[module] ?? {};
    final content =
        (data['content'] as List?)?.map((item) => item.toString()).toList() ??
            <String>[];
    final isDone = data['status'] == 'COMPLETED';

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                    color: hairline, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 18),
            Text((data['label'] ?? module).toString(),
                style: dmHeading(size: 19)),
            const SizedBox(height: 6),
            Text(
              data['is_required'] == true
                  ? 'Required module'
                  : 'Optional module',
              style: dmCaption(size: 11.5),
            ),
            const SizedBox(height: 14),
            ...content.map(
              (point) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
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
            const SizedBox(height: 8),
            DmInfoBox(
              icon: Icons.science_outlined,
              color: warning,
              text: isDone
                  ? 'You already marked this module complete.'
                  : 'Prototype note: this summary stands in for the final training material. '
                      'Marking it complete records your acknowledgement.',
            ),
            const SizedBox(height: 16),
            if (!isDone)
              DmPrimaryButton(
                label: 'Mark as completed',
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _markModuleComplete(module);
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Marks one training module complete and refreshes the checklist.
  /// Lives on the State (not inside the bottom sheet) so context usage stays safe.
  Future<void> _markModuleComplete(String module) async {
    try {
      await AuthService.completeTraining(module);
      await _load();
      if (!mounted) return;
      showDmMessage(context, 'Module marked as completed.');
    } on ApiException catch (error) {
      if (!mounted) return;
      showDmMessage(context, error.message, error: true);
    }
  }

  Future<void> _submit() async {
    final missingDocs = _documents
        .where((doc) => doc.required && !_uploaded.containsKey(doc.type))
        .toList();
    if (missingDocs.isNotEmpty) {
      showDmMessage(context,
          'Still needed: ${missingDocs.map((doc) => doc.label).join(', ')}',
          error: true);
      return;
    }
    if (!(_consentBackgroundCheck && _consentTerms && _consentAccuracy)) {
      showDmMessage(
          context, 'All three consents are required before submitting.',
          error: true);
      return;
    }
    final missingTraining = _training.values
        .where((module) =>
            module['is_required'] == true && module['status'] != 'COMPLETED')
        .map((module) => module['label'].toString())
        .toList();
    if (missingTraining.isNotEmpty) {
      showDmMessage(context,
          'Complete the required training: ${missingTraining.join(', ')}',
          error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      if (!_savedConsents) await AuthService.saveConsents();
      if (!mounted) return;
      showDmMessage(context, 'Application submitted for verification.');
      Navigator.of(context)
          .push(dmRoute(DriverApplicationStatusScreen(name: widget.name)));
    } on ApiException catch (error) {
      if (mounted) showDmMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool get _requiredTrainingDone => _training.values
      .where((module) => module['is_required'] == true)
      .every((module) => module['status'] == 'COMPLETED');

  bool get _requiredDocumentsDone => _documents
      .where((doc) => doc.required)
      .every((doc) => _uploaded.containsKey(doc.type));

  bool get _readyToSubmit =>
      _requiredDocumentsDone &&
      _requiredTrainingDone &&
      _consentBackgroundCheck &&
      _consentTerms &&
      _consentAccuracy;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return DmScreen(
      showBack: true,
      backFallback: DriverDrivingDetailsScreen(name: widget.name),
      backResult: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StepHeader(
            step: 4,
            title: 'Documents & consent',
            subtitle:
                'Upload clear photos, accept the required consents and finish the training checklist.',
          ),
          const SizedBox(height: 22),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_loadError != null)
            DmErrorState(
              title: 'Could not load your application',
              message: _loadError!,
              onRetry: _load,
              icon: Icons.cloud_off_rounded,
            )
          else ...[
            const DmSectionLabel('Required documents'),
            ..._documents.map((spec) => _DocumentTile(
                  spec: spec,
                  document: _uploaded[spec.type],
                  busy: _busyDocuments.contains(spec.type),
                  onTap: () => _chooseSource(spec),
                )),
            const SizedBox(height: 18),
            const DmSectionLabel('Consent'),
            DmAgreementRow(
              value: _consentBackgroundCheck,
              onChanged: (value) =>
                  setState(() => _consentBackgroundCheck = value),
              text: [
                const TextSpan(
                    text:
                        'I consent to identity and licence verification as described in the '),
                policySpan('background verification policy', context,
                    PolicyDoc.backgroundCheck),
                const TextSpan(text: '.'),
              ],
            ),
            DmAgreementRow(
              value: _consentTerms,
              onChanged: (value) => setState(() => _consentTerms = value),
              text: [
                const TextSpan(text: 'I accept the '),
                policySpan('Terms & Conditions', context, PolicyDoc.terms),
                const TextSpan(text: '.'),
              ],
            ),
            DmAgreementRow(
              value: _consentAccuracy,
              onChanged: (value) => setState(() => _consentAccuracy = value),
              text: const [
                TextSpan(
                  text:
                      'I confirm that all details and documents I submitted are true. I understand that '
                      'false documents lead to rejection or suspension.',
                ),
              ],
            ),
            const SizedBox(height: 18),
            const DmSectionLabel('Training checklist'),
            ..._training.values.map((module) => _TrainingTile(
                  module: module,
                  onTap: () => _openTraining(module['module'].toString()),
                )),
            const SizedBox(height: 20),
            _SummaryCard(
              documentsReady: _requiredDocumentsDone,
              consentsReady:
                  _consentBackgroundCheck && _consentTerms && _consentAccuracy,
              trainingReady: _requiredTrainingDone,
            ),
            const SizedBox(height: 18),
            DmPrimaryButton(
              label: _readyToSubmit
                  ? 'Submit for verification'
                  : 'Complete all items to submit',
              loading: _saving,
              onPressed: _readyToSubmit ? _submit : null,
              showArrow: _readyToSubmit,
            ),
            const SizedBox(height: 12),
            const DmInfoBox(
              icon: Icons.lock_outline_rounded,
              text:
                  'Documents are stored privately. Only authorised verification staff can open them, and no '
                  'public links are created.',
            ),
          ],
        ],
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  final _DocumentSpec spec;
  final Map<String, dynamic>? document;
  final bool busy;
  final VoidCallback onTap;

  const _DocumentTile(
      {required this.spec,
      required this.document,
      required this.busy,
      required this.onTap});

  ({Color color, IconData icon, String label}) get _state {
    if (document == null) {
      return (
        color: spec.required ? warning : muted,
        icon: Icons.upload_file_rounded,
        label: spec.required ? 'Required' : 'Optional'
      );
    }
    switch (document!['review_status']) {
      case 'APPROVED':
        return (
          color: success,
          icon: Icons.verified_rounded,
          label: 'Approved'
        );
      case 'REJECTED':
        return (
          color: danger,
          icon: Icons.error_outline_rounded,
          label: 'Rejected'
        );
      default:
        return (
          color: info,
          icon: Icons.check_circle_outline_rounded,
          label: 'Uploaded'
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    final state = _state;
    final rejection = document?['rejection_reason']?.toString() ?? '';

    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(radiusCard),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(radiusCard),
          border: Border.all(color: state.color.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: state.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(spec.icon, color: state.color, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(spec.label,
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w700)),
                      ),
                      StatusPill(
                        label: busy ? 'Uploading' : state.label,
                        color: state.color,
                        icon: state.icon,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    document == null ? spec.hint : 'Tap to replace this file.',
                    style: dmCaption(size: 11.3),
                  ),
                  if (rejection.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text('Reason: $rejection',
                          style:
                              const TextStyle(color: danger, fontSize: 11.2)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrainingTile extends StatelessWidget {
  final Map<String, dynamic> module;
  final VoidCallback onTap;

  const _TrainingTile({required this.module, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    final done = module['status'] == 'COMPLETED';
    final required = module['is_required'] == true;
    final color = done ? success : (required ? warning : muted);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radiusCard),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(radiusCard),
          border: Border.all(color: hairline),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                  done ? Icons.school_rounded : Icons.menu_book_outlined,
                  color: color,
                  size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(module['label'].toString(),
                      style: const TextStyle(
                          fontSize: 13.2, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(required ? 'Required' : 'Optional',
                      style: dmCaption(size: 11)),
                ],
              ),
            ),
            Icon(
                done ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                color: color,
                size: 22),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final bool documentsReady;
  final bool consentsReady;
  final bool trainingReady;

  const _SummaryCard({
    required this.documentsReady,
    required this.consentsReady,
    required this.trainingReady,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    Widget row(String label, bool done) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(
                done
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 17,
                color: done ? success : muted,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.4,
                    color: done ? softWhite : muted,
                    fontWeight: done ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: panel3,
        borderRadius: BorderRadius.circular(radiusCard),
        border: Border.all(color: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DmSectionLabel('Before you submit'),
          row('Required documents uploaded', documentsReady),
          row('All consents accepted', consentsReady),
          row('Required training completed', trainingReady),
        ],
      ),
    );
  }
}
