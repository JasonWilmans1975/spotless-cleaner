import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api_client.dart';
import '../format.dart';
import '../theme/spotless_theme.dart';
import '../ui/layout.dart';
import '../ui/tiles.dart';

/// Average star rating of [reviews], or null if there are none.
double? averageRating(List<Review> reviews) =>
    reviews.isEmpty ? null : reviews.map((r) => r.rating).reduce((a, b) => a + b) / reviews.length;

/// Every review customers have left this cleaner, newest first.
class ReviewsScreen extends StatefulWidget {
  /// Load override for tests; defaults to the API.
  final Future<List<Review>> Function()? loadReviews;

  const ReviewsScreen({super.key, this.loadReviews});

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  late Future<List<Review>> _future = _fetch();

  Future<List<Review>> _fetch() => (widget.loadReviews ?? ApiClient().getMyReviews)();

  Future<void> _refresh() async {
    setState(() => _future = _fetch());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: FutureBuilder<List<Review>>(
            future: _future,
            builder: (context, snapshot) {
              final reviews = snapshot.data;
              final avg = reviews == null ? null : averageRating(reviews);
              return Column(children: [
                ScreenHeader(
                  title: 'Reviews',
                  subtitle: avg == null
                      ? null
                      : '${avg.toStringAsFixed(1)} average · ${reviews!.length} ${reviews.length == 1 ? 'review' : 'reviews'}',
                  showBack: true,
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: Builder(builder: (context) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return ListView(children: [
                          EmptyState(
                            icon: LucideIcons.wifiOff,
                            title: "Couldn't load your reviews",
                            message: snapshot.error.toString(),
                            actionLabel: 'Try again',
                            onAction: _refresh,
                          ),
                        ]);
                      }
                      if (reviews!.isEmpty) {
                        return ListView(children: const [
                          EmptyState(
                            icon: LucideIcons.star,
                            title: 'No reviews yet',
                            message: 'Customers can rate a clean once it’s finished — their reviews will show up here.',
                          ),
                        ]);
                      }
                      return ListView(
                        padding: EdgeInsets.fromLTRB(20, 6, 20, 24 + MediaQuery.paddingOf(context).bottom),
                        children: [
                          for (var n = 0; n < reviews.length; n++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: FadeSlideIn(index: n, child: ReviewCard(review: reviews[n])),
                            ),
                        ],
                      );
                    }),
                  ),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

/// One review: who, which clean and when, stars, tip, comment and praise tags.
class ReviewCard extends StatelessWidget {
  const ReviewCard({super.key, required this.review});
  final Review review;

  @override
  Widget build(BuildContext context) {
    final s = context.tokens;
    final r = review;
    final meta = [
      if (r.serviceName.isNotEmpty) r.serviceName,
      if (r.createdAt != null) shortDate(r.createdAt!),
    ].join(' · ');
    return SpotlessCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          InitialsAvatar(name: r.reviewerName, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.reviewerName.isEmpty ? 'Customer' : r.reviewerName,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              if (meta.isNotEmpty) Text(meta, style: TextStyle(fontSize: 12, color: s.muted)),
            ]),
          ),
          Semantics(
            label: '${r.rating} out of 5 stars',
            excludeSemantics: true,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var n = 1; n <= 5; n++)
                Icon(Icons.star_rounded, size: 16, color: n <= r.rating ? context.colors.secondary : s.line),
            ]),
          ),
        ]),
        if (r.tipCents > 0) ...[
          const SizedBox(height: 8),
          SpotlessPill('${formatMoney(r.tipCents)} tip', colors: s.approved, icon: LucideIcons.heartHandshake),
        ],
        if (r.comment?.trim().isNotEmpty ?? false) ...[
          const SizedBox(height: 10),
          Text(r.comment!.trim(), style: const TextStyle(fontSize: 14, height: 1.55, color: SpotlessColors.inkSoft)),
        ],
        if (r.tags.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in r.tags) SpotlessPill(t, colors: (s.primarySofter, s.primaryDeep)),
          ]),
        ],
      ]),
    );
  }
}
