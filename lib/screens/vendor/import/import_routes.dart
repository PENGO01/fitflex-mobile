// Vendor smart import V3: the addresses and the route table. The router
// adds [vendorImportRoutes] next to the other vendor sub-pages and lets a
// vendor who is still waiting for approval reach them ([vendorImportPath]),
// as for their other own records.
import 'package:flutter/widgets.dart' show ValueKey;
import 'package:go_router/go_router.dart';

import 'import_batch_page.dart';
import 'import_history_page.dart';
import 'import_new_page.dart';

const vendorImportRoute = '/vendor/import';
const vendorImportNewRoute = '/vendor/import/new';

String vendorImportBatchRoute(String id) =>
    '$vendorImportRoute/${Uri.encodeComponent(id)}';

/// Ids in import addresses: the characters the server issues (`vib_...`).
final importIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// Every import address, for the pending-vendor rule.
final vendorImportPath = RegExp(
  r'^/vendor/import(/(new|[A-Za-z0-9_-]{1,64}))?$',
);

GoRoute vendorImportRoutes() => GoRoute(
  path: vendorImportRoute,
  name: 'vendorImport',
  builder: (context, state) => const ImportHistoryPage(),
  routes: [
    GoRoute(
      path: 'new',
      name: 'vendorImportNew',
      builder: (context, state) => const ImportNewPage(),
    ),
    GoRoute(
      path: ':id',
      name: 'vendorImportBatch',
      redirect: (context, state) =>
          importIdPattern.hasMatch(state.pathParameters['id'] ?? '')
          ? null
          : vendorImportRoute,
      builder: (context, state) => ImportBatchPage(
        key: ValueKey('import-${state.pathParameters['id']}'),
        batchId: state.pathParameters['id']!,
      ),
    ),
  ],
);
