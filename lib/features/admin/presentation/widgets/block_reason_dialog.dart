import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';

/// Resultado del diálogo de bloqueo/suspensión.
class BlockReasonResult {
  final String category; // incident, disciplinary, fraud, other
  final String reason;
  const BlockReasonResult({required this.category, required this.reason});
}

/// Diálogo reutilizable para bloquear cuentas o suspender conductores.
/// Pide categoría (incidente, medida disciplinaria, fraude, otro) y una
/// descripción obligatoria que queda en el historial de moderación.
Future<BlockReasonResult?> showBlockReasonDialog(
  BuildContext context, {
  required String title,
  required String subtitle,
  String confirmLabel = 'Bloquear',
}) {
  return showDialog<BlockReasonResult>(
    context: context,
    builder: (_) => _BlockReasonDialog(
      title: title,
      subtitle: subtitle,
      confirmLabel: confirmLabel,
    ),
  );
}

class _BlockReasonDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final String confirmLabel;

  const _BlockReasonDialog({
    required this.title,
    required this.subtitle,
    required this.confirmLabel,
  });

  @override
  State<_BlockReasonDialog> createState() => _BlockReasonDialogState();
}

class _BlockReasonDialogState extends State<_BlockReasonDialog> {
  final _reasonController = TextEditingController();
  String _category = AppConstants.blockCategoryIncident;
  String? _error;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _confirm() {
    final reason = _reasonController.text.trim();
    if (reason.length < 5) {
      setState(() => _error = 'Describe el motivo (mínimo 5 caracteres)');
      return;
    }
    Navigator.pop(
      context,
      BlockReasonResult(category: _category, reason: reason),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.subtitle,
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),

            // Categoría
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _category,
              decoration: const InputDecoration(
                labelText: 'Categoría',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: AppConstants.blockCategoryLabels.entries
                  .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _category = v!),
            ),
            const SizedBox(height: 12),

            // Descripción
            TextField(
              controller: _reasonController,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: 'Descripción del motivo',
                hintText: 'Ej: agresión verbal reportada por un pasajero el 10/06',
                alignLabelWithHint: true,
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _confirm,
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
