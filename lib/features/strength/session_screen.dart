import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/session_repository.dart';
import 'data/strength_session.dart';
import 'rest_timer.dart';
import 'package:go_router/go_router.dart';
import 'session_exercise_card.dart';

class SessionScreen extends ConsumerStatefulWidget {
  final int sessionId;
  const SessionScreen({super.key, required this.sessionId});
  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  bool warmup = false;
  bool saving = false;
  String? error;
  SessionRepository get repo => ref.read(sessionRepositoryProvider);
  Future<void> operate(Future<StrengthSession> Function() action) async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await action();
      ref.read(sessionRevisionProvider.notifier).refresh();
      await ref.read(sessionProvider(widget.sessionId).future);
    } catch (e) {
      if (mounted) setState(() => error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> finish(StrengthSession session, bool cancel) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(cancel ? 'Cancel workout?' : 'Finish workout?'),
        content: Text(
          cancel
              ? 'Your recorded sets will be kept in a cancelled session for review.'
              : '${session.completedSets}/${session.totalSets} sets recorded. Unfinished and skipped sets will be kept as a partial workout.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep logging'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(cancel ? 'Cancel workout' : 'Save workout'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await operate(() => repo.finish(session.id, cancel: cancel));
      if (mounted && error == null && !cancel) {
        context.go('/completed/${session.id}');
      }
    }
  }

  Future<void> configureRest(StrengthSession session) async {
    final controller = TextEditingController(
      text: '${session.data['restSeconds'] ?? ''}',
    );
    String? validation;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rest after each set'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Blank uses exercise settings (90 seconds if unset). 0 turns rest off. Applies to the next completed set.',
              ),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Seconds (0–3600)',
                  errorText: validation,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                final number = int.tryParse(text);
                if (text.isNotEmpty &&
                    (number == null || number < 0 || number > 3600)) {
                  setDialogState(
                    () => validation = 'Enter 0–3600 or leave blank',
                  );
                  return;
                }
                Navigator.pop(context, text);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    // Dispose after the dialog route has finished its closing animation.
    Future<void>.delayed(const Duration(milliseconds: 300), controller.dispose);
    if (value != null && mounted) {
      await operate(
        () => repo.configureRest(
          session.id,
          value.isEmpty ? null : int.parse(value),
        ),
      );
    }
  }

  Future<void> notes(StrengthSession session) async {
    final controller = TextEditingController(
      text: session.data['notes'] as String? ?? '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Workout notes'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          readOnly: !session.unfinished,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (session.unfinished)
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Save'),
            ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 300), controller.dispose);
    if (value != null && mounted) {
      await operate(() => repo.saveNotes(session.id, value));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sessionProvider(widget.sessionId));
    final session = state.value;
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Workout')),
        body: Center(
          child: state.hasError
              ? Text('${state.error}')
              : const CircularProgressIndicator(),
        ),
      );
    }
    return PopScope(
      canPop: !saving,
      child: Scaffold(
        appBar: AppBar(
          title: PopupMenuButton<String>(
            tooltip: 'Active workout',
            onSelected: (value) {
              if (value == 'choose') context.go('/');
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'active', child: Text(session.name)),
              const PopupMenuItem(
                value: 'choose',
                child: Text('Choose workout'),
              ),
            ],
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    session.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
          actions: [
            if (session.unfinished)
              TextButton(
                onPressed: saving ? null : () => finish(session, false),
                child: const Text('Finish'),
              ),
            if (session.unfinished)
              IconButton(
                tooltip: 'Configure rest timer',
                icon: const Icon(Icons.timer_outlined),
                onPressed: saving ? null : () => configureRest(session),
              ),
            PopupMenuButton<String>(
              tooltip: 'Workout options',
              onSelected: (value) {
                if (value == 'notes') notes(session);
                if (value == 'pause') {
                  operate(
                    () => session.status == 'paused'
                        ? repo.resume(session.id)
                        : repo.pause(session.id),
                  );
                }
                if (value == 'cancel') finish(session, true);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'notes',
                  child: Text('Workout notes'),
                ),
                if (session.unfinished)
                  PopupMenuItem(
                    value: 'pause',
                    enabled: !saving,
                    child: Text(
                      session.status == 'paused'
                          ? 'Resume workout'
                          : 'Pause workout',
                    ),
                  ),
                if (session.unfinished)
                  PopupMenuItem(
                    value: 'cancel',
                    enabled: !saving,
                    child: const Text('Discard workout'),
                  ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Row(
              children: [
                for (final tab in ['Workout', 'Warmup'])
                  Expanded(
                    child: TextButton(
                      onPressed: () => setState(() => warmup = tab == 'Warmup'),
                      child: Text(
                        tab,
                        style: TextStyle(
                          color: warmup == (tab == 'Warmup')
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                          fontWeight: warmup == (tab == 'Warmup')
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (session.status == 'paused')
              TextButton(
                onPressed: saving
                    ? null
                    : () => operate(() => repo.resume(session.id)),
                child: const Text('Paused - Resume workout'),
              ),
            if (error != null || state.hasError)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  error ?? '${state.error}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (session.unfinished)
              RestTimer(
                session: session,
                onStop: saving
                    ? null
                    : () => operate(() => repo.stopRest(session.id)),
              ),
            Expanded(
              child: ListView.builder(
                key: PageStorageKey('session-${session.id}-$warmup'),
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: session.exercises.length,
                itemBuilder: (context, index) {
                  if ((session.exercises[index]['target']['warmup'] == true) !=
                      warmup) {
                    return const SizedBox.shrink();
                  }
                  return SessionExerciseCard(
                    session: session,
                    index: index,
                    saving: saving,
                    operate: operate,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
