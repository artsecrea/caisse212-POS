import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/permission_service.dart';

/// Widget that shows/hides content based on user permissions
class PermissionGuard extends ConsumerWidget {
  final String? permission;
  final List<String>? permissions;
  final bool requireAll;
  final Widget child;
  final Widget? fallback;
  final bool showTooltip;

  const PermissionGuard({
    super.key,
    this.permission,
    this.permissions,
    this.requireAll = false,
    required this.child,
    this.fallback,
    this.showTooltip = false,
  }) : assert(permission != null || permissions != null, 'Either permission or permissions must be provided');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissionService = ref.watch(permissionServiceProvider);

    bool hasAccess;
    if (permission != null) {
      hasAccess = permissionService.hasPermission(permission!);
    } else if (permissions != null) {
      hasAccess = requireAll
          ? permissionService.hasAllPermissions(permissions!)
          : permissionService.hasAnyPermission(permissions!);
    } else {
      hasAccess = false;
    }

    if (!hasAccess) {
      if (showTooltip) {
        return Tooltip(
          message: 'Insufficient permissions',
          child: Opacity(
            opacity: 0.3,
            child: IgnorePointer(child: child),
          ),
        );
      }
      return fallback ?? const SizedBox.shrink();
    }

    return child;
  }
}

/// Button wrapper with permission check
class PermissionButton extends ConsumerWidget {
  final String permission;
  final VoidCallback onPressed;
  final Widget child;
  final ButtonStyle? style;
  final String? tooltip;

  const PermissionButton({
    super.key,
    required this.permission,
    required this.onPressed,
    required this.child,
    this.style,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissionService = ref.watch(permissionServiceProvider);
    final hasPermission = permissionService.hasPermission(permission);

    final button = ElevatedButton(
      onPressed: hasPermission ? onPressed : null,
      style: style,
      child: child,
    );

    if (!hasPermission && tooltip != null) {
      return Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    return button;
  }
}

/// IconButton wrapper with permission check
class PermissionIconButton extends ConsumerWidget {
  final String permission;
  final VoidCallback onPressed;
  final Icon icon;
  final String? tooltip;
  final Color? color;

  const PermissionIconButton({
    super.key,
    required this.permission,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissionService = ref.watch(permissionServiceProvider);
    final hasPermission = permissionService.hasPermission(permission);

    return IconButton(
      onPressed: hasPermission ? onPressed : null,
      icon: icon,
      tooltip: tooltip ?? (hasPermission ? null : 'Insufficient permissions'),
      color: hasPermission ? color : Colors.grey,
    );
  }
}

/// Menu item wrapper with permission check
class PermissionMenuItem extends ConsumerWidget {
  final String permission;
  final VoidCallback onTap;
  final Widget title;
  final Widget? leading;
  final Widget? trailing;

  const PermissionMenuItem({
    super.key,
    required this.permission,
    required this.onTap,
    required this.title,
    this.leading,
    this.trailing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissionService = ref.watch(permissionServiceProvider);
    final hasPermission = permissionService.hasPermission(permission);

    if (!hasPermission) {
      return const SizedBox.shrink();
    }

    return ListTile(
      leading: leading,
      title: title,
      trailing: trailing,
      onTap: onTap,
    );
  }
}

/// Mixin for checking permissions in widgets
mixin PermissionCheckMixin on ConsumerWidget {
  bool checkPermission(WidgetRef ref, String permission) {
    return ref.read(permissionServiceProvider).hasPermission(permission);
  }

  void showPermissionDenied(BuildContext context, {String? message}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message ?? 'You do not have permission to perform this action'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

