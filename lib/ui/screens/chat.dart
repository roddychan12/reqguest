import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/mapping.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../components/ds.dart';
import '../copy.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.requestId});
  final int requestId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  bool _internal = false;
  bool _busy = false;

  /// Shown above the composer while a file is being sent.
  String? _uploading;
  Timer? _poll;
  bool _polling = false;
  int _lastCount = 0;

  AppState get _s => context.read<AppState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final s = _s;
      _markSeen(s);
      await s.reloadChat(widget.requestId);
      if (mounted) _markSeen(s);
    });
    _poll = Timer.periodic(const Duration(seconds: 8), (_) async {
      if (_polling || !mounted) return;
      _polling = true;
      final s = _s;
      try {
        await s.loadEvents(widget.requestId);
      } finally {
        _polling = false;
      }
      if (mounted) _markSeen(s);
    });
    _input.addListener(() => setState(() {}));
  }

  /// Marks the chat read only while someone is actually looking at it:
  /// this screen is on top (no photo viewer over it) and the app is in the foreground.
  void _markSeen(AppState s) {
    final r = s.byId(widget.requestId);
    if (r == null) return;
    final onTop = ModalRoute.of(context)?.isCurrent ?? true;
    final foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (onTop && foreground) s.markSeen(r);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  /// Jumps to the newest message. Unless [force]d, it only does so when the reader
  /// is already near the bottom, so reading older messages is not interrupted.
  void _scrollToEnd({bool force = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      if (!force && _scroll.offset > 120) return;
      _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  /// Runs one action at a time. Returns whether it succeeded; failures show a toast.
  Future<bool> _run(Future<void> Function() f) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await f();
      return true;
    } catch (e, st) {
      if (e is! ApiException) debugPrint('Chat action failed: $e\n$st');
      if (mounted) Toaster.show(context, friendlyError(e), tone: ToastTone.danger);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send(Req r) async {
    final text = _input.text.trim();
    // Never clear what was typed unless it is really being sent.
    if (text.isEmpty || _busy) return;
    _input.clear();
    _scrollToEnd();
    final ok = await _run(() => _s.sendComment(r, text, internal: _internal));
    // Put the text back so a failed message does not have to be retyped.
    if (!ok && mounted && _input.text.isEmpty) _input.text = text;
  }

  Future<void> _transition(Req r, WfTransition t) async {
    if (isCancelTransition(t.name)) {
      final ok = await _confirmCancel(r);
      if (ok != true || !mounted) return;
    }
    final s = _s;
    // The navigator outlives this screen, so Undo still works after going back.
    final nav = Navigator.of(context);
    // The first step on a new request (e.g. Accept Request) also makes it yours.
    final claims = s.assigneeOf(r.id) == null && !isCancelTransition(t.name);
    await _run(() async {
      if (claims) await s.pick(r);
      await s.applyTransition(r, t, note: _noteFor(t));
      if (!mounted) return;
      final to = s.statuses[t.toStatusId];
      final fin = to?.isFinal ?? false;
      Toaster.show(
        context,
        '${r.chatName} · ${to?.name ?? t.name}',
        tone: fin ? ToastTone.success : ToastTone.neutral,
        icon: fin ? Symbols.check_circle_rounded : Symbols.swap_horiz_rounded,
        // Accepting cannot be undone: undoing the status would leave it yours with nothing to undo the claim.
        actionLabel: claims ? null : 'Undo',
        onAction: claims ? null : () => mounted ? _run(() => s.undoTransition(r, t)) : _undoAway(nav, s, r, t),
      );
      _scrollToEnd();
    });
  }

  /// Undo tapped after this chat was closed: run it without touching this screen.
  static Future<void> _undoAway(NavigatorState nav, AppState s, Req r, WfTransition t) async {
    try {
      await s.undoTransition(r, t);
      if (nav.mounted) Toaster.show(nav.context, '${r.chatName} · Undone', tone: ToastTone.success);
    } catch (e) {
      if (nav.mounted) Toaster.show(nav.context, friendlyError(e), tone: ToastTone.danger);
    }
  }

  String _noteFor(WfTransition t) {
    final n = t.name.toLowerCase();
    if (n.contains('start delivery')) return 'On the way';
    if (n.contains('mark delivered')) return 'Delivered to guest';
    if (n.contains('ready')) return 'Ready for pickup';
    if (n.contains('resume')) return 'Resumed work';
    if (n.contains('hold')) return 'Put on hold';
    return _s.statuses[t.toStatusId]?.name ?? t.name;
  }

  Future<bool?> _confirmCancel(Req r) => showRgSheet<bool>(
    context,
    title: 'Cancel this request?',
    builder: (ctx) {
      final c = RgColors.of(ctx);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${r.chatName} · ${r.chatTitle} will move to Closed. The team will see it in the chat.',
            style: RgType.subhead.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: 16),
          RgButton(
            label: 'Cancel Request',
            variant: BtnVariant.danger,
            size: BtnSize.lg,
            expand: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
          const SizedBox(height: 8),
          RgButton(
            label: 'Keep Open',
            variant: BtnVariant.ghost,
            size: BtnSize.lg,
            expand: true,
            onPressed: () => Navigator.pop(ctx, false),
          ),
        ],
      );
    },
  );

  Future<void> _attach(Req r, {ImageSource? direct}) async {
    // One action at a time: picking now would only lose the file.
    if (_busy) return;
    ImageSource? source = direct;
    bool video = false;
    if (source == null) {
      final choice = await showRgSheet<(ImageSource, bool)>(
        context,
        title: 'Share',
        builder: (ctx) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RgButton(
              label: 'Take Photo',
              icon: Symbols.photo_camera_rounded,
              variant: BtnVariant.secondary,
              size: BtnSize.lg,
              onPressed: () => Navigator.pop(ctx, (ImageSource.camera, false)),
            ),
            const SizedBox(height: 8),
            RgButton(
              label: 'Photo Library',
              icon: Symbols.photo_library_rounded,
              variant: BtnVariant.secondary,
              size: BtnSize.lg,
              onPressed: () => Navigator.pop(ctx, (ImageSource.gallery, false)),
            ),
            const SizedBox(height: 8),
            RgButton(
              label: 'Video',
              icon: Symbols.videocam_rounded,
              variant: BtnVariant.secondary,
              size: BtnSize.lg,
              onPressed: () => Navigator.pop(ctx, (ImageSource.gallery, true)),
            ),
          ],
        ),
      );
      if (choice == null) return;
      (source, video) = choice;
    }
    final picker = ImagePicker();
    final XFile? file;
    try {
      file = video
          ? await picker.pickVideo(source: source)
          : await picker.pickImage(source: source, imageQuality: 80, maxWidth: 2000);
    } catch (_) {
      if (mounted) Toaster.show(context, 'Camera or photos are not available', tone: ToastTone.warning);
      return;
    }
    if (file == null || !mounted) return;
    final picked = file;
    final mime = picked.mimeType ?? _mimeFor(picked.name, video: video);
    _scrollToEnd();
    setState(() => _uploading = video ? 'Sending video…' : 'Sending photo…');
    try {
      await _run(() async {
        // Checked before reading, so a huge video is never loaded into memory.
        if (await picked.length() > kMaxUploadBytes) {
          throw ApiException(413, 'This file is too large. The limit is ${kMaxUploadBytes ~/ (1024 * 1024)} MB.');
        }
        await _s.uploadAttachment(r, await picked.readAsBytes(), picked.name, mime);
      });
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  /// The picker often reports no type on phones; guess it from the file name.
  static String _mimeFor(String name, {required bool video}) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      'jpg' || 'jpeg' => 'image/jpeg',
      'mov' => 'video/quicktime',
      'mp4' || 'm4v' => 'video/mp4',
      '3gp' => 'video/3gpp',
      'webm' => 'video/webm',
      _ => video ? 'video/mp4' : 'image/jpeg',
    };
  }

  /// Press-and-hold menu on a message or photo: copy, open, delete.
  Future<void> _eventActions(Req r, ChatEvent e) async {
    final s = _s;
    final isMedia = e.kind == EventKind.attach;
    final url = isMedia ? s.attachmentUrl(e) : null;
    final canDelete = s.canDelete(e) && s.canMessage(r);
    if (e.isDeleted || (!isMedia && (e.body ?? '').isEmpty && !canDelete)) return;
    HapticFeedback.selectionClick();
    final choice = await showRgSheet<String>(
      context,
      title: isMedia ? (e.fileName ?? 'Attachment') : (e.isInternal ? 'Internal note' : 'Message'),
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isMedia && (e.body ?? '').isNotEmpty) ...[
            RgButton(
              label: 'Copy Text',
              icon: Symbols.content_copy_rounded,
              variant: BtnVariant.secondary,
              size: BtnSize.lg,
              onPressed: () => Navigator.pop(ctx, 'copy'),
            ),
            const SizedBox(height: 8),
          ],
          if (url != null) ...[
            RgButton(
              label: 'Open',
              icon: Symbols.open_in_new_rounded,
              variant: BtnVariant.secondary,
              size: BtnSize.lg,
              onPressed: () => Navigator.pop(ctx, 'open'),
            ),
            const SizedBox(height: 8),
          ],
          if (canDelete) ...[
            RgButton(
              label: 'Delete',
              icon: Symbols.delete_rounded,
              variant: BtnVariant.danger,
              size: BtnSize.lg,
              onPressed: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
          RgButton(label: 'Close', variant: BtnVariant.ghost, size: BtnSize.lg, onPressed: () => Navigator.pop(ctx)),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: e.body ?? ''));
        if (mounted) Toaster.show(context, 'Copied', icon: Symbols.content_copy_rounded);
      case 'open':
        _openMedia(context, url!, e, video: isVideo(e.mimeType));
      case 'delete':
        await _confirmDelete(r, e);
    }
  }

  Future<void> _confirmDelete(Req r, ChatEvent e) async {
    final isMedia = e.kind == EventKind.attach;
    final what = isMedia ? (isVideo(e.mimeType) ? 'video' : 'photo') : (e.isInternal ? 'note' : 'message');
    final ok = await showRgSheet<bool>(
      context,
      title: 'Delete this $what?',
      builder: (ctx) {
        final c = RgColors.of(ctx);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'It will be removed from this chat for everyone, including the CMS. This cannot be undone.',
              style: RgType.subhead.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: 16),
            RgButton(
              label: 'Delete',
              icon: Symbols.delete_rounded,
              variant: BtnVariant.danger,
              size: BtnSize.lg,
              expand: true,
              onPressed: () => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 8),
            RgButton(
              label: 'Keep',
              variant: BtnVariant.ghost,
              size: BtnSize.lg,
              expand: true,
              onPressed: () => Navigator.pop(ctx, false),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;
    final done = await _run(() => _s.deleteEvent(r, e));
    if (done && mounted) {
      Toaster.show(context, '${what[0].toUpperCase()}${what.substring(1)} deleted', tone: ToastTone.success);
    }
  }

  void _details(Req r) {
    final s = _s;
    final copy = Copy(s);
    showRgSheet(
      context,
      title: '${r.chatName} · ${r.chatTitle}',
      builder: (ctx) {
        final c = RgColors.of(ctx);
        final st = s.statusOf(r);
        final who = s.assigneeOf(r.id);
        final rows = <(String, String)>[
          ('Reference', r.referenceNo),
          ('Type', copy.typeName(r)),
          ('Status', st?.name ?? 'Unclassified'),
          ('Priority', r.priorityName[0].toUpperCase() + r.priorityName.substring(1)),
          ('Department', s.departments[r.departmentId]?.name ?? '–'),
          ('Assigned to', who == null ? 'Unassigned' : s.nameOf(who)),
          ('Guest contact', r.requesterContact ?? '–'),
          if (r.locationNote?.isNotEmpty ?? false) ('Location note', r.locationNote!),
          if (r.dueAt != null) ('Due', '${dayLabel(r.dueAt!)}, ${hhmm(r.dueAt!)}'),
          ('Created', '${dayLabel(r.createdAt)}, ${hhmm(r.createdAt)}'),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (r.description?.isNotEmpty ?? false)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(r.description!, style: RgType.subhead.copyWith(color: c.textSecondary)),
              ),
            for (final (k, v) in rows)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: hairlineBottom(ctx),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(k, style: TextStyle(fontSize: 15, color: c.textSecondary)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        v,
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 15, color: c.textPrimary, fontFeatures: RgType.tabular),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            RgButton(
              label: 'Done',
              variant: BtnVariant.outline,
              size: BtnSize.lg,
              expand: true,
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = RgColors.of(context);
    final r = s.byId(widget.requestId);
    if (r == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: c.surfaceApp),
        body: const EmptyState(
          icon: Symbols.search_off_rounded,
          title: 'Request not found',
          message: 'It may have been removed.',
        ),
      );
    }
    final list = s.eventsFor(r.id);
    if (list.length != _lastCount) {
      if (_lastCount != 0) _scrollToEnd(force: false);
      _lastCount = list.length;
    }
    final loaded = s.eventsLoaded(r.id) || list.isNotEmpty;
    final others = s.openChats.where((x) => x.id != r.id && s.unreadCount(x) > 0).length;

    return Scaffold(
      backgroundColor: c.surfaceApp,
      body: Column(
        children: [
          _Header(req: r, backBadge: others, onBack: () => Navigator.pop(context), onInfo: () => _details(r)),
          Expanded(
            child: loaded
                ? _Messages(req: r, events: list, controller: _scroll, onHold: (e) => _eventActions(r, e))
                : s.eventsFailed(r.id)
                ? EmptyState(
                    icon: Symbols.cloud_off_rounded,
                    title: 'Could not load this chat',
                    message: 'Check your connection. It will keep retrying.',
                    action: RgButton(
                      label: 'Try Again',
                      icon: Symbols.refresh_rounded,
                      variant: BtnVariant.secondary,
                      onPressed: () => s.reloadChat(r.id),
                    ),
                  )
                : Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: c.brand)),
          ),
          _BottomBar(
            req: r,
            input: _input,
            internal: _internal,
            busy: _busy,
            uploading: _uploading,
            onToggleInternal: () => setState(() => _internal = !_internal),
            onSend: () => _send(r),
            onAttach: () => _attach(r),
            onCamera: () => _attach(r, direct: ImageSource.camera),
            onTransition: (t) => _transition(r, t),
            onPick: () => _run(() => _s.pick(r)),
          ),
        ],
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.req, required this.backBadge, required this.onBack, required this.onInfo});
  final Req req;
  final int backBadge;
  final VoidCallback onBack, onInfo;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = RgColors.of(context);
    final copy = Copy(s);
    return Glass(
      bottom: true,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 68,
          child: Padding(
            padding: const EdgeInsets.only(left: 2, right: 8),
            child: Row(
              children: [
                Semantics(
                  button: true,
                  label: 'Back',
                  child: GestureDetector(
                    onTap: onBack,
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      height: 44,
                      child: Row(
                        children: [
                          RgIcon(Symbols.chevron_left_rounded, size: 32, weight: 500, color: c.textBrand),
                          if (backBadge > 0)
                            Container(
                              constraints: const BoxConstraints(minWidth: 22),
                              height: 22,
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: c.surfaceSunken,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Text(
                                '$backBadge',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: c.textPrimary,
                                  fontFeatures: RgType.tabular,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: onInfo,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      children: [
                        GlyphAvatar(icon: copy.typeIcon(req), tint: copy.tint(context, req), size: 44, iconSize: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${req.chatName} · ${req.chatTitle}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 17,
                                  height: 21 / 17,
                                  fontWeight: FontWeight.w600,
                                  color: c.textPrimary,
                                  fontFeatures: RgType.tabular,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                copy.subline(req),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, height: 16 / 13, color: c.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Request details',
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onInfo,
                      child: Center(child: RgIcon(Symbols.info_rounded, color: c.textBrand)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Messages ─────────────────────────────────────────────────────────────────

class _Messages extends StatelessWidget {
  const _Messages({required this.req, required this.events, required this.controller, required this.onHold});
  final Req req;
  final List<ChatEvent> events;
  final ScrollController controller;

  /// Long-press on a message or media bubble (copy / open / delete).
  final ValueChanged<ChatEvent> onHold;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[const _Banner()];
    String? day;
    for (final e in events) {
      final d = dayLabel(e.at);
      if (d != day) {
        items.add(_DatePill(d));
        day = d;
      }
      items.add(switch (e.kind) {
        _ when e.isDeleted => _DeletedBubble(event: e),
        EventKind.guest => _GuestCard(req: req, event: e),
        EventKind.status => _StatusPill(event: e),
        EventKind.assign => _AssignPill(event: e),
        EventKind.comment => GestureDetector(
          onLongPress: () => onHold(e),
          child: _CommentBubble(event: e),
        ),
        EventKind.attach => GestureDetector(
          onLongPress: () => onHold(e),
          child: _AttachBubble(event: e),
        ),
      });
    }
    // Reversed so the list opens at the latest message, like WhatsApp.
    final reversed = items.reversed.toList();
    return ListView.separated(
      controller: controller,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      itemCount: reversed.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final w = reversed[i];
        return w is _Banner ? _Banner(reference: req.referenceNo) : w;
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({this.reference = ''});
  final String reference;

  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.only(top: 4, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: c.warningBg, borderRadius: BorderRadius.circular(10)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            RgIcon(Symbols.lock_rounded, size: 15, color: c.warningFg),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Staff chat for $reference. Status changes appear here in order, as they happen.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, height: 16 / 12, color: c.warningFg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DatePill extends StatelessWidget {
  const _DatePill(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: c.surfaceCard, borderRadius: BorderRadius.circular(8), boxShadow: c.shadow1),
        child: Text(
          label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textSecondary),
        ),
      ),
    );
  }
}

const _tailLeft = BorderRadius.only(
  topLeft: Radius.circular(4),
  topRight: Radius.circular(16),
  bottomLeft: Radius.circular(16),
  bottomRight: Radius.circular(16),
);
const _tailRight = BorderRadius.only(
  topLeft: Radius.circular(16),
  topRight: Radius.circular(4),
  bottomLeft: Radius.circular(16),
  bottomRight: Radius.circular(16),
);

TextStyle _meta(RgColors c) => TextStyle(fontSize: 11, color: c.textTertiary, fontFeatures: RgType.tabular);

class _GuestCard extends StatelessWidget {
  const _GuestCard({required this.req, required this.event});
  final Req req;
  final ChatEvent event;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = RgColors.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 290),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
        decoration: BoxDecoration(color: c.surfaceCard, borderRadius: _tailLeft, boxShadow: c.shadow1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RgIcon(Symbols.concierge_rounded, size: 16, color: c.textBrand),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '${req.chatName} · Guest request',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textBrand),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(req.chatTitle, style: RgType.headline.copyWith(color: c.textPrimary)),
            if (req.description?.isNotEmpty ?? false) ...[
              const SizedBox(height: 4),
              Text(req.description!, style: RgType.callout.copyWith(color: c.textPrimary)),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                PriorityTag(priority: req.priorityName),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Logged by ${s.whoOf(event.by ?? req.createdBy)} · ${hhmm(event.at)}',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _meta(c),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.event});
  final ChatEvent event;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = RgColors.of(context);
    final copy = Copy(s);
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
        decoration: BoxDecoration(color: c.surfaceCard, borderRadius: BorderRadius.circular(14), boxShadow: c.shadow1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusBadge(
              kind: statusKindFor(event.toStatusCode ?? s.statuses[event.toStatusId]?.code),
              label: copy.statusName(event),
              small: true,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                copy.statusLine(event),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, height: 17 / 13, color: c.textSecondary),
              ),
            ),
            const SizedBox(width: 8),
            Text(hhmm(event.at), style: _meta(c)),
          ],
        ),
      ),
    );
  }
}

class _AssignPill extends StatelessWidget {
  const _AssignPill({required this.event});
  final ChatEvent event;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = RgColors.of(context);
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: c.surfaceCard, borderRadius: BorderRadius.circular(14), boxShadow: c.shadow1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RgIcon(Symbols.person_add_rounded, size: 16, color: c.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                Copy(s).assignText(event),
                style: TextStyle(fontSize: 13, height: 17 / 13, color: c.textSecondary),
              ),
            ),
            const SizedBox(width: 6),
            Text(hhmm(event.at), style: _meta(c)),
          ],
        ),
      ),
    );
  }
}

class _CommentBubble extends StatelessWidget {
  const _CommentBubble({required this.event});
  final ChatEvent event;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = RgColors.of(context);
    final mine = event.by != null && event.by == s.me?.userId;
    final bg = mine ? c.ownBubble : (event.isInternal ? c.warningBg : c.surfaceCard);
    final dept = s.deptOfUser(event.by)?.name;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Opacity(
        opacity: event.pending ? 0.6 : 1,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 290),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 5),
          decoration: BoxDecoration(color: bg, borderRadius: mine ? _tailRight : _tailLeft, boxShadow: c.shadow1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (event.isInternal)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RgIcon(Symbols.lock_rounded, size: 13, color: c.warningFg),
                      const SizedBox(width: 3),
                      Text(
                        'INTERNAL NOTE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                          color: c.warningFg,
                        ),
                      ),
                    ],
                  ),
                ),
              if (!mine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    dept == null ? s.nameOf(event.by) : '${s.nameOf(event.by)} · $dept',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textBrand),
                  ),
                ),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 10,
                children: [
                  Text(event.body ?? '', style: RgType.callout.copyWith(color: c.textPrimary)),
                  _Meta(at: event.at, mine: mine, pending: event.pending),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What is left of a deleted message or photo: "This message was deleted", like WhatsApp,
/// with who deleted it when it was someone else.
class _DeletedBubble extends StatelessWidget {
  const _DeletedBubble({required this.event});
  final ChatEvent event;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = RgColors.of(context);
    final mine = event.by != null && event.by == s.me?.userId;
    final what = event.kind == EventKind.attach ? 'photo' : 'message';
    final by = event.deletedBy;
    final text = by == null || by == event.by
        ? (mine ? 'You deleted this $what' : 'This $what was deleted')
        : 'This $what was deleted by ${s.whoOf(by, short: false)}';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 290),
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 6),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: mine ? _tailRight : _tailLeft,
          border: Border.all(color: c.borderDefault),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  s.nameOf(event.by),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textSecondary),
                ),
              ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RgIcon(Symbols.block_rounded, size: 16, color: c.textTertiary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        text,
                        style: RgType.callout.copyWith(color: c.textTertiary, fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                ),
                Text(hhmm(event.at), style: _meta(c)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.at, required this.mine, this.pending = false});
  final DateTime at;
  final bool mine, pending;

  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(hhmm(at), style: _meta(c)),
          if (mine) ...[
            const SizedBox(width: 3),
            RgIcon(
              pending ? Symbols.schedule_rounded : Symbols.done_all_rounded,
              size: 16,
              color: pending ? c.textTertiary : c.infoFg,
            ),
          ],
        ],
      ),
    );
  }
}

