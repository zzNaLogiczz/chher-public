/// A readable ledger preserves the source's column labels and values.
library;

import 'package:flutter/material.dart';
import '../design/tokens.dart';
import '../design/shapes.dart';
import '../design/typography.dart';
import '../di.dart';
import '../data/space_repository.dart';
import '../widgets/large_title_scaffold.dart';
import '../models/models.dart';
import '../widgets/paged_list.dart';

class CreditLogPage extends StatefulWidget {
  final SpaceRepository? repository;
  const CreditLogPage({super.key, this.repository});
  @override
  State<CreditLogPage> createState() => _CreditLogPageState();
}

class _CreditLogPageState extends State<CreditLogPage> {
  List<String> _headers = const [];
  @override
  Widget build(BuildContext context) => LargeTitleScaffold(
    title: '积分记录',
    surface: AppSurface.grouped,
    body: PagedList<List<String>>(
      emptyMessage: '还没有积分记录',
      padding: const EdgeInsets.fromLTRB(
        AppSpace.groupInset,
        10,
        AppSpace.groupInset,
        40,
      ),
      loader: (page, {bool refresh = false}) async {
        final table = await (widget.repository ?? spaceRepo).creditLog(
          page: page,
          refresh: refresh,
        );
        if (table.headers.isNotEmpty) _headers = table.headers;
        return Paged(
          items: table.rows,
          page: table.page,
          nextUrl: table.nextUrl,
        );
      },
      itemBuilder: (context, row) => _LedgerEntry(headers: _headers, row: row),
    ),
  );
}

class _LedgerEntry extends StatelessWidget {
  final List<String> headers;
  final List<String> row;
  const _LedgerEntry({required this.headers, required this.row});
  int _index(bool Function(String) match) {
    for (var i = 0; i < headers.length && i < row.length; i++) {
      if (match(headers[i])) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final operation = _index((h) => h.contains('操作'));
    final change = _index((h) => h.contains('变更') && !h.contains('时间'));
    final time = _index((h) => h.contains('时间'));
    final titleIndex = operation >= 0
        ? operation
        : row.indexWhere((v) => v.isNotEmpty);
    final hidden = {titleIndex, change, time};
    final amount = change >= 0 ? row[change] : '';
    // 增加记绿色、减少记红色,数字保留源站给出的正负号
    final amountColor = amount.contains('-') || amount.contains('−')
        ? t.red
        : amount.contains('+')
        ? t.green
        : t.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: t.surface,
          shape: appShape(AppRadii.md),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.rowInset, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      titleIndex >= 0 ? row[titleIndex] : '积分记录',
                      style: AppType.callout.copyWith(color: t.text),
                    ),
                  ),
                  if (amount.isNotEmpty) ...[
                    const SizedBox(width: 16),
                    Text(
                      amount,
                      key: const ValueKey('credit-amount'),
                      style: AppType.headline.copyWith(color: amountColor),
                    ),
                  ],
                ],
              ),
              if (time >= 0 && row[time].isNotEmpty)
                Text(
                  row[time],
                  style: AppType.footnote.copyWith(color: t.text3),
                ),
              for (var i = 0; i < row.length; i++)
                if (!hidden.contains(i) && row[i].isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${i < headers.length && headers[i].isNotEmpty ? '${headers[i]}  ' : ''}${row[i]}',
                      style: AppType.footnote.copyWith(color: t.text2),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
