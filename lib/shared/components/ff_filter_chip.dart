import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_tokens.dart';

/// What a chip's selection means to assistive tech.
enum FFChipSelection {
  /// A button with a selected state (filters; the default).
  button,

  /// One of a single-choice group: a radio button, checked or not.
  radio,

  /// One of a multi-choice group: a checkbox, checked or not.
  checkbox,
}

/// How a selected [FFFilterChip] is drawn.
enum FFFilterChipTone {
  /// Selected fills with the primary colour (tier and specialty rows).
  solid,

  /// Selected fills with Volt and ink text (panel options).
  tint,
}

/// A compact filter chip that is still a full button (F-11).
///
/// The pill stays small, but the tap target is at least 48x48, Tab reaches
/// it, Space or Enter selects it, and assistive tech hears a button with its
/// label and whether it is selected. Keyboard focus draws the V2 2px ring
/// outside the pill (slate-900 on light, slate-100 on dark).
class FFFilterChip extends StatefulWidget {
  const FFFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
    this.tone = FFFilterChipTone.solid,
    this.focusNode,
    this.semanticLabel,
    this.selection = FFChipSelection.button,
  });

  /// Radio or checkbox semantics for choice groups (forms); [selected] is
  /// then read as checked / not checked.
  final FFChipSelection selection;

  final String label;

  /// Read out instead of [label] (e.g. "Age group, 30 to 44").
  final String? semanticLabel;
  final bool selected;
  final VoidCallback onSelected;

  /// Optional icon before the label. Not announced.
  final IconData? icon;
  final FFFilterChipTone tone;
  final FocusNode? focusNode;

  /// The smallest tap target on every side.
  static const double minTarget = 48;

  @override
  State<FFFilterChip> createState() => _FFFilterChipState();
}

class _FFFilterChipState extends State<FFFilterChip> {
  bool _focused = false;

  static const _shortcuts = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
  };

  late final Map<Type, Action<Intent>> _actions = {
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) {
        widget.onSelected();
        return null;
      },
    ),
    ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
      onInvoke: (_) {
        widget.onSelected();
        return null;
      },
    ),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final ring = dark ? ffFocusRingDark : ffFocusRingLight;
    final solid = widget.tone == FFFilterChipTone.solid;
    final sel = widget.selected;
    // Light system: every chip is a pill.
    const radius = FFTokens.radiusFull;

    final Color fill;
    final Color border;
    final Color fg;
    if (solid) {
      fill = sel ? cs.primary : cs.surface;
      border = sel ? cs.primary : cs.outline;
      fg = sel ? cs.onPrimary : cs.onSurface;
    } else {
      fill = sel ? FFTokens.volt : cs.surface;
      border = sel ? FFTokens.volt : cs.outline;
      fg = sel ? FFTokens.onVolt : cs.onSurface;
    }

    final text = Text(
      widget.label,
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontSize: solid ? 13 : 12,
        fontWeight: solid
            ? FontWeight.w500
            : (sel ? FontWeight.w600 : FontWeight.w400),
        color: fg,
      ),
    );

    final pill = AnimatedContainer(
      key: const Key('ff-filter-chip-pill'),
      duration: const Duration(milliseconds: 100),
      padding: solid
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: widget.icon == null
          ? text
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 14, color: fg),
                const SizedBox(width: 4),
                text,
              ],
            ),
    );

    return Semantics(
      container: true,
      button: widget.selection == FFChipSelection.button,
      selected: sel,
      checked: widget.selection == FFChipSelection.button ? null : sel,
      inMutuallyExclusiveGroup: widget.selection == FFChipSelection.radio
          ? true
          : null,
      label: widget.semanticLabel ?? widget.label,
      onTap: widget.onSelected,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        shortcuts: _shortcuts,
        actions: _actions,
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        child: GestureDetector(
          onTap: widget.onSelected,
          excludeFromSemantics: true,
          behavior: HitTestBehavior.opaque,
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: FFFilterChip.minTarget,
                minWidth: FFFilterChip.minTarget,
              ),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: DecoratedBox(
                  key: const Key('ff-filter-chip-focus-ring'),
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    border: _focused
                        ? Border.all(
                            color: ring,
                            width: 2,
                            strokeAlign: BorderSide.strokeAlignOutside,
                          )
                        : null,
                  ),
                  child: pill,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