class _AttachBubble extends StatelessWidget {
  const _AttachBubble({required this.event});
  final ChatEvent event;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = RgColors.of(context);
    final mine = event.by != null && event.by == s.me?.userId;
    final video = isVideo(event.mimeType);
    final dept = s.deptOfUser(event.by)?.name;
    final url = s.attachmentUrl(event);
    final placeholder = CustomPaint(
      painter: _Stripes(c.surfaceSunken, c.borderDefault),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RgIcon(
              video ? Symbols.play_circle_rounded : Symbols.image_rounded,
              size: 36,
              fill: true,
              color: c.textSecondary,
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                event.fileName ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: c.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: mine ? c.ownBubble : c.surfaceCard,
          borderRadius: mine ? _tailRight : _tailLeft,
          boxShadow: c.shadow1,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!mine)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
                child: Text(
                  dept == null ? s.nameOf(event.by) : '${s.nameOf(event.by)} · $dept',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textBrand),
                ),
              ),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: GestureDetector(
                onTap: url == null ? null : () => _openMedia(context, url, event, video: video),
                child: SizedBox(
                  height: 150,
                  child: url != null && isImage(event.mimeType)
                      ? Image.network(
                          url,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          // The asset host sends no CORS headers; let web fall back to an <img> element.
                          webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                          loadingBuilder: (_, child, progress) => progress == null ? child : placeholder,
                          errorBuilder: (_, _, _) => placeholder,
                        )
                      : placeholder,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 2),
              child: Row(
                children: [
                  Expanded(child: Text('${Copy(s).mediaLabel(event)} · ${fileSize(event.fileSize)}', style: _meta(c))),
                  _Meta(at: event.at, mine: mine),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Photos open full screen with pinch-zoom; videos and other files open outside the app.
void _openMedia(BuildContext context, String url, ChatEvent e, {required bool video}) {
  if (!isImage(e.mimeType)) {
    _openExternal(context, url);
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(e.fileName ?? 'Photo', style: const TextStyle(fontSize: 15)),
          actions: [
            IconButton(
              tooltip: 'Open original',
              icon: const Icon(Symbols.open_in_new_rounded),
              onPressed: () => _openExternal(ctx, url),
            ),
          ],
        ),
        body: InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: Image.network(
              url,
              fit: BoxFit.contain,
              webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
              errorBuilder: (_, _, _) =>
                  const Text('Could not load this photo', style: TextStyle(color: Colors.white70)),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openExternal(BuildContext context, String url) async {
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context.mounted) {
    Toaster.show(context, 'Could not open this file on this device', tone: ToastTone.warning);
  }
}

class _Stripes extends CustomPainter {
  _Stripes(this.bg, this.line);
  final Color bg, line;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    final p = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (double x = -size.height; x < size.width; x += 11) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(_Stripes old) => old.bg != bg || old.line != line;
}

// ── Bottom bar: action strip + composer ─────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.req,
    required this.input,
    required this.internal,
    required this.busy,
    this.uploading,
    required this.onToggleInternal,
    required this.onSend,
    required this.onAttach,
    required this.onCamera,
    required this.onTransition,
    required this.onPick,
  });

  final Req req;
  final TextEditingController input;
  final bool internal, busy;
  final String? uploading;
  final VoidCallback onToggleInternal, onSend, onAttach, onCamera, onPick;
  final ValueChanged<WfTransition> onTransition;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = RgColors.of(context);
    final closed = s.isFinal(req);
    final hasText = input.text.trim().isNotEmpty;

    if (!s.canMessage(req)) return _viewOnly(context, s, closed);

    return Glass(
      top: true,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (uploading != null) ...[
                Row(
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.brand)),
                    const SizedBox(width: 8),
                    Text(uploading!, style: TextStyle(fontSize: 13, color: c.textSecondary)),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (closed) _closedLine(context, s) else _actions(context, s),
              const SizedBox(height: 8),
              Row(
                children: [
                  Semantics(
                    button: true,
                    label: 'Attach photo or video',
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: busy ? null : onAttach,
                        child: Center(
                          child: RgIcon(Symbols.add_rounded, size: 28, color: busy ? c.textDisabled : c.textBrand),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      constraints: const BoxConstraints(minHeight: 38),
                      padding: const EdgeInsets.only(left: 14, right: 4),
                      decoration: BoxDecoration(
                        color: internal ? c.warningBg : c.surfaceCard,
                        borderRadius: BorderRadius.circular(19),
                        border: Border.all(color: c.borderDefault),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: input,
                              minLines: 1,
                              maxLines: 5,
                              textCapitalization: TextCapitalization.sentences,
                              style: TextStyle(fontSize: 16, color: c.textPrimary),
                              decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 9),
                                hintText: internal ? 'Internal note · staff only' : 'Message',
                                hintStyle: TextStyle(fontSize: 16, color: internal ? c.warningFg : c.textTertiary),
                              ),
                            ),
                          ),
                          Semantics(
                            button: true,
                            toggled: internal,
                            label: 'Internal note, staff only',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: onToggleInternal,
                              child: SizedBox(
                                width: 40,
                                height: 40,
                                child: Center(
                                  child: RgIcon(
                                    internal ? Symbols.lock_rounded : Symbols.lock_open_rounded,
                                    size: 20,
                                    color: internal ? c.warningFg : c.textTertiary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Semantics(
                    button: true,
                    label: hasText ? 'Send message' : 'Take photo',
                    child: Pressable(
                      scale: 0.94,
                      onTap: busy ? null : (hasText ? onSend : onCamera),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: busy ? c.trackOff : c.brand, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: RgIcon(
                          hasText ? Symbols.send_rounded : Symbols.photo_camera_rounded,
                          size: 22,
                          fill: true,
                          color: c.textOnPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shown instead of the actions and chat box on a request a colleague picked up.
  Widget _viewOnly(BuildContext context, AppState s, bool closed) {
    final c = RgColors.of(context);
    final who = s.assigneeOf(req.id);
    final name = who == null ? 'A colleague' : s.nameOf(who);
    return Glass(
      top: true,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (closed) ...[_closedLine(context, s), const SizedBox(height: 8)],
              Semantics(
                label: '$name is handling this request. View only.',
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: c.surfaceCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.borderDefault),
                  ),
                  child: Row(
                    children: [
                      RgIcon(Symbols.visibility_rounded, size: 20, color: c.textSecondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: closed ? '$name handled this' : '$name is handling this',
                                style: TextStyle(fontWeight: FontWeight.w600, color: c.textPrimary),
                              ),
                              TextSpan(text: ' · View only', style: TextStyle(color: c.textSecondary)),
                            ],
                          ),
                          style: const TextStyle(fontSize: 14),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      RgIcon(Symbols.lock_rounded, size: 18, color: c.textTertiary),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _closedLine(BuildContext context, AppState s) {
    final c = RgColors.of(context);
    final st = s.statusOf(req);
    final at = s.eventsFor(req.id).where((e) => e.kind == EventKind.status).lastOrNull?.at ?? req.closedAt;
    final when = at == null ? '' : ' ${dayLabel(at).toLowerCase()} at ${hhmm(at)}';
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        RgIcon(Symbols.verified_rounded, size: 16, color: c.textBrand),
        const SizedBox(width: 6),
        Text('${st?.name ?? 'Closed'}$when', style: TextStyle(fontSize: 13, color: c.textSecondary)),
      ],
    );
  }

  Widget _actions(BuildContext context, AppState s) {
    final unassigned = s.assigneeOf(req.id) == null;
    // A new request shows its first workflow step (e.g. "Accept Request"); taking it
    // also claims the request, so there is no separate Pick Up step. Staff only get
    // the forward steps until it is theirs; after that, only the owner sees buttons.
    final List<WfTransition> ts;
    if (s.canManage(req)) {
      ts = s.transitionsFor(req);
    } else if (unassigned) {
      ts = s.transitionsFor(req).where((t) => !isCancelTransition(t.name) && !isHoldTransition(t.name)).toList();
    } else {
      ts = const [];
    }
    final forward = ts.where((t) => !isCancelTransition(t.name)).toList();
    final primary = forward.where((t) => !isHoldTransition(t.name)).firstOrNull ?? forward.firstOrNull;
    final cancels = ts.where((t) => isCancelTransition(t.name));
    final ordered = [?primary, ...forward.where((t) => t != primary), ...cancels];
    // A workflow with no step out of its first status still needs a way to take the request.
    final acceptOnly = ordered.isEmpty && unassigned;
    if (ordered.isEmpty && !acceptOnly) return const SizedBox.shrink();
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: [
          for (final t in ordered) ...[
            RgButton(
              label: t.name,
              icon: transitionIcon(t.name),
              size: BtnSize.sm,
              variant: t == primary
                  ? BtnVariant.primary
                  : (isCancelTransition(t.name) ? BtnVariant.ghost : BtnVariant.outline),
              onPressed: busy ? null : () => onTransition(t),
            ),
            const SizedBox(width: 8),
          ],
          if (acceptOnly)
            RgButton(
              label: 'Accept Request',
              icon: Symbols.check_circle_rounded,
              size: BtnSize.sm,
              onPressed: busy ? null : onPick,
            ),
        ],
      ),
    );
  }
}
