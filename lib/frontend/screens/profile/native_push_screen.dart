import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/push/native_ios_push.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/custom_notification.dart';
import 'web_push_screen.dart';

class NativePushScreen extends StatefulWidget {
  const NativePushScreen({super.key});
  @override
  State<NativePushScreen> createState() => _NativePushScreenState();
}

class _NativePushScreenState extends State<NativePushScreen> {
  final _url = TextEditingController();
  final _secret = TextEditingController();
  bool _busy = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final (url, secret) = await NativeIosPush.config();
    if (!mounted) return;
    _url.text = url;
    _secret.text = secret;
    setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _url.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showCustomNotification(context, success);
    } on PlatformException catch (e) {
      if (mounted) {
        showCustomNotification(
          context,
          '${e.message ?? e.code}\n${AppLocalizations.of(context)!.proMaxPushSigningHint}',
        );
      }
    } catch (e) {
      if (mounted) showCustomNotification(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.proMaxNativePush)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            l10n.proMaxNativePushExplanation,
            style: const TextStyle(fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            icon: const Icon(Icons.notifications_active_outlined),
            label: Text(l10n.proMaxTestNotification),
            onPressed: _busy
                ? null
                : () => _run(
                    NativeIosPush.testLocal,
                    l10n.proMaxTestNotificationScheduled,
                  ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WebPushScreen()),
                  ),
            child: Text(l10n.proMaxPushWebLogin),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _url,
            enabled: _loaded && !_busy,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l10n.proMaxPushRelayUrl,
              hintText: 'https://push.example.com',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _secret,
            enabled: _loaded && !_busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(labelText: l10n.proMaxPushRelayKey),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy || !_loaded
                ? null
                : () => _run(
                    () => NativeIosPush.connect(_url.text, _secret.text),
                    l10n.proMaxPushRegistered,
                  ),
            child: _busy
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.proMaxPushConnect),
          ),
        ],
      ),
    );
  }
}
