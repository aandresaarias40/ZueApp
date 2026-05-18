import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_theme.dart';

class AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final int? maxLines;
  final int? maxLength;
  final bool enabled;
  final void Function(String)? onChanged;
  final List<TextInputFormatter>? inputFormatters;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.prefixIcon,
    this.suffixIcon,
    this.validator,
    this.maxLines = 1,
    this.maxLength,
    this.enabled = true,
    this.onChanged,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: obscureText ? 1 : maxLines,
      maxLength: maxLength,
      enabled: enabled,
      onChanged: onChanged,
      validator: validator,
      inputFormatters: inputFormatters,
      style: const TextStyle(
        fontFamily: 'Poppins',
        fontSize: 15,
        color: AppTheme.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',  // Ocultar contador de caracteres
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: AppTheme.textSecondary, size: 22)
            : null,
        suffixIcon: suffixIcon,
      ),
    );
  }
}
