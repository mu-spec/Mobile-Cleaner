import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phone_storage_cleaner/core/scanning/scan_progress.dart';

/// Coalesces very short *visual* stage transitions only. Never advances counts,
/// adds work, waits in the scanner, or queues a history of completed stages.
class ScanStagePresentation extends StatefulWidget {
  const ScanStagePresentation({
    required this.snapshot,
    required this.builder,
    super.key,
  });
  final ScanSnapshot? snapshot;
  final Widget Function(BuildContext, ScanSnapshot?) builder;
  @override
  State<ScanStagePresentation> createState() => _ScanStagePresentationState();
}

class _ScanStagePresentationState extends State<ScanStagePresentation> {
  ScanSnapshot? _shown;
  Timer? _boundary;
  @override
  void initState() {
    super.initState();
    _shown = widget.snapshot;
  }

  @override
  void didUpdateWidget(ScanStagePresentation oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.snapshot;
    if (_shown?.id != next?.id || next?.outcome != ScanOutcome.running) {
      _boundary?.cancel();
      _boundary = null;
      _shown = next;
    } else if (_shown?.displayStage?.id == next?.displayStage?.id) {
      _boundary?.cancel();
      _boundary = null;
      _shown = next;
    } else {
      // Keep label/count/ring atomic while a boundary settles. Read the latest
      // real snapshot at expiry, skipping intermediate fast stages entirely.
      _boundary ??= Timer(const Duration(milliseconds: 240), () {
        if (mounted)
          setState(() {
            _shown = widget.snapshot;
            _boundary = null;
          });
      });
    }
  }

  @override
  void dispose() {
    _boundary?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _shown);
}
