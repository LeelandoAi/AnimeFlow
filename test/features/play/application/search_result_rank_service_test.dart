import 'package:anime_flow/core/logger/logger.dart';
import 'package:anime_flow/features/play/application/search_result_rank_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模拟持有不可发送字段的调用方（原来的 `VideoSourceNotifier`）。
///
/// `LiggLogger` 内部的 `Logger` 持有 `Future`，一旦被捕获进 isolate 消息就会
/// 抛 `Illegal argument in isolate message: object is unsendable`。
class _NotifierLikeCaller {
  final LiggLogger logger = LiggLogger();
  final SearchResultRankService rankService = SearchResultRankService(
    searchTerm: '葬送的芙莉莲',
  );

  Future<RankedCandidates> rank(List<String> names) {
    // 与方法内其它闭包一样捕获 this，使本方法的上下文包含 logger。
    void touchesThis() => logger.d('active');
    touchesThis();

    return rankService.rankInIsolate(names: names);
  }
}

void main() {
  group('SearchResultRankService.rankInIsolate', () {
    const mushokuSearchTerm = '无职转生 第二季 ～到了异世界就拿出真本事～ 第2部分';
    const mushokuAliases = [
      '无职转生 第二季 ～在异世界认真地活下去～ 第2部分',
      'Mushoku Tensei II: Isekai Ittara Honki Dasu (2024)',
      'Mushoku Tensei: Jobless Reincarnation Season 2 (2024)',
      'Mushoku Tensei: Jobless Reincarnation Season 2 part 2',
      'Mushoku Tensei II: Isekai Ittara Honki Dasu part 2',
    ];

    test('波浪号及其他标点在评分前移除，不影响季数和部分识别', () async {
      final service = SearchResultRankService(
        searchTerm: mushokuSearchTerm,
        aliases: mushokuAliases,
      );
      final result = await service.rankInIsolate(names: [
        '无职转生第二季到了异世界就拿出真本事第2部分',
        '无职转生 第二季 ~到了异世界就拿出真本事~ 第2部分',
        '无职转生 第二季 〜到了异世界就拿出真本事〜 第2部分',
        '【无职转生】「第二季」《到了异世界就拿出真本事》（第2部分）！',
        '无职转生Ⅱ到了异世界就拿出真本事第2部分',
        '无职转生Ⅱ ~到了异世界就拿出真本事~ 第2部分',
        '无职转生Ⅱ ～到了异世界就拿出真本事～ 第2部分',
      ]);

      expect(result.indices, [0, 1, 2, 3, 4, 5, 6]);
      expect(result.matchRatios.take(4), [1.0, 1.0, 1.0, 1.0]);
      for (final ratio in result.matchRatios.skip(4)) {
        expect(ratio, closeTo(0.92, 1e-12));
      }
    });

    test('无职转生罗马数字季标与中文季标匹配，并区分部分', () async {
      final service = SearchResultRankService(
        searchTerm: mushokuSearchTerm,
        aliases: mushokuAliases,
      );
      final result = await service.rankInIsolate(names: [
        '无职转生Ⅱ ～到了异世界就拿出真本事～ 第1部分',
        '无职转生Ⅲ ～到了异世界就拿出真本事～ 第2部分',
        '无职转生Ⅱ ～到了异世界就拿出真本事～ 第2部分',
        '无职转生Ⅱ ～到了异世界就拿出真本事～',
      ]);

      expect(result.indices.first, 2);
      expect(result.matchRatios[2], closeTo(0.92, 1e-12));
      expect(result.matchRatios[0], lessThan(0.6));
      expect(result.matchRatios[1], lessThan(0.6));
      expect(result.matchRatios[3], lessThan(result.matchRatios[2]));
    });

    test('罗马数字季标的识别不依赖别名', () {
      final service = SearchResultRankService(searchTerm: mushokuSearchTerm);
      for (final seasonMarker in ['Ⅱ', 'ⅱ', 'II', 'ii']) {
        expect(
          service.computeMatchRatio(
            '无职转生$seasonMarker ～到了异世界就拿出真本事～ 第2部分',
          ),
          closeTo(0.92, 1e-12),
          reason: seasonMarker,
        );
      }
    });

    test('英文 season 和 part 分别比较，别名不能提高错误部分的匹配度', () async {
      final service = SearchResultRankService(
        searchTerm: mushokuSearchTerm,
        aliases: mushokuAliases,
      );
      final result = await service.rankInIsolate(names: [
        'Mushoku Tensei: Jobless Reincarnation Season 2 part 1',
        'Mushoku Tensei: Jobless Reincarnation Season 3 part 2',
        'Mushoku Tensei: Jobless Reincarnation Season 2 part 2',
        'Mushoku Tensei II: Isekai Ittara Honki Dasu part 2',
      ]);

      expect(result.indices.take(2), [2, 3]);
      expect(result.matchRatios[2], 1.0);
      expect(result.matchRatios[3], 1.0);
      expect(result.matchRatios[0], lessThan(0.6));
      expect(result.matchRatios[1], lessThan(0.6));
    });

    test('第2部分不能单独当作第二季，第2部仍可表示第二季', () {
      final service = SearchResultRankService(searchTerm: '银河 第二季');
      expect(service.computeMatchRatio('银河 第2部分'), lessThan(0.8));
      expect(service.computeMatchRatio('银河 第2部'), closeTo(0.92, 1e-12));
    });

    test('英文标题中的普通单词 I 不会被当作第一季', () {
      final service = SearchResultRankService(searchTerm: 'I Am A Hero');
      expect(service.computeMatchRatio('I-Am-A-Hero'), 1.0);
      final other = SearchResultRankService(searchTerm: 'When I Go Home');
      expect(other.computeMatchRatio('When-I-Go-Home'), 1.0);
    });

    test('省略季数和部分的别名继承主标题约束', () async {
      final service = SearchResultRankService(
        searchTerm: '银河 第二季 第2部分',
        aliases: ['Galaxy'],
      );
      final result = await service.rankInIsolate(names: [
        'Galaxy Season 2 part 1',
        'Galaxy Season 3 part 2',
        'Galaxy Season 2 part 2',
      ]);

      expect(result.indices.first, 2);
      expect(result.matchRatios[0], lessThan(result.matchRatios[2]));
      expect(result.matchRatios[1], lessThan(result.matchRatios[2]));
    });

    test('中文部分编号与英文 part 编号等价', () {
      final service = SearchResultRankService(searchTerm: '银河 第二季 第2部分');
      expect(
        service.computeMatchRatio('银河 第2季 第二部分'),
        closeTo(0.92, 1e-12),
      );
      expect(
        service.computeMatchRatio('银河 season 2 part 2'),
        closeTo(0.92, 1e-12),
      );
      expect(
        service.computeMatchRatio('银河 season 2 part 1'),
        lessThan(0.6),
      );
    });

    test('返回按得分降序的下标，且与名称一一对应', () async {
      final service = SearchResultRankService(
        searchTerm: '葬送的芙莉莲',
      );
      final result = await service.rankInIsolate(
        names: ['无关作品', '葬送的芙莉莲 第二季', '葬送的芙莉莲'],
      );

      expect(result.indices, hasLength(3));
      expect(result.indices.toSet(), {0, 1, 2});
      expect(result.matchRatios, hasLength(3));
      // 完全匹配的那条应排在最前。
      expect(result.indices.first, 2);
    });

    test('空候选返回空结果', () async {
      final service = SearchResultRankService(
        searchTerm: '葬送的芙莉莲',
      );
      final result = await service.rankInIsolate(names: const []);

      expect(result.indices, isEmpty);
      expect(result.matchRatios, isEmpty);
    });

    test('调用方持有不可发送字段时依然可以执行', () async {
      final caller = _NotifierLikeCaller();

      final result = await caller.rank(['葬送的芙莉莲', '别的动画']);

      expect(result.indices.first, 0);
    });

    test('同一实例多次排序复用名称和别名，且同分保持原顺序', () async {
      final service = SearchResultRankService(
        searchTerm: '葬送的芙莉莲',
        aliases: ['Frieren'],
      );

      final first = await service.rankInIsolate(
        names: ['无关作品', 'Frieren'],
      );
      final second = await service.rankInIsolate(
        names: ['葬送的芙莉莲', 'Frieren', '无关作品'],
      );

      expect(first.indices, [1, 0]);
      expect(first.matchRatios[1], 1.0);
      expect(second.indices, [0, 1, 2]);
      expect(second.matchRatios.take(2), [1.0, 1.0]);
    });

    test('构造后修改外部别名列表不影响已有实例的排序配置', () async {
      final aliases = ['Frieren'];
      final service = SearchResultRankService(
        searchTerm: '葬送的芙莉莲',
        aliases: aliases,
      );
      aliases.clear();

      final result = await service.rankInIsolate(
        names: ['无关作品', 'Frieren'],
      );

      expect(result.indices, [1, 0]);
      expect(result.matchRatios[1], 1.0);
    });

    test('相同季数优先于其他季数和剧场版，匹配度保持原有规则', () async {
      final service = SearchResultRankService(searchTerm: '银河 第二季');
      final result = await service.rankInIsolate(
        names: ['银河 第三季', '银河 剧场版', '银河 第二季', '银河 第2季'],
      );

      expect(result.indices, [2, 3, 0, 1]);
      expect(result.matchRatios[0], closeTo(0.4784, 1e-12));
      expect(result.matchRatios[1], closeTo(0.46, 1e-12));
      expect(result.matchRatios[2], 1.0);
      expect(result.matchRatios[3], closeTo(0.92, 1e-12));
    });

    test('规范化名称和重复别名后仍取最高匹配度', () async {
      final service = SearchResultRankService(
        searchTerm: '葬送的芙莉莲',
        aliases: ['frieren', ' FR IEREN! ', '', '!!!'],
      );
      final result = await service.rankInIsolate(
        names: ['', 'Frieren!', ' FRIEREN ', '葬送的芙莉莲'],
      );

      expect(result.indices, [1, 2, 3, 0]);
      expect(result.matchRatios, [0.0, 1.0, 1.0, 1.0]);
    });

    test('没有有效词条时所有匹配度为零，并保留候选顺序', () async {
      final service = SearchResultRankService(
        searchTerm: '!!!',
        aliases: ['', ' '],
      );
      final result = await service.rankInIsolate(
        names: ['银河', 'Frieren', ''],
      );

      expect(result.indices, [0, 1, 2]);
      expect(result.matchRatios, [0.0, 0.0, 0.0]);
    });
  });
}
