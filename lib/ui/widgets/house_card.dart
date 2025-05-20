import 'package:flutter/material.dart';
import 'energy_indicator.dart';

class HouseCard extends StatelessWidget {
  final String title;
  final double energy;
  final double voltage;
  final double current;
  final bool relayStatus;
  final VoidCallback onRecharge;
  final ValueChanged<bool> onRelayToggle;

  const HouseCard({
    super.key,
    required this.title,
    required this.energy,
    required this.voltage,
    required this.current,
    required this.relayStatus,
    required this.onRecharge,
    required this.onRelayToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Switch(
                  value: relayStatus,
                  onChanged: onRelayToggle,
                  activeColor: Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                EnergyIndicator(
                  icon: Icons.bolt,
                  label: 'Énergie',
                  value: energy,
                  max: 100, // Supposons que 100 kWh est le maximum
                  unit: 'kWh',
                ),
                EnergyIndicator(
                  icon: Icons.electric_meter,
                  label: 'Tension',
                  value: voltage,
                  max: 250, // Par exemple, 250V comme tension max
                  unit: 'V',
                ),
                EnergyIndicator(
                  icon: Icons.power,
                  label: 'Courant',
                  value: current,
                  max: 32, // Par exemple, 32A comme courant max
                  unit: 'A',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: onRecharge,
                  icon: const Icon(Icons.add),
                  label: const Text('Recharger'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
