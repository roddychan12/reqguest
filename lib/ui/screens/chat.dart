import 'dart:async';

import 'package:flutter/material.dart';
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
  Timer? _poll;
  int _lastCount = 0;

  AppState get _s => context.read<AppState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final r = _s.byId(widget.requestId);
      if (r != null) _s.markSeen(r);
      await _s.reloadChat(widget.requestId);
      if (mounted && r != null) _s.markSeen(r);
    });
    _poll = Timer.periodic(const Duration(seconds: 8), (_) async {
      await _s.loadEvents(widget.requestId);
      final r = _s.byId(widget.requestId);
      if (mounted && r != null) _s.markSeen(r);
    });
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _run(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } on ApiException catch (e) {
      if (mounted) Toaster.show(context, e.message, tone: ToastTone.danger);
    } catch (e, st) {
      debugPrint('Chat action failed: $e\n$st');
      if (mounted) Toaster.show(context, 'Could not reach the server', tone: ToastTone.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send(Req r) async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    _scrollToEnd();
    await _run(() => _s.sendComment(r, text, internal: _internal));
  }

  Future<void> _transition(Req r, WfTransition t) async {
    if (isCancelTransition(t.name)) {
      final ok = await _confirmCancel(r);
      if (ok != true) return;
    }
    await _run(() async {
      await _s.applyTransition(r, t, note: _noteFor(t));
      if (!mounted) return;
      final to = _s.statuses[t.toStatusId];
      final fin = to?.isFinal ?? false;
      Toaster.show(
        context,
        '${r.chatName} · ${to?.name ?? t.name}',
        tone: fin ? ToastTone.success : ToastTone.neutral,
        icon: fin ? Symbols.check_circle_rounded : Symbols.swap_horiz_rounded,
        actionLabel: 'Undo',
        onAction: () => _run(() => _s.undoTransition(r, t)),
      );
      _scrollToEnd();
    });
  }

  String _noteFor(WfTransition t) {
    final n = t.name.toLowerCase();
    if (n.contains('start delivery')) return 'On the way';
    if (n.contains('mark delivered')) return 'Delivered to guest';
    if (n.contains('ready')) return 'Ready for pickup';
    if (n.contains('hold')) return 'Put on hold';
    if (n.contains('resume')) return 'Resumed work';
    return _s.statuses[t.toStatusId]?.name ?? t.name;
  }

  Future<bool?> _confirmCancel(Req r) => showRgSheet<bool>(
        context,
        title: 'Cancel this request?',
        builder: (ctx) {
          final c = RgColors.of(ctx);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${r.chatName} · ${r.chatTitle} will move to Closed. The team will see it in the chat.',
                style: RgType.subhead.copyWith(color: c.textSecondary)),
            const SizedBox(height: 16),
            RgButton(
                label: 'Cancel Request',
                variant: BtnVariant.danger,
                size: BtnSize.lg,
                expand: true,
                onPressed: () => Navigator.pop(ctx, true)),
            const SizedBox(height: 8),
            RgButton(
                label: 'Keep Open',
                variant: BtnVariant.ghost,
                size: BtnSize.lg,
                expand: true,
                onPressed: () => Navigator.pop(ctx, false)),
          ]);
        },
      );

  Future<void> _attach(Req r, {ImageSource? direct}) async {
    ImageSource? source = direct;
    bool video = false;
    if (source == null) {
      final choice = await showRgSheet<(ImageSource, bool)>(
        context,
        title: 'Share',
        builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          RgButton(
              label: 'Take Photo',
              icon: Symbols.photo_camera_rounded,
              variant: BtnVariant.secondary,
              size: BtnSize.lg,
              onPressed: () => Navigator.pop(ctx, (ImageSource.camera, false))),
          const SizedBox(height: 8),
          RgButton(
              label: 'Photo Library',
              icon: Symbols.photo_library_rounded,
              variant: BtnVariant.secondary,
              size: BtnSize.lg,
              onPressed: () => Navigator.pop(ctx, (ImageSource.gallery, false))),
          const SizedBox(height: 8),
          RgButton(
              label: 'Video',
              icon: Symbols.videocam_rounded,
              variant: BtnVariant.secondary,
              size: BtnSize.lg,
              onPressed: () => Navigator.pop(ctx, (ImageSource.gallery, true))),
        ]),
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
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final mime = file.mimeType ?? (video ? 'video/mp4' : 'image/jpeg');
    _scrollToEnd();
    await _run(() => _s.uploadAttachment(r, bytes, file!.name, mime));
  }

  void _details(Req r) {
    final s = _s;
    final copy = Copy(s);
    showRgSheet(context, title: '${r.chatName} · ${r.chatTitle}', builder: (ctx) {
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
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (r.description?.isNotEmpty ?? false)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(r.description!, style: RgType.subhead.copyWith(color: c.textSecondary)),
          ),
        for (final (k, v) in rows)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: hairlineBottom(ctx),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(k, style: TextStyle(fontSize: 15, color: c.textSecondary)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(v,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 15, color: c.textPrimary, fontFeatures: RgType.tabular)),
              ),
            ]),
          ),
        const SizedBox(height: 16),
        RgButton(
            label: 'Done', variant: BtnVariant.outline, size: BtnSize.lg, expand: true, onPressed: () => Navigator.pop(ctx)),
      ]);
    });
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
            icon: Symbols.search_off_rounded, title: 'Request not found', message: 'It may have been removed.'),
      );
    }
    final list = s.eventsFor(r.id);
    if (list.length != _lastCount) {
      if (_lastCount != 0) _scrollToEnd();
      _lastCount = list.length;
    }
    final others = s.openChats.where((x) => x.id != r.id && s.unreadCount(x) > 0).length;

    return Scaffold(
      backgroundColor: c.surfaceApp,
      body: Column(children: [
        _Header(
          req: r,
          backBadge: others,
          onBack: () => Navigator.pop(context),
          onInfo: () => _details(r),
        ),
        Expanded(
          child: !s.eventsLoaded(r.id) && list.isEmpty
              ? Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: c.brand))
              : _Messages(req: r, events: list, controller: _scroll),
        ),
        _BottomBar(
          req: r,
          input: _input,
          internal: _internal,
          busy: _busy,
          onToggleInternal: () => setState(() => _internal = !_internal),
          onSend: () => _send(r),
          onAttach: () => _attach(r),
          onCamera: () => _attach(r, direct: ImageSource.camera),
          onTransition: (t) => _transition(r, t),
          onPick: () => _run(() => _s.pick(r)),
        ),
      ]),
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
          height: 56,
          child: Padding(
            padding: const EdgeInsets.only(left: 2, right: 8),
            child: Row(children: [
              GestureDetector(
                onTap: onBack,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  height: 44,
                  child: Row(children: [
                    RgIcon(Symbols.chevron_left_rounded, size: 32, weight: 500, color: c.textBrand),
                    if (backBadge > 0)
                      Container(
                        constraints: const BoxConstraints(minWidth: 22),
                        height: 22,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: c.surfaceSunken, borderRadius: BorderRadius.circular(11)),
                        child: Text('$backBadge',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: c.textPrimary,
                                fontFeatures: RgType.tabular)),
                      ),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: onInfo,
                  behavior: HitTestBehavior.opaque,
                  child: Row(children: [
                    GlyphAvatar(icon: copy.typeIcon(req), tint: copy.tint(context, req), size: 38, iconSize: 21),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${req.chatName} · ${req.chatTitle}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 17,
                                height: 21 / 17,
                                fontWeight: FontWeight.w600,
                                color: c.textPrimary,
                                fontFeatures: RgType.tabular)),
                        Text(copy.subline(req),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, height: 16 / 13, color: c.textSecondary)),
                      ]),
                    ),
                  ]),
                ),
              ),
              SizedBox(
                  width: 40,
                  height: 44,
                  child: GestureDetector(onTap: onInfo, child: Center(child: RgIcon(Symbols.info_rounded, color: c.textBrand)))),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Messages ─────────────────────────────────────────────────────────────────

