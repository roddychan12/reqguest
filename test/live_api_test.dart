// ignore_for_file: avoid_print
// Runs the real AppState against a live server. Skipped unless credentials are given:
//   flutter test test/live_api_test.dart --dart-define=LIVE_EMAIL=... --dart-define=LIVE_PASSWORD=...
import 'package:flutter_test/flutter_test.dart';
import 'package:reqguest/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _email = String.fromEnvironment('LIVE_EMAIL');
const _password = String.fromEnvironment('LIVE_PASSWORD');
const _server = String.fromEnvironment('LIVE_SERVER', defaultValue: 'https://dev-hotel4.hasuite.ai');

void main() {
  test('signs in and loads real requests', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppState.create();
    await s.signIn(_server, _email, _password);
    print('phase=${s.phase} error=${s.error}');
    print('me=${s.me?.name} role=${s.me?.role} dept=${s.me?.departmentId}');
    print('tenants=${s.tenants.map((t) => '${t.id}:${t.name}').toList()}');
    if (s.phase == Phase.pickTenant) {
      s.tenants.isEmpty ? await s.openTenantById(1) : await s.selectTenant(s.tenants.first);
    }
    print('tenant=${s.tenant?.name} phase=${s.phase} error=${s.error}');
    print('departments=${s.departments.length} statuses=${s.statuses.length} '
        'transitions=${s.transitions.length} types=${s.types.length} staff=${s.staff.length} users=${s.userNames.length}');
    print('visible=${s.visible.length} open=${s.openChats.length} closed=${s.closedChats.length}');
    for (final r in s.openChats.take(5)) {
      print('  ${r.referenceNo} | ${r.chatName} · ${r.chatTitle} | ${s.statusOf(r)?.name} | events=${s.eventsFor(r.id).length}');
    }
    expect(s.phase, anyOf(Phase.ready, Phase.error));
    s.dispose();
  }, skip: _email.isEmpty ? 'Set LIVE_EMAIL and LIVE_PASSWORD to run' : false, timeout: const Timeout(Duration(minutes: 3)));
}
