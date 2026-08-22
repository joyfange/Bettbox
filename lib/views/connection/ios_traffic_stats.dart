import 'dart:math';
import 'dart:async';

import 'package:bett_box/clash/core.dart';
import 'package:bett_box/models/common.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/plugins/app.dart';
import 'package:bett_box/providers/providers.dart';
import 'package:bett_box/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

/// iOS风格的流量统计轻应用界面
class IOSTrafficStatsPage extends ConsumerStatefulWidget {
  const IOSTrafficStatsPage({super.key});

  @override
  ConsumerState<IOSTrafficStatsPage> createState() => _IOSTrafficStatsPageState();
}

class _IOSTrafficStatsPageState extends ConsumerState<IOSTrafficStatsPage>
    with TickerProviderStateMixin {
  Timer? _timer;
  List<TrackerInfo> _connections = [];
  bool _loading = true;
  bool _hasError = false;
  String? _errorMessage;

  // 包名 → 图标缓存
  final Map<String, Uint8List?> _iconCache = {};

  // 今日/本周切换
  bool _isWeekly = false;

  // 动画控制器
  late AnimationController _ringAnimationController;
  late AnimationController _listAnimationController;
  late Animation<double> _ringAnimation;
  late Animation<double> _listAnimation;

  // 环形图进度 (0.0 ~ 1.0)
  double _ringProgress = 0.0;

  // 流量超限阈值（字节）
  static const int _trafficLimit = 500 * 1024 * 1024; // 500MB

  // 选中的应用
  String? _selectedApp;

  @override
  void initState() {
    super.initState();
    _ringAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _listAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _ringAnimation = CurvedAnimation(
      parent: _ringAnimationController,
      curve: Curves.easeOutCubic,
    );
    _listAnimation = CurvedAnimation(
      parent: _listAnimationController,
      curve: Curves.easeOut,
    );

    _loadData();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _loadData());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ringAnimationController.dispose();
    _listAnimationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final data = await clashCore.getConnections();
      if (mounted) {
        setState(() {
          _connections = data;
          _loading = false;
          _hasError = false;
          _errorMessage = null;
        });
        _updateRingProgress();
        _ringAnimationController.forward(from: 0);
        _listAnimationController.forward(from: 0);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _updateRingProgress() {
    final trafficData = _getTrafficData();
    _ringProgress = trafficData.total > _trafficLimit ? 1.0 : (trafficData.total / _trafficLimit).clamp(0.0, 1.0);
  }

  void _togglePeriod() {
    setState(() {
      _isWeekly = !_isWeekly;
      _updateRingProgress();
    });
    _ringAnimationController.forward(from: 0);
    _listAnimationController.forward(from: 0);
  }

  /// 从 processPath 提取包名
  String? _extractPackageName(String processPath) {
    if (processPath.isEmpty) return null;
    final match = RegExp(r'/data/app/(?:~~[a-zA-Z0-9]+/)?([a-zA-Z0-9_.\-]+)(?:/|$)').firstMatch(processPath);
    if (match != null) return match.group(1);
    final last = processPath.split('/').last;
    return last.contains('.') ? last.substring(0, last.lastIndexOf('.')) : last;
  }

  Future<Uint8List?> _loadIcon(String? packageName) async {
    if (packageName == null || packageName.isEmpty) return null;
    // 先检查缓存
    if (_iconCache.containsKey(packageName)) return _iconCache[packageName];
    try {
      // 调用原生方法获取图标
      final bytes = await app.getPackageIcon(packageName);
      if (bytes != null && bytes.isNotEmpty) {
        _iconCache[packageName] = bytes;
        return bytes;
      }
    } catch (e) {
      // 静默失败
    }
    // 不缓存 null，下次重试
    return null;
  }

  /// 按应用聚合流量
  Map<String, Map<String, dynamic>> _aggregateAppTraffic() {
    final Map<String, Map<String, dynamic>> appTraffic = {};
    for (final info in _connections) {
      final process = info.metadata.process;
      final processPath = info.metadata.processPath;

      // 优先使用 process 作为包名（Android 应用 process 通常就是包名）
      String appName;
      String? pkg;

      if (process.isNotEmpty) {
        appName = process;
        pkg = process;
      } else if (processPath.isNotEmpty) {
        final extracted = _extractPackageName(processPath);
        appName = extracted ?? '未知应用';
        pkg = extracted;
      } else {
        appName = '未知应用';
        pkg = null;
      }

      appTraffic.putIfAbsent(appName, () => {'up': 0, 'down': 0, 'pkg': pkg});
      appTraffic[appName]!['up'] = (appTraffic[appName]!['up'] ?? 0) + info.upload;
      appTraffic[appName]!['down'] = (appTraffic[appName]!['down'] ?? 0) + info.download;
    }
    return appTraffic;
  }

  /// 获取今日/本周流量数据（模拟）
  ({int up, int down, int total}) _getTrafficData() {
    final appTraffic = _aggregateAppTraffic();
    int totalUp = 0, totalDown = 0;
    for (final entry in appTraffic.values) {
      totalUp += entry['up'] as int;
      totalDown += entry['down'] as int;
    }
    // 模拟周数据：放大3倍
    if (_isWeekly) {
      return (up: totalUp * 3 ~/ 2, down: totalDown * 3 ~/ 2, total: (totalUp + totalDown) * 3 ~/ 2);
    }
    return (up: totalUp, down: totalDown, total: totalUp + totalDown);
  }

  @override
  Widget build(BuildContext context) {
    final trafficData = _getTrafficData();
    final isOverLimit = trafficData.total > _trafficLimit;
    final appTraffic = _aggregateAppTraffic();
    final sortedApps = appTraffic.entries.toList()
      ..sort((a, b) => (a.value['up']! + a.value['down']!).compareTo(b.value['up']! + b.value['down']!));

    return CommonScaffold(
      title: '流量统计',
      body: _loading
          ? _buildSkeletonLoader()
          : _hasError
              ? _buildErrorView()
              : Column(
                  children: [
                    // 顶部胶囊按钮
                    _buildPeriodToggle(),
                    const SizedBox(height: 24),
                    // 环形图
                    _buildRingChart(trafficData.total, isOverLimit),
                    const SizedBox(height: 24),
                    // 上下行明细
                    _buildTrafficDetail(trafficData),
                    const SizedBox(height: 24),
                    // 高流量应用列表
                    _buildAppList(sortedApps),
                  ],
                ),
    );
  }

  /// 骨架屏
  Widget _buildSkeletonLoader() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 胶囊按钮骨架
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          const SizedBox(height: 24),
          // 环形图骨架
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 24),
          // 明细骨架
          Row(
            children: [
              Expanded(child: Container(height: 60, color: Colors.grey.shade200)),
              const SizedBox(width: 12),
              Expanded(child: Container(height: 60, color: Colors.grey.shade200)),
            ],
          ),
          const SizedBox(height: 24),
          // 列表骨架
          ...List.generate(5, (index) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(height: 72, color: Colors.grey.shade200),
          )),
        ],
      ),
    );
  }

  /// 错误视图
  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(
            '加载失败',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? '未知错误',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 时段切换胶囊按钮
  Widget _buildPeriodToggle() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildToggleChip('今日', !_isWeekly, () {
              if (_isWeekly) _togglePeriod();
            }),
            _buildToggleChip('本周', _isWeekly, () {
              if (!_isWeekly) _togglePeriod();
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFF9500) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFFFF9500).withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey.shade600,
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  /// 环形图
  Widget _buildRingChart(int total, bool isOverLimit) {
    final percentage = _ringProgress;
    final displayTotal = TrafficValue(value: total).show;

    return AnimatedBuilder(
      animation: _ringAnimation,
      builder: (context, child) {
        final animatedProgress = percentage * _ringAnimation.value;
        return Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isOverLimit
                ? Colors.red.withValues(alpha: 0.08)
                : Colors.white,
            boxShadow: [
              BoxShadow(
                color: (isOverLimit ? Colors.red : const Color(0xFFFF9500)).withValues(alpha: 0.2),
                blurRadius: 28,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 背景圆环
              CustomPaint(
                size: const Size(240, 240),
                painter: _RingBackgroundPainter(
                  progress: animatedProgress,
                  isOverLimit: isOverLimit,
                  animationValue: _ringAnimation.value,
                ),
              ),
              // 中心文字
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    displayTotal,
                    style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                      color: isOverLimit ? Colors.red : Colors.black87,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '总流量',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// 上下行明细
  Widget _buildTrafficDetail(({int up, int down, int total}) data) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildDetailCard(
              '上行',
              TrafficValue(value: data.up).show,
              Colors.red,
              Icons.arrow_upward,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildDetailCard(
              '下行',
              TrafficValue(value: data.down).show,
              Colors.green,
              Icons.arrow_downward,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  /// 应用列表
  Widget _buildAppList(List<MapEntry<String, Map<String, dynamic>>> apps) {
    return Expanded(
      child: FadeTransition(
        opacity: _listAnimation,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: apps.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final entry = apps[index];
            final appName = entry.key;
            final up = entry.value['up'] as int;
            final down = entry.value['down'] as int;
            final pkg = entry.value['pkg'] as String?;
            final total = up + down;
            final isSelected = _selectedApp == appName;

            return _buildAppCard(
              appName: appName,
              pkg: pkg,
              up: up,
              down: down,
              total: total,
              isSelected: isSelected,
              index: index,
            );
          },
        ),
      ),
    );
  }

  Widget _buildAppCard({
    required String appName,
    required String? pkg,
    required int up,
    required int down,
    required int total,
    required bool isSelected,
    required int index,
  }) {
    final iconColor = Colors.primaries[appName.hashCode.abs() % Colors.primaries.length];

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedApp = isSelected ? null : appName;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: EdgeInsets.only(bottom: isSelected ? 0 : 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            children: [
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                leading: FutureBuilder<Uint8List?>(
                  future: _loadIcon(pkg),
                  builder: (context, snapshot) {
                    final bytes = snapshot.data;
                    if (bytes != null) {
                      final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
                      final cacheSize = (42 * devicePixelRatio).ceil();
                      return RepaintBoundary(
                        child: Image(
                          image: ResizeImage(
                            MemoryImage(bytes),
                            width: cacheSize,
                            height: cacheSize,
                            allowUpscaling: false,
                          ),
                          width: 42,
                          height: 42,
                          gaplessPlayback: true,
                        ),
                      );
                    }
                    return _buildFallbackIcon(appName, iconColor);
                  },
                ),
                title: Text(
                  appName,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: pkg != null && pkg.isNotEmpty
                    ? Text(
                        pkg,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      TrafficValue(value: total).show,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '↑${TrafficValue(value: up).show} ↓${TrafficValue(value: down).show}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              // 展开详情
              if (isSelected)
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(height: 1),
                        const SizedBox(height: 14),
                        _buildDetailRow('上行流量', TrafficValue(value: up).show, Colors.red),
                        const SizedBox(height: 10),
                        _buildDetailRow('下行流量', TrafficValue(value: down).show, Colors.green),
                        const SizedBox(height: 10),
                        _buildDetailRow('总流量', TrafficValue(value: total).show, Colors.blue),
                        const SizedBox(height: 10),
                        _buildDetailRow('占比', '${((total / _getTrafficData().total) * 100).toStringAsFixed(1)}%', Colors.orange),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }

  Widget _buildFallbackIcon(String label, Color color) {
    final letter = label.isNotEmpty ? label[0].toUpperCase() : '?';
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
    );
  }
}

/// 环形图背景绘制
class _RingBackgroundPainter extends CustomPainter {
  final double progress;
  final bool isOverLimit;
  final double animationValue;

  _RingBackgroundPainter({
    required this.progress,
    required this.isOverLimit,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 20;
    final strokeWidth = 12.0;

    // 背景圆环
    final bgPaint = Paint()
      ..color = Colors.grey.shade200
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    // 进度圆环
    final sweepAngle = 2 * pi * progress;
    final gradient = SweepGradient(
      startAngle: -pi / 2,
      endAngle: -pi / 2 + sweepAngle,
      colors: isOverLimit
          ? [Colors.red.shade400, Colors.red.shade600]
          : [const Color(0xFFFF9500), const Color(0xFFFF6B00)],
    );

    final progressPaint = Paint()
      ..shader = gradient.createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // 动画绘制
    final drawPath = Path()
      ..addArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        sweepAngle * animationValue,
      );
    canvas.drawPath(drawPath, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _RingBackgroundPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isOverLimit != isOverLimit ||
        oldDelegate.animationValue != animationValue;
  }
}
