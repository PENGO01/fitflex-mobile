// Vendor tools · sale extras #2 (docs/design/vendor-sale-extras-1110.md §2):
// the optional Customer section of the payment sheet — customer type, and
// a name and mobile that become a link to a vendor customer.
//
// Privacy (§2.7, Q-7, security review of functions#341): the typed name and
// mobile live in this controller's memory only. They are turned into a
// customer id (match, or POST /vendor/customers) BEFORE the sale is sent;
// the sale body, the draft cart and the offline queue never hold them. With
// no connection they are hidden and nothing typed is kept.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../customers/customer_models.dart';
import '../stock/stock_options.dart' show fillIn;
import 'sale_models.dart';

/// What the section needs from the POS. Every customer change goes through
/// the cart (one source: `PosCart.customerId`), so the chip and the
/// section always agree.
class SaleCustomerSetup {
  const SaleCustomerSetup({
    required this.namesAllowed,
    required this.online,
    required this.customer,
    required this.type,
    required this.setType,
    required this.link,
    required this.unlink,
    required this.pickCustomer,
    required this.search,
    required this.create,
  });

  /// Customers are on (`tools.customers`): name and mobile may be used.
  final bool namesAllowed;

  /// The POS has a connection (its own signal and the browser's).
  final bool Function() online;

  /// The cart's customer right now.
  final ({String? id, String? name}) Function() customer;

  /// The cart's customer type, and setting it (kept in the draft).
  final String? Function() type;
  final void Function(String? type) setType;

  /// Links a customer to the cart (a search row: owed amounts when sent).
  final void Function(String id, String name, Map<String, dynamic> row) link;
  final VoidCallback unlink;

  /// Opens the S4 picker (updates the cart).
  final Future<void> Function() pickCustomer;

  /// GET /vendor/customers?q= — the rows.
  final Future<List<Map<String, dynamic>>> Function(String q) search;

  /// POST /vendor/customers — the answer.
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> body) create;
}

/// The rows of a mobile lookup that are this number: not archived, and the
/// full phone equal (people with `customers`) or, for sales-only staff (the
/// picker shape), the last 3 digits equal. A name that merely contains the
/// digits never counts.
List<Map<String, dynamic>> phoneMatches(
  List<Map<String, dynamic>> rows,
  String normalised,
) => [
  for (final r in rows)
    if (r['archived'] != true &&
        r['id'] != null &&
        (r['phone'] != null
            ? r['phone'].toString() == normalised
            : r['phoneLast3']?.toString() ==
                  normalised.substring(normalised.length - 3)))
      r,
];

/// A stable idempotency key per typed name + phone, so Try again replays
/// the same customer instead of making a second one.
class _Refs {
  final _byDetails = <String, String>{};
  String of(String name, String? phone) => _byDetails.putIfAbsent(
    '$name\u0000${phone ?? ''}',
    () => newCustomerClientRef('cus'),
  );
}

/// The section's state, owned by the payment sheet.
class SaleCustomerController extends ChangeNotifier {
  SaleCustomerController(
    this.setup, {
    this.lookupDelay = const Duration(milliseconds: 400),
  });

  final SaleCustomerSetup setup;
  final Duration lookupDelay;

  final name = TextEditingController();
  final mobile = TextEditingController();
  final nameFocus = FocusNode();
  final mobileFocus = FocusNode();
  final expandFocus = FocusNode();
  final firstPillFocus = FocusNode();

  bool expanded = false;

  /// i18n keys of the field errors.
  String? nameError;
  String? mobileError;

  /// A mobile lookup is running.
  bool looking = false;

  /// More than one customer has the typed number (no auto-link).
  int? manyMatches;

  /// The customer could not be saved: Try again or Complete without.
  bool saveFailed = false;

  /// The server said customers are off (404 feature_disabled).
  bool namesOff = false;

  final _refs = _Refs();
  Timer? _debounce;
  int _ask = 0;
  bool _disposed = false;

  bool get linked => setup.customer().id != null;

  /// Name and mobile are offered: customers on, not turned off, online.
  bool get namesShown => setup.namesAllowed && !namesOff && setup.online();

