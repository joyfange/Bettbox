import 'dart:math';

import 'package:bett_box/common/common.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/providers/app.dart';
import 'package:bett_box/state.dart';
import 'package:bett_box/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TrafficUsage extends StatefulWidget {
  const TrafficUsage({super.key});

  @override
  State<TrafficUsage> createState() => _TrafficUsageState();
}

class _TrafficUsageState extends State<TrafficUsage> {
  // cache text measurement results
  Size? _uploadTextSize;
  Size? _downloadTextSize;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // dependency changes when clear cache
    _uploadTextSize = null;
    _downloadTextSize = null;
  }

  Size _getUploadTextSize(BuildContext context) {
    return _uploadTextSize ??= globalState.measure.computeTextSize(
      Text(
        appLocalizations.upload,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textTheme.bodySmall,
      ),
    );
  }

  Size _getDownloadTextSize(BuildContext context) {
    return _downloadTextSize ??= globalState.measure.computeTextSize(
      Text(
        appLocalizations.download,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textTheme.bodySmall,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = globalState.theme.darken3PrimaryContainer;
    final secondaryColor = globalState.theme.darken2SecondaryContainer;
    return SizedBox(
      height: getWidgetHeight(2),
      child: CommonCard(
        info: Info(
          label: appLocalizations.trafficUsage,
          iconData: Icons.data_saver_off,
        ),
        onPressed: () {},
        child: Consumer(
          builder: (_, ref, _) {
            return ValueListenableBuilder<int>(
              valueListenable: dashboardRefreshManager.tick1s,
              builder: (_, _, _) {
                final totalTraffic = ref.read(totalTrafficProvider);
                final upTotalTrafficValue = totalTraffic.up;
                final downTotalTrafficValue = totalTraffic.down;
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 200;
                    return Padding(
                      padding: baseInfoEdgeInsets.copyWith(top: 0),
                      child: isCompact
                          ? _buildCompactTrafficView(
                              context,
                              primaryColor,
                              secondaryColor,
                              upTotalTrafficValue,
                              downTotalTrafficValue,
                            )
                          : _buildNormalTrafficView(
                              context,
                              primaryColor,
                              secondaryColor,
                              upTotalTrafficValue,
                              downTotalTrafficValue,
                            ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildNormalTrafficView(
    BuildContext context,
    Color primaryColor,
    Color secondaryColor,
    TrafficValue upTotalTrafficValue,
    TrafficValue downTotalTrafficValue,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: DonutChart(
                    data: [
                      DonutChartData(
                        value: upTotalTrafficValue.value.toDouble(),
                        color: primaryColor,
                      ),
                      DonutChartData(
                        value: downTotalTrafficValue.value.toDouble(),
                        color: secondaryColor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 6,
                            decoration: BoxDecoration(
                              color: primaryColor,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            appLocalizations.upload,
                            style: context.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        upTotalTrafficValue.show,
                        style: context.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 6,
                            decoration: BoxDecoration(
                              color: secondaryColor,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            appLocalizations.download,
                            style: context.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        downTotalTrafficValue.show,
                        style: context.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactTrafficView(
    BuildContext context,
    Color primaryColor,
    Color secondaryColor,
    TrafficValue upTotalTrafficValue,
    TrafficValue downTotalTrafficValue,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(Icons.arrow_upward, color: primaryColor, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      upTotalTrafficValue.show,
                      style: context.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.arrow_downward, color: secondaryColor, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      downTotalTrafficValue.show,
                      style: context.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          height: 60,
          child: DonutChart(
            data: [
              DonutChartData(
                value: upTotalTrafficValue.value.toDouble(),
                color: primaryColor,
              ),
              DonutChartData(
                value: downTotalTrafficValue.value.toDouble(),
                color: secondaryColor,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
