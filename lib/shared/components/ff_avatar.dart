import 'package:flutter/material.dart';
import '../tone_theme.dart';
import 'ff_remote_image.dart';

/// Avatar size variants.
enum FFAvatarSize { sm, md, lg, xl }

/// User avatar with initials fallback — matches portal's Avatar component.
class FFAvatar extends StatelessWidget {
  const FFAvatar({super.key, this.name, this.src, this.size = FFAvatarSize.md});

  final String? name;
  final String? src;
  final FFAvatarSize size;

  double get _radius => switch (size) {
    FFAvatarSize.sm => 14,
    FFAvatarSize.md => 18,
    FFAvatarSize.lg => 22,
    FFAvatarSize.xl => 32,
  };

  double get _fontSize => switch (size) {
    FFAvatarSize.sm => 12,
    FFAvatarSize.md => 14,
    FFAvatarSize.lg => 16,
    FFAvatarSize.xl => 22,
  };

  String get _initials {
    final parts = (name ?? '?').split(' ');
    return parts
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (src != null && src!.isNotEmpty) {
      return CircleAvatar(
        radius: _radius,
        backgroundColor: FFToneTheme.of(context).neutral.bg,
        child: ClipOval(
          child: FFRemoteImage(
            src: src!,
            profilePhoto: true,
            width: _radius * 2,
            height: _radius * 2,
            fit: BoxFit.cover,
            fallback: _InitialsAvatar(
              radius: _radius,
              fontSize: _fontSize,
              initials: _initials,
            ),
          ),
        ),
      );
    }
    return _InitialsAvatar(
      radius: _radius,
      fontSize: _fontSize,
      initials: _initials,
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({
    required this.radius,
    required this.fontSize,
    required this.initials,
  });

  final double radius;
  final double fontSize;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: FFToneTheme.of(context).brand.bg,
      child: Text(
        initials,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: FFToneTheme.of(context).brand.fg,
        ),
      ),
    );
  }
}
