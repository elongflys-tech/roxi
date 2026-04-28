import 'package:fixnum/fixnum.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/core/widget/animated_text.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/features/stats/widget/stats_card.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final showAllSidebarStatsProvider = PreferencesNotifier.createAutoDispose("show_all_sidebar_stats", false);

class SideBarStatsOverview extends HookConsumerWidget {
  const SideBarStatsOverview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final showAll = ref.watch(showAllSidebarStatsProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(2.0),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: Theme.of(context).textTheme.labelSmall,
              ),
              onPressed: () {
                ref.read(showAllSidebarStatsProvider.notifier).update(!showAll);
              },
              icon: AnimatedRotation(
                turns: showAll ? 1 : 0.5,
                duration: kAnimationDuration,
                child: const Icon(FluentIcons.chevron_down_16_regular, size: 16),
              ),
              label: AnimatedText(showAll ? t.common.showLess : t.common.showMore),
            ),
          ),
          const Gap(8),
          AnimatedCrossFade(
            crossFadeState: showAll ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: kAnimationDuration,
            firstChild: const _CompactTrafficCard(),
            secondChild: const _ExpandedTrafficCards(),
          ),
        ],
      ),
    );
  }
}

/// Compact view — only watches downlink + downlinkTotal.
class _CompactTrafficCard extends ConsumerWidget {
  const _CompactTrafficCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    // Select only the two fields we display so unrelated changes don't rebuild.
    final downlink = ref.watch(
      statsNotifierProvider.select((s) => s.asData?.value.downlink ?? Int64.ZERO),
    );
    final downlinkTotal = ref.watch(
      statsNotifierProvider.select((s) => s.asData?.value.downlinkTotal ?? Int64.ZERO),
    );

    return RepaintBoundary(
      child: StatsCard(
        title: t.components.stats.traffic,
        stats: [
          (
            label: const Icon(FluentIcons.arrow_download_16_regular),
            data: Text(downlink.toInt().speed()),
            semanticLabel: t.components.stats.speed,
          ),
          (
            label: const Icon(FluentIcons.arrow_bidirectional_up_down_16_regular),
            data: Text(downlinkTotal.toInt().size()),
            semanticLabel: t.components.stats.totalTransferred,
          ),
        ],
      ),
    );
  }
}

/// Expanded view — watches uplink/downlink + totals.
class _ExpandedTrafficCards extends ConsumerWidget {
  const _ExpandedTrafficCards();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final uplink = ref.watch(
      statsNotifierProvider.select((s) => s.asData?.value.uplink ?? Int64.ZERO),
    );
    final downlink = ref.watch(
      statsNotifierProvider.select((s) => s.asData?.value.downlink ?? Int64.ZERO),
    );
    final uplinkTotal = ref.watch(
      statsNotifierProvider.select((s) => s.asData?.value.uplinkTotal ?? Int64.ZERO),
    );
    final downlinkTotal = ref.watch(
      statsNotifierProvider.select((s) => s.asData?.value.downlinkTotal ?? Int64.ZERO),
    );

    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatsCard(
            title: t.components.stats.trafficLive,
            stats: [
              (
                label: const Text("↑", style: TextStyle(color: Colors.green)),
                data: Text(uplink.toInt().speed()),
                semanticLabel: t.components.stats.uplink,
              ),
              (
                label: Text("↓", style: TextStyle(color: theme.colorScheme.error)),
                data: Text(downlink.toInt().speed()),
                semanticLabel: t.components.stats.downlink,
              ),
            ],
          ),
          const Gap(8),
          StatsCard(
            title: t.components.stats.trafficTotal,
            stats: [
              (
                label: const Text("↑", style: TextStyle(color: Colors.green)),
                data: Text(uplinkTotal.toInt().size()),
                semanticLabel: t.components.stats.uplink,
              ),
              (
                label: Text("↓", style: TextStyle(color: theme.colorScheme.error)),
                data: Text(downlinkTotal.toInt().size()),
                semanticLabel: t.components.stats.downlink,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
