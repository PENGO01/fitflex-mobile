import 'package:flutter/material.dart';

import '../components/components.dart';
import '../design_tokens.dart';
import '../i18n.dart';

/// A swipeable row of photos; tapping one opens it full screen with zoom,
/// previous / next and a counter. Used for gyms and for trainers.
class PhotoGallery extends StatelessWidget {
  const PhotoGallery({
    super.key,
    required this.images,
    this.keyPrefix = 'gym',
    this.emptyIcon = Icons.fitness_center,
    this.height = 180,
  });

  final List<String> images;

  /// Prefix of the widget keys (`<prefix>-photo-0`, `<prefix>-photo-next`…).
  final String keyPrefix;

  /// Shown when there are no photos, or one fails to load.
  final IconData emptyIcon;
  final double height;

  void _openPhoto(BuildContext context, String image, int index) {
    final controller = PageController(initialPage: index);
    var currentIndex = index;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog.fullscreen(
          key: Key('$keyPrefix-photo-fullscreen'),
          backgroundColor: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: controller,
                itemCount: images.length,
                onPageChanged: (value) =>
                    setDialogState(() => currentIndex = value),
                itemBuilder: (context, photoIndex) => InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: FFRemoteImage(
                    src: images[photoIndex],
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.contain,
                    fallback: const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              // Previous / next sit centred on the side edges. They must be
              // wrapped in Center: a bare IconButton.filled inside a
              // top:0/bottom:0 Positioned stretches to the full height and
              // shows as a primary-coloured bar down each side.
              if (images.length > 1) ...[
                Positioned(
                  left: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: IconButton.filled(
                      tooltip: context.tr('a11y.previous'),
                      key: Key('$keyPrefix-photo-previous'),
                      onPressed: currentIndex == 0
                          ? null
                          : () => controller.previousPage(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                            ),
                      icon: const Icon(Icons.chevron_left),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: IconButton.filled(
                      tooltip: context.tr('a11y.next'),
                      key: Key('$keyPrefix-photo-next'),
                      onPressed: currentIndex == images.length - 1
                          ? null
                          : () => controller.nextPage(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                            ),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ),
                ),
              ],
              Positioned(
                top: 12,
                right: 12,
                child: SafeArea(
                  child: IconButton.filled(
                    key: Key('$keyPrefix-photo-close'),
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close),
                    tooltip: MaterialLocalizations.of(
                      dialogContext,
                    ).closeButtonTooltip,
                  ),
                ),
              ),
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Center(
                    child: Text(
                      '${currentIndex + 1}/${images.length}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
      ),
      child: images.isNotEmpty
          ? PageView.builder(
              itemCount: images.length,
              itemBuilder: (context, index) => GestureDetector(
                key: Key('$keyPrefix-photo-$index'),
                onTap: () => _openPhoto(context, images[index], index),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    FFRemoteImage(
                      src: images[index],
                      width: double.infinity,
                      height: height,
                      fit: BoxFit.cover,
                      fallback: Center(
                        child: Icon(
                          emptyIcon,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          size: 48,
                        ),
                      ),
                    ),
                    if (images.length > 1)
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: FFBadge(
                          label: '${index + 1}/${images.length}',
                          tone: FFBadgeTone.gray,
                        ),
                      ),
                  ],
                ),
              ),
            )
          : Center(
              child: Icon(
                emptyIcon,
                color: Theme.of(context).colorScheme.primary,
                size: 48,
              ),
            ),
    );
  }
}
