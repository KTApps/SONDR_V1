import 'package:flutter/material.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../shared/ring/mini_ring.dart';
import '../../shared/ring/ring_dial.dart';

/// Temporary step-1 showcase: exercises the hero [RingDial] and [MiniRing] so
/// the greyscale ladder and double-stroke variant can be eyeballed before any
/// real screens exist. Replaced by the timer screen in step 2.
class RingShowcaseScreen extends StatefulWidget {
  const RingShowcaseScreen({super.key});

  @override
  State<RingShowcaseScreen> createState() => _RingShowcaseScreenState();
}

class _RingShowcaseScreenState extends State<RingShowcaseScreen> {
  // Drive the dial from sliders so the animation + ladder can be checked live.
  double _task = 0.65;
  double _habit = 0.4;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sondr', style: Theme.of(context).textTheme.headlineMedium),
              Text(
                'ring component · step 1',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 28),

              // The hero, on a solid surface.
              Center(
                child: RingDial(
                  taskProgress: _task,
                  habitProgress: _habit,
                  size: 280,
                  centerValue: '13 hrs',
                  centerLabel: 'today',
                ),
              ),
              const SizedBox(height: 28),

              _slider('Task ring', _task, (v) => setState(() => _task = v)),
              _slider('Habit ring', _habit, (v) => setState(() => _habit = v)),
              const SizedBox(height: 16),

              Text('Last 10 days', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _miniRow(),
              const SizedBox(height: 28),

              Text('On a photo', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _photoSample(tokens),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _slider(String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 84,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(child: Slider(value: value, onChanged: onChanged)),
      ],
    );
  }

  Widget _miniRow() {
    // Stand-in progress values for ten past days.
    const days = [0.9, 0.4, 1.0, 0.7, 0.2, 0.55, 0.85, 0.3, 0.6, 1.0];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final p in days) MiniRing(progress: p, size: 28),
      ],
    );
  }

  Widget _photoSample(GreyscaleTokens tokens) {
    // No real photo asset yet — a busy greyscale gradient stands in to prove
    // the halos keep the ring legible over a varied background.
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 320,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEDEDED), Color(0xFF2A2A2A), Color(0xFFBBBBBB)],
          ),
        ),
        child: Stack(
          children: [
            // The baked-in scrim: darker top/bottom, lighter middle.
            Positioned.fill(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent, Colors.black54],
                    stops: [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
            Center(
              child: RingDial(
                taskProgress: _task,
                habitProgress: _habit,
                size: 220,
                onPhoto: true,
                centerValue: '13 hrs',
                centerLabel: 'today',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
