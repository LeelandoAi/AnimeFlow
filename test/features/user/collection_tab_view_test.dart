import 'package:anime_flow/app/localization/app_localizations.dart';
import 'package:anime_flow/app/localization/app_localizations_delegates.dart';
import 'package:anime_flow/features/user/presentation/providers/user_collection_provider.dart';
import 'package:anime_flow/features/user/presentation/providers/user_collection_state.dart';
import 'package:anime_flow/features/user/presentation/widgets/collection_tab_view.dart';
import 'package:anime_flow/shared/models/bangumi/user_collections_item.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Collections extends UserCollections {
  int requests = 0;

  @override
  UserCollectionsState build() => UserCollectionsState(tabs: {
        1: UserCollectionTabState(
          data: UserCollectionsItem(data: [], total: 20),
          hasMore: true,
        ),
      });

  @override
  Future<void> loadMore(int type) async {
    requests++;
    state = state.updateTab(
        type,
        (tab) => requests == 1
            ? tab.copyWith(loadMoreErrorMessage: 'Network error')
            : tab.copyWith(
                data: UserCollectionsItem(data: [], total: 0),
                hasMore: false,
                clearLoadMoreErrorMessage: true,
              ));
  }
}

class _PagedCollections extends UserCollections {
  int requests = 0;

  @override
  UserCollectionsState build() => UserCollectionsState(tabs: {
        1: UserCollectionTabState(
          data: UserCollectionsItem(
            data: List.generate(
                20,
                (id) => UserCollectionData.fromJson({
                      'id': id,
                      'name': 'Example',
                      'type': 2,
                      'rating': <String, dynamic>{},
                      'images': <String, dynamic>{},
                      'interest': {'id': id, 'type': 1, 'updatedAt': 1},
                    })),
            total: 40,
          ),
          offset: 20,
          hasMore: true,
        ),
      });

  @override
  Future<void> loadMore(int type) async {
    requests++;
    state = state.updateTab(
        type, (tab) => tab.copyWith(loadMoreErrorMessage: 'Network error'));
  }
}

class _EpisodeCollections extends UserCollections {
  final Map<String, dynamic> episodeData;

  _EpisodeCollections(this.episodeData);

  @override
  UserCollectionsState build() => UserCollectionsState(tabs: {
        1: UserCollectionTabState(
          data: UserCollectionsItem(data: [
            UserCollectionData.fromJson({
              'id': 42,
              'name': 'Example',
              'type': 2,
              'rating': <String, dynamic>{},
              'images': <String, dynamic>{},
              'interest': {'id': 42, 'type': 1, 'updatedAt': 1},
              'totalEpisodes': 12,
              'watchedEpisode': 5,
              ...episodeData,
            })
          ], total: 1),
          hasMore: false,
        ),
      });
}

