import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../backend/api.dart';
import '../../../backend/modules/contacts.dart';
import '../../../backend/modules/messages.dart' show ContactCache;
import '../../../core/config/app_shape.dart';
import '../../../core/config/countries.dart';
import '../../../core/protocol/opcode_map.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/storage/token_storage.dart';
import '../../../core/utils/user_facing_error.dart';
import '../../../l10n/app_localizations.dart';
import '../../../main.dart';
import '../../../models/contact_info.dart';
import '../../widgets/hint_bubble.dart';
import '../../widgets/sheet_helpers.dart';
import '../../widgets/small_spinner.dart';
import '../auth/select_country_screen.dart';
import 'phone_lookup_input.dart';

typedef FoundUser = ({int userId, int chatId, String name, String avatarUrl});

enum _FindMode { phone, id }

Future<FoundUser?> showFindUserSheet(
  BuildContext context, {
  required String title,
  required String actionLabel,
}) {
  return showModalBottomSheet<FoundUser>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 520),
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
    shape: kSheetShape,
    builder: (_) =>
        FindUserSheet(client: api, title: title, actionLabel: actionLabel),
  );
}

class FindUserSheet extends StatefulWidget {
  final Api client;
  final String title;
  final String actionLabel;

  const FindUserSheet({
    super.key,
    required this.client,
    required this.title,
    required this.actionLabel,
  });

  @override
  State<FindUserSheet> createState() => _FindUserSheetState();
}

class _FindUserSheetState extends State<FindUserSheet> {
  final _phoneController = TextEditingController();
  final _idController = TextEditingController();
  final _focus = FocusNode();
  final _inputKey = GlobalKey();
  late CountryName _country;
  _FindMode _mode = _FindMode.phone;
  bool _loading = false;
  bool _pickingCountry = false;
  String? _error;

