import 'package:flutter/material.dart';

class EnergyIndicator extends StatelessWidget {
  final double value;
  final double max;
  final IconData icon;
  final String label;
  final String? unit;

  const EnergyIndicator({
    super.key,
    required this.value,
    required this.max,
    required this.icon,
    required this.label,
    this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.blue),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(
              '${value.toStringAsFixed(2)}${unit != null ? ' $unit' : ''}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0,
          minHeight: 10,
          backgroundColor: Colors.grey[300],
          valueColor: AlwaysStoppedAnimation<Color>(
            value > (0.2 * max) ? Colors.green : Colors.red,
          ),
        ),
      ],
    );
  }
}
