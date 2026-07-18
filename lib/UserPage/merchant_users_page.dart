import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Common/merchant_permissions.dart';
import '../Controller/merchant_session_provider.dart';
import '../Controller/merchant_users_provider.dart';
import '../Models/merchant_managed_user.dart';

class MerchantUsersPage extends StatefulWidget {
  const MerchantUsersPage({super.key});

  @override
  State<MerchantUsersPage> createState() => _MerchantUsersPageState();
}

class _MerchantUsersPageState extends State<MerchantUsersPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  Future<void> _fetch() async {
    final session = context.read<MerchantSessionProvider>();
    final token = session.token;
    if (token == null) return;
    await context.read<MerchantUsersProvider>().fetchAll(
      apiClient: session.apiClient,
      token: token,
    );
  }

  Future<void> _createUser() async {
    final session = context.read<MerchantSessionProvider>();
    final input = await showDialog<_CreateUserInput>(
      context: context,
      builder: (_) => _CreateUserDialog(
        canCreateOwner: session.merchantUser?.role == 'owner',
      ),
    );
    if (!mounted || input == null || session.token == null) return;

    final provider = context.read<MerchantUsersProvider>();
    final ok = await provider.createUser(
      apiClient: session.apiClient,
      token: session.token!,
      username: input.username,
      displayName: input.displayName,
      role: input.role,
      password: input.password,
    );
    if (!mounted) return;
    _showResult(
      ok,
      success: 'User created. A password change is required at first login.',
    );
  }

  Future<void> _editUser(MerchantManagedUser user) async {
    final session = context.read<MerchantSessionProvider>();
    final input = await showDialog<_EditUserInput>(
      context: context,
      builder: (_) => _EditUserDialog(
        user: user,
        canManageOwner: session.merchantUser?.role == 'owner',
        isCurrentUser: session.merchantUser?.id == user.id,
      ),
    );
    if (!mounted || input == null || session.token == null) return;

    final provider = context.read<MerchantUsersProvider>();
    final ok = await provider.updateUser(
      apiClient: session.apiClient,
      token: session.token!,
      merchantUserId: user.id,
      displayName: input.displayName,
      role: input.role,
      active: input.active,
    );
    if (!mounted) return;
    _showResult(ok, success: 'User updated.');
  }

  Future<void> _editPermissions(MerchantManagedUser user) async {
    final provider = context.read<MerchantUsersProvider>();
    final overrides = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _PermissionsDialog(
        user: user,
        catalog: provider.permissionCatalog,
        roleDefaults: provider.roleDefaults[user.role] ?? const <String>{},
        readOnly: false,
      ),
    );
    if (!mounted || overrides == null) return;

    final session = context.read<MerchantSessionProvider>();
    if (session.token == null) return;
    final ok = await provider.updatePermissions(
      apiClient: session.apiClient,
      token: session.token!,
      merchantUserId: user.id,
      overrides: overrides,
    );
    if (!mounted) return;
    _showResult(ok, success: 'Permissions updated. The user must login again.');
  }

  Future<void> _viewPermissions(MerchantManagedUser user) async {
    final provider = context.read<MerchantUsersProvider>();
    await showDialog<void>(
      context: context,
      builder: (_) => _PermissionsDialog(
        user: user,
        catalog: provider.permissionCatalog,
        roleDefaults: provider.roleDefaults[user.role] ?? const <String>{},
        readOnly: true,
      ),
    );
  }

  Future<void> _resetPassword(MerchantManagedUser user) async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => _ResetPasswordDialog(user: user),
    );
    if (!mounted || password == null) return;

    final session = context.read<MerchantSessionProvider>();
    if (session.token == null) return;
    final provider = context.read<MerchantUsersProvider>();
    final ok = await provider.resetPassword(
      apiClient: session.apiClient,
      token: session.token!,
      merchantUserId: user.id,
      password: password,
    );
    if (!mounted) return;
    _showResult(
      ok,
      success: 'Temporary password saved. The user must change it at login.',
    );
  }

  void _showResult(bool ok, {required String success}) {
    final provider = context.read<MerchantUsersProvider>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? success : provider.errorMessage ?? 'Unable to save user.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MerchantUsersProvider>();
    final session = context.watch<MerchantSessionProvider>();
    final canManage = session.can(MerchantPermissions.usersManage);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Users & Permissions'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: provider.isLoading ? null : _fetch,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            if (provider.isLoading) const LinearProgressIndicator(),
            if (provider.errorMessage != null && provider.users.isEmpty)
              _ErrorPanel(message: provider.errorMessage!, onRetry: _fetch),
            if (!provider.isLoading && provider.users.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: Center(child: Text('No merchant users found.')),
              ),
            for (final user in provider.users) ...[
              _UserCard(
                user: user,
                canManage: canManage,
                canManageOwner: session.merchantUser?.role == 'owner',
                isCurrentUser: session.merchantUser?.id == user.id,
                onEdit: () => _editUser(user),
                onViewPermissions: () => _viewPermissions(user),
                onPermissions: () => _editPermissions(user),
                onResetPassword: () => _resetPassword(user),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: provider.isSaving ? null : _createUser,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Add user'),
            )
          : null,
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.canManage,
    required this.canManageOwner,
    required this.isCurrentUser,
    required this.onEdit,
    required this.onViewPermissions,
    required this.onPermissions,
    required this.onResetPassword,
  });

  final MerchantManagedUser user;
  final bool canManage;
  final bool canManageOwner;
  final bool isCurrentUser;
  final VoidCallback onEdit;
  final VoidCallback onViewPermissions;
  final VoidCallback onPermissions;
  final VoidCallback onResetPassword;

  @override
  Widget build(BuildContext context) {
    final ownerLocked = user.isOwner && !canManageOwner;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              child: Text(
                user.resolvedName.isEmpty
                    ? '?'
                    : user.resolvedName.substring(0, 1).toUpperCase(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        user.resolvedName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      _Badge(label: _titleCase(user.role)),
                      _Badge(
                        label: user.active ? 'Active' : 'Inactive',
                        muted: !user.active,
                      ),
                      if (isCurrentUser) const _Badge(label: 'You'),
                      if (user.mustChangePassword)
                        const _Badge(label: 'Password change required'),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text('@${user.username}'),
                  const SizedBox(height: 3),
                  Text(
                    '${user.permissions.length} permissions · Last login ${_dateLabel(user.lastLoginAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'User actions',
              onSelected: (value) {
                switch (value) {
                  case 'view_permissions':
                    onViewPermissions();
                  case 'edit':
                    onEdit();
                  case 'permissions':
                    onPermissions();
                  case 'password':
                    onResetPassword();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'view_permissions',
                  child: Text('View access'),
                ),
                if (canManage && !ownerLocked)
                  const PopupMenuItem(value: 'edit', child: Text('Edit user')),
                if (canManage &&
                    !ownerLocked &&
                    !user.isOwner &&
                    !isCurrentUser)
                  const PopupMenuItem(
                    value: 'permissions',
                    child: Text('Edit permissions'),
                  ),
                if (canManage && !ownerLocked && !isCurrentUser)
                  const PopupMenuItem(
                    value: 'password',
                    child: Text('Reset password'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.muted = false});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: muted ? colors.surfaceContainerHighest : colors.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog({required this.canCreateOwner});

  final bool canCreateOwner;

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  String _role = 'staff';
  bool _obscure = true;

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add merchant user'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _username,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Username'),
                  validator: (value) {
                    final username = value?.trim() ?? '';
                    return RegExp(r'^[A-Za-z0-9._-]{3,64}$').hasMatch(username)
                        ? null
                        : 'Use 3-64 letters, numbers, dot, dash, or underscore';
                  },
                ),
                TextFormField(
                  controller: _displayName,
                  decoration: const InputDecoration(labelText: 'Display name'),
                  validator: (value) =>
                      (value?.trim().isEmpty ?? true) ? 'Required' : null,
                ),
                DropdownButtonFormField<String>(
                  value: _role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: [
                    if (widget.canCreateOwner)
                      const DropdownMenuItem(
                        value: 'owner',
                        child: Text('Owner'),
                      ),
                    const DropdownMenuItem(
                      value: 'manager',
                      child: Text('Manager'),
                    ),
                    const DropdownMenuItem(
                      value: 'staff',
                      child: Text('Staff'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _role = value ?? 'staff'),
                ),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Temporary password',
                    helperText: 'At least 10 characters',
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) => (value?.length ?? 0) < 10
                      ? 'Use at least 10 characters'
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.pop(
              context,
              _CreateUserInput(
                username: _username.text.trim(),
                displayName: _displayName.text.trim(),
                role: _role,
                password: _password.text,
              ),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _EditUserDialog extends StatefulWidget {
  const _EditUserDialog({
    required this.user,
    required this.canManageOwner,
    required this.isCurrentUser,
  });

  final MerchantManagedUser user;
  final bool canManageOwner;
  final bool isCurrentUser;

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  late final TextEditingController _displayName;
  late String _role;
  late bool _active;

  @override
  void initState() {
    super.initState();
    _displayName = TextEditingController(text: widget.user.displayName);
    _role = widget.user.role;
    _active = widget.user.active;
  }

  @override
  void dispose() {
    _displayName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.user.resolvedName}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _displayName,
              decoration: const InputDecoration(labelText: 'Display name'),
            ),
            DropdownButtonFormField<String>(
              value: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: [
                if (widget.canManageOwner)
                  const DropdownMenuItem(value: 'owner', child: Text('Owner')),
                const DropdownMenuItem(
                  value: 'manager',
                  child: Text('Manager'),
                ),
                const DropdownMenuItem(value: 'staff', child: Text('Staff')),
              ],
              onChanged: (value) => setState(() => _role = value ?? _role),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              subtitle: widget.isCurrentUser
                  ? const Text('You cannot deactivate your own account.')
                  : null,
              value: _active,
              onChanged: widget.isCurrentUser
                  ? null
                  : (value) => setState(() => _active = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _displayName.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              _EditUserInput(displayName: name, role: _role, active: _active),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _PermissionsDialog extends StatefulWidget {
  const _PermissionsDialog({
    required this.user,
    required this.catalog,
    required this.roleDefaults,
    required this.readOnly,
  });

  final MerchantManagedUser user;
  final List<MerchantPermissionDefinition> catalog;
  final Set<String> roleDefaults;
  final bool readOnly;

  @override
  State<_PermissionsDialog> createState() => _PermissionsDialogState();
}

class _PermissionsDialogState extends State<_PermissionsDialog> {
  late final Map<String, String> _overrides;

  @override
  void initState() {
    super.initState();
    _overrides = {...widget.user.permissionOverrides};
  }

  bool _effective(String permission) {
    final override = _overrides[permission];
    if (override == 'allow') return true;
    if (override == 'deny') return false;
    return widget.roleDefaults.contains(permission);
  }

  void _setEffective(String permission, bool allowed) {
    final roleAllowed = widget.roleDefaults.contains(permission);
    setState(() {
      if (allowed == roleAllowed) {
        _overrides.remove(permission);
      } else {
        _overrides[permission] = allowed ? 'allow' : 'deny';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final modules = <String, List<MerchantPermissionDefinition>>{};
    for (final permission in widget.catalog) {
      modules.putIfAbsent(permission.module, () => []).add(permission);
    }
    return AlertDialog(
      title: Text('${widget.user.resolvedName} access'),
      content: SizedBox(
        width: 620,
        height: MediaQuery.sizeOf(context).height * 0.68,
        child: ListView(
          children: [
            Text('Role defaults: ${_titleCase(widget.user.role)}'),
            const SizedBox(height: 8),
            for (final entry in modules.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(
                  entry.key,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              for (final permission in entry.value)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _effective(permission.key),
                  title: Text(permission.displayName),
                  subtitle: Text(
                    '${permission.description}${_overrideLabel(permission.key)}',
                  ),
                  onChanged: widget.readOnly
                      ? null
                      : (value) =>
                            _setEffective(permission.key, value ?? false),
                ),
            ],
          ],
        ),
      ),
      actions: [
        if (!widget.readOnly)
          TextButton(
            onPressed: () => setState(_overrides.clear),
            child: const Text('Use role defaults'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.readOnly ? 'Close' : 'Cancel'),
        ),
        if (!widget.readOnly)
          FilledButton(
            onPressed: () => Navigator.pop(context, _overrides),
            child: const Text('Save permissions'),
          ),
      ],
    );
  }

  String _overrideLabel(String permission) {
    return switch (_overrides[permission]) {
      'allow' => ' Custom allow.',
      'deny' => ' Custom deny.',
      _ => '',
    };
  }
}

class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog({required this.user});

  final MerchantManagedUser user;

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Reset ${widget.user.resolvedName} password'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _password,
          autofocus: true,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'Temporary password',
            helperText: 'At least 10 characters',
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
          validator: (value) =>
              (value?.length ?? 0) < 10 ? 'Use at least 10 characters' : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.pop(context, _password.text);
          },
          child: const Text('Reset password'),
        ),
      ],
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _CreateUserInput {
  const _CreateUserInput({
    required this.username,
    required this.displayName,
    required this.role,
    required this.password,
  });

  final String username;
  final String displayName;
  final String role;
  final String password;
}

class _EditUserInput {
  const _EditUserInput({
    required this.displayName,
    required this.role,
    required this.active,
  });

  final String displayName;
  final String role;
  final bool active;
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';
}

String _dateLabel(DateTime? value) {
  if (value == null) return 'Never';
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}
