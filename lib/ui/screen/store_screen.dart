import 'package:flutter/material.dart';

import '../component/maker_scaffold.dart';
import '../theme/tone.dart';

/// 资源商店: 现在是空白页。
///
/// 卖什么、怎么结算都还没定, 与其先画一排假商品让人以为能买, 不如留白 ——
/// 这一页只保留标题和一句说明。等清单接口定了再填内容, 路由与配色都不用动。
class StoreScreen extends StatelessWidget {
  const StoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PageTone tone = ToneScope.of(context);

    return MakerScaffold(
      title: '资源商店',
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 28, 4, 0),
          child: Text(
            '这里还是空的。',
            style: theme.textTheme.bodyMedium?.copyWith(color: tone.muted),
          ),
        ),
      ],
    );
  }
}