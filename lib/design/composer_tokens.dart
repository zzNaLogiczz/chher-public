import 'package:flutter/painting.dart';

import 'chat_tokens.dart';
import 'tokens.dart';
import 'typography.dart';

/// Geometry and typography from the composer 2026-11-26 prototype.
abstract final class ComposerTokens {
  static const panelRadius = AppRadii.xl;
  static const grabber = 21.0;
  static const grabberWidth = 36.0;
  static const grabberThickness = 5.0;
  static const grabberRadius = 3.0;

  static const headerHeight = AppSpace.titleRow;
  static const headerGap = 8.0;
  static const headerEndInset = 10.0;
  static const replyIcon = 18.0;
  static const title = TextStyle(
    fontSize: AppType.sizeBody,
    fontWeight: FontWeight(650),
  );
  static const cancel = TextStyle(fontSize: AppType.sizeCallout);
  static const cancelRadius = 22.0;
  static const cancelInset = 10.0;
  static const contextEndInset = 24.0;
  static const contextBottomInset = 6.0;
  static const quoteInset = editorInset + replyIcon + headerGap;

  static const editorInset = AppSpace.screen;
  static const editorPadding = EdgeInsets.fromLTRB(
    editorInset,
    2,
    editorInset,
    10,
  );
  static const editorContentPadding = EdgeInsets.symmetric(vertical: 4);
  static const editorMinHeight = 92.0;
  static const chatPanelTopInset = 6.0;
  static const chatEditorInsets = EdgeInsets.fromLTRB(editorInset, 0, 14, 0);
  static const chatInputPadding = EdgeInsets.symmetric(vertical: 10);
  static const chatInputMinHeight = 44.0;
  static const chatMaxLines = 5;
  static const chatBody = TextStyle(
    fontSize: ChatTokens.bodySize,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );
  static const statusPadding = EdgeInsets.symmetric(
    horizontal: 24,
    vertical: 14,
  );
  static const statusActionGap = 12.0;
  static const statusIcon = 20.0;
  static const statusIconGap = 10.0;
  static const statusText = TextStyle(
    fontSize: AppType.sizeFootnote,
    height: 1.6,
  );

  static const thumbnailSize = 58.0;
  static const thumbnailRadius = AppRadii.sm;
  static const thumbnailGap = 12.0;
  static const thumbnailRemoveSize = 22.0;
  static const thumbnailRemoveBorder = 2.0;
  static const trayPadding = EdgeInsets.fromLTRB(
    editorInset,
    10,
    editorInset,
    2,
  );

  static const strip = 52.0;
  static const stripInset = 8.0;
  static const tool = 44.0;
  static const toolRadius = AppRadii.sm;
  static const icon = 24.0;
  static const rightGap = 4.0;

  static const emojiHeight = 300.0;
  static const emojiComposerClearance = 180.0;
  static const emojiKeyboardHandoff = Duration(milliseconds: 350);
  static const emojiPadding = EdgeInsets.fromLTRB(8, 12, 8, 0);
  static const emojiCategoryPadding = EdgeInsets.fromLTRB(10, 0, 10, 6);
  static const emojiCategory = TextStyle(fontSize: 12);
  static const emojiCellGap = 2.0;
  static const emojiCell = tool;
  static const emojiImage = 26.0;
  static const emojiRadius = 10.0;
  static const emojiDeleteRight = 12.0;
  static const emojiDeleteBottom = 30.0;
  static const emojiDeleteWidth = 56.0;
  static const emojiDeleteHeight = 42.0;
  static const emojiDeleteIcon = AppType.sizeBody;
  static const emojiGridBottom = emojiDeleteBottom + emojiDeleteHeight + 8;

  static List<BoxShadow> emojiKeyShadow(Color color) => [
    BoxShadow(offset: const Offset(0, 1), color: color),
  ];

  static ({Color background, Color key, Color keyShadow}) emojiColors(
    AppTokens t,
  ) => switch ((t.style, t.isDark)) {
    (AppearanceStyle.misty, false) => (
      background: const Color(0xFFD3D6DC),
      key: const Color(0xFFFFFFFF),
      keyShadow: const Color(0xFFABB0BA),
    ),
    (AppearanceStyle.misty, true) => (
      background: const Color(0xFF26272B),
      key: const Color(0xFF46474C),
      keyShadow: const Color(0xFF333438),
    ),
    (AppearanceStyle.cinnabar, false) => (
      background: const Color(0xFFD6D2D0),
      key: const Color(0xFFFFFFFE),
      keyShadow: const Color(0xFFB9B3B0),
    ),
    (AppearanceStyle.cinnabar, true) => (
      background: const Color(0xFF232120),
      key: const Color(0xFF3B3736),
      keyShadow: const Color(0xFF2C2928),
    ),
  };

  static const capsuleWidth = 124.0;
  static const capsuleMinWidth = 88.0;
  static const capsuleHeight = 36.0;
  static const capsuleRadius = AppRadii.md;
  static const capsuleGap = 7.0;
  static const barWidth = 3.0;
  static const barGap = 2.5;
  static const barRadius = barWidth / 2;
  static const barHeights = [6.0, 12.0, 17.0, 12.0, 6.0];
  static const voiceLabel = TextStyle(
    fontSize: AppType.sizeFilter,
    fontWeight: FontWeight.w600,
  );

  static const voiceHoldDelay = Duration(milliseconds: 300);
  static const voiceDragSlop = 10.0;
  static const voiceHeight = 44.0;
  static const voiceRadius = voiceHeight / 2;
  static const voiceLabelInset = 16.0;
  static const voiceIcon = 16.0;
  static const voiceChipHeight = 40.0;
  static const voiceChipGap = 6.0;
  static const voiceChatChipGap = 10.0;
  static const voiceChipPadding = EdgeInsets.symmetric(
    horizontal: 4,
    vertical: 2,
  );
  static const voiceMessagePadding = EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 6,
  );
  static const voiceActionPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 6,
  );
  static const voiceOutline = .5;
  static const voiceOnGradient = Color(0xFFFFFFFF);
  static const voiceTimeWarning = Color(0xFFFFE7A6);
  static const voiceLabelShadows = [
    Shadow(color: Color(0xA6000000), blurRadius: 4),
  ];
  static LinearGradient voiceGradient(AppTokens t) => LinearGradient(
    colors: [t.ai1, t.ai3, t.ai2, t.ai4],
    stops: const [0, .34, .72, 1],
  );

  static const sendHeight = 36.0;
  static const sendRadius = AppRadii.md;
  static const sendInset = 15.0;
  static const sendLabel = TextStyle(
    fontSize: AppType.sizeSubhead,
    fontWeight: FontWeight(650),
    letterSpacing: 0,
  );
}
