import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/mapping.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../components/ds.dart';

/// Raise a guest request from the app, with the same fields and rules as the CMS form.
/// Pops with the created [Req] (or null when the server did not return it).
class NewRequestScreen extends StatefulWidget {
  const NewRequestScreen({super.key});

  @override
  State<NewRequestScreen> createState() => _NewRequestScreenState();
}

class _NewRequestScreenState extends State<NewRequestScreen> {
  // Same limits as the CMS form.
  static const _maxTitle = 255, _maxRequester = 150, _maxText = 20000;

  final _title = TextEditingController();
  final _description = TextEditingController();
  final _guest = TextEditingController();
  final _contact = TextEditingController();

  RequestType? _type;
  Location? _location;
  int? _departmentId;
  int _priority = 2;
  DateTime? _due;

  bool _busy = false, _loadingLocations = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    if (s.locations.isEmpty) _loadLocations(s);
    // Most requests belong to the creator's own department.
    _departmentId = s.me?.departmentId;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _guest.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _loadLocations(AppState s) async {
    setState(() => _loadingLocations = true);
    try {
      await s.loadLocations();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load locations. ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _loadingLocations = false);
    }
  }

  /// Picking a type fills in its department, as the CMS does, unless the user already chose a different one.
  void _setType(RequestType t) {
    setState(() {
      final previousDefault = _type?.departmentId;
      if (t.departmentId != null && (_departmentId == null || _departmentId == previousDefault)) {
        _departmentId = t.departmentId;
      }
      if (_title.text.trim().isEmpty || _title.text.trim() == _type?.name) _title.text = t.name;
      _type = t;
    });
  }

  String? _missing() {
    if (_type == null) return 'Choose a request type.';
    if (_title.text.trim().isEmpty) return 'Enter a title.';
    if (_location == null) return 'Choose a location.';
    if (_departmentId == null) return 'Choose a department.';
    return null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final missing = _missing();
    if (missing != null) {
      setState(() => _error = missing);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final req = await context.read<AppState>().createRequest(
        title: _title.text,
        requestTypeId: _type!.id,
        locationId: _location!.id,
        departmentId: _departmentId!,
        priority: _priority,
        description: _description.text,
        requesterName: _guest.text,
        requesterContact: _contact.text,
        dueAt: _due,
      );
      if (mounted) Navigator.of(context).pop(req ?? false);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiException && e.status == 403
              ? 'Your role is not allowed to create requests. Ask an administrator for request create access.'
              : friendlyError(e),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final start = _due ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(start));
    if (time == null || !mounted) return;
    setState(() => _due = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  /// A searchable list in a bottom sheet; returns the chosen item.
  Future<T?> _choose<T>({
    required String title,
    required List<T> items,
    required String Function(T) label,
    String Function(T)? detail,
    T? selected,
  }) {
    final search = TextEditingController();
    return showRgSheet<T>(
      context,
      title: title,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final c = RgColors.of(ctx);
          final q = search.text.trim().toLowerCase();
          final shown = q.isEmpty ? items : items.where((i) => label(i).toLowerCase().contains(q)).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (items.length > 8) ...[
                RgSearchField(controller: search, placeholder: 'Search', onChanged: (_) => setSheet(() {})),
                const SizedBox(height: 8),
              ],
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Nothing found',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.textSecondary),
                  ),
                ),
              for (final item in shown)
                Pressable(
                  pressedColor: c.surfaceSunken,
                  onTap: () => Navigator.pop(ctx, item),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: hairlineBottom(ctx),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label(item), style: RgType.body.copyWith(color: c.textPrimary)),
                              if (detail != null && detail(item).isNotEmpty)
                                Text(detail(item), style: RgType.footnote.copyWith(color: c.textSecondary)),
                            ],
                          ),
                        ),
                        if (item == selected) RgIcon(Symbols.check_rounded, color: c.textBrand),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ).whenComplete(search.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = RgColors.of(context);
    final types = s.types.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final depts = s.departments.values.where((d) => d.isActive).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final dept = s.departments[_departmentId];

    return Scaffold(
      backgroundColor: c.surfaceApp,
      body: SafeArea(
        child: Column(
          children: [
            // Header: Cancel · New request
            SizedBox(
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: Text('Cancel', style: TextStyle(fontSize: 17, color: c.textBrand)),
                    ),
                  ),
                  Text('New request', style: RgType.headline.copyWith(color: c.textPrimary)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  const SectionHeader('Request'),
                  RgCard(
                    child: Column(
                      children: [
                        _PickerRow(
                          label: 'Type',
                          required: true,
                          value: _type?.name,
                          placeholder: types.isEmpty ? 'No request types set up' : 'Choose',
                          onTap: types.isEmpty
                              ? null
                              : () async {
                                  final t = await _choose<RequestType>(
                                    title: 'Request type',
                                    items: types,
                                    label: (t) => t.name,
                                    detail: (t) => s.departments[t.departmentId]?.name ?? '',
                                    selected: _type,
                                  );
                                  if (t != null) _setType(t);
                                },
                        ),
                        _TextRow(controller: _title, label: 'Title', required: true, maxLength: _maxTitle),
                        _TextRow(
                          controller: _description,
                          label: 'Details',
                          hint: 'Optional',
                          maxLength: _maxText,
                          multiline: true,
                          last: true,
                        ),
                      ],
                    ),
                  ),
                  const SectionHeader('Where'),
                  RgCard(
                    child: Column(
                      children: [
                        _PickerRow(
                          label: 'Location',
                          required: true,
                          value: _location?.name,
                          placeholder: _loadingLocations ? 'Loading…' : 'Choose',
                          onTap: _loadingLocations
                              ? null
                              : () async {
                                  if (s.locations.isEmpty) {
                                    await _loadLocations(s);
                                    if (!mounted || s.locations.isEmpty) return;
                                  }
                                  final l = await _choose<Location>(
                                    title: 'Location',
                                    items: s.locations,
                                    label: (l) => l.name,
                                    selected: _location,
                                  );
                                  if (l != null) setState(() => _location = l);
                                },
                        ),
                        _PickerRow(
                          label: 'Department',
                          required: true,
                          value: dept?.name,
                          placeholder: 'Choose',
                          last: true,
                          onTap: () async {
                            final d = await _choose<Department>(
                              title: 'Department',
                              items: depts,
                              label: (d) => d.name,
                              selected: dept,
                            );
                            if (d != null) setState(() => _departmentId = d.id);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SectionHeader('Guest'),
                  RgCard(
                    child: Column(
                      children: [
                        _TextRow(controller: _guest, label: 'Name or room', hint: 'Optional', maxLength: _maxRequester),
                        _TextRow(
                          controller: _contact,
                          label: 'Contact',
                          hint: 'Optional',
                          maxLength: _maxRequester,
                          keyboard: TextInputType.phone,
                          last: true,
                        ),
                      ],
                    ),
                  ),
                  const SectionHeader('Priority'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (p, label) in [(1, 'Low'), (2, 'Normal'), (3, 'High')])
                          RgChip(label: label, selected: _priority == p, onTap: () => setState(() => _priority = p)),
                      ],
                    ),
                  ),
                  const SectionHeader('Due'),
                  RgCard(
                    child: _PickerRow(
                      label: 'Due by',
                      value: _due == null ? null : '${dayLabel(_due!)}, ${DateFormat('HH:mm').format(_due!)}',
                      placeholder: 'No due time',
                      last: true,
                      onTap: _pickDue,
                      trailing: _due == null
                          ? null
                          : Semantics(
                              button: true,
                              label: 'Clear due time',
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => setState(() => _due = null),
                                child: SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: Center(child: RgIcon(Symbols.close_rounded, size: 20, color: c.textTertiary)),
                                ),
                              ),
                            ),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RgIcon(Symbols.error_rounded, size: 18, fill: true, color: c.dangerFg),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(_error!, style: RgType.footnote.copyWith(color: c.dangerFg)),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                    child: RgButton(
                      label: 'Create Request',
                      icon: Symbols.add_rounded,
                      size: BtnSize.lg,
                      expand: true,
                      loading: _busy,
                      onPressed: _submit,
                    ),
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

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onTap,
    this.required = false,
    this.last = false,
    this.trailing,
  });
  final String label, placeholder;
  final String? value;
  final VoidCallback? onTap;
  final bool required, last;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    return Semantics(
      button: true,
      label: '$label${required ? ', required' : ''}: ${value ?? placeholder}',
      excludeSemantics: true,
      child: Pressable(
        pressedColor: c.surfaceSunken,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
            decoration: last ? null : hairlineBottom(context),
            child: Row(
              children: [
                _Label(label, required: required),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value ?? placeholder,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RgType.body.copyWith(color: value == null ? c.textTertiary : c.textPrimary),
                  ),
                ),
                trailing ?? RgIcon(Symbols.chevron_right_rounded, color: c.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TextRow extends StatelessWidget {
  const _TextRow({
    required this.controller,
    required this.label,
    required this.maxLength,
    this.hint,
    this.required = false,
    this.multiline = false,
    this.keyboard,
    this.last = false,
  });
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLength;
  final bool required, multiline, last;
  final TextInputType? keyboard;

  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.only(right: 14),
        decoration: last ? null : hairlineBottom(context),
        child: Row(
          crossAxisAlignment: multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            Padding(
              padding: EdgeInsets.only(top: multiline ? 13 : 0),
              child: _Label(label, required: required),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: controller,
                maxLength: maxLength,
                minLines: multiline ? 2 : 1,
                maxLines: multiline ? 6 : 1,
                keyboardType: multiline ? TextInputType.multiline : keyboard,
                textCapitalization: keyboard == TextInputType.phone
                    ? TextCapitalization.none
                    : TextCapitalization.sentences,
                textAlign: multiline ? TextAlign.left : TextAlign.right,
                style: RgType.body.copyWith(color: c.textPrimary),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  counterText: '',
                  hintText: hint ?? (required ? 'Required' : null),
                  hintStyle: TextStyle(color: c.textTertiary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.required = false});
  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text),
          if (required)
            TextSpan(
              text: ' *',
              style: TextStyle(color: c.dangerFg),
            ),
        ],
      ),
      style: RgType.body.copyWith(color: c.textPrimary),
    );
  }
}
