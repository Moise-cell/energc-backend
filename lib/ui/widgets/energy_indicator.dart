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
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.blue),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Text(
              '${value.toStringAsFixed(2)}${unit != null ? ' $unit' : ''}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 200,
          height: 10,
          child: LinearProgressIndicator(
            value: max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(
              value > (0.2 * max) ? Colors.green : Colors.red,
            ),
          ),
        ),
      ],
    );
  }
}
