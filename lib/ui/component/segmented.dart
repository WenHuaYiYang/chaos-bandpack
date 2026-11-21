import 'package:flutter/material.dart';

import '../theme/motion.dart';
import '../theme/paper_palette.dart';
import '../theme/tone.dart';

/// 分段选择器: 一块底槽 + 一个会滑动的滑块。
///
/// 为什么不是「每格各自变色」: 机型(10 Pro / 9 Pro)、字集档、主题这些选择互斥
/// 且后果都很重, 只有看见滑块从左边滑到右边, 才觉得是同一个开关被拨过去了。
/// 每格独立淡入淡出在 42dp 高度上几乎看不出变化 —— 手感上像没生效。
///
/// 滑块宽度取整格(而不是内容宽度), 这样滑到底时正好贴合底槽内侧, 不会差一点。
class Segmented<T> extends StatelessWidget {
  const Segmented({
    required this.value,
    required this.items,
    required this.onChanged,
    this.height = 42,
    this.padding = 4,
    super.key,
  });

  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  final double height;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PageTone tone = ToneScope.of(context);
    final bool motion = animationsEnabled(context);
    final List<T> keys = items.keys.toList();
    final int raw = keys.indexOf(value);
    final int index = raw < 0 ? 0 : raw;
    return Container(
      height: height,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: tone.field,
        borderRadius: BorderRadius.circular(PaperPalette.shapeSm),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final double cell = keys.isEmpty ? box.maxWidth : box.maxWidth / keys.length;
          // 对齐值 -1 左端, +1 右端; 只有一格时居中。
          final double align =
              keys.length <= 1 ? 0 : -1 + 2 * (index / (keys.length - 1)).clamp(0.0, 1.0);
          return Stack(
            children: <Widget>[
              AnimatedAlign(
                alignment: Alignment(align, 0),
                duration: motion ? const Duration(milliseconds: 300) : Duration.zero,
                curve: Curves.easeOutCubic,
                child: Container(
                  width: cell,
                  height: box.maxHeight,
                  decoration: BoxDecoration(
                    color: tone.card,
                    borderRadius: BorderRadius.circular(PaperPalette.shapeXs),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  for (final T key in keys)
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(PaperPalette.shapeXs),
                        onTap: () => onChanged(key),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: motion ? const Duration(milliseconds: 200) : Duration.zero,
                            style: (key == value
                                    ? theme.textTheme.labelLarge
                                    : theme.textTheme.labelMedium)
                                ?.copyWith(
                              color: key == value ? tone.onField : tone.muted,
                              fontWeight: key == value ? FontWeight.w700 : FontWeight.w500,
                            ) ?? const TextStyle(),
                            child: Text(items[key] ?? ''),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
