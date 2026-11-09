import 'dart:async';
import 'package:flutter/material.dart';
import 'data/strength_session.dart';

class RestTimer extends StatefulWidget {
  final StrengthSession session;
  final VoidCallback? onStop;
  final VoidCallback? onConfigure;
  const RestTimer({
    super.key,
    required this.session,
    this.onStop,
    this.onConfigure,
  });
  @override
  State<RestTimer> createState() => _RestTimerState();
}

class _RestTimerState extends State<RestTimer> with WidgetsBindingObserver {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = widget.session.restRemaining(DateTime.now());
    final hasTimer =
        widget.session.data['restUntil'] != null ||
        widget.session.data['pausedRestSeconds'] != null;
    final text = seconds > 0
        ? '${widget.session.status == 'paused' ? 'Paused rest' : 'Rest'} ${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}'
        : hasTimer
        ? 'Rest complete'
        : 'Rest timer';
    if (!hasTimer) return const SizedBox.shrink();
    return SizedBox(
      height: 32,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.timer_outlined, size: 16),
          const SizedBox(width: 6),
          Semantics(liveRegion: seconds == 0, child: Text(text)),
          IconButton(
            tooltip: 'Stop rest',
            padding: EdgeInsets.zero,
            iconSize: 18,
            onPressed: widget.onStop,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