  bool get _isCurrent => mounted && ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    final countries = widget.client.registrationCountries;
    _country = countries.firstWhere(
      (country) => country.code == 'RU',
      orElse: () => countries.isEmpty ? allCountries.first : countries.first,
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _idController.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setMode(_FindMode mode) {
    if (_mode == mode || _loading || _pickingCountry) return;
    setState(() {
      _mode = mode;
      _error = null;
    });
    _focus.requestFocus();
  }

  Future<void> _pickCountry() async {
    if (_loading || _pickingCountry) return;
    setState(() => _pickingCountry = true);
    _focus.unfocus();
    final picked = await Navigator.of(context).push<CountryName>(
      MaterialPageRoute(
        builder: (_) => SelectCountryScreen(selectedCountry: _country),
      ),
    );
    if (!mounted) return;
    setState(() {
      _pickingCountry = false;
      if (picked != null && picked.code != _country.code) {
        _country = picked;
        _phoneController.clear();
        _error = null;
      }
    });
    if (_isCurrent) _focus.requestFocus();
  }

  void _showError(String message) {
    if (!_isCurrent) return;
    setState(() => _error = message);
    _focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isCurrent) {
        showHintBubble(_inputKey.currentContext ?? context, message);
      }
    });
  }

  Future<void> _submit() async {
    if (_loading || _pickingCountry || !_isCurrent) return;
    final l10n = AppLocalizations.of(context)!;
    final mode = _mode;
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    final phone = '${_country.phoneCode}$digits';
    final id = int.tryParse(_idController.text.trim());
    if (mode == _FindMode.phone &&
        (_phoneController.text.startsWith('+') ||
            digits.length != _country.phoneDigits ||
            phone.length > 16)) {
      _showError(l10n.findUserInvalidPhone);
      return;
    }
    if (mode == _FindMode.id && (id == null || id <= 0)) {
      _showError(l10n.findUserInvalidId);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final sessionEpoch = widget.client.sessionEpoch;
    int? accountId;
    try {
      accountId = await TokenStorage.getActiveAccountId();
      if (!await _acceptsResult(accountId, sessionEpoch)) return;
      if (mode == _FindMode.phone) {
        final result = await ContactsModule.findByPhone(
          widget.client,
          phone,
          silent: true,
          cacheResult: false,
        );
        if (!await _acceptsResult(accountId, sessionEpoch)) return;
        if (result == null) {
          _showError(l10n.findUserPhoneNotFound);
          return;
        }
        final name = result.name;
        if (name != null) ContactCache.put(result.id, name);
        ContactCache.putAvatar(result.id, result.avatarUrl);
        ContactCache.putPhone(result.id, result.phone);
        await _finish(
          accountId: accountId,
          sessionEpoch: sessionEpoch,
          userId: result.id,
          name: result.name,
          avatarUrl: result.avatarUrl,
        );
      } else {
        final packet = await widget.client.sendRequest(Opcode.contactInfo, {
          'contactIds': [id!],
        }, silent: true);
        if (!await _acceptsResult(accountId, sessionEpoch)) return;
        final contacts = (packet.payload as Map?)?['contacts'] as List?;
        final contact = contacts
            ?.whereType<Map>()
            .where((contact) => contact['id'] == id)
            .firstOrNull;
        if (contact == null) {
          _showError(l10n.findUserIdNotFound);
          return;
        }
        final raw = Map<String, dynamic>.from(contact);
        final info = ContactInfo.fromMap(raw);
        ContactsModule.primeContactCache(raw);
        await _finish(
          accountId: accountId,
          sessionEpoch: sessionEpoch,
          userId: id,
          name: info.displayName,
          avatarUrl: info.avatarUrl,
        );
      }
    } catch (error) {
      if (await _acceptsResult(accountId, sessionEpoch)) {
        _showError(l10n.devicesGenericError(userFacingError(error, l10n)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _acceptsResult(int? accountId, int sessionEpoch) async {
    if (!_isCurrent || widget.client.sessionEpoch != sessionEpoch) return false;
    final activeAccount = await TokenStorage.getActiveAccountId();
    return _isCurrent &&
        widget.client.sessionEpoch == sessionEpoch &&
        activeAccount == accountId;
  }

  Future<void> _finish({
    required int? accountId,
    required int sessionEpoch,
    required int userId,
    required String? name,
    required String? avatarUrl,
  }) async {
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context)!;
    if (!await _acceptsResult(accountId, sessionEpoch)) return;
    final existing = accountId == null
        ? null
        : await AppDatabase.findDialogChatByParticipant(accountId, userId);
    if (!await _acceptsResult(accountId, sessionEpoch)) return;
    navigator.pop((
      userId: userId,
      chatId: existing ?? ((accountId ?? 0) ^ userId),
      name: ContactCache.get(userId) ?? name ?? l10n.userFallbackName(userId),
      avatarUrl: avatarUrl ?? '',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final phoneMode = _mode == _FindMode.phone;
    final busy = _loading || _pickingCountry;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetGrabberBar(
                action: IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Symbols.close, size: 20),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              SegmentedButton<_FindMode>(
                segments: [
                  ButtonSegment(
                    value: _FindMode.phone,
                    label: Text(l10n.findUserPhoneTab),
                    icon: const Icon(Symbols.call, size: 18),
                  ),
                  const ButtonSegment(
                    value: _FindMode.id,
                    label: Text('ID'),
                    icon: Icon(Symbols.tag, size: 18),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: busy ? null : (s) => _setMode(s.first),
                showSelectedIcon: false,
                expandedInsets: EdgeInsets.zero,
              ),
              const SizedBox(height: 20),
              if (phoneMode) ...[
                OutlinedButton(
                  onPressed: busy ? null : _pickCountry,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(14),
                    foregroundColor: cs.onSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppShape.field),
                    ),
                    side: BorderSide(color: cs.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: cs.surfaceContainerHighest,
                          foregroundColor: cs.onSurfaceVariant,
                          child: Text(
                            _country.code,
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.loginCountry,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              _country.displayName(
                                Localizations.localeOf(context).languageCode,
                              ),
                              style: theme.textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Symbols.unfold_more, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              SizedBox(
                key: _inputKey,
                child: TextField(
                  key: ValueKey(_mode),
                  controller: phoneMode ? _phoneController : _idController,
                  focusNode: _focus,
                  autofocus: true,
                  keyboardType: phoneMode
                      ? TextInputType.phone
                      : TextInputType.number,
                  textInputAction: TextInputAction.search,
                  autofillHints: phoneMode
                      ? const [AutofillHints.telephoneNumberNational]
                      : null,
                  autocorrect: false,
                  enableSuggestions: false,
                  enabled: !busy,
                  inputFormatters: phoneMode
                      ? [
                          PhoneLookupInputFormatter(
                            country: _country,
                            onCountryChanged: (country) {
                              setState(() => _country = country);
                            },
                          ),
                        ]
                      : null,
                  onSubmitted: (_) => _submit(),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    labelText: phoneMode ? l10n.loginPhoneNumber : 'ID',
                    hintText: phoneMode
                        ? _country.phoneMask.replaceAll('#', '0')
                        : l10n.findUserIdHint,
                    prefixText: phoneMode ? '${_country.phoneCode}  ' : null,
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppShape.field),
                      borderSide: BorderSide(
                        color: _error == null ? cs.outlineVariant : cs.error,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppShape.field),
                      borderSide: BorderSide(
                        color: _error == null ? cs.primary : cs.error,
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy ? null : _submit,
                style: FilledButton.styleFrom(
                  shape: AppShape.buttonBorder,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_loading) ...[
                      const SmallSpinner(size: 20),
                      const SizedBox(width: 10),
                    ],
                    Flexible(child: Text(widget.actionLabel)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
