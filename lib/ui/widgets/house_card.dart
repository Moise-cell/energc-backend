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
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.blue.shade50, Colors.white],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  Switch(
                    value: relayStatus,
                    onChanged: onRelayToggle,
                    activeColor: Colors.green,
                    activeTrackColor: Colors.green.shade200,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withAlpha(26),
                      spreadRadius: 1,
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    EnergyIndicator(
                      value: energy,
                      max: 100,
                      icon: Icons.bolt,
                      label: 'Énergie',
                      unit: 'kWh',
                    ),
                    const SizedBox(height: 15),
                    EnergyIndicator(
                      value: voltage,
                      max: 240,
                      icon: Icons.electric_bolt,
                      label: 'Tension',
                      unit: 'V',
                    ),
                    const SizedBox(height: 15),
                    EnergyIndicator(
                      value: current,
                      max: 30,
                      icon: Icons.power,
                      label: 'Courant',
                      unit: 'A',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onRecharge,
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Recharger'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
