import 'package:flutter/material.dart';

import '../theme/motion.dart';
import '../theme/paper_palette.dart';
import '../theme/tone.dart';
import 'app_icons.dart';

/// 二级页左上角的返回。
///
/// 二级页没有底栏, 退回上一层的唯一出口就是这里, 所以热区按 44dp 给,
/// 不把 22dp 的图标本身当热区。
class BackChevron extends StatelessWidget {
  const BackChevron({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final PageTone tone = ToneScope.of(context);
    return PressScale(
      child: Tooltip(
        message: '返回',
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(PaperPalette.shapeSm),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(AppIcons.back, size: 22, color: tone.onField),
            ),
          ),
        ),
      ),
    );
  }
}