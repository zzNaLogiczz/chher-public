import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/motion.dart';

/// One visibility signal for a reader's bars, including an embedded thread.
class ImageViewerChromeScope extends StatefulWidget {
  const ImageViewerChromeScope({
    super.key,
    required this.child,
    this.overlayStyle,
  });

  final Widget child;
  final SystemUiOverlayStyle? overlayStyle;

  @override
  State<ImageViewerChromeScope> createState() => _ImageViewerChromeScopeState();
}

class _ImageViewerChromeScopeState extends State<ImageViewerChromeScope> {
  final _covered = ValueNotifier(false);

  @override
  Widget build(BuildContext context) =>
      ImageViewerChromeController.maybeOf(context) != null
      ? widget.child
      : ImageViewerChromeController(
          covered: _covered,
          overlayStyle: () => mounted ? widget.overlayStyle : null,
          restore: () {
            if (mounted) _covered.value = false;
          },
          child: widget.child,
        );

  @override
  void dispose() {
    _covered.dispose();
    super.dispose();
  }
}

class ImageViewerChromeController extends InheritedWidget {
  const ImageViewerChromeController({
    super.key,
    required this.covered,
    required this.overlayStyle,
    required this.restore,
    required super.child,
  });

  final ValueNotifier<bool> covered;
  final ValueGetter<SystemUiOverlayStyle?> overlayStyle;
  final VoidCallback restore;

  static ImageViewerChromeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ImageViewerChromeController>();

  @override
  bool updateShouldNotify(ImageViewerChromeController oldWidget) =>
      covered != oldWidget.covered;
}

class ImageViewerReaderChrome extends StatelessWidget {
  const ImageViewerReaderChrome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = ImageViewerChromeController.maybeOf(context);
    if (controller == null) return child;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return ValueListenableBuilder<bool>(
      valueListenable: controller.covered,
      child: child,
      builder: (context, covered, child) => IgnorePointer(
        ignoring: covered,
        child: AnimatedOpacity(
          opacity: covered ? 0 : 1,
          duration: reduced
              ? Duration.zero
              : covered
              ? AppMotion.viewerChromeOut
              : AppMotion.viewerChromeIn,
          curve: AppMotion.mediaFadeCurve,
          child: child,
        ),
      ),
    );
  }
}