Widget _page(UserCollections collections) => ProviderScope(
      overrides: [userCollectionsProvider.overrideWith(() => collections)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DefaultTabController(
          length: 1,
          child: Builder(
            builder: (context) => Scaffold(
              body: NestedScrollView(
                headerSliverBuilder: (context, _) => [
                  SliverOverlapAbsorber(
                    handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                        context),
                    sliver: const SliverAppBar(title: Text('Collections')),
                  ),
                ],
                body: CollectionTabView(
                  tabController: DefaultTabController.of(context),
                  tabs: const ['Plan'],
                  refreshIndicatorKeys: {
                    1: GlobalKey<RefreshIndicatorState>(),
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

FixedScrollMetrics _metrics(AxisDirection direction) => FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 100,
      pixels: 100,
      viewportDimension: 600,
      axisDirection: direction,
      devicePixelRatio: 1,
    );

void main() {
  testWidgets(
      'collection menu callbacks rotate only the arrow and reset on dismissal',
      (tester) async {
    await tester.pumpWidget(_page(_EpisodeCollections({})));
    await tester.pump();
    final arrow = find.byIcon(Icons.expand_more_outlined);
    final rotation =
        find.ancestor(of: arrow, matching: find.byType(AnimatedRotation));
    final header = find.ancestor(of: arrow, matching: find.byType(Row)).first;
    final headerBefore = tester.widget<Row>(header);
    expect(tester.widget<AnimatedRotation>(rotation).turns, 0);

    await tester.tap(arrow);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<AnimatedRotation>(rotation).turns, 0.5);
    expect(identical(tester.widget<Row>(header), headerBefore), isTrue);

    await tester.tapAt(const Offset(750, 550));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<AnimatedRotation>(rotation).turns, 0);
    expect(identical(tester.widget<Row>(header), headerBefore), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  final date = '${DateTime.now().year}-10-15';
  final episodeCases = <String, (Map<String, dynamic>, String)>{
    'new response': (
      {
        'nextEpisode': {'sort': 6, 'airdate': date},
        'nextEpisodeAirDate': '2000-01-01'
      },
      '看过5 · 预计12集 · 第6集 10-15'
    ),
    'legacy response': (
      {'nextEpisodeAirDate': date},
      '看过5 · 预计12集 · 下一集 10-15'
    ),
    'no next episode': ({}, '看过5 · 全12集'),
    'new response without legacy date': (
      {
        'nextEpisode': {'sort': 6, 'airdate': date}
      },
      '看过5 · 预计12集 · 第6集 10-15'
    ),
    'null next episode object': (
      {'nextEpisode': null, 'nextEpisodeAirDate': null},
      '看过5 · 全12集'
    ),
    'empty dates': (
      {
        'nextEpisode': {'airdate': '  '},
        'nextEpisodeAirDate': ''
      },
      '看过5 · 全12集'
    ),
    'null fields': (
      {
        'nextEpisode': {'sort': null, 'airdate': null},
        'nextEpisodeAirDate': null
      },
      '看过5 · 全12集'
    ),
    'sort only': (
      {
        'nextEpisode': {'sort': 6}
      },
      '看过5 · 预计12集 · 第6集'
    ),
    'empty new date falls back': (
      {
        'nextEpisode': {'sort': 6, 'airdate': ''},
        'nextEpisodeAirDate': date
      },
      '看过5 · 预计12集 · 第6集 10-15'
    ),
  };
  for (final entry in episodeCases.entries) {
    testWidgets('episode label handles ${entry.key}', (tester) async {
      await tester.pumpWidget(_page(_EpisodeCollections(entry.value.$1)));
      // 封面加载动画会持续请求帧，文案验证无需等待图片加载完成。
      await tester.pump();
      expect(find.text(entry.value.$2), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('metrics load more; failure requires explicit retry',
      (tester) async {
    final collections = _PagedCollections();
    await tester.pumpWidget(_page(collections));
    await tester.pump();
    expect(collections.requests, 0);
    final scrollContext = tester.element(find.byType(CustomScrollView).last);
    ScrollMetricsNotification(
      metrics: _metrics(AxisDirection.right),
      context: scrollContext,
    ).dispatch(scrollContext);
    await tester.pump();
    expect(collections.requests, 0);
    ScrollMetricsNotification(
      metrics: _metrics(AxisDirection.down),
      context: scrollContext,
    ).dispatch(scrollContext);
    await tester.pump();
    expect(collections.requests, 1);
    ScrollEndNotification(
      metrics: _metrics(AxisDirection.down),
      context: scrollContext,
    ).dispatch(scrollContext);
    await tester.pump();
    expect(collections.requests, 1);
    final l10n =
        AppLocalizations.of(tester.element(find.byType(CollectionTabView)));
    final innerScrollable = find
        .descendant(
          of: find.byType(CustomScrollView).last,
          matching: find.byType(Scrollable),
        )
        .first;
    final position = tester.state<ScrollableState>(innerScrollable).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(collections.requests, 1);
    await tester.tap(find.widgetWithText(TextButton, l10n.retry));
    expect(collections.requests, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'empty cache can load more, retry, then display a true empty state',
      (tester) async {
    final collections = _Collections();
    await tester.pumpWidget(ProviderScope(
      overrides: [userCollectionsProvider.overrideWith(() => collections)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DefaultTabController(
          length: 1,
          child: Builder(
              builder: (context) => Scaffold(
                    body: NestedScrollView(
                      headerSliverBuilder: (context, _) => [
                        SliverOverlapAbsorber(
                          handle:
                              NestedScrollView.sliverOverlapAbsorberHandleFor(
                                  context),
                          sliver:
                              const SliverAppBar(title: Text('Collections')),
                        ),
                      ],
                      body: CollectionTabView(
                        tabController: DefaultTabController.of(context),
                        tabs: const ['Plan'],
                        refreshIndicatorKeys: {
                          1: GlobalKey<RefreshIndicatorState>()
                        },
                      ),
                    ),
                  )),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final l10n =
        AppLocalizations.of(tester.element(find.byType(CollectionTabView)));
    expect(find.text(l10n.noData), findsNothing);
    expect(collections.requests, 0);
    await tester.tap(find.text(l10n.viewMore));
    await tester.pumpAndSettle();
    expect(collections.requests, 1);
    expect(find.text(l10n.collectionLoadMoreFailed), findsOneWidget);
    await tester.tap(find.text(l10n.retry));
    await tester.pumpAndSettle();
    expect(collections.requests, 2);
    expect(find.text(l10n.noData), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
