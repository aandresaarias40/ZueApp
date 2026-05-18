import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class RatingDialog extends StatefulWidget {
  final String driverName;
  final void Function(int rating, String? comment) onRated;

  const RatingDialog({
    super.key,
    required this.driverName,
    required this.onRated,
  });

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  int _rating = 5;
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: AppTheme.successColor, size: 56),
            const SizedBox(height: 16),
            const Text(
              '¡Llegaste a tu destino!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '¿Cómo fue tu viaje con ${widget.driverName}?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 24),

            // Estrellas
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                5,
                (index) => GestureDetector(
                  onTap: () => setState(() => _rating = index + 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      index < _rating ? Icons.star : Icons.star_border,
                      color: AppTheme.accentColor,
                      size: 40,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Comentario opcional
            TextField(
              controller: _commentController,
              decoration: const InputDecoration(
                hintText: 'Deja un comentario (opcional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => widget.onRated(
                  _rating,
                  _commentController.text.isEmpty
                      ? null
                      : _commentController.text,
                ),
                child: const Text('Enviar calificación'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
