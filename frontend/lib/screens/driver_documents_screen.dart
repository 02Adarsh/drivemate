import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class DriverDocumentsScreen extends StatefulWidget {
  final String name;
  const DriverDocumentsScreen({super.key, required this.name});
  @override State<DriverDocumentsScreen> createState() => _DriverDocumentsScreenState();
}

class _DriverDocumentsScreenState extends State<DriverDocumentsScreen> {
  String? licencePath, identityPath, licenceName, identityName;
  bool saving = false;

  Future<void> pick(bool license) async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf']);
    if (file == null || file.path == null) return;
    setState(() {
      if (license) { licencePath = file.path; licenceName = file.name; }
      else { identityPath = file.path; identityName = file.name; }
    });
  }

  Future<void> submit() async {
    if (licencePath == null || identityPath == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Both licence and identity proof are required.'))); return; }
    setState(() => saving = true);
    try {
      await AuthService.uploadPrivateFile('profile/documents/', licencePath!, fields: {'document_type': 'LICENSE'});
      await AuthService.uploadPrivateFile('profile/documents/', identityPath!, fields: {'document_type': 'IDENTITY'});
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context, PageRouteBuilder(pageBuilder: (_, a, b) => HomeScreen(role: 'Driver', name: widget.name), transitionsBuilder: (_, a, b, child) => FadeTransition(opacity: a, child: child), transitionDuration: const Duration(milliseconds: 350)), (_) => false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Application submitted. It is pending admin document review.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: red));
    } finally { if (mounted) setState(() => saving = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Verification documents', style: TextStyle(fontWeight: FontWeight.w700))),
    body: ListView(padding: const EdgeInsets.all(22), children: [
      Container(width: 54, height: 54, decoration: BoxDecoration(color: red.withOpacity(.13), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.shield_outlined, color: red)),
      const SizedBox(height: 19),
      const Text('Upload your documents', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
      const SizedBox(height: 7),
      const Text('Files are stored privately. Only authorized verification staff can review them.', style: TextStyle(color: muted, fontSize: 12, height: 1.5)),
      const SizedBox(height: 22),
      _DocumentCard(title: 'Driving licence', subtitle: 'Photo or PDF • max 5 MB', filename: licenceName, onTap: () => pick(true)),
      const SizedBox(height: 12),
      _DocumentCard(title: 'Identity proof', subtitle: 'Photo or PDF • max 5 MB', filename: identityName, onTap: () => pick(false)),
      const SizedBox(height: 21),
      Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(14)), child: const Text('Your driver status stays PENDING REVIEW. You cannot go online until an administrator approves your application.', style: TextStyle(color: muted, fontSize: 12, height: 1.45))),
      const SizedBox(height: 24),
      SizedBox(height: 53, child: FilledButton(onPressed: saving ? null : submit, style: FilledButton.styleFrom(backgroundColor: red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: saving ? const CircularProgressIndicator(color: Colors.white) : const Text('Submit for verification', style: TextStyle(fontWeight: FontWeight.w700)))),
    ]),
  );
}

class _DocumentCard extends StatelessWidget {
  final String title, subtitle;
  final String? filename;
  final VoidCallback onTap;
  const _DocumentCard({required this.title, required this.subtitle, required this.filename, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(17),
    child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(17), border: Border.all(color: Colors.white12)), child: Row(children: [
      Container(width: 44, height: 44, decoration: BoxDecoration(color: red.withOpacity(.12), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.description_outlined, color: red)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 3), Text(filename ?? subtitle, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted, fontSize: 11))])),
      Icon(filename == null ? Icons.upload_file_rounded : Icons.check_circle, color: filename == null ? muted : red),
    ])),
  );
}
