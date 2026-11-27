import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/composer_tokens.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/tokens.dart';
import '../../design/voice_tokens.dart';
import '../../ui/press.dart';

class ComposerToolStrip extends StatelessWidget {
  final Widget? leading;
  final Widget? image;
  final Widget send;
  final Widget? voice;
  final bool voiceActive;

  const ComposerToolStrip({
    super.key,
    this.leading,
    this.image,
    required this.send,
    this.voice,
    this.voiceActive = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: ComposerTokens.strip,
    child: CustomMultiChildLayout(
      delegate: _ToolStripLayout(
        hasImage: image != null,
        hasLeading: leading != null,
        voiceActive: voiceActive,
      ),
      children: [
        if (voice != null) LayoutId(id: _ToolSlot.voice, child: voice!),
        if (leading != null)
          LayoutId(id: _ToolSlot.leading, child: _side(context, leading!)),
        LayoutId(
          id: _ToolSlot.trailing,
          child: _side(
            context,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (image != null) ...[
                  image!,
                  const SizedBox(width: ComposerTokens.rightGap),
                ],
                Flexible(child: send),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _side(BuildContext context, Widget child) => AnimatedOpacity(
    opacity: voiceActive ? 0 : 1,
    duration: VoiceTokens.toolsFade,
    curve: AppMotion.contentFadeCurve,
    child: ExcludeFocus(
      excluding: voiceActive,
      child: ExcludeSemantics(
        excluding: voiceActive,
        child: IgnorePointer(ignoring: voiceActive, child: child),
      ),
    ),
  );
}

enum _ToolSlot { leading, voice, trailing }

class _ToolStripLayout extends MultiChildLayoutDelegate {
  final bool hasImage;
  final bool hasLeading;
  final bool voiceActive;

  _ToolStripLayout({
    required this.hasImage,
    required this.hasLeading,
    required this.voiceActive,
  });

  @override
  void performLayout(Size size) {
    final half = math.max(0.0, size.width / 2 - ComposerTokens.stripInset);
    final trailingMinimum = hasImage
        ? 2 * ComposerTokens.tool + ComposerTokens.rightGap
        : ComposerTokens.tool;
    final voiceMinimum = (2 * (half - trailingMinimum)).clamp(
      0.0,
      ComposerTokens.capsuleMinWidth,
    );
    // Measure the right group first. Its current label can use any space
    // beside the centered capsule without shifting either group on show/hide.
    final trailing = layoutChild(
      _ToolSlot.trailing,
      BoxConstraints(
        maxWidth: math.max(trailingMinimum, half - voiceMinimum / 2),
      ),
    );
    positionChild(
      _ToolSlot.trailing,
      Offset(
        size.width - ComposerTokens.stripInset - trailing.width,
        (size.height - trailing.height) / 2,
      ),
    );
    final sideWidth = hasLeading
        ? math.max(trailing.width, ComposerTokens.tool)
        : trailing.width;
    final capsuleWidth = (2 * (half - sideWidth)).clamp(
      0.0,
      ComposerTokens.capsuleWidth,
    );
    if (hasChild(_ToolSlot.voice)) {
      final voiceWidth = voiceActive ? 2 * half : capsuleWidth;
      final voice = layoutChild(
        _ToolSlot.voice,
        BoxConstraints.tightFor(width: voiceWidth),
      );
      positionChild(
        _ToolSlot.voice,
        Offset(
          (size.width - voice.width) / 2,
          (size.height - voice.height) / 2,
        ),
      );
    }
    if (hasChild(_ToolSlot.leading)) {
      final leading = layoutChild(
        _ToolSlot.leading,
        BoxConstraints(
          maxWidth: hasChild(_ToolSlot.voice) ? half - capsuleWidth / 2 : half,
        ),
      );
      positionChild(
        _ToolSlot.leading,
        Offset(ComposerTokens.stripInset, (size.height - leading.height) / 2),
      );
    }
  }

  @override
  bool shouldRelayout(_ToolStripLayout oldDelegate) =>
      oldDelegate.hasImage != hasImage ||
      oldDelegate.hasLeading != hasLeading ||
      oldDelegate.voiceActive != voiceActive;
}

class ComposerImageTool extends StatelessWidget {
  final VoidCallback? onPressed;
  final String semanticLabel;

  const ComposerImageTool({
    super.key,
    required this.onPressed,
    this.semanticLabel = '添加图片',
  });

  @override
  Widget build(BuildContext context) => _ComposerTool(
    icon: AppIcons.image,
    onPressed: onPressed,
    label: semanticLabel,
  );
}

class ComposerEmojiTool extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool selected;

  const ComposerEmojiTool({
    super.key,
    required this.onPressed,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: _ComposerTool(
      icon: AppIcons.smile,
      onPressed: onPressed,
      label: '表情',
      selected: selected,
    ),
  );
}

class _ComposerTool extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String label;
  final bool selected;

  const _ComposerTool({
    required this.icon,
    required this.onPressed,
    required this.label,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final radius = BorderRadius.circular(ComposerTokens.toolRadius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? t.accentFill : null,
        borderRadius: radius,
      ),
      child: PressHighlight(
        onTap: onPressed,
        semanticLabel: label,
        color: t.fill,
        borderRadius: radius,
        child: SizedBox.square(
          dimension: ComposerTokens.tool,
          child: Icon(
            icon,
            size: ComposerTokens.icon,
            color: selected
                ? t.accent
                : onPressed == null
                ? t.text3
                : t.text2,
          ),
        ),
      ),
    );
  }
}
