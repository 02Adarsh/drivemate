import 'package:flutter/material.dart';

import '../config.dart';
import '../services/auth_service.dart';
import '../services/navigation.dart';
import '../services/server_connection.dart';
import '../theme/dm_surfaces.dart';
import '../theme/dm_theme.dart';
import '../widgets/dm_buttons.dart';
import '../widgets/dm_dashboard.dart';
import '../widgets/dm_feedback.dart';
import '../widgets/dm_fields.dart';
import '../widgets/dm_screen.dart';
import '../widgets/dm_ui.dart';
import 'login_screen.dart';

/// Connection diagnostics are reachable BEFORE sign-in and from Account.
/// Never claims to detect Windows USB drivers from inside an Android app.
class ServerConnectionScreen extends StatefulWidget {
  final String loginRole;
  const ServerConnectionScreen({super.key, this.loginRole = 'CUSTOMER'});

  @override
  State<ServerConnectionScreen> createState() => _ServerConnectionScreenState();
}

class _ServerConnectionScreenState extends State<ServerConnectionScreen> {
  final _form = GlobalKey<FormState>();
  final _url = TextEditingController();
  ServerCheck? _check;
  bool _busy = false;
  bool _loading = true;
  String? _custom;
  String _active = apiBaseUrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await AuthService.initializeBackend();
    if (!mounted) return;
    setState(() {
      _custom = AuthService.customBaseUrl;
      _active = AuthService.activeBaseUrl;
      _url.text = _custom ?? _active;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _choose(String value) {
    setState(() {
      _url.text = value;
      _check = null;
      _error = null;
    });
  }

  Future<void> _test() async {
    if (!_form.currentState!.validate() || _busy) return;
    FocusScope.of(context).unfocus();
    final target = _url.text.trim();
    setState(() {
      _busy = true;
      _check = null;
      _error = null;
    });
    try {
      final result = await AuthService.checkServer(target);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _check = _url.text.trim() == target ? result : null;
      });
    } on FormatException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.message;
        });
      }
    }
  }

  Future<void> _apply({bool reset = false}) async {
    final normalized = reset ? null : ServerConnection.normalize(_url.text);
    if (_busy ||
        (!reset && (_check?.ok != true || _check!.baseUrl != normalized))) {
      return;
    }
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              backgroundColor: panel,
              title: const Text('Use this trusted server?'),
              content: Text(
                  '${normalized ?? 'Built-in USB / emulator discovery'}\n\n'
                  'Sign-in credentials will be sent to the server you select. Choose only a server you trust. '
                  'Switching signs out this phone; it does not delete data on the old backend. '
                  'HTTP is development-only. Use HTTPS for a real deployment.',
                  style: dmSubtitle(size: 12.5)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Use server')),
              ],
            ));
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final hadSession = await AuthService.hasSession();
    final changed = await AuthService.setBackendUrl(normalized);
    if (!mounted) return;
    setState(() => _busy = false);
    if (changed && hadSession) {
      pushClean(context, LoginScreen(role: widget.loginRole));
      return;
    }
    await _load();
    if (mounted) {
      showDmMessage(
          context,
          changed
              ? 'Server saved. Go back and sign in.'
              : 'This server is already selected.');
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return DmScreen(
        showBack: true,
        backFallback: LoginScreen(role: widget.loginRole),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CONNECTION', style: dmSectionLabel()),
            const SizedBox(height: 8),
            Text('Server connection', style: dmHeading(size: 25)),
            const SizedBox(height: 7),
            Text(
                'Test the backend from this phone. USB detection on your PC is a separate check.',
                style: dmSubtitle(size: 13)),
            const SizedBox(height: 18),
            Container(
                padding: const EdgeInsets.all(15),
                decoration: dmSurface(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DmTag(
                        label: _custom == null
                            ? 'BUILT-IN DISCOVERY'
                            : 'CUSTOM SERVER PINNED',
                        color: info),
                    const SizedBox(height: 10),
                    Text(_active,
                        style: const TextStyle(
                            fontSize: 12.6, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    Text(
                        'Signed-in sessions stay pinned to their server; a failed call does not send your token to another host.',
                        style: dmCaption(size: 11.2)),
                  ],
                )),
            const SizedBox(height: 20),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DmField(
                          controller: _url,
                          hint: 'http://PC-WIFI-IP:8000/api',
                          icon: Icons.dns_outlined,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.done,
                          onChanged: (_) => setState(() {
                                _check = null;
                                _error = null;
                              }),
                          validator: (value) {
                            try {
                              ServerConnection.normalize(value ?? '');
                              return null;
                            } on FormatException catch (error) {
                              return error.message;
                            }
                          }),
                      const SizedBox(height: 12),
                      DmPrimaryButton(
                          label: 'Test connection',
                          loading: _busy,
                          onPressed: _test,
                          icon: Icons.network_check_rounded),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        DmInfoBox(text: _error!, color: danger)
                      ],
                      if (_check != null) ...[
                        const SizedBox(height: 14),
                        DmListCard(
                            icon: _check!.ok
                                ? Icons.check_circle_outline_rounded
                                : Icons.wifi_off_rounded,
                            title: _check!.ok
                                ? 'DriveMate API reached'
                                : 'Connection not ready',
                            body:
                                '${_check!.message}\n${_check!.baseUrl} · ${_check!.elapsedMs} ms'
                                '${_check!.statusCode == null ? '' : ' · HTTP ${_check!.statusCode}'}',
                            accent: _check!.ok ? success : warning),
                      ],
                      const SizedBox(height: 12),
                      DmPrimaryButton(
                          label: 'Use this server',
                          onPressed: !_busy && _check?.ok == true
                              ? () => _apply()
                              : null,
                          icon: Icons.save_outlined),
                      if (_custom != null) ...[
                        const SizedBox(height: 8),
                        TextButton(
                            onPressed: _busy ? null : () => _apply(reset: true),
                            child: const Text('Reset to built-in discovery')),
                      ],
                    ],
                  )),
            const SizedBox(height: 22),
            const DmSectionHeader(title: 'Choose your setup'),
            DmOptionRow(
                label: 'USB cable',
                caption:
                    '127.0.0.1 is the phone. It only reaches your PC after a working adb reverse tunnel.',
                icon: Icons.usb_rounded,
                onTap:
                    _busy ? null : () => _choose('http://127.0.0.1:8000/api')),
            DmOptionRow(
                label: 'Android emulator',
                caption:
                    '10.0.2.2 is for the Android emulator, not a normal physical phone.',
                icon: Icons.phone_android_rounded,
                onTap:
                    _busy ? null : () => _choose('http://10.0.2.2:8000/api')),
            const DmInfoBox(
                icon: Icons.wifi_rounded,
                text:
                    'LAN / manually installed APK: enter your PC’s physical Wi-Fi/Ethernet IPv4. '
                    'Both devices must be on the same network. Do not pick a VirtualBox, VPN, WSL or host-only adapter IP.'),
            const SizedBox(height: 12),
            const DmInfoBox(
                icon: Icons.usb_off_rounded,
                color: warning,
                text:
                    'If adb devices is blank on Windows: unlock the phone, enable USB debugging, try a known data cable/direct USB port '
                    'and check Device Manager/OEM drivers. This app cannot fix a missing USB device or install a Windows driver.'),
          ],
        ));
  }
}
