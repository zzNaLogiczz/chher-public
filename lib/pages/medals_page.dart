/// A compact collection of actual source medals, with details on demand.
library;

import 'package:flutter/material.dart';
import '../ui/segmented.dart';
import '../ui/picker.dart';
import '../di.dart';
import '../data/space_repository.dart';
import '../widgets/large_title_scaffold.dart';
import '../widgets/expressive_controls.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../ui/grouped.dart';
import '../ui/sheet_scaffold.dart';
import '../models/models.dart';
import '../widgets/net_image.dart';
import '../widgets/state_view.dart';

class MedalsPage extends StatefulWidget {
  final SpaceRepository? repository;
  const MedalsPage({super.key, this.repository});
  @override
  State<MedalsPage> createState() => _MedalsPageState();
}

class _MedalsPageState extends State<MedalsPage> {
  static const _labels = ['勋章中心', '我的勋章'];
  int _seg = 0;
  late Future<List<MedalItem>> _future = (widget.repository ?? spaceRepo)
      .medals();
  void _switch(int i) {
    if (_seg == i) return;
    setState(() {
      _seg = i;
      _future = (widget.repository ?? spaceRepo).medals(mine: i == 1);
    });
  }

  Future<void> _reload() async {
    setState(
      () => _future = (widget.repository ?? spaceRepo).medals(
        mine: _seg == 1,
        refresh: true,
      ),
    );
    await _future;
  }

  @override
  Widget build(BuildContext context) => LargeTitleScaffold(
    title: '勋章',
    surface: AppSurface.grouped,
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screen,
            0,
            AppSpace.screen,
            12,
          ),
          child: AppSegmented<int>(
            fallbackTitle: '勋章',
            options: [
              for (var i = 0; i < _labels.length; i++)
                PickerOption(value: i, label: _labels[i]),
            ],
            value: _seg,
            onChanged: _switch,
          ),
        ),
        Expanded(
          child: FutureBuilder<List<MedalItem>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return StateView.loading();
              }
              final err = snap.error;
              if (err is PageMessage) {
                return StateView.forMessage(
                  err,
                  onLogin: () async {
                    await Navigator.of(context).pushNamed('/login');
                    if (mounted) await _reload();
                  },
                );
              }
              if (err != null) return StateView.error(err, onRetry: _reload);
              final medals = snap.data ?? const [];
              if (medals.isEmpty) {
                return StateView.empty(
                  message: _seg == 1 ? '还没有获得勋章' : '没有可展示的勋章',
                );
              }
              final t = AppTokens.of(context);
              return ExpressivePageReveal(
                active: true,
                animateOnMount: true,
                child: RefreshIndicator(
                  onRefresh: _reload,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(32, 20, 32, 7),
                          child: Text(
                            '${medals.length} 枚勋章',
                            style: AppType.footnote.copyWith(
                              color: t.text3,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.groupInset,
                          0,
                          AppSpace.groupInset,
                          40,
                        ),
                        sliver: SliverList.builder(
                          itemCount: medals.length,
                          itemBuilder: (context, i) => _MedalCard(
                            medal: medals[i],
                            first: i == 0,
                            last: i == medals.length - 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

/// 勋章行:分组面里的一行,44dp 勋章图 + 可换行的名称与说明
class _MedalCard extends StatelessWidget {
  final MedalItem medal;
  final bool first;
  final bool last;
  const _MedalCard({
    required this.medal,
    required this.first,
    required this.last,
  });
  String get _name => medal.name.isEmpty ? '勋章 ${medal.id}' : medal.name;
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        top: first ? const Radius.circular(AppRadii.md) : Radius.zero,
        bottom: last ? const Radius.circular(AppRadii.md) : Radius.zero,
      ),
      child: ColoredBox(
        color: t.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GroupedRow(
              title: _name,
              subtitle: medal.description?.isNotEmpty == true
                  ? medal.description
                  : null,
              leading: SizedBox.square(
                dimension: 44,
                child: medal.imageUrl == null
                    ? Icon(AppIcons.medal, size: 28, color: t.text3)
                    : NetImage(
                        url: medal.imageUrl!,
                        width: 44,
                        height: 44,
                        fit: BoxFit.contain,
                      ),
              ),
              onTap: () => _details(context),
            ),
            if (!last)
              Padding(
                padding: const EdgeInsets.only(left: AppSpace.rowInset + 56),
                child: Divider(
                  height: AppSpace.hairline,
                  thickness: AppSpace.hairline,
                  color: t.separator,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _details(BuildContext context) {
    final t = AppTokens.of(context);
    showAppSheet<void>(
      context,
      builder: (_) => SheetScaffold(
        title: _name,
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screen,
            8,
            AppSpace.screen,
            32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (medal.imageUrl != null) ...[
                NetImage(
                  url: medal.imageUrl!,
                  width: 88,
                  height: 88,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 18),
              ],
              if (medal.description?.isNotEmpty == true)
                SelectableText(
                  medal.description!,
                  style: AppType.reading.copyWith(color: t.text2),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
