import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' show ClientException;
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../components/ds.dart';
import 'home.dart';

/// Routes between sign-in, workspace picker, loading and the main app.
class Gate extends StatelessWidget {
  const Gate({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (s.phase != Phase.ready) {
      // Signed out or switching workspace: close any chat or screen left open on top.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      });
    }
    return switch (s.phase) {
      Phase.booting || Phase.loading => const _Loading(),
      Phase.signedOut => const SignInScreen(),
      Phase.pickTenant => const TenantPicker(),
      Phase.error => _ErrorScreen(message: s.error ?? 'Something went wrong.'),
      Phase.ready => const HomeShell(),
    };
  }
}

class Logo extends StatelessWidget {
  const Logo({super.key, this.height = 30});
  final double height;

  @override
  Widget build(BuildContext context) => SvgPicture.asset('assets/reqguest-logo.svg', height: height);
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Logo(height: 36),
            const SizedBox(height: 24),
            SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: c.brand)),
          ],
        ),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                EmptyState(icon: Symbols.cloud_off_rounded, title: 'Could not load', message: message),
                RgButton(label: 'Try Again', icon: Symbols.refresh_rounded, onPressed: s.retry),
                const SizedBox(height: 8),
                RgButton(label: 'Sign Out', variant: BtnVariant.ghost, onPressed: s.signOut),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  // Pre-filled only on a device that has signed in before; a first-time user
  // starts with an empty, visible Property field and must fill it in.
  late final String? _savedProperty = propertyOf(context.read<AppState>().api.savedBaseUrl ?? '');
  late final _server = TextEditingController(text: _savedProperty ?? '');
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  late bool _showServer = _savedProperty == null;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final property = _server.text.trim();
    if (property.isEmpty) {
      setState(() {
        _showServer = true;
        _error = 'Enter your property name.';
      });
      return;
    }
    final server = propertyUrl(property);
    if (server == null) {
      setState(() {
        _showServer = true;
        _error = 'Enter the property name only, for example dev-hotel4 (letters, numbers and hyphens).';
      });
      return;
    }
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().signIn(server, _email.text.trim(), _password.text);
    } catch (e) {
      final host = Uri.parse(server).host;
      if (!mounted) return;
      setState(
        () => _error = switch (e) {
          ApiException() => e.message,
          // In a browser a blocked cross-site request looks the same as no connection.
          ClientException() when kIsWeb =>
            'The browser blocked the request to $host. The server must allow '
                'this page’s origin (${Uri.base.origin}) in CORS_ALLOWED_ORIGINS, or use the mobile app.',
          ClientException() => 'Could not reach $host. Check the address and your connection.',
          _ => friendlyError(e),
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: Logo(height: 40)),
                        const SizedBox(height: 12),
                        Text(
                          'Staff sign in',
                          textAlign: TextAlign.center,
                          style: RgType.subhead.copyWith(color: c.textSecondary),
                        ),
                        const SizedBox(height: 32),
                        RgCard(
                          margin: EdgeInsets.zero,
                          child: Column(
                            children: [
                              _Field(controller: _email, label: 'Email', keyboard: TextInputType.emailAddress),
                              const Padding(padding: EdgeInsets.only(left: 14), child: Hairline()),
                              _Field(controller: _password, label: 'Password', obscure: true, onSubmit: _submit),
                              if (_showServer) ...[
                                const Padding(padding: EdgeInsets.only(left: 14), child: Hairline()),
                                _Field(
                                  controller: _server,
                                  label: 'Property',
                                  keyboard: TextInputType.url,
                                  hint: 'dev-hotel4',
                                  onSubmit: _submit,
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              RgIcon(Symbols.error_rounded, size: 18, fill: true, color: c.dangerFg),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(_error!, style: RgType.footnote.copyWith(color: c.dangerFg)),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 20),
                        RgButton(label: 'Sign In', size: BtnSize.lg, expand: true, loading: _busy, onPressed: _submit),
                        const SizedBox(height: 8),
                        RgButton(
                          label: _showServer ? 'Hide Property' : 'Change Property',
                          variant: BtnVariant.ghost,
                          size: BtnSize.sm,
                          onPressed: () => setState(() => _showServer = !_showServer),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Padding(padding: EdgeInsets.only(bottom: 16), child: PoweredBy()),
          ],
        ),
      ),
    );
  }
}

/// A scrolling page that ends with "Powered by HeroApps" just above the tab bar.
/// Short content: the text sits at the bottom of the screen. Long content: it is
/// the last item, seen once scrolled to the end.
class PoweredByList extends StatelessWidget {
  const PoweredByList({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverList.list(children: children),
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Padding(padding: EdgeInsets.only(top: 20), child: PoweredBy()),
              BottomBarSpacer(),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Powered by HeroApps", shown at the bottom of the sign-in and list pages.
class PoweredBy extends StatelessWidget {
  const PoweredBy({super.key});

  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    return Text(
      'Powered by HeroApps',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12, color: c.textTertiary),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.obscure = false,
    this.keyboard,
    this.onSubmit,
    this.hint,
  });
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboard;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = RgColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: RgType.body.copyWith(color: c.textPrimary)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboard,
              autocorrect: false,
              onSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
              style: RgType.body.copyWith(color: c.textPrimary),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: hint,
                hintStyle: TextStyle(color: c.textTertiary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TenantPicker extends StatefulWidget {
  const TenantPicker({super.key});
  @override
  State<TenantPicker> createState() => _TenantPickerState();
}

class _TenantPickerState extends State<TenantPicker> {
  final _id = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  void _open() {
    final id = int.tryParse(_id.text.trim());
    if (id == null || id <= 0) {
      setState(() => _error = 'Enter the workspace number your administrator gave you.');
      return;
    }
    context.read<AppState>().openTenantById(id);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = RgColors.of(context);
    if (s.tenants.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              const Padding(padding: EdgeInsets.only(top: 36, bottom: 8), child: LargeTitle('Workspace')),
              Text(
                'Your account cannot list workspaces. Enter the workspace number to open it.',
                style: RgType.subhead.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: 16),
              RgCard(
                margin: EdgeInsets.zero,
                child: _Field(controller: _id, label: 'Number', keyboard: TextInputType.number, onSubmit: _open),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: RgType.footnote.copyWith(color: c.dangerFg)),
              ],
              const SizedBox(height: 16),
              RgButton(label: 'Open Workspace', size: BtnSize.lg, expand: true, onPressed: _open),
              const SizedBox(height: 8),
              RgButton(label: 'Sign Out', variant: BtnVariant.ghost, onPressed: s.signOut),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: ListView(
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(16, 36, 16, 8), child: LargeTitle('Workspace')),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                'Choose the property you are working at.',
                style: RgType.subhead.copyWith(color: c.textSecondary),
              ),
            ),
            RgCard(
              child: Column(
                children: [
                  for (final (i, t) in s.tenants.indexed)
                    Pressable(
                      pressedColor: c.surfaceSunken,
                      onTap: () => s.selectTenant(t),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 14),
                        child: Container(
                          decoration: i < s.tenants.length - 1 ? hairlineBottom(context) : null,
                          padding: const EdgeInsets.fromLTRB(0, 13, 14, 13),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(t.name, style: RgType.body.copyWith(color: c.textPrimary)),
                              ),
                              RgIcon(Symbols.chevron_right_rounded, color: c.textTertiary),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: RgButton(label: 'Sign Out', variant: BtnVariant.ghost, onPressed: s.signOut),
            ),
          ],
        ),
      ),
    );
  }
}
