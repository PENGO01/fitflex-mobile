// Vendor smart import V3: the addresses. A vendor still waiting for approval
// reaches the import pages (like their other own records); a member does not;
// a junk id goes back to the list; the pattern only matches what the server
// issues.
import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/screens/vendor/import/import_routes.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'import_support.dart';

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://localhost:0');
  @override
  Future<Map<String, dynamic>> vendorToolsOptions() async => importToolsOn;
  @override
  Future<Map<String, dynamic>> vendorImports({
    int limit = 50,
    String? cursor,
  }) async => {'batches': <Object>[], 'nextCursor': null};
  @override
  Future<Map<String, dynamic>> vendorImport(String id) async => {
    'batch': batchJson(id),
    'columns': <Object>[],
  };
  @override
  Future<Map<String, dynamic>> vendorImportPreview(
    String id, {
    String? applyState,
    int limit = 20,
    String? cursor,
  }) async => {'rows': <Object>[], 'nextCursor': null};
  @override
  Future<List<dynamic>> vendorProducts() async => const [];
  @override
  Future<List<dynamic>> vendorOrders() async => const [];
  @override
  Future<Map<String, dynamic>> vendorProfile() async => {'status': 'draft'};
  @override
  Future<Map<String, dynamic>> vendorPayments() async => const {};
  @override
  Future<List<dynamic>> vendorEnquiries({String? search}) async => const [];
  @override
  Future<List<dynamic>> vendorStaff() async => const [];
  @override
  Future<Map<String, dynamic>> me() async => throw ApiException(500, null);
  @override
  Future<Map<String, dynamic>> myTerms({String? lang, String? role}) async =>
      throw ApiException(500, null);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the address pattern matches only what the server issues', () {
    for (final ok in [
      '/vendor/import',
      '/vendor/import/new',
      '/vendor/import/vib_AbC-123',
    ]) {
      expect(vendorImportPath.hasMatch(ok), isTrue, reason: ok);
    }
    for (final bad in [
      '/vendor/imports',
      '/vendor/import/',
      '/vendor/import/a/b',
      '/vendor/import/has space',
      '/vendor/import/${'x' * 65}',
      '/vendor/importer',
    ]) {
      expect(vendorImportPath.hasMatch(bad), isFalse, reason: bad);
    }
    expect(importIdPattern.hasMatch('vib_1'), isTrue);
    expect(importIdPattern.hasMatch('a b'), isFalse);
    expect(vendorImportBatchRoute('vib_1'), '/vendor/import/vib_1');
    expect(vendorImportBatchRoute('a/b'), '/vendor/import/a%2Fb');
  });

  testWidgets('who reaches the import pages while pending', (tester) async {
    Future<String> landing(String userType, String to) async {
      final api = _Api();
      final auth = AuthState(api);
      await auth.signIn('token', {
        'id': 'u1',
        'userType': userType,
        'approvalStatus': 'pending_approval',
        if (userType == 'vendor') 'displayName': 'V',
      });
      final router = buildRouter(auth);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        AppScope(
          api: api,
          auth: auth,
          child: ThemeScope(
            notifier: ThemeNotifier(),
            child: FFLocaleScope(
              notifier: FFLocale(),
              child: MaterialApp.router(
                theme: buildTheme(),
                routerConfig: router,
              ),
            ),
          ),
        ),
      );
      router.go(to);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      final location = router.state.matchedLocation;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
      return location;
    }

    expect(await landing('vendor', '/vendor/import'), '/vendor/import');
    expect(await landing('vendor', '/vendor/import/new'), '/vendor/import/new');
    expect(
      await landing('vendor', '/vendor/import/vib_1'),
      '/vendor/import/vib_1',
    );
    // Not for a pending member.
    expect(await landing('member', '/vendor/import'), AppRoutes.pending);
  });
}