  /// Offline note: customers on but no connection.
  bool get showOffline => setup.namesAllowed && !namesOff && !setup.online();

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void toggle() {
    expanded = !expanded;
    _changed();
    // §6: expanding moves focus to the first pill; collapsing returns it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      (expanded ? firstPillFocus : expandFocus).requestFocus();
    });
  }

  void chooseType(String type) {
    // Tapping the chosen one again clears it.
    setup.setType(setup.type() == type ? null : type);
    _changed();
  }

  void nameChanged(String _) {
    nameError = null;
    saveFailed = false;
    _changed();
  }

  void mobileChanged(String _) {
    mobileError = null;
    manyMatches = null;
    saveFailed = false;
    _debounce?.cancel();
    _ask++;
    looking = false;
    if (normaliseTzPhone(mobile.text) != null) {
      _debounce = Timer(lookupDelay, () => unawaited(lookup()));
    }
    _changed();
  }

  /// Errors on leaving a field (§2.2).
  void nameBlurred() {
    final n = name.text.trim();
    if (n.isNotEmpty &&
        (n.length < customerNameMin || n.length > customerNameMax)) {
      nameError = 'vendor.pos.cust.nameLength';
      _changed();
    }
  }

  void mobileBlurred() {
    final m = mobile.text.trim();
    if (m.isNotEmpty && normaliseTzPhone(m) == null) {
      mobileError = 'vendor.customers.phoneInvalid';
      _changed();
    }
  }

  /// Looks the typed mobile up (the S4 picker search, 9 local digits). One
  /// live match links it; several show "choose one". Any failure: nothing
  /// (the lookup is optional).
  Future<void> lookup() async {
    final phone = normaliseTzPhone(mobile.text);
    if (phone == null || !namesShown || linked) return;
    final ask = ++_ask;
    looking = true;
    _changed();
    try {
      final rows = await setup.search(phone.substring(4));
      if (_disposed || ask != _ask) return;
      final found = phoneMatches(rows, phone);
      if (found.length == 1) {
        _linkMatch(found.single);
      } else if (found.length > 1) {
        manyMatches = found.length;
      }
    } catch (_) {
      // No answer or refused: create on Complete as usual.
    } finally {
      if (!_disposed && ask == _ask) {
        looking = false;
        _changed();
      }
    }
  }

  void _linkMatch(Map<String, dynamic> row) {
    final stored = row['name']?.toString().trim() ?? '';
    // The stored name wins; the typed one is dropped (§2.1).
    setup.link(row['id'].toString(), stored, row);
    if (setup.type() == null) setup.setType('returning');
    _clearTyped();
  }

  void _clearTyped() {
    _debounce?.cancel();
    _ask++;
    looking = false;
    name.clear();
    mobile.clear();
    nameError = null;
    mobileError = null;
    manyMatches = null;
  }

  /// "Remove {name} from this sale".
  void remove() {
    setup.unlink();
    _changed();
  }

  Future<void> search() async {
    await setup.pickCustomer();
    if (linked) _clearTyped();
    _changed();
  }

  /// "Complete without customer": keeps the type, drops name and mobile.
  void completeWithout() {
    _clearTyped();
    saveFailed = false;
    _changed();
  }

  /// Runs before the sale is sent (§2.5). True: send the sale (the cart has
  /// the customer's id, or none). False: stay — a field error (focus moved
  /// to it) or [saveFailed]. Nothing typed ever reaches the sale body.
  Future<bool> prepare() async {
    saveFailed = false;
    if (linked) {
      _clearTyped();
      return true;
    }
    if (!namesShown) {
      // Offline or customers off: never kept, never sent.
      _clearTyped();
      return true;
    }
    final n = name.text.trim();
    final m = mobile.text.trim();
    if (n.isEmpty && m.isEmpty) return true;
    final phone = m.isEmpty ? null : normaliseTzPhone(m);
    nameError = null;
    mobileError = null;
    if (m.isNotEmpty && phone == null) {
      mobileError = 'vendor.customers.phoneInvalid';
    }
    if (n.isEmpty && m.isNotEmpty) {
      nameError = 'vendor.pos.cust.nameNeeded';
    } else if (n.isNotEmpty &&
        (n.length < customerNameMin || n.length > customerNameMax)) {
      nameError = 'vendor.pos.cust.nameLength';
    }
    if (nameError != null || mobileError != null) {
      _focusFirstError();
      return false;
    }
    if (phone != null) {
      // Typed fast: look it up now (a match links it, no new customer).
      if (manyMatches == null) {
        _debounce?.cancel();
        await lookup();
        if (_disposed) return false;
        if (linked) return true;
      }
      if (manyMatches != null) {
        // Several customers have this number: the seller chooses one (or
        // clears the mobile). Never a third copy, never silently dropped.
        expanded = true;
        _changed();
        mobileFocus.requestFocus();
        return false;
      }
    }
    try {
      final res = await setup.create({
        'clientRef': _refs.of(n, phone),
        'name': n,
        'phone': ?phone,
      });
      if (_disposed) return false;
      final c = res['customer'];
      if (c is! Map || c['id'] == null) throw StateError('no customer');
      final stored = c['name']?.toString().trim();
      setup.link(
        c['id'].toString(),
        stored == null || stored.isEmpty ? n : stored,
        {...Map<String, dynamic>.from(c), 'owedTzs': 0, 'overdueTzs': 0},
      );
      if (setup.type() == null) setup.setType('new');
      _clearTyped();
      _changed();
      return true;
    } on ApiException catch (e) {
      if (_disposed) return false;
      switch (e.code) {
        case 'name_invalid':
          nameError = 'vendor.pos.cust.nameLength';
          _focusFirstError();
        case 'phone_invalid':
          mobileError = 'vendor.customers.phoneInvalid';
          _focusFirstError();
        case 'feature_disabled':
          // Customers went off: type only from now on.
          namesOff = true;
          _clearTyped();
          saveFailed = true;
          _changed();
        default:
          saveFailed = true;
          _changed();
      }
      return false;
    } catch (_) {
      if (_disposed) return false;
      saveFailed = true;
      _changed();
      return false;
    }
  }

  void _focusFirstError() {
    expanded = true;
    _changed();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      (nameError != null ? nameFocus : mobileFocus).requestFocus();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    name.dispose();
    mobile.dispose();
    nameFocus.dispose();
    mobileFocus.dispose();
    expandFocus.dispose();
    firstPillFocus.dispose();
    super.dispose();
  }
}

