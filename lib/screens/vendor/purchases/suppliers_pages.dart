// Vendor tools · S9: suppliers (spec §4.6–§4.7) — the list (search,
// filters, sort, load more), the form (add / edit; 409 duplicate_supplier
// links to the existing one) and the profile (owed, aging, open
// instalments, deliveries; Receive stock from them, Edit, Archive /
// Restore). Every page passes the purchases gate itself.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../customers/customer_models.dart' show eatTodayString, formatDay;
import '../sales/sale_models.dart' show pluralKey;
import '../customers/customers_widgets.dart' show AgingTiles, overdueBadge;
import '../stock/stock_options.dart';
import 'purchase_models.dart';
import 'purchases_widgets.dart';

/// How "Call" opens the dialler. Replaceable in tests.
@visibleForTesting
Future<bool> Function(Uri uri) supplierLaunch = (uri) => launchUrl(uri);

const supplierFilters = ['active', 'owing', 'overdue', 'archived'];
const supplierSorts = ['name', 'owed', 'recent'];

String supplierFilterKey(String f) => switch (f) {
  'owing' => 'vendor.suppliers.filter.owing',
  'overdue' => 'vendor.suppliers.filter.overdue',
  'archived' => 'vendor.suppliers.filter.archived',
  _ => 'vendor.suppliers.filter.all',
};

