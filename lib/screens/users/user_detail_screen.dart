import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/models/models.dart';
import '../../core/utils/utils.dart';
import '../../providers/admin_auth/admin_auth_provider.dart';
import '../../widgets/common/common_widgets.dart';

class UserDetailScreen extends ConsumerStatefulWidget {
  final Customer customer;
  const UserDetailScreen({super.key, required this.customer});

  @override
  ConsumerState<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends ConsumerState<UserDetailScreen>
    with TickerProviderStateMixin {
  late TabController _tabCtrl;
  late Customer _customer;
  RequestAnalytics _requestAnalytics = const RequestAnalytics();

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    _tabCtrl = TabController(length: 4, vsync: this);
    _loadDetails();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Customer get c => _customer;

  Future<void> _loadDetails() async {
    try {
      final service = ref.read(adminAuthServiceProvider);
      final nextCustomer = await service.fetchCustomerDetails(c);
      RequestAnalytics nextAnalytics = _requestAnalytics;
      try {
        nextAnalytics = await service.fetchRequestAnalytics();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _customer = nextCustomer;
        _requestAnalytics = nextAnalytics;
      });
    } catch (_) {}
  }

  Future<void> _showActionSheet(String action) async {
    if (action == 'Extend Plan') {
      final days = await showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _ExtendPlanSheet(customer: c),
      );
      if (days == null) return;
      try {
        final updated = await ref
            .read(adminAuthServiceProvider)
            .extendCustomerPlan(customer: c, days: days);
        if (!mounted) return;
        setState(() => _customer = updated);
        _showSnack('Plan extended by $days days', AppColors.success);
      } catch (e) {
        if (!mounted) return;
        _showSnack(_cleanError(e), AppColors.error);
      }
      return;
    }

