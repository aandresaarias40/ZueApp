import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/trip_model.dart';

class TripRequestSheet extends StatefulWidget {
  final TripModel trip;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const TripRequestSheet({
    super.key,
    required this.trip,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<TripRequestSheet> createState() => _TripRequestSheetState();
}

class _TripRequestSheetState extends State<TripRequestSheet> {
  late Timer _timer;
  int _secondsLeft = 30; // 30 segundos para aceptar

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        _timer.cancel();
        widget.onReject();
        if (mounted) Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Timer
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 70,
                height: 70,
                child: CircularProgressIndicator(
                  value: _secondsLeft / 30,
                  strokeWidth: 5,
                  backgroundColor: AppTheme.dividerColor,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _secondsLeft > 10
                        ? AppTheme.primaryColor
                        : AppTheme.errorColor,
                  ),
                ),
              ),
              Text(
                '$_secondsLeft',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _secondsLeft > 10
                      ? AppTheme.primaryColor
                      : AppTheme.errorColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          const Text(
            '¡Nueva solicitud de viaje!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),

          // Pasajero
          Row(
            children: [
              const CircleAvatar(
                radius: 22,
                backgroundColor: Color(0xFFF0F4FF),
                child: Icon(Icons.person, color: AppTheme.primaryColor),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.trip.passengerName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Pasajero',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (widget.trip.fare != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '\$${widget.trip.fare!.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    Text(
                      'COP',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 20),

          // Ruta
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.backgroundColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _RouteRow(
                  icon: Icons.circle,
                  iconColor: AppTheme.successColor,
                  address: widget.trip.originAddress,
                  label: 'Origen',
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Icon(Icons.more_vert,
                      size: 16, color: AppTheme.textSecondary),
                ),
                _RouteRow(
                  icon: Icons.location_on,
                  iconColor: AppTheme.errorColor,
                  address: widget.trip.destinationAddress,
                  label: 'Destino',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Botones
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: OutlinedButton(
                    onPressed: () {
                      _timer.cancel();
                      widget.onReject();
                      Navigator.pop(context);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.errorColor,
                      side: const BorderSide(color: AppTheme.errorColor),
                    ),
                    child: const Text('Rechazar'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () {
                      _timer.cancel();
                      widget.onAccept();
                      Navigator.pop(context);
                    },
                    child: const Text('Aceptar viaje'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String address;
  final String label;

  const _RouteRow({
    required this.icon,
    required this.iconColor,
    required this.address,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 12, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.textSecondary,
                ),
              ),
              Text(
                address,
                style: const TextStyle(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