// ── list ─────────────────────────────────────────────────────────────────

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key});

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  final _q = TextEditingController();
  String _filter = 'active';
  String _sort = 'name';
  List<Map<String, dynamic>> _rows = [];
  String? _cursor;
  bool _ready = false;
  bool _loading = true;
  bool _more = false;
  Object? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await enterPurchasesRoute(context) == null || !mounted) return;
      setState(() => _ready = true);
      await _load();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      if (more) {
        _more = true;
      } else {
        _loading = true;
      }
      _error = null;
    });
    try {
      final res = await AppScope.of(context).api.vendorSuppliers(
        q: _q.text,
        filter: _filter,
        sort: _sort,
        cursor: more ? _cursor : null,
      );
      if (!mounted) return;
      setState(() {
        final rows = mapsOf(res['suppliers']);
        _rows = more ? [..._rows, ...rows] : rows;
        _cursor = strOf(res['nextCursor']);
        _loading = false;
        _more = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
          _more = false;
        });
      }
    }
  }

  Future<void> _open(String path) async {
    await context.push(path);
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('vendor.suppliers.title')),
        actions: [
          PopupMenuButton<String>(
            key: const Key('suppliers-sort'),
            tooltip: t('vendor.customers.sort'),
            icon: const Icon(Icons.sort),
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
            onSelected: (v) {
              setState(() => _sort = v);
              _load();
            },
            itemBuilder: (_) => [
              for (final s in supplierSorts)
                CheckedPopupMenuItem(
                  value: s,
                  checked: _sort == s,
                  child: Text(t('vendor.suppliers.sort.$s')),
                ),
            ],
          ),
        ],
      ),
      floatingActionButton: !_ready
          ? null
          : FloatingActionButton.extended(
              key: const Key('suppliers-add'),
              onPressed: () => _open(newSupplierRoute),
              icon: const Icon(Icons.add),
              label: Text(t('vendor.suppliers.add')),
            ),
      body: !_ready
          ? const Center(child: FFSpinner())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  FFTokens.spacingLg,
                  FFTokens.spacingLg,
                  FFTokens.spacingLg,
                  96,
                ),
                children: [
                  FFTextField(
                    key: const Key('suppliers-search'),
                    controller: _q,
                    label: t('vendor.suppliers.search'),
                    prefixIcon: const Icon(Icons.search),
                    onChanged: (_) {
                      _debounce?.cancel();
                      _debounce = Timer(
                        const Duration(milliseconds: 300),
                        _load,
                      );
                    },
                  ),
                  const SizedBox(height: FFTokens.spacingSm),
                  Wrap(
                    spacing: FFTokens.spacingXs,
                    runSpacing: FFTokens.spacingXs,
                    children: [
                      for (final f in supplierFilters)
                        Semantics(
                          selected: _filter == f,
                          inMutuallyExclusiveGroup: true,
                          child: FFPill(
                            key: Key('suppliers-filter-$f'),
                            label: t(supplierFilterKey(f)),
                            filled: _filter == f,
                            onTap: () {
                              setState(() => _filter = f);
                              _load();
                            },
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: FFTokens.spacingMd),
                  if (_loading)
                    FFSkeletonList(semanticLabel: t('vendor.suppliers.loading'))
                  else if (_error != null)
                    FFErrorState(
                      message: t(
                        _error is ApiException &&
                                purchaseLoadErrorKey(_error!) ==
                                    'vendor.purchases.failed'
                            ? 'vendor.suppliers.failed'
                            : purchaseLoadErrorKey(_error!),
                      ),
                      onRetry: _load,
                    )
                  else if (_rows.isEmpty)
                    _filter == 'active' && _q.text.trim().isEmpty
                        ? FFEmptyState(
                            key: const Key('suppliers-empty'),
                            title: t('vendor.suppliers.empty'),
                            icon: Icons.local_shipping_outlined,
                            action: FFButton(
                              label: t('vendor.suppliers.add'),
                              onPressed: () => _open(newSupplierRoute),
                            ),
                          )
                        : FFEmptyState(
                            key: const Key('suppliers-empty-filter'),
                            title: t('vendor.suppliers.emptyFilter'),
                          )
                  else ...[
                    FFCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (final s in _rows)
                            SupplierRowTile(
                              row: s,
                              onTap: purchaseIdPattern.hasMatch('${s['id']}')
                                  ? () => _open(supplierRoute('${s['id']}'))
                                  : null,
                            ),
                        ],
                      ),
                    ),
                    if (_cursor != null)
                      Center(
                        child: FFButton(
                          key: const Key('suppliers-more'),
                          label: t('vendor.stock.loadMore'),
                          variant: FFButtonVariant.ghost,
                          loading: _more,
                          onPressed: () => _load(more: true),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}

class SupplierRowTile extends StatelessWidget {
  const SupplierRowTile({super.key, required this.row, this.onTap});
  final Map<String, dynamic> row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final theme = Theme.of(context);
    final name = row['name']?.toString() ?? '';
    final owed = intOfP(row['owedTzs']);
    final overdue = intOfP(row['overdueTzs']);
    final contact = strOf(row['contactPerson']) ?? strOf(row['phone']);
    final owes = owed > 0
        ? fillIn(t('vendor.suppliers.youOwe'), {'amount': formatCurrency(owed)})
        : t('vendor.payables.nothingOwed');
    final overdueText = overdue > 0
        ? fillIn(t('vendor.purchases.overdueAmount'), {
            'amount': formatCurrency(overdue),
          })
        : '';
    return Semantics(
      container: true,
      button: onTap != null,
      onTap: onTap,
      label: fillIn(t('vendor.suppliers.rowLabel'), {
        'name': name,
        'amount': formatCurrency(owed),
        'overdue': overdueText,
      }),
      excludeSemantics: true,
      child: InkWell(
        key: Key('supplier-row-${row['id']}'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FFTokens.spacingMd,
              vertical: FFTokens.spacingSm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: theme.textTheme.titleSmall),
                      if (contact != null)
                        Text(contact, style: theme.textTheme.bodySmall),
                      Text(owes, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                if (overdue > 0)
                  Flexible(child: overdueBadge(context, label: overdueText)),
                if (row['archived'] == true)
                  FFBadge(label: t('vendor.suppliers.archivedBadge')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── form ─────────────────────────────────────────────────────────────────

class SupplierFormPage extends StatefulWidget {
  const SupplierFormPage({super.key, this.supplierId});
  final String? supplierId;

  @override
  State<SupplierFormPage> createState() => _SupplierFormPageState();
}

class _SupplierFormPageState extends State<SupplierFormPage> {
  /// UAT L-6: the last try got no answer: the button says Try again.
  bool _netFailed = false;

  static const _fields = [
    'name',
    'phone',
    'contactPerson',
    'email',
    'address',
    'tin',
    'note',
  ];
  final Map<String, TextEditingController> _c = {
    for (final f in _fields) f: TextEditingController(),
  };
  Map<String, dynamic> _original = {};
  bool _ready = false;
  bool _saving = false;
  bool _edited = false;
  final Map<String, String> _errors = {};
  String? _problem;
  String? _duplicateId;

  /// The existing supplier's own name (UAT L-4), for the message and link.
  String? _duplicateName;

  bool get _editing => widget.supplierId != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _start() async {
    if (await enterPurchasesRoute(context) == null || !mounted) return;
    if (_editing) {
      try {
        final res = await AppScope.of(
          context,
        ).api.vendorSupplier(widget.supplierId!);
        _original = mapOf(res['supplier']);
        for (final f in _fields) {
          _c[f]!.text = _original[f]?.toString() ?? '';
        }
      } catch (_) {
        if (mounted) _problem = context.tr('vendor.suppliers.failed');
      }
    }
    if (mounted) setState(() => _ready = true);
  }

  bool _check() {
    final t = context.tr;
    _errors.clear();
    final name = _c['name']!.text.trim();
    if (name.length < supplierNameMin || name.length > supplierNameMax) {
      _errors['name'] = t('vendor.suppliers.nameRequired');
    }
    final email = _c['email']!.text.trim();
    if (email.isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      _errors['email'] = t('vendor.suppliers.invalidEmail');
    }
    for (final e in supplierFieldMax.entries) {
      if (e.key == 'email') continue;
      if (_c[e.key]!.text.trim().length > e.value) {
        _errors[e.key] = fillIn(t('vendor.suppliers.tooLong'), {
          'max': e.value,
        });
      }
    }
    return _errors.isEmpty;
  }

  Map<String, dynamic> _body() {
    final body = <String, dynamic>{};
    for (final f in _fields) {
      final v = _c[f]!.text.trim();
      if (_editing) {
        final before = _original[f]?.toString() ?? '';
        if (v != before) body[f] = v.isEmpty && f != 'name' ? null : v;
      } else if (v.isNotEmpty) {
        body[f] = v;
      }
    }
    return body;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _problem = null;
      _duplicateId = null;
      _netFailed = false;
    });
    if (!_check()) {
      setState(() {});
      return;
    }
    final body = _body();
    if (_editing && body.isEmpty) {
      context.pop();
      return;
    }
    setState(() => _saving = true);
    final api = AppScope.of(context).api;
    try {
      final res = _editing
          ? await api.vendorUpdateSupplier(widget.supplierId!, body)
          : await api.vendorCreateSupplier(body);
      if (!mounted) return;
      final s = mapOf(res['supplier']);
      FFSnack.success(context, context.tr('vendor.suppliers.saved'));
      _edited = false;
      if (_editing || !purchaseIdPattern.hasMatch('${s['id']}')) {
        context.pop(s);
      } else {
        context.pushReplacement(supplierRoute('${s['id']}'));
      }
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      final b = e.body is Map ? e.body as Map : const {};
      final t = context.tr;
      switch (e.code) {
        case 'duplicate_supplier':
          final dup = duplicateSupplierOf(b, typedName: _c['name']!.text);
          _errors['name'] = fillIn(
            t('vendor.purchases.err.duplicateSupplier'),
            {'name': dup.name},
          );
          _duplicateId = dup.id;
          _duplicateName = dup.name;
        case 'name_required' || 'name_too_long':
          _errors['name'] = t('vendor.suppliers.nameRequired');
        case 'invalid_phone':
          _errors['phone'] = t('vendor.suppliers.invalidPhone');
        case 'invalid_email':
          _errors['email'] = t('vendor.suppliers.invalidEmail');
        case 'field_too_long':
          final f = b['field']?.toString() ?? '';
          if (_c.containsKey(f)) {
            _errors[f] = fillIn(t('vendor.suppliers.tooLong'), {
              'max': intOfP(b['max']),
            });
          } else {
            _problem = purchaseErrorText(t, e, where: 'supplier');
          }
        default:
          _problem = purchaseErrorText(t, e, where: 'supplier');
      }
    } catch (_) {
      if (mounted) {
        _problem = context.tr('vendor.purchases.offlineWrite');
        _netFailed = true;
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _leave() async {
    if (!_edited) return _pop();
    final ok = await showFFConfirmDialog(
      context,
      title: context.tr('vendor.customers.discardTitle'),
      confirmLabel: context.tr('vendor.purchases.discard'),
      destructive: true,
    );
    if (ok && mounted) _pop();
  }

  void _pop() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(suppliersRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    String label(String f) => t('vendor.suppliers.$f');
    return PopScope(
      canPop: !_edited && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _leave),
          title: Text(
            t(_editing ? 'vendor.suppliers.editTitle' : 'vendor.suppliers.add'),
          ),
        ),
        body: !_ready
            ? const Center(child: FFSpinner())
            : ListView(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                children: [
                  for (final f in _fields) ...[
                    FFTextField(
                      key: Key('supplier-form-$f'),
                      controller: _c[f],
                      label: label(f),
                      helperText: f == 'phone'
                          ? t('vendor.suppliers.phoneHelp')
                          : null,
                      keyboardType: switch (f) {
                        'phone' => TextInputType.phone,
                        'email' => TextInputType.emailAddress,
                        _ => null,
                      },
                      maxLength: f == 'name'
                          ? supplierNameMax
                          : supplierFieldMax[f],
                      maxLines: f == 'note' || f == 'address' ? 3 : 1,
                      minLines: 1,
                      errorText: _errors[f],
                      enabled: !_saving,
                      onChanged: (_) => setState(() {
                        _edited = true;
                        _errors.remove(f);
                      }),
                    ),
                    if (f == 'name' && _duplicateId != null)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: FFButton(
                          key: const Key('supplier-form-open-duplicate'),
                          label: fillIn(t('vendor.suppliers.open'), {
                            'name': _duplicateName ?? _c['name']!.text.trim(),
                          }),
                          variant: FFButtonVariant.ghost,
                          visualDensity: VisualDensity.standard,
                          onPressed: purchaseIdPattern.hasMatch(_duplicateId!)
                              ? () => context.pushReplacement(
                                  supplierRoute(_duplicateId!),
                                )
                              : null,
                        ),
                      ),
                    const SizedBox(height: FFTokens.spacingSm),
                  ],
                  if (_problem != null)
                    Semantics(
                      liveRegion: true,
                      child: FFAlert(
                        key: const Key('supplier-form-problem'),
                        message: _problem!,
                        tone: FFAlertTone.error,
                      ),
                    ),
                  const SizedBox(height: FFTokens.spacingMd),
                  FFButton(
                    key: const Key('supplier-form-save'),
                    label: _netFailed
                        ? t('common.retry')
                        : t('vendor.suppliers.save'),
                    fullWidth: true,
                    loading: _saving,
                    onPressed: _save,
                  ),
                ],
              ),
      ),
    );
  }
}

// ── profile ──────────────────────────────────────────────────────────────

class SupplierProfilePage extends StatefulWidget {
  const SupplierProfilePage({super.key, required this.supplierId});
  final String supplierId;

  @override
  State<SupplierProfilePage> createState() => _SupplierProfilePageState();
}

class _SupplierProfilePageState extends State<SupplierProfilePage> {
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _purchases = [];
  String? _cursor;
  bool _ready = false;
  bool _loading = true;
  bool _notFound = false;
  bool _failed = false;
  bool _busy = false;
  final _heading = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await enterPurchasesRoute(context) == null || !mounted) return;
      setState(() => _ready = true);
      await _load();
      if (mounted) _heading.requestFocus();
    });
  }

  @override
  void dispose() {
    _heading.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final api = AppScope.of(context).api;
    try {
      final res = await api.vendorSupplier(widget.supplierId);
      Map<String, dynamic> list = const {};
      try {
        list = await api.vendorPurchases(
          supplierId: widget.supplierId,
          limit: 20,
        );
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _data = res;
        _purchases = mapsOf(list['purchases']);
        _cursor = strOf(list['nextCursor']);
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _notFound = e.status == 404;
        _failed = !_notFound;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _morePurchases() async {
    try {
      final list = await AppScope.of(context).api.vendorPurchases(
        supplierId: widget.supplierId,
        limit: 20,
        cursor: _cursor,
      );
      if (!mounted) return;
      setState(() {
        _purchases = [..._purchases, ...mapsOf(list['purchases'])];
        _cursor = strOf(list['nextCursor']);
      });
    } catch (_) {
      if (mounted) FFSnack.error(context, context.tr('error.network'));
    }
  }

  Future<void> _archive(bool archived) async {
    setState(() => _busy = true);
    try {
      await AppScope.of(
        context,
      ).api.vendorUpdateSupplier(widget.supplierId, {'archived': archived});
      if (!mounted) return;
      FFSnack.success(
        context,
        context.tr(
          archived
              ? 'vendor.suppliers.archivedDone'
              : 'vendor.suppliers.restoredDone',
        ),
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        FFSnack.error(
          context,
          purchaseErrorText(
            context.tr,
            e,
            where: 'supplier',
            name: _data?['supplier']?['name']?.toString(),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        FFSnack.error(context, context.tr('vendor.purchases.offlineWrite'));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _go(String path) async {
    await context.push(path);
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final d = _data;
    final s = mapOf(d?['supplier']);
    final archived = s['archivedAt'] != null || s['archived'] == true;
    final owed = intOfP(d?['owedTzs']);
    final name = s['name']?.toString() ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(name.isEmpty ? t('vendor.suppliers.title') : name),
        actions: [
          if (d != null)
            PopupMenuButton<String>(
              key: const Key('supplier-more'),
              tooltip: t('vendor.purchases.more'),
              style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
              onSelected: (v) {
                if (v == 'edit') _go(editSupplierRoute(widget.supplierId));
                if (v == 'archive') _archive(true);
                if (v == 'restore') _archive(false);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  key: const Key('supplier-edit'),
                  value: 'edit',
                  child: Text(t('vendor.edit')),
                ),
                if (archived)
                  PopupMenuItem(
                    key: const Key('supplier-restore'),
                    value: 'restore',
                    child: Text(t('vendor.suppliers.restore')),
                  )
                else
                  PopupMenuItem(
                    key: const Key('supplier-archive'),
                    value: 'archive',
                    enabled: owed == 0 && !_busy,
                    child: Text(t('vendor.suppliers.archive')),
                  ),
              ],
            ),
        ],
      ),
      body: !_ready || (_loading && d == null)
          ? const Center(child: FFSpinner())
          : d == null
          ? ListView(
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              children: [
                if (_notFound)
                  FFEmptyState(
                    key: const Key('supplier-not-found'),
                    title: t('vendor.suppliers.notFound'),
                  )
                else if (_failed)
                  FFErrorState(message: t('error.network'), onRetry: _load),
              ],
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                children: _content(d, s, archived, owed),
              ),
            ),
    );
  }

  List<Widget> _content(
    Map<String, dynamic> d,
    Map<String, dynamic> s,
    bool archived,
    int owed,
  ) {
    final t = context.tr;
    final theme = Theme.of(context);
    final lang = langOf(context);
    final name = s['name']?.toString() ?? '';
    final phone = strOf(s['phone']);
    final totals = mapOf(d['totals']);
    return [
      Focus(
        focusNode: _heading,
        child: Semantics(
          header: true,
          child: Text(name, style: theme.textTheme.titleLarge),
        ),
      ),
      for (final f in ['contactPerson', 'email', 'address', 'tin', 'note'])
        if (strOf(s[f]) case final v?)
          Text(f == 'tin' ? 'TIN $v' : v, style: theme.textTheme.bodyMedium),
      if (phone != null)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FFButton(
            key: const Key('supplier-call'),
            label: phone,
            semanticLabel: fillIn(t('vendor.suppliers.call'), {'name': name}),
            icon: Icons.call_outlined,
            variant: FFButtonVariant.ghost,
            visualDensity: VisualDensity.standard,
            onPressed: () => supplierLaunch(Uri(scheme: 'tel', path: phone)),
          ),
        ),
      if (archived) ...[
        const SizedBox(height: FFTokens.spacingSm),
        FFAlert(
          key: const Key('supplier-archived'),
          message: t('vendor.suppliers.archived'),
        ),
      ],
      const SizedBox(height: FFTokens.spacingMd),
      if (!archived)
        FFButton(
          key: const Key('supplier-receive'),
          label: fillIn(t('vendor.purchases.receiveFrom'), {'name': name}),
          icon: Icons.local_shipping_outlined,
          fullWidth: true,
          maxLines: 2,
          onPressed: () => _go(receiveFromRoute(widget.supplierId)),
        ),
      if (!archived && owed > 0)
        Padding(
          padding: const EdgeInsets.only(top: FFTokens.spacingXs),
          child: Text(
            fillIn(t('vendor.suppliers.archiveOwes'), {
              'amount': formatCurrency(owed),
            }),
            key: const Key('supplier-archive-owes'),
            style: theme.textTheme.bodySmall,
          ),
        ),
      const SizedBox(height: FFTokens.spacingMd),
      FFCard(
        key: const Key('supplier-owed'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              owed > 0
                  ? fillIn(t('vendor.suppliers.youOwe'), {
                      'amount': formatCurrency(owed),
                    })
                  : t('vendor.payables.nothingOwed'),
              style: theme.textTheme.titleMedium,
            ),
            if (intOfP(d['overdueTzs']) > 0)
              Text(
                fillIn(t('vendor.purchases.overdueAmount'), {
                  'amount': formatCurrency(intOfP(d['overdueTzs'])),
                }),
              ),
            const SizedBox(height: FFTokens.spacingSm),
            AgingTiles(aging: mapOf(d['aging']), keyPrefix: 'supplier-aging'),
            const SizedBox(height: FFTokens.spacingXs),
            Text(
              fillIn(t('vendor.customers.asOf'), {
                'date': formatDay(d['asOf']?.toString(), locale: lang),
              }),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      if (mapsOf(d['openInstalments']).isNotEmpty) ...[
        const SizedBox(height: FFTokens.spacingMd),
        FFSectionTitle(t('vendor.suppliers.openInstalments')),
        FFCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final i in mapsOf(d['openInstalments']))
                ListTile(
                  key: Key('supplier-open-${i['purchaseId']}-${i['seq']}'),
                  minTileHeight: 56,
                  title: Text(
                    '${i['number']} · ${fillIn(t('vendor.purchases.instalmentN'), {'n': i['seq']})}',
                  ),
                  subtitle: Text(
                    '${formatDay(i['dueDate']?.toString(), locale: lang)} · ${formatCurrency(intOfP(i['openTzs']))}',
                  ),
                  trailing: intOfP(i['daysOverdue']) > 0
                      ? overdueBadge(
                          context,
                          label: fillIn(
                            t(
                              pluralKey(
                                'vendor.purchases.inst.overdue',
                                intOfP(i['daysOverdue']),
                              ),
                            ),
                            {'n': intOfP(i['daysOverdue'])},
                          ),
                        )
                      // UAT L-2: "Due in N days" as on the purchase detail.
                      : Text(
                          dueText(
                            t,
                            '${i['dueDate']}',
                            d['asOf']?.toString() ?? eatTodayString(),
                          ),
                          key: Key(
                            'supplier-open-due-${i['purchaseId']}-${i['seq']}',
                          ),
                          style: theme.textTheme.bodySmall,
                        ),
                  onTap: purchaseIdPattern.hasMatch('${i['purchaseId']}')
                      ? () => _go(purchaseRoute('${i['purchaseId']}'))
                      : null,
                ),
            ],
          ),
        ),
      ],
      const SizedBox(height: FFTokens.spacingMd),
      FFSectionTitle(t('vendor.purchases.listTitle')),
      Text(
        fillIn(
          t(
            pluralKey(
              'vendor.suppliers.bought',
              intOfP(totals['purchaseCount']),
            ),
          ),
          {
            'amount': formatCurrency(intOfP(totals['purchasedTzs'])),
            'n': intOfP(totals['purchaseCount']),
            'paid': formatCurrency(intOfP(totals['paidTzs'])),
          },
        ),
        key: const Key('supplier-bought'),
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: FFTokens.spacingXs),
      if (_purchases.isEmpty)
        FFEmptyState(title: t('vendor.purchases.empty'))
      else
        FFCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final p in _purchases)
                PurchaseRowTile(
                  row: p,
                  onTap: purchaseIdPattern.hasMatch('${p['id']}')
                      ? () => _go(purchaseRoute('${p['id']}'))
                      : null,
                ),
            ],
          ),
        ),
      if (_cursor != null)
        Center(
          child: FFButton(
            label: t('vendor.stock.loadMore'),
            variant: FFButtonVariant.ghost,
            onPressed: _morePurchases,
          ),
        ),
      const SizedBox(height: FFTokens.spacingLg),
    ];
  }
}

/// Tests: the stored canVendor answer for `purchases` (re-exported for the
/// home page).
bool canPurchases(BuildContext context) => canVendor(context, 'purchases');