/// The section (§2.4). [typeOnly]: pay later (the customer is picked in
/// the credit body).
class SaleCustomerSection extends StatelessWidget {
  const SaleCustomerSection({
    super.key,
    required this.controller,
    required this.saving,
    this.typeOnly = false,
  });

  final SaleCustomerController controller;
  final bool saving;
  final bool typeOnly;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final setup = c.setup;
    final type = setup.type();
    final typeName = customerTypeKey(type) == null
        ? null
        : context.tr(customerTypeKey(type)!);
    final linkedName = c.linked
        ? (setup.customer().name ?? context.tr('vendor.pos.customer.selected'))
        : null;
    final typedName = c.name.text.trim();
    final who = typeOnly
        ? null
        : linkedName ?? (typedName.isEmpty ? null : typedName);
    final summary = [?who, ?typeName].join(' · ');
    final summaryText = summary.isEmpty
        ? context.tr('vendor.pos.cust.empty')
        : summary;
    return FFCard(
      key: const Key('pos-cust-section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: c.expanded,
            label: '${context.tr('vendor.pos.cust.sectionA11y')}, $summaryText',
            excludeSemantics: true,
            child: InkWell(
              key: const Key('pos-cust-toggle'),
              focusNode: c.expandFocus,
              onTap: c.toggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline),
                    const SizedBox(width: FFTokens.spacingSm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.tr('vendor.pos.cust.section'),
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            summaryText,
                            key: const Key('pos-cust-summary'),
                            style: muted,
                          ),
                        ],
                      ),
                    ),
                    Icon(c.expanded ? Icons.expand_less : Icons.expand_more),
                  ],
                ),
              ),
            ),
          ),
          if (c.expanded) ...[
            const SizedBox(height: FFTokens.spacingSm),
            Text(
              context.tr('vendor.pos.cust.type'),
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: FFTokens.spacingXs),
            Wrap(
              spacing: FFTokens.spacingXs,
              runSpacing: FFTokens.spacingXs,
              children: [
                for (final (i, t) in saleCustomerTypes.indexed)
                  Semantics(
                    inMutuallyExclusiveGroup: true,
                    selected: type == t,
                    child: FFPill(
                      key: Key('pos-cust-type-$t'),
                      label: context.tr('vendor.customerType.$t'),
                      filled: type == t,
                      focusNode: i == 0 ? c.firstPillFocus : null,
                      onTap: saving ? null : () => c.chooseType(t),
                    ),
                  ),
              ],
            ),
            if (!typeOnly) ..._details(context, muted),
          ],
        ],
      ),
    );
  }

  List<Widget> _details(BuildContext context, TextStyle? muted) {
    final c = controller;
    if (c.showOffline) {
      return [
        const SizedBox(height: FFTokens.spacingSm),
        Semantics(
          container: true,
          liveRegion: true,
          child: Text(
            context.tr('vendor.pos.cust.offline'),
            key: const Key('pos-cust-offline'),
            style: muted,
          ),
        ),
      ];
    }
    if (!c.namesShown) return const [];
    if (c.linked) {
      final name =
          c.setup.customer().name ?? context.tr('vendor.pos.customer.selected');
      return [
        const SizedBox(height: FFTokens.spacingSm),
        Row(
          children: [
            Expanded(
              child: Semantics(
                container: true,
                liveRegion: true,
                child: Text(
                  fillIn(context.tr('vendor.pos.cust.matched'), {'name': name}),
                  key: const Key('pos-cust-matched'),
                ),
              ),
            ),
            IconButton(
              key: const Key('pos-cust-remove'),
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                visualDensity: VisualDensity.standard,
              ),
              tooltip: fillIn(context.tr('vendor.pos.customer.remove'), {
                'name': name,
              }),
              icon: const Icon(Icons.close),
              onPressed: saving ? null : c.remove,
            ),
          ],
        ),
      ];
    }
    final nameField = Focus(
      onFocusChange: (has) {
        if (!has) c.nameBlurred();
      },
      skipTraversal: true,
      child: FFTextField(
        key: const Key('pos-cust-name'),
        controller: c.name,
        focusNode: c.nameFocus,
        label: context.tr('vendor.pos.cust.name'),
        maxLength: customerNameMax,
        errorText: c.nameError == null ? null : context.tr(c.nameError!),
        textCapitalization: TextCapitalization.words,
        enabled: !saving,
        onChanged: c.nameChanged,
      ),
    );
    final mobileField = Focus(
      onFocusChange: (has) {
        if (!has) c.mobileBlurred();
      },
      skipTraversal: true,
      child: FFTextField(
        key: const Key('pos-cust-mobile'),
        controller: c.mobile,
        focusNode: c.mobileFocus,
        label: context.tr('vendor.pos.cust.mobile'),
        hint: context.tr('vendor.pos.cust.mobileHint'),
        keyboardType: TextInputType.phone,
        errorText: c.mobileError == null ? null : context.tr(c.mobileError!),
        enabled: !saving,
        suffixIcon: c.looking
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  key: Key('pos-cust-looking'),
                  width: 16,
                  height: 16,
                  child: FFSpinner(),
                ),
              )
            : null,
        onChanged: c.mobileChanged,
      ),
    );
    return [
      const SizedBox(height: FFTokens.spacingSm),
      LayoutBuilder(
        builder: (context, box) {
          // Desktop width: side by side (each ≥ 240), unless text is large.
          final scale = MediaQuery.textScalerOf(context).scale(1);
          if (box.maxWidth >= 496 && scale <= 1.3) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: nameField),
                const SizedBox(width: FFTokens.spacingSm),
                Expanded(child: mobileField),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [nameField, mobileField],
          );
        },
      ),
      if (c.manyMatches != null)
        Semantics(
          container: true,
          liveRegion: true,
          child: Text(
            fillIn(context.tr('vendor.pos.cust.manyMatches'), {
              'n': c.manyMatches,
            }),
            key: const Key('pos-cust-many'),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FFButton(
          key: const Key('pos-cust-search'),
          label: context.tr('vendor.pos.cust.search'),
          icon: Icons.search,
          variant: FFButtonVariant.ghost,
          visualDensity: VisualDensity.standard,
          onPressed: saving ? null : () => unawaited(c.search()),
        ),
      ),
    ];
  }
}
