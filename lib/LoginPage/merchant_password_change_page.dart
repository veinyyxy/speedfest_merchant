import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Controller/merchant_session_provider.dart';

class MerchantPasswordChangePage extends StatefulWidget {
  const MerchantPasswordChangePage({super.key, this.required = false});

  final bool required;

  @override
  State<MerchantPasswordChangePage> createState() =>
      _MerchantPasswordChangePageState();
}

class _MerchantPasswordChangePageState
    extends State<MerchantPasswordChangePage> {
  final _formKey = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _isSaving = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);
    final session = context.read<MerchantSessionProvider>();
    final ok = await session.changePassword(
      currentPassword: _currentPassword.text,
      newPassword: _newPassword.text,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (ok) {
      if (!widget.required && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password changed.')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(session.errorMessage ?? 'Unable to change password.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MerchantSessionProvider>();
    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Card(
          margin: const EdgeInsets.all(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.required ? 'Set a new password' : 'Change password',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (widget.required) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Your temporary password must be changed before using the merchant app.',
                    ),
                  ],
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _currentPassword,
                    autofocus: true,
                    obscureText: _obscureCurrent,
                    decoration: InputDecoration(
                      labelText: 'Current password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'Show password',
                        onPressed: () =>
                            setState(() => _obscureCurrent = !_obscureCurrent),
                        icon: Icon(
                          _obscureCurrent
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) =>
                        value?.isEmpty == true ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _newPassword,
                    obscureText: _obscureNew,
                    decoration: InputDecoration(
                      labelText: 'New password',
                      helperText: 'At least 10 characters',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'Show password',
                        onPressed: () =>
                            setState(() => _obscureNew = !_obscureNew),
                        icon: Icon(
                          _obscureNew
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => (value?.length ?? 0) < 10
                        ? 'Use at least 10 characters'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmPassword,
                    obscureText: _obscureNew,
                    decoration: const InputDecoration(
                      labelText: 'Confirm new password',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value != _newPassword.text
                        ? 'Passwords do not match'
                        : null,
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.password_outlined),
                    label: Text(_isSaving ? 'Saving' : 'Change password'),
                  ),
                  if (widget.required) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _isSaving || session.isLoggingOut
                          ? null
                          : session.logout,
                      child: Text(
                        session.isLoggingOut ? 'Logging out' : 'Logout',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.required) return Scaffold(body: content);
    return Scaffold(
      appBar: AppBar(title: const Text('Password')),
      body: content,
    );
  }
}
