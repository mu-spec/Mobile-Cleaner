import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phone_storage_cleaner/core/scanning/scan_progress.dart';
import 'package:phone_storage_cleaner/core/ui/circular_file_scanner.dart';
import 'package:phone_storage_cleaner/core/ui/reference_progress_art.dart';

/// Approved Smart Scan hierarchy, shared by file/photo scan loading views.
/// No work, timing estimates, navigation or permission decisions live here.
class SmartScanProgress extends StatelessWidget {
  const SmartScanProgress({
    required this.snapshot,
    required this.activity,
    required this.description,
    this.active = true,
    this.completed = false,
    this.succeeded = false,
    this.currentPath,
    this.footer,
    super.key,
  });

  final ScanSnapshot? snapshot;
  final String activity;
  final String description;
  final bool active;
  final bool completed;
  final bool succeeded;

  /// Only supply when the scanner actually provides a current path. Existing
  /// scan snapshots do not, so production callers deliberately leave it null.
  final String? currentPath;
  final Widget? footer;

  static const ink = Color(0xFF101D40);
  static const blue = Color(0xFF0055F5);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = math.min(constraints.maxWidth, 960.0);
      final scale = (width / 512).clamp(.625, 1.3);
      final height = constraints.hasBoundedHeight
          ? constraints.maxHeight
          : MediaQuery.sizeOf(context).height * .8;
      final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final diameter = math.min(
        width * .72,
        math.max(120.0, height - 290 * scale * math.max(1, textScale)),
      );
      final dark = Theme.of(context).brightness == Brightness.dark;
      final foreground = dark ? Colors.white : ink;
      final muted = dark ? const Color(0xFFAABAD6) : const Color(0xFF7487A5);
      final stage = snapshot?.displayStage;
      final name = stage?.name ?? snapshot?.stage;
      final processed = stage?.processed ?? snapshot?.processed;
      final total = stage?.total ?? (stage == null ? snapshot?.total : null);
      final unit = stage?.unit ?? snapshot?.unit ?? 'items checked';
      final count = processed == null
          ? null
          : '$processed${total == null ? '' : ' / $total'} $unit';
      final path = currentPath?.trim();
      final running = active && !completed && !succeeded;
      final compactFactor = textScale > 1.15 ? 0.75 : 1.0;
      final topGap = (height * 0.065 * compactFactor).clamp(
        12 * scale,
        56 * scale,
      );
      final radarToPercentGap = (height * 0.032 * compactFactor).clamp(
        12 * scale,
        28 * scale,
      );

      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          child: SingleChildScrollView(
            key: const Key('smart_scan_scroll'),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: height),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  width * .0586,
                  topGap,
                  width * .0586,
                  36 * scale,
                ),
                child: CircularFileScanner(
                  key: const Key('scan_progress_ring'),
                  size: diameter,
                  scanId: snapshot?.id,
                  stageId: stage?.id ?? snapshot?.stage,
                  progress: snapshot?.fraction,
                  active: active,
                  completed: completed,
                  succeeded: succeeded,
                  presentationBuilder: (context, radar, fill, motion) =>
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: math.max(0, height - topGap - 36 * scale),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              children: [
                                radar,
                                SizedBox(height: radarToPercentGap),
                                if (fill != null)
                                  Text(
                                    '${(fill * 100).floor()}%',
                                    key: const Key('scan_percentage_below'),
                                    style: TextStyle(
                                      color: blue,
                                      fontSize: 46 * scale,
                                      height: 1.12,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -1.4,
                                    ),
                                  ),
                                SizedBox(height: 6 * scale),
                                Text(
                                  completed ? 'Scan complete' : activity,
                                  key: const Key('scan_activity'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: foreground,
                                    fontSize: 19 * scale,
                                    height: 1.25,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (path != null && path.isNotEmpty) ...[
                                  SizedBox(height: 8 * scale),
                                  Text(
                                    path,
                                    key: const Key('scan_current_path'),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 14 * scale,
                                    ),
                                  ),
                                ],
                                if (count != null) ...[
                                  SizedBox(height: 10 * scale),
                                  Text(
                                    count,
                                    key: const Key('scan_work_counter'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: foreground,
                                      fontSize: 16 * scale,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                                if (fill != null)
                                  Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      width * .095,
                                      18 * scale,
                                      width * .095,
                                      0,
                                    ),
                                    child: _ScanMeasuredBar(
                                      value: fill,
                                      scale: scale,
                                    ),
                                  ),
                              ],
                            ),
                            Padding(
                              padding: EdgeInsets.only(top: 26 * scale),
                              child:
                                  footer ??
                                  Container(
                                    key: const Key('scan_status_card'),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 23 * scale,
                                      vertical: 19 * scale,
                                    ),
                                    decoration: BoxDecoration(
                                      color: dark
                                          ? const Color(0xFF152235)
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(
                                        18 * scale,
                                      ),
                                      border: Border.all(
                                        color: dark
                                            ? const Color(0xFF283B58)
                                            : const Color(0xFFEDF2F9),
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x0612356B),
                                          blurRadius: 12,
                                          offset: Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.find_in_page_rounded,
                                          color: blue,
                                          size: 33 * scale,
                                        ),
                                        SizedBox(width: 20 * scale),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                completed
                                                    ? 'Scan complete'
                                                    : 'Stage: ${name ?? activity}',
                                                key: const Key(
                                                  'scan_progress_status',
                                                ),
                                                style: TextStyle(
                                                  color: foreground,
                                                  fontSize: 16 * scale,
                                                  height: 1.25,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              SizedBox(height: 4 * scale),
                                              Text(
                                                description,
                                                style: TextStyle(
                                                  color: muted,
                                                  fontSize: 14 * scale,
                                                  height: 1.25,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(width: 12 * scale),
                                        if (running)
                                          SizedBox.square(
                                            dimension: 22 * scale,
                                            child: AnimatedBuilder(
                                              animation: motion,
                                              builder: (context, child) =>
                                                  Transform.rotate(
                                                    angle:
                                                        motion.value *
                                                        math.pi *
                                                        2,
                                                    child: child,
                                                  ),
                                              child: CircularProgressIndicator(
                                                key: const Key(
                                                  'scan_stage_spinner',
                                                ),
                                                value: .72,
                                                strokeWidth: 2.5 * scale,
                                                color: blue,
                                                backgroundColor: const Color(
                                                  0xFFE2EAFF,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                            ),
                          ],
                        ),
                      ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// A single measured fill shared with the number and radar, not a second
/// implicit animation (which could lag or overtake one of those displays).
class _ScanMeasuredBar extends StatelessWidget {
  const _ScanMeasuredBar({required this.value, required this.scale});
  final double? value;
  final double scale;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Confirmed stage progress',
    value: value == null
        ? 'Total unknown'
        : '${(value! * 100).floor()} percent',
    child: ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        key: const Key('scan_measured_bar'),
        height: 11 * scale,
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(color: Color(0xFFD7E5FC)),
              ),
              if (value != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    key: const Key('scan_measured_bar_fill'),
                    width: constraints.maxWidth * value!,
                    height: 11 * scale,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      color: ReferenceProgressColors.orange,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
