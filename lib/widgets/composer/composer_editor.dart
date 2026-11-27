import 'package:flutter/material.dart';

import '../../design/composer_tokens.dart';
import '../../design/editor_tokens.dart';
import '../../design/tokens.dart';
import '../../ui/editor_touch.dart';
import 'composer_dictation_text.dart';
import 'dictation_controller.dart';
import 'smiley_editing_controller.dart';

/// The plain-text editor shared by the composer hosts.
class ComposerEditor extends StatelessWidget {
  final Key? fieldKey;
  final TextEditingController controller;
  final DictationController? dictation;
  final FocusNode focusNode;
  final String hintText;
  final bool readOnly;
  final bool enabled;
  final bool notifyOnUserEntry;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final bool chat;
  final double horizontalInset;
  final VoidCallback? onTap;

  const ComposerEditor({
    super.key,
    this.fieldKey,
    required this.controller,
    this.dictation,
    required this.focusNode,
    required this.hintText,
    this.readOnly = false,
    this.enabled = true,
    this.notifyOnUserEntry = false,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.chat = false,
    this.horizontalInset = ComposerTokens.editorInset,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final style = chat ? ComposerTokens.chatBody : EditorTokens.body;
    return Padding(
      padding: chat
          ? ComposerTokens.chatEditorInsets
          : ComposerTokens.editorPadding.copyWith(
              left: horizontalInset,
              right: horizontalInset,
            ),
      child: EditorTouchGuard(
        focusNode: focusNode,
        enabled: enabled && !readOnly && dictation?.editorLocked != true,
        notifyOnUserEntry: notifyOnUserEntry,
        builder: (context, editorFocus, notifyTap) {
          Widget field({bool hideHint = false, bool listening = false}) =>
              TextField(
                key: fieldKey,
                controller: controller,
                focusNode: editorFocus,
                onTap: () {
                  onTap?.call();
                  notifyTap();
                },
                onTapAlwaysCalled: true,
                autofocus: autofocus,
                enabled: enabled,
                readOnly: readOnly,
                showCursor: listening || dictation?.editorLocked == true
                    ? false
                    : null,
                minLines: 1,
                maxLines: chat ? ComposerTokens.chatMaxLines : null,
                textCapitalization: textCapitalization,
                inputFormatters: [
                  if (controller case final SmileyEditingController smileys)
                    smileys.inputFormatter,
                ],
                style: style.copyWith(color: t.text, letterSpacing: 0),
                decoration: InputDecoration(
                  hintText: hideHint ? null : hintText,
                  hintStyle: style.copyWith(color: t.text3, letterSpacing: 0),
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: chat
                      ? ComposerTokens.chatInputPadding
                      : ComposerTokens.editorContentPadding,
                  constraints: BoxConstraints(
                    minHeight: chat
                        ? ComposerTokens.chatInputMinHeight
                        : ComposerTokens.editorMinHeight,
                  ),
                ),
              );
          if (dictation case final voice?) {
            if (controller case final SmileyEditingController editor) {
              return ComposerDictationText(
                dictation: voice,
                editor: editor,
                field: field,
              );
            }
          }
          return field();
        },
      ),
    );
  }
}
