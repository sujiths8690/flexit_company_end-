import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/models/models.dart';
import '../../core/utils/utils.dart';
import '../../providers/admin_auth/admin_auth_provider.dart';
import '../../widgets/common/common_widgets.dart';
import 'user_detail_screen.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  final _searchCtrl = TextEditingController();
  String _filter = 'All';
  List<Customer> _filtered = [];
  bool _isLoading = true;
  String? _error;

  final _filters = ['All', 'Active', 'Flagged', 'Banned'];

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final customers = await ref.read(adminAuthServiceProvider).fetchUsers(
            search: _searchCtrl.text,
            status: _filter,
          );
      if (!mounted) return;
      setState(() {
        _filtered = customers;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _setFilter(String f) {
    setState(() => _filter = f);
    _loadUsers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadUsers,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                FxSearchBar(
                  hint: 'Search by name, ID, email...',
                  controller: _searchCtrl,
                  onChanged: (_) => _loadUsers(),
                ),
                const SizedBox(height: 10),
                FxFilterChips(
                  options: _filters,
                  selected: _filter,
                  onChanged: _setFilter,
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _UsersErrorState(
                  message: _error!,
                  onRetry: _loadUsers,
                )
          : _filtered.isEmpty
              ? const FxEmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No users found',
                  subtitle: 'Try adjusting your search or filter',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _CustomerTile(
                    customer: _filtered[i],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            UserDetailScreen(customer: _filtered[i]),
                      ),
                    ),
                  ),
                ),
    );
  }
}

class _UsersErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _UsersErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 44,
              color: AppColors.error,
            ),
            const SizedBox(height: 12),
            const Text(
              'Could not load users',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  final Customer customer;
  final VoidCallback onTap;

  const _CustomerTile({required this.customer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FxCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Stack(
            children: [
              FxAvatar(
                initials: customer.avatarInitials ??
                    customer.name.substring(0, 2).toUpperCase(),
                size: 46,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: customer.isOnline
                        ? AppColors.success
                        : AppColors.textMuted,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? AppColors.darkCard : AppColors.lightCard,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        customer.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.textPrimary
                              : AppColors.textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    StatusBadge(customer.status),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  customer.businessName,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _pill(
                        AppUtils.planEmoji(customer.plan) + ' ' + customer.plan,
                        AppUtils.planColor(customer.plan)),
                    const SizedBox(width: 6),
                    _pill('${customer.deviceCount} devices', AppColors.info),
                    const Spacer(),
                    Text(
                      customer.id,
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded,
              size: 18,
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ],
      ),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