    if (action == 'Send Offer') {
      final service = ref.read(adminAuthServiceProvider);
      var planOptions = _fallbackPlanOptions;
      try {
        final plans = await service.fetchManagedPlans();
        planOptions = plans
            .where((plan) => plan.id != 'trial')
            .map(_PlanOption.fromManagedPlan)
            .toList();
        if (planOptions.isEmpty) planOptions = _fallbackPlanOptions;
      } catch (_) {}
      if (!mounted) return;

      final offer = await showModalBottomSheet<_PlanOfferInput>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _PlanOfferSheet(
          customer: c,
          plans: planOptions,
        ),
      );
      if (offer == null) return;
      try {
        final updated =
            await service.sendCustomerPlanOffer(
                  customer: c,
                  planId: offer.planId,
                  planName: offer.planName,
                  originalAmount: offer.originalAmount,
                  offerAmount: offer.offerAmount,
                  validUntil: offer.validUntil,
                );
        if (!mounted) return;
        setState(() => _customer = updated);
        _showSnack('Offer sent to ${c.name}', AppColors.success);
      } catch (e) {
        if (!mounted) return;
        _showSnack(_cleanError(e), AppColors.error);
      }
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ActionConfirmSheet(action: action, customerName: c.name),
    );
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String _cleanError(Object error) {
    final text = error.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final daysToPayment = c.nextPaymentDate.difference(DateTime.now()).inDays;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (nestedContext, innerBoxIsScrolled) => [
          SliverOverlapAbsorber(
            handle:
                NestedScrollView.sliverOverlapAbsorberHandleFor(nestedContext),
            sliver: SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            forceElevated: innerBoxIsScrolled,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppUtils.planColor(c.plan).withOpacity(0.15),
                      isDark ? AppColors.darkBg : AppColors.lightBg,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 64, 20, 64),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            FxAvatar(
                              initials: c.avatarInitials ??
                                  c.name.substring(0, 2).toUpperCase(),
                              size: 54,
                              color: AppUtils.planColor(c.plan),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          c.name,
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                            color: isDark
                                                ? AppColors.textPrimary
                                                : AppColors.textDark,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      StatusBadge(c.status),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(c.businessName,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color: AppColors.textSecondary),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      _pill(
                                          AppUtils.planEmoji(c.plan) +
                                              ' ' +
                                              c.plan,
                                          AppUtils.planColor(c.plan)),
                                      _pill(
                                          c.isOnline ? '● Online' : '○ Offline',
                                          c.isOnline
                                              ? AppColors.success
                                              : AppColors.textMuted),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(kTextTabBarHeight),
              child: Material(
                color: isDark ? AppColors.darkBg : AppColors.lightBg,
                child: TabBar(
                  controller: _tabCtrl,
                  tabs: const [
                    Tab(text: 'Overview'),
                    Tab(text: 'Payments'),
                    Tab(text: 'Devices'),
                    Tab(text: 'Errors'),
                  ],
                  labelStyle:
                      const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  unselectedLabelStyle:
                      const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
                  labelColor: AppColors.accent,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.accent,
                  indicatorSize: TabBarIndicatorSize.tab,
                ),
              ),
            ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabCtrl,
          children: [
            _OverviewTab(
                c: c,
                isDark: isDark,
                daysToPayment: daysToPayment,
                apiDetails: _apiDetailsForCustomer(c),
                onAction: _showActionSheet),
            _PaymentsTab(c: c, isDark: isDark),
            _DevicesTab(c: c, isDark: isDark),
            _ErrorsTab(c: c, isDark: isDark),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  UserRequestAnalytics? _apiDetailsForCustomer(Customer customer) {
    for (final user in _requestAnalytics.users) {
      if (user.id == 'user:${customer.id}') return user;
    }
    return null;
  }
}

// ─── Overview Tab ──────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  final Customer c;
  final bool isDark;
  final int daysToPayment;
  final UserRequestAnalytics? apiDetails;
  final void Function(String) onAction;

  const _OverviewTab(
      {required this.c,
      required this.isDark,
      required this.daysToPayment,
      required this.apiDetails,
      required this.onAction});

  @override
  Widget build(BuildContext context) {
    final cityValue =
        [c.city, c.country].where((part) => part.trim().isNotEmpty).join(', ');

    return _NestedTabList(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // Payment Alert
        if (daysToPayment < 0)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_rounded,
                    color: AppColors.error, size: 20),
                const SizedBox(width: 10),
                Text(
                  'Payment overdue by ${-daysToPayment} days',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error),
                ),
              ],
            ),
          ),
        // Stats Row
        Row(
          children: [
            _statBox('${c.deviceCount}', 'Devices', AppColors.info, context),
            const SizedBox(width: 10),
            _statBox(
                '${c.errorCount}',
                'Errors',
                c.errorCount > 0 ? AppColors.error : AppColors.success,
                context),
            const SizedBox(width: 10),
            _statBox('${c.monthlyUsageGB.toStringAsFixed(1)}GB', 'This Month',
                AppColors.accent, context),
          ],
        ),
        const SizedBox(height: 20),
        // Contact Info
        FxDetailSection(
          title: 'Contact',
          children: [
            InfoRow(label: 'Full Name', value: c.name),
            InfoRow(label: 'Email', value: c.email),
            InfoRow(label: 'Phone', value: _displayValue(c.phone)),
            InfoRow(label: 'Address', value: _displayValue(c.address)),
            InfoRow(label: 'City', value: _displayValue(cityValue)),
          ],
        ),
        const SizedBox(height: 16),
        // Plan Info
        FxDetailSection(
          title: 'Subscription',
          children: [
            InfoRow(
              label: 'Plan',
              value: c.plan,
              trailing: _pill(AppUtils.planEmoji(c.plan) + ' ' + c.plan,
                  AppUtils.planColor(c.plan)),
            ),
            InfoRow(
                label: 'Monthly Charge',
                value: '₹${c.monthlyCharge.toStringAsFixed(0)}'),
            InfoRow(
              label: 'Next Payment',
              value: AppUtils.formatDate(c.nextPaymentDate),
              valueColor: daysToPayment < 0
                  ? AppColors.error
                  : daysToPayment < 7
                      ? AppColors.warning
                      : null,
            ),
            InfoRow(
                label: 'Member Since', value: AppUtils.formatDate(c.joinDate)),
            InfoRow(
                label: 'Total Usage',
                value: '${c.totalUsageGB.toStringAsFixed(1)} GB'),
          ],
        ),
        const SizedBox(height: 12),
        _ApiDetailsDropdown(apiDetails: apiDetails, isDark: isDark),
        const SizedBox(height: 24),
        _OffersDropdown(offers: c.offers, isDark: isDark),
        const SizedBox(height: 24),
        // Actions
        Text(
          'ACTIONS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: isDark ? AppColors.textMuted : AppColors.textDarkSecondary,
          ),
        ),
        const SizedBox(height: 10),
        _ActionGrid(onAction: onAction, status: c.status),
      ],
    );
  }

  Widget _statBox(String val, String label, Color color, BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Text(val,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: color,
                    letterSpacing: -0.5)),
            const SizedBox(height: 3),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  String _displayValue(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'Not available' : trimmed;
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _NestedTabList extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final List<Widget> children;

  const _NestedTabList({
    required this.padding,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverPadding(
          padding: padding,
          sliver: SliverList(
            delegate: SliverChildListDelegate(children),
          ),
        ),
      ],
    );
  }
}

