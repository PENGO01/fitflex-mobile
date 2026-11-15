// Profile entry to the security activity page. It asks the server once per
// profile open (limit=1): a 404 means the feature is off and the tile stays
// hidden; a 200 shows it; a network error shows it too, so the page itself
// can explain and offer a retry.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/components/components.dart';
import '../../shared/i18n.dart';
import '../../shared/inbox/inbox_controller.dart';

class SecurityActivityTile extends StatefulWidget {
  const SecurityActivityTile({super.key});

  @override
  State<SecurityActivityTile> createState() => _SecurityActivityTileState();
}

class _SecurityActivityTileState extends State<SecurityActivityTile> {
  bool _started = false;
  bool _visible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _probe(AppScope.of(context).api);
  }

  Future<void> _probe(ApiClient api) async {
    var show = true;
    try {
      await api.securityActivity(limit: 1);
    } on ApiException catch (e) {
      // Feature off: hidden. Any other answer leaves the tile for the page
      // to explain.
      if (e.status == 404) show = false;
    } catch (_) {
      // Offline: shown.
    }
    if (mounted && show != _visible) setState(() => _visible = show);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return FFActionTile(
      icon: Icons.shield_outlined,
      title: context.tr('secAct.title'),
      subtitle: context.tr('secAct.tile.subtitle'),
      onTap: () => context.push(securityActivityRoute),
    );
  }
}
