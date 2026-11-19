import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

/// Message rows in the confirmed November design.
abstract final class NoticeTokens {
  static const timeWidthFraction = 0.46;
  static const pokeIcon = SolarIconsOutline.handStars;
  static const avatar = 40.0;
  static const conversationAvatar = 48.0;
  static const avatarGap = 12.0;
  static const kind = 16.0;
  static const kindFrame = 20.0;
  static const kindIcon = 12.0;
  static const kindOffset = -3.0;
  static const systemIcon = 20.0;
  static const dot = 7.0;
  static const rowRadius = 18.0;
  static const quoteRadius = 12.0;
  static const titleGap = 3.0;
  static const scoreTitleGap = 6.0;
  static const quoteGap = 8.0;
  static const rowPadding = EdgeInsets.fromLTRB(12, 12, 14, 12);
  static const conversationPadding = EdgeInsets.fromLTRB(12, 11, 14, 11);
  static const quotePadding = EdgeInsets.symmetric(horizontal: 11, vertical: 8);
  static const sentence = TextStyle(fontSize: 14.5, height: 1.45);
  static const preview = TextStyle(fontSize: 14, height: 1.5);
  static const name = TextStyle(fontSize: 15, height: 1.45);
  static const time = TextStyle(fontSize: 12.5, height: 1.4);
}