class _NestedSeparatedTabList extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder separatorBuilder;

  const _NestedSeparatedTabList({
    required this.padding,
    required this.itemCount,
    required this.itemBuilder,
    required this.separatorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverPadding(
          padding: padding,
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index.isOdd) return separatorBuilder(context, index ~/ 2);
                return itemBuilder(context, index ~/ 2);
              },
              childCount: itemCount == 0 ? 0 : itemCount * 2 - 1,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionGrid extends StatelessWidget {
  final void Function(String) onAction;
  final String status;

  const _ActionGrid({required this.onAction, required this.status});

  @override
  Widget build(BuildContext context) {
    final actions = [
      ('Extend Plan', Icons.add_circle_outline_rounded, AppColors.accent),
      ('Send Offer', Icons.local_offer_rounded, AppColors.success),
      ('Mark / Flag', Icons.flag_outlined, AppColors.warning),
      status == 'banned'
          ? ('Unban User', Icons.check_circle_outline_rounded, AppColors.info)
          : ('Ban User', Icons.block_rounded, AppColors.error),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.8,
      children: actions.map((a) {
        return GestureDetector(
          onTap: () => onAction(a.$1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: (a.$3 as Color).withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: (a.$3 as Color).withOpacity(0.25)),
            ),
            child: Row(
              children: [
                Icon(a.$2 as IconData, size: 18, color: a.$3 as Color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    a.$1 as String,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: a.$3 as Color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ApiDetailsDropdown extends StatelessWidget {
  final UserRequestAnalytics? apiDetails;
  final bool isDark;

  const _ApiDetailsDropdown({
    required this.apiDetails,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final total = apiDetails?.total ?? 0;
    return FxCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.api_rounded,
              color: AppColors.info,
              size: 20,
            ),
          ),
          title: Text(
            'Api Details',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.textPrimary : AppColors.textDark,
            ),
          ),
          subtitle: Text(
            total == 0
                ? 'No gateway requests recorded'
                : '${AppUtils.formatNumber(total)} request${total == 1 ? '' : 's'} till now',
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          children: [
            if (apiDetails == null)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'No request data has been recorded for this user yet.',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              )
            else ...[
              _ApiPeriodBlock(
                title: 'Current Day',
                period: apiDetails!.currentDay,
                color: AppColors.info,
              ),
              const SizedBox(height: 10),
              _ApiPeriodBlock(
                title: 'Current Month',
                period: apiDetails!.currentMonth,
                color: AppColors.accent,
              ),
              const SizedBox(height: 10),
              _ApiPeriodBlock(
                title: 'Current Year',
                period: apiDetails!.currentYear,
                color: AppColors.warning,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ApiPeriodBlock extends StatelessWidget {
  final String title;
  final RequestAnalyticsPeriod period;
  final Color color;

  const _ApiPeriodBlock({
    required this.title,
    required this.period,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                period.bucket.isEmpty ? '-' : period.bucket,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (period.endpoints.isEmpty)
            const Text(
              'No requests',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            )
          else
            ...period.endpoints.map(
              (endpoint) => _ApiRequestRow(endpoint: endpoint, color: color),
            ),
        ],
      ),
    );
  }
}

class _ApiRequestRow extends StatelessWidget {
  final ApiRequestCount endpoint;
  final Color color;

  const _ApiRequestRow({
    required this.endpoint,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              endpoint.endpoint,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              AppUtils.formatNumber(endpoint.count),
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OffersDropdown extends StatelessWidget {
  final List<CustomerOffer> offers;
  final bool isDark;

  const _OffersDropdown({required this.offers, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return FxCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.local_offer_rounded,
                color: AppColors.success, size: 20),
          ),
          title: Text(
            'See all offers given',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.textPrimary : AppColors.textDark,
            ),
          ),
          subtitle: Text(
            offers.isEmpty
                ? 'No offers or plan extensions yet'
                : '${offers.length} offer${offers.length == 1 ? '' : 's'} recorded',
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          children: [
            if (offers.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Offers sent from Flexit will appear here with their validity and plan-extension history.',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              )
            else
              ...offers.map(
                (offer) => Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _OfferHistoryTile(offer: offer),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OfferHistoryTile extends StatelessWidget {
  final CustomerOffer offer;

  const _OfferHistoryTile({required this.offer});

  @override
  Widget build(BuildContext context) {
    final isPlanOffer = offer.isPlanOffer;
    final color = isPlanOffer ? AppColors.success : AppColors.accent;
    final daysLeft = offer.validUntil == null
        ? null
        : offer.validUntil!.difference(DateTime.now()).inDays + 1;
    final title = isPlanOffer
        ? '${offer.planName ?? 'Plan'} offer'
        : 'Plan extended ${offer.extensionDays ?? 0} day${offer.extensionDays == 1 ? '' : 's'}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isPlanOffer
                ? Icons.sell_outlined
                : Icons.add_circle_outline_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color)),
                const SizedBox(height: 4),
                if (isPlanOffer)
                  Text(
                    '₹${offer.originalAmount?.toStringAsFixed(0) ?? '-'} to ₹${offer.offerAmount?.toStringAsFixed(0) ?? '-'}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  )
                else
                  Text(
                    'New end date ${offer.newEndsAt == null ? '-' : AppUtils.formatDate(offer.newEndsAt!)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                if (offer.validUntil != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Valid until ${AppUtils.formatDate(offer.validUntil!)} • ${daysLeft != null && daysLeft <= 0 ? 'Expired' : '${daysLeft ?? 0} days left'}',
                    style: TextStyle(
                      fontSize: 11,
                      color: daysLeft != null && daysLeft <= 3
                          ? AppColors.warning
                          : AppColors.textMuted,
                    ),
                  ),
                ],
                if (offer.createdAt != null) ...[
                  const SizedBox(height: 3),
                  Text('Given on ${AppUtils.formatDate(offer.createdAt!)}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textMuted)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Payments Tab ─────────────────────────────────────────────────────────────

class _PaymentsTab extends StatelessWidget {
  final Customer c;
  final bool isDark;

  const _PaymentsTab({required this.c, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (c.paymentHistory.isEmpty) {
      return const FxEmptyState(
        icon: Icons.receipt_long_rounded,
        title: 'No payment history',
        subtitle: 'This user has no transactions yet',
      );
    }

    return _NestedSeparatedTabList(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: c.paymentHistory.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final p = c.paymentHistory[i];
        return FxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppUtils.statusBg(p.status),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(AppUtils.paymentMethodIcon(p.method),
                        size: 20, color: AppUtils.statusColor(p.status)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.description,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppColors.textPrimary
                                    : AppColors.textDark)),
                        Text(AppUtils.formatDateTime(p.date),
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('₹${p.amount.toStringAsFixed(0)}',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppColors.textPrimary
                                  : AppColors.textDark)),
                      StatusBadge(p.status),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _chip(p.transactionId),
                  const Spacer(),
                  _chip(p.method.toUpperCase()),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.textMuted.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: const TextStyle(
              fontSize: 10,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600)),
    );
  }
}

// ─── Devices Tab ──────────────────────────────────────────────────────────────

class _DevicesTab extends StatelessWidget {
  final Customer c;
  final bool isDark;

  const _DevicesTab({required this.c, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (c.devices.isEmpty) {
      return const FxEmptyState(
        icon: Icons.devices_rounded,
        title: 'No devices registered',
        subtitle: 'This user hasn\'t registered any devices yet',
      );
    }

    return _NestedSeparatedTabList(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: c.devices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final d = c.devices[i];
        return FxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color:
                          (d.isOnline ? AppColors.success : AppColors.textMuted)
                              .withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.tablet_android_rounded,
                        size: 22,
                        color: d.isOnline
                            ? AppColors.success
                            : AppColors.textMuted),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.deviceName,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppColors.textPrimary
                                    : AppColors.textDark)),
                        Text('${d.manufacturer} ${d.model}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  StatusBadge(d.isOnline ? 'active' : 'offline'),
                ],
              ),
              const SizedBox(height: 12),
              Divider(
                  height: 1,
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
              const SizedBox(height: 10),
              Row(
                children: [
                  _info('MAC', d.macAddress),
                  const Spacer(),
                  _info('Android', d.androidVersion),
                  const Spacer(),
                  _info('App', d.appVersion),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _info('Battery', '${d.batteryLevel}%'),
                  const Spacer(),
                  _info('Storage',
                      '${d.storageUsedGB.toStringAsFixed(1)}/${d.storageTotalGB.toStringAsFixed(0)}GB'),
                  const Spacer(),
                  _info('IP', d.ipAddress),
                ],
              ),
              if (d.lastSeen != null) ...[
                const SizedBox(height: 8),
                Text('Last seen: ${AppUtils.timeAgo(d.lastSeen!)}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
              ],
              const SizedBox(height: 12),
              Text(
                'TV DEVICE DETAILS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: isDark
                      ? AppColors.textMuted
                      : AppColors.textDarkSecondary,
                ),
              ),
              const SizedBox(height: 6),
              ...d.extraDetails.entries.map(
                (entry) => InfoRow(label: entry.key, value: entry.value),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _info(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        Text(value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ─── Errors Tab ───────────────────────────────────────────────────────────────

class _ErrorsTab extends StatelessWidget {
  final Customer c;
  final bool isDark;

  const _ErrorsTab({required this.c, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (c.errorCount == 0) {
      return const FxEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'No errors',
        subtitle: 'This user\'s devices haven\'t reported any errors',
      );
    }

    return _NestedTabList(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.error.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.error.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: AppColors.error, size: 18),
              const SizedBox(width: 10),
              Text(
                '${c.errorCount} error${c.errorCount > 1 ? 's' : ''} reported by this account',
                style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.error,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const FxEmptyState(
          icon: Icons.open_in_full_rounded,
          title: 'View full error log',
          subtitle: 'Go to the Errors section to filter by this user',
        ),
      ],
    );
  }
}

class _ExtendPlanSheet extends StatefulWidget {
  final Customer customer;

  const _ExtendPlanSheet({required this.customer});

  @override
  State<_ExtendPlanSheet> createState() => _ExtendPlanSheetState();
}

class _ExtendPlanSheetState extends State<_ExtendPlanSheet> {
  int _days = 1;

  DateTime get _currentEnd => widget.customer.nextPaymentDate;
  DateTime get _newEnd => _currentEnd.add(Duration(days: _days));

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Extend Plan',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.textPrimary : AppColors.textDark)),
          const SizedBox(height: 16),
          FxDetailSection(
            title: 'Current Plan',
            children: [
              InfoRow(label: 'Plan', value: widget.customer.plan),
              InfoRow(
                  label: 'Ending Date',
                  value: AppUtils.formatDate(_currentEnd)),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Extend by $_days day${_days == 1 ? '' : 's'}',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary),
          ),
          Slider(
            min: 1,
            max: 30,
            divisions: 29,
            value: _days.toDouble(),
            label: '$_days days',
            onChanged: (value) => setState(() => _days = value.round()),
          ),
          FxDetailSection(
            title: 'New Plan End',
            children: [
              InfoRow(
                  label: 'New Ending Date',
                  value: AppUtils.formatDate(_newEnd)),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, _days),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanOfferInput {
  final String planId;
  final String planName;
  final double originalAmount;
  final double offerAmount;
  final DateTime validUntil;

  const _PlanOfferInput({
    required this.planId,
    required this.planName,
    required this.originalAmount,
    required this.offerAmount,
    required this.validUntil,
  });
}

class _PlanOption {
  final String id;
  final String name;
  final double amount;
  final String? discountName;
  final double? discountAmount;
  final DateTime? discountEndsAt;

  const _PlanOption(
    this.id,
    this.name,
    this.amount, {
    this.discountName,
    this.discountAmount,
    this.discountEndsAt,
  });

  factory _PlanOption.fromManagedPlan(ManagedPlan plan) {
    return _PlanOption(
      plan.id,
      plan.name,
      plan.amount,
      discountName: plan.discountName,
      discountAmount: plan.discountAmount,
      discountEndsAt: plan.discountEndsAt,
    );
  }

  bool get hasActiveDiscount =>
      discountName != null &&
      discountAmount != null &&
      discountAmount! < amount &&
      (discountEndsAt == null || discountEndsAt!.isAfter(DateTime.now()));

  double get defaultOfferAmount =>
      hasActiveDiscount ? discountAmount! : amount * 0.9;
}

const _fallbackPlanOptions = [
  _PlanOption('clay', 'Clay', 999),
  _PlanOption('metal', 'Metal', 2499),
  _PlanOption('steel', 'Steel', 4999),
];

class _PlanOfferSheet extends StatefulWidget {
  final Customer customer;
  final List<_PlanOption> plans;

  const _PlanOfferSheet({
    required this.customer,
    required this.plans,
  });

  @override
  State<_PlanOfferSheet> createState() => _PlanOfferSheetState();
}

class _PlanOfferSheetState extends State<_PlanOfferSheet> {
  late _PlanOption _selectedPlan;
  final _amountCtrl = TextEditingController();
  late DateTime _validUntil;

  @override
  void initState() {
    super.initState();
    _selectedPlan = widget.plans.firstWhere(
      (plan) => plan.name.toLowerCase() == widget.customer.plan.toLowerCase(),
      orElse: () => widget.plans.first,
    );
    _amountCtrl.text = _selectedPlan.defaultOfferAmount.round().toString();
    _validUntil = DateTime.now().add(const Duration(days: 7));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  double get _offerAmount => double.tryParse(_amountCtrl.text.trim()) ?? 0;

  void _save() {
    final offer = _offerAmount;
    if (offer <= 0 || offer >= _selectedPlan.amount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Offer amount must be below ₹${_selectedPlan.amount.toStringAsFixed(0)}'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.pop(
      context,
      _PlanOfferInput(
        planId: _selectedPlan.id,
        planName: _selectedPlan.name,
        originalAmount: _selectedPlan.amount,
        offerAmount: offer,
        validUntil: _validUntil,
      ),
    );
  }

  Future<void> _pickValidUntil() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _validUntil,
      firstDate: DateTime(now.year, now.month, now.day + 1),
      lastDate: DateTime(now.year + 1, now.month, now.day),
    );
    if (picked == null) return;
    setState(() {
      _validUntil = DateTime(
        picked.year,
        picked.month,
        picked.day,
        23,
        59,
        59,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Send Plan Offer',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color:
                        isDark ? AppColors.textPrimary : AppColors.textDark)),
            const SizedBox(height: 16),
            DropdownButtonFormField<_PlanOption>(
              initialValue: _selectedPlan,
              decoration: const InputDecoration(labelText: 'Plan'),
              items: widget.plans
                  .map(
                    (plan) => DropdownMenuItem(
                      value: plan,
                      child: Text(
                          '${plan.name} - ₹${plan.amount.toStringAsFixed(0)}'),
                    ),
                  )
                  .toList(),
              onChanged: (plan) {
                if (plan == null) return;
                setState(() {
                  _selectedPlan = plan;
                  _amountCtrl.text = plan.defaultOfferAmount.round().toString();
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Offer Price',
                prefixText: '₹',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _pickValidUntil,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Offer Valid Until',
                  suffixIcon: Icon(Icons.calendar_month_rounded),
                ),
                child: Text(AppUtils.formatDate(_validUntil)),
              ),
            ),
            const SizedBox(height: 12),
            FxDetailSection(
              title: 'Offer Preview',
              children: [
                InfoRow(
                  label: 'Original Price',
                  value: '₹${_selectedPlan.amount.toStringAsFixed(0)}',
                ),
                InfoRow(
                  label: 'Offer Price',
                  value: '₹${_offerAmount.toStringAsFixed(0)}',
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _save,
                    child: const Text('Save'),
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

// ─── Action Bottom Sheet ──────────────────────────────────────────────────────

class _ActionConfirmSheet extends StatelessWidget {
  final String action;
  final String customerName;

  const _ActionConfirmSheet({required this.action, required this.customerName});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDestructive = action == 'Ban User';

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(action,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.textPrimary : AppColors.textDark)),
          const SizedBox(height: 8),
          Text(
            'Are you sure you want to "$action" for $customerName?',
            textAlign: TextAlign.center,
            style:
                const TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: isDark
                            ? AppColors.darkBorder
                            : AppColors.lightBorder),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Cancel',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('$action applied to $customerName'),
                        backgroundColor:
                            isDestructive ? AppColors.error : AppColors.success,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isDestructive ? AppColors.error : AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Confirm'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