class _Messages extends StatelessWidget {
  const _Messages({required this.req, required this.events, required this.controller});
  final Req req;
  final List<ChatEvent> events;
  final ScrollController controller;

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
        EventKind.guest => _GuestCard(req: req, event: e),
        EventKind.status => _StatusPill(event: e),
        EventKind.assign => _AssignPill(event: e),
        EventKind.comment => _CommentBubble(event: e),
        EventKind.attach => _AttachBubble(event: e),
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
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          RgIcon(Symbols.lock_rounded, size: 15, color: c.warningFg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Staff chat for $reference. Status changes appear here in order, as they happen.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, height: 16 / 12, color: c.warningFg),
            ),
          ),
        ]),
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
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textSecondary)),
      ),
    );
  }
}

const _tailLeft = BorderRadius.only(
    topLeft: Radius.circular(4), topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16));
const _tailRight = BorderRadius.only(
    topLeft: Radius.circular(16), topRight: Radius.circular(4), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16));

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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            RgIcon(Symbols.concierge_rounded, size: 16, color: c.textBrand),
            const SizedBox(width: 6),
            Flexible(
              child: Text('${req.chatName} · Guest request',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textBrand)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(req.chatTitle, style: RgType.headline.copyWith(color: c.textPrimary)),
          if (req.description?.isNotEmpty ?? false) ...[
            const SizedBox(height: 4),
            Text(req.description!, style: RgType.callout.copyWith(color: c.textPrimary)),
          ],
          const SizedBox(height: 6),
          Row(children: [
            PriorityTag(priority: req.priorityName),
            const SizedBox(width: 12),
            const Spacer(),
            Text('Logged by ${s.whoOf(event.by ?? req.createdBy)} · ${hhmm(event.at)}', style: _meta(c)),
          ]),
        ]),
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
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          StatusBadge(
              kind: statusKindFor(event.toStatusCode ?? s.statuses[event.toStatusId]?.code),
              label: copy.statusName(event),
              small: true),
          const SizedBox(width: 8),
          Flexible(
            child: Text(copy.statusLine(event),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, height: 17 / 13, color: c.textSecondary)),
          ),
          const SizedBox(width: 8),
          Text(hhmm(event.at), style: _meta(c)),
        ]),
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
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          RgIcon(Symbols.person_add_rounded, size: 16, color: c.textSecondary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(Copy(s).assignText(event),
                style: TextStyle(fontSize: 13, height: 17 / 13, color: c.textSecondary)),
          ),
          const SizedBox(width: 6),
          Text(hhmm(event.at), style: _meta(c)),
        ]),
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (event.isInternal)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  RgIcon(Symbols.lock_rounded, size: 13, color: c.warningFg),
                  const SizedBox(width: 3),
                  Text('INTERNAL NOTE',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: c.warningFg)),
                ]),
              ),
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(dept == null ? s.nameOf(event.by) : '${s.nameOf(event.by)} · $dept',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textBrand)),
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
          ]),
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
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(hhmm(at), style: _meta(c)),
        if (mine) ...[
          const SizedBox(width: 3),
          RgIcon(pending ? Symbols.schedule_rounded : Symbols.done_all_rounded,
              size: 16, color: pending ? c.textTertiary : c.infoFg),
        ],
      ]),
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          RgIcon(video ? Symbols.play_circle_rounded : Symbols.image_rounded, size: 36, fill: true, color: c.textSecondary),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(event.fileName ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: c.textSecondary)),
          ),
        ]),
      ),
    );
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: mine ? c.ownBubble : c.surfaceCard, borderRadius: mine ? _tailRight : _tailLeft, boxShadow: c.shadow1),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!mine)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
              child: Text(dept == null ? s.nameOf(event.by) : '${s.nameOf(event.by)} · $dept',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textBrand)),
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
            child: Row(children: [
              Expanded(
                child: Text('${Copy(s).mediaLabel(event)} · ${fileSize(event.fileSize)}', style: _meta(c)),
              ),
              _Meta(at: event.at, mine: mine),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Photos open full screen with pinch-zoom; videos and other files open outside the app.
void _openMedia(BuildContext context, String url, ChatEvent e, {required bool video}) {
  if (!isImage(e.mimeType)) {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    return;
  }
  Navigator.of(context).push(MaterialPageRoute(
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
            onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
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
  ));
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
  final VoidCallback onToggleInternal, onSend, onAttach, onCamera, onPick;
  final ValueChanged<WfTransition> onTransition;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = RgColors.of(context);
    final closed = s.isFinal(req);
    final hasText = input.text.trim().isNotEmpty;

    return Glass(
      top: true,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (closed) _closedLine(context, s) else _actions(context, s),
            const SizedBox(height: 8),
            Row(children: [
              SizedBox(
                width: 40,
                height: 40,
                child: GestureDetector(
                    onTap: onAttach, child: Center(child: RgIcon(Symbols.add_rounded, size: 28, color: c.textBrand))),
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
                  child: Row(children: [
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
                    GestureDetector(
                      onTap: onToggleInternal,
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: Center(
                          child: RgIcon(internal ? Symbols.lock_rounded : Symbols.lock_open_rounded,
                              size: 20, color: internal ? c.warningFg : c.textTertiary),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 6),
              Pressable(
                scale: 0.94,
                onTap: hasText ? onSend : onCamera,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: RgIcon(hasText ? Symbols.send_rounded : Symbols.photo_camera_rounded,
                      size: 22, fill: true, color: c.textOnPrimary),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _closedLine(BuildContext context, AppState s) {
    final c = RgColors.of(context);
    final st = s.statusOf(req);
    final at = s.eventsFor(req.id).where((e) => e.kind == EventKind.status).lastOrNull?.at ?? req.closedAt;
    final when = at == null ? '' : ' ${dayLabel(at).toLowerCase()} at ${hhmm(at)}';
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      RgIcon(Symbols.verified_rounded, size: 16, color: c.textBrand),
      const SizedBox(width: 6),
      Text('${st?.name ?? 'Closed'}$when', style: TextStyle(fontSize: 13, color: c.textSecondary)),
    ]);
  }

  Widget _actions(BuildContext context, AppState s) {
    final ts = s.transitionsFor(req);
    final forward = ts.where((t) => !isCancelTransition(t.name)).toList();
    final primary = forward.where((t) => !isHoldTransition(t.name)).firstOrNull ?? forward.firstOrNull;
    final cancels = ts.where((t) => isCancelTransition(t.name));
    final ordered = [
      ?primary,
      ...forward.where((t) => t != primary),
      ...cancels,
    ];
    final unassigned = s.assigneeOf(req.id) == null;
    if (ordered.isEmpty && !unassigned) return const SizedBox.shrink();
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
          if (unassigned)
            RgButton(
              label: 'Pick Up',
              icon: Symbols.front_hand_rounded,
              size: BtnSize.sm,
              variant: ordered.isEmpty ? BtnVariant.primary : BtnVariant.outline,
              onPressed: busy ? null : onPick,
            ),
        ],
      ),
    );
  }
}
