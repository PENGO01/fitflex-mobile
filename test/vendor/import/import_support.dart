// Shared seeds for the vendor smart import tests (V3). Nothing here talks to
// a real server: every answer comes from the RecordingApi fake at
// http://fixtures.local.
import 'dart:typed_data';

import 'package:fitflexmobile/screens/vendor/documents/document_share_sheet.dart'
    show DocumentActions;
import 'package:fitflexmobile/screens/vendor/import/import_batch_page.dart';
import 'package:fitflexmobile/screens/vendor/import/import_history_page.dart';
import 'package:fitflexmobile/screens/vendor/import/import_new_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/recording_api.dart';

const importToolsOn = {
  'import': true,
  'importLimits': {'maxBytes': 2097152, 'maxRows': 2000},
};
const importToolsOff = {'import': false};

const ownerUser = {'id': 'v1', 'userType': 'vendor', 'displayName': 'Owner'};

Map<String, dynamic> staffUser(List<String> perms) => {
  'id': 's1',
  'userType': 'vendor_staff',
  'vendorId': 'v1',
  'vendorRole': 'admin',
  'displayName': 'Asha',
  'vendorPermissions': perms,
};

Map<String, int> counts({
  int total = 10,
  int valid = 7,
  int needsReview = 2,
  int invalid = 1,
  int pending = 10,
  int applied = 0,
  int failed = 0,
  int skipped = 0,
}) => {
  'total': total,
  'valid': valid,
  'needs_review': needsReview,
  'invalid': invalid,
  'pending': pending,
  'applied': applied,
  'failed': failed,
  'skipped': skipped,
};

Map<String, dynamic> batchJson(
  String id, {
  String entity = 'products',
  String status = 'ready',
  Map<String, int>? counts_,
  bool? include,
  String filename = 'products.csv',
  String createdAt = '2026-11-03T09:00:00Z',
}) => {
  'id': id,
  'entity': entity,
  'status': status,
  'filename': filename,
  'sizeBytes': 2048,
  'templateVersion': 'v1',
  'delimiter': ',',
  'counts': counts_ ?? counts(),
  'createdBy': 'v1',
  'includeNeedsReview': include,
  'needsConfirmation': status == 'mapping_required',
  'missingRequired': <String>[],
  'createdAt': createdAt,
  'updatedAt': createdAt,
  'applyStartedAt': null,
  'finishedAt': null,
};

Map<String, dynamic> columnJson(
  String source,
  String? field,
  String match, {
  List<String> sample = const [],
}) => {
  'source': source,
  'field': field,
  'match': match,
  'confirmed': false,
  'sample': sample,
};

Map<String, dynamic> rowJson(
  String id,
  int rowNo, {
  String status = 'invalid',
  String applyState = 'pending',
  String? name,
  String? en,
  String? sw,
  Map<String, dynamic>? lastError,
}) => {
  'id': id,
  'rowNo': rowNo,
  'status': status,
  'applyState': applyState,
  'issues': [
    if (en != null)
      {
        'code': 'price_invalid',
        'field': 'price_tzs',
        'severity': status == 'needs_review' ? 'warning' : 'error',
        'params': {},
        'message': {'en': en, 'sw': sw ?? 'SW $en'},
      },
  ],
  'values': {'name': ?name},
  'resultId': null,
  'lastError': lastError,
  'attempts': 0,
};

Map<String, dynamic> previewJson(
  Map<String, dynamic> batch,
  List<Map<String, dynamic>> rows, {
  String? next,
}) => {
  'batch': batch,
  'counts': batch['counts'],
  'rows': rows,
  'nextCursor': next,
};

Map<String, dynamic> applyJson(
  Map<String, dynamic> batch, {
  int processed = 0,
  int remaining = 0,
}) => {'batch': batch, 'processed': processed, 'remaining': remaining};

/// Routes the import pages can navigate to.
List<RouteBase> importRoutes() => [
  GoRoute(
    path: '/vendor/home',
    builder: (_, _) => const Scaffold(body: Text('ROUTE-VENDOR-HOME')),
  ),
  GoRoute(
    path: '/vendor/import',
    builder: (_, _) => const Scaffold(body: Text('ROUTE-IMPORT-LIST')),
    routes: [
      GoRoute(
        path: 'new',
        builder: (_, _) => const Scaffold(body: Text('ROUTE-IMPORT-NEW')),
      ),
      GoRoute(
        path: ':id',
        builder: (_, state) => Scaffold(
          body: Text('ROUTE-IMPORT-BATCH ${state.pathParameters['id']}'),
        ),
      ),
    ],
  ),
];

Future<PageHost> pumpHistory(
  WidgetTester tester,
  RecordingApi api, {
  Map<String, dynamic> user = ownerUser,
  String lang = 'en',
  Size size = const Size(360, 800),
  double textScale = 1.0,
}) => pumpPage(
  tester,
  api,
  const ImportHistoryPage(),
  user: user,
  lang: lang,
  size: size,
  textScale: textScale,
  extraRoutes: importRoutes(),
);

Future<PageHost> pumpNew(
  WidgetTester tester,
  RecordingApi api, {
  Map<String, dynamic> user = ownerUser,
  String lang = 'en',
  Size size = const Size(360, 900),
  double textScale = 1.0,
  PickImportFile? pick,
}) => pumpPage(
  tester,
  api,
  ImportNewPage(pickFile: pick),
  user: user,
  lang: lang,
  size: size,
  textScale: textScale,
  extraRoutes: importRoutes(),
);

Future<PageHost> pumpBatch(
  WidgetTester tester,
  RecordingApi api, {
  String id = 'vib_1',
  Map<String, dynamic> user = ownerUser,
  String lang = 'en',
  Size size = const Size(360, 900),
  double textScale = 1.0,
}) => pumpPage(
  tester,
  api,
  ImportBatchPage(
    batchId: id,
    runConfig: ImportRunConfig(sleep: (_) async {}),
  ),
  user: user,
  lang: lang,
  size: size,
  textScale: textScale,
  extraRoutes: importRoutes(),
);

PickImportFile pickOf(
  String name,
  String content, {
  int? size,
  List<int>? bytes,
}) => () async {
  final data = Uint8List.fromList(bytes ?? content.codeUnits);
  return PickedImportFile(
    name: name,
    size: size ?? data.length,
    read: () async => data,
  );
};

/// What was handed to the share sheet / the browser download.
class Delivered {
  Delivered(this.name, this.bytes, this.mime);
  final String name;
  final Uint8List bytes;
  final String mime;
  String get text => String.fromCharCodes(bytes);
}

/// Replaces [DocumentActions] for one test; restores them on tear-down.
List<Delivered> captureDeliveries({required bool web}) {
  final out = <Delivered>[];
  final oldWeb = DocumentActions.isWeb;
  final oldDownload = DocumentActions.download;
  final oldShare = DocumentActions.shareTypedFile;
  DocumentActions.isWeb = () => web;
  DocumentActions.download = (b, n, m) async => out.add(Delivered(n, b, m));
  DocumentActions.shareTypedFile = (b, n, m) async =>
      out.add(Delivered(n, b, m));
  addTearDown(() {
    DocumentActions.isWeb = oldWeb;
    DocumentActions.download = oldDownload;
    DocumentActions.shareTypedFile = oldShare;
  });
  return out;
}
