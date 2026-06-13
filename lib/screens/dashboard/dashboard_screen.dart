import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_provider.dart';
import '../../core/models/models.dart';
import '../../core/utils/mock_data.dart';
import '../../core/utils/utils.dart';
import '../../providers/admin_auth/admin_auth_provider.dart';
import '../../screens/admins/admins_screen.dart';
import '../../screens/users/users_screen.dart';
import '../../screens/users/user_detail_screen.dart';
import '../../screens/devices/devices_screen.dart';
import '../../screens/income/income_screen.dart';
import '../../screens/errors/errors_screen.dart';
import '../../screens/notifications/notifications_screen.dart';
import '../../screens/auth/login_screen.dart';
import '../../widgets/common/common_widgets.dart';
import '../../widgets/dashboard/stat_card.dart';
import '../../widgets/dashboard/analytics_chart.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _staggerCtrl;
  Timer? _statsRefreshTimer;
  Timer? _liveReloadDebounce;
  WebSocket? _adminSocket;
  static const _fallbackRefreshInterval = Duration(minutes: 2);
  _DashboardRefreshRequest _pendingLiveRefresh =
      const _DashboardRefreshRequest.none();
  List<Customer> _dashboardUsers = const [];
  List<DeviceInfo> _dashboardDevices = const [];
  RevenueOverview _dashboardRevenue = const RevenueOverview(
    totalRevenue: 0,
    revenueThisMonth: 0,
    transactions: [],
  );
  List<ErrorRecord> _dashboardErrors = const [];
  List<DashboardActivity> _dashboardActivities = const [];
  RequestAnalytics _requestAnalytics = const RequestAnalytics();
  DashboardChartData chartData = const DashboardChartData(
    labels: ['Oct', 'Nov', 'Dec', 'Jan', 'Feb', 'Mar', 'Apr', 'May'],
    revenue: [0, 0, 0, 0, 0, 0, 0, 0],
    users: [0, 0, 0, 0, 0, 0, 0, 0],
    devices: [0, 0, 0, 0, 0, 0, 0, 0],
  );
  List<DashboardActivity> recentActivities = const [];
  List<_AtRiskCustomer> atRiskCustomers = const [];
  List<_ConvertibleCustomer> convertibleCustomers = const [];
  List<_PlanUpgradeCandidate> planUpgradeCandidates = const [];
  List<_ConvertedCustomer> convertedCustomers = const [];
  List<_ConvertedRiskCustomer> convertedRiskCustomers = const [];
  List<_PlanUpgradedCustomer> planUpgradedCustomers = const [];
  int adminCount = 0;
  var stats = DashboardStats(
    totalUsers: MockData.stats.totalUsers,
    activeUsers: MockData.stats.activeUsers,
    newUsersThisMonth: MockData.stats.newUsersThisMonth,
    userGrowthPercent: MockData.stats.userGrowthPercent,
    liveDevices: MockData.stats.liveDevices,
    totalDevices: MockData.stats.totalDevices,
    offlineDevices: MockData.stats.offlineDevices,
    deviceGrowthPercent: MockData.stats.deviceGrowthPercent,
    totalRevenue: MockData.stats.totalRevenue,
    revenueThisMonth: MockData.stats.revenueThisMonth,
    revenueGrowthPercent: MockData.stats.revenueGrowthPercent,
    totalErrors: 0,
    openErrors: 0,
    criticalErrors: 0,
    errorChangePercent: MockData.stats.errorChangePercent,
  );

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    _loadDashboardData();
    _connectAdminSocket();
    _statsRefreshTimer = Timer.periodic(
      _fallbackRefreshInterval,
      (_) => _loadDashboardData(),
    );
  }

  @override
  void dispose() {
    _statsRefreshTimer?.cancel();
    _liveReloadDebounce?.cancel();
    _adminSocket?.close();
    _staggerCtrl.dispose();
    super.dispose();
  }

  Animation<double> _staggered(int index) {
    final start = (index * 0.10).clamp(0.0, 0.85);
    final end = (start + 0.5).clamp(0.0, 1.0);
    return CurvedAnimation(
      parent: _staggerCtrl,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
  }

  Future<void> _navigate(BuildContext ctx, Widget screen) async {
    await Navigator.push(ctx, MaterialPageRoute(builder: (_) => screen));
    if (mounted) unawaited(_loadDashboardData());
  }

  Future<void> _loadDashboardData({
    bool refreshUserSummary = true,
    bool refreshUsers = true,
    bool refreshDevices = true,
    bool refreshRevenue = true,
    bool refreshErrors = true,
    bool refreshActivities = true,
    bool refreshAdmins = true,
    bool refreshRequestAnalytics = true,
  }) async {
    final service = ref.read(adminAuthServiceProvider);
    var nextStats = stats;
    var users = _dashboardUsers;
    var devices = _dashboardDevices;
    var revenue = _dashboardRevenue;
    var errors = _dashboardErrors;
    var activities = _dashboardActivities;
    var nextAdminCount = adminCount;

    if (refreshUserSummary) {
      try {
        nextStats = await service.fetchUserSummary(nextStats);
      } catch (_) {}
    }

    if (refreshUsers) {
      try {
        users = await service.fetchUsers();
      } catch (_) {}
    }

    if (refreshDevices) {
      try {
        devices = await service.fetchRegisteredDevices();
      } catch (_) {}
    }

    if (refreshDevices || refreshUsers) {
      final liveDevices = devices.where((device) => device.isOnline).length;
      nextStats = DashboardStats(
        totalUsers: nextStats.totalUsers,
        activeUsers: nextStats.activeUsers,
        newUsersThisMonth: nextStats.newUsersThisMonth,
        userGrowthPercent:
            _periodGrowth(users.map((user) => user.joinDate).toList()),
        liveDevices: liveDevices,
        totalDevices: devices.length,
        offlineDevices: devices.length - liveDevices,
        deviceGrowthPercent: _periodGrowth(
            devices.map((device) => device.registeredAt).toList()),
        totalRevenue: nextStats.totalRevenue,
        revenueThisMonth: nextStats.revenueThisMonth,
        revenueGrowthPercent: nextStats.revenueGrowthPercent,
        totalErrors: nextStats.totalErrors,
        openErrors: nextStats.openErrors,
        criticalErrors: nextStats.criticalErrors,
        errorChangePercent: nextStats.errorChangePercent,
      );
    }

    if (refreshRevenue) {
      try {
        revenue = await service.fetchRevenueOverview();
      } catch (_) {}
    }

    if (refreshRevenue) {
      nextStats = DashboardStats(
        totalUsers: nextStats.totalUsers,
        activeUsers: nextStats.activeUsers,
        newUsersThisMonth: nextStats.newUsersThisMonth,
        userGrowthPercent: nextStats.userGrowthPercent,
        liveDevices: nextStats.liveDevices,
        totalDevices: nextStats.totalDevices,
        offlineDevices: nextStats.offlineDevices,
        deviceGrowthPercent: nextStats.deviceGrowthPercent,
        totalRevenue: revenue.totalRevenue,
        revenueThisMonth: revenue.revenueThisMonth,
        revenueGrowthPercent: _amountPeriodGrowth(revenue.transactions),
        totalErrors: nextStats.totalErrors,
        openErrors: nextStats.openErrors,
        criticalErrors: nextStats.criticalErrors,
        errorChangePercent: nextStats.errorChangePercent,
      );
    }

    if (refreshErrors) {
      try {
        errors = await service.fetchErrors();
      } catch (_) {}
    }

    if (refreshErrors) {
      final openErrors = errors.where((error) => error.status == 'open').length;
      final criticalErrors =
          errors.where((error) => error.severity == 'critical').length;
      nextStats = DashboardStats(
        totalUsers: nextStats.totalUsers,
        activeUsers: nextStats.activeUsers,
        newUsersThisMonth: nextStats.newUsersThisMonth,
        userGrowthPercent: nextStats.userGrowthPercent,
        liveDevices: nextStats.liveDevices,
        totalDevices: nextStats.totalDevices,
        offlineDevices: nextStats.offlineDevices,
        deviceGrowthPercent: nextStats.deviceGrowthPercent,
        totalRevenue: nextStats.totalRevenue,
        revenueThisMonth: nextStats.revenueThisMonth,
        revenueGrowthPercent: nextStats.revenueGrowthPercent,
        totalErrors: errors.length,
        openErrors: openErrors,
        criticalErrors: criticalErrors,
        errorChangePercent:
            _periodGrowth(errors.map((error) => error.timestamp).toList()),
      );
    }

    if (refreshActivities) {
      try {
        activities = await service.fetchUserActivities();
      } catch (_) {}
    }

    if (refreshAdmins && service.currentAdmin?.isSuperAdmin == true) {
      try {
        final admins = await service.fetchAdmins();
        nextAdminCount = admins.length;
      } catch (_) {}
    }

    var nextRequestAnalytics = _requestAnalytics;
    if (refreshRequestAnalytics) {
      try {
        nextRequestAnalytics = await service.fetchRequestAnalytics();
      } catch (_) {}
    }

    final nextChartData = _buildChartData(
      users: users,
      devices: devices,
      transactions: revenue.transactions,
    );
    final nextActivities = _buildActivityFeed(
      activities: activities,
      users: users,
      transactions: revenue.transactions,
      errors: errors,
    );
    final nextAtRiskCustomers = _buildAtRiskCustomers(
      users: users,
      transactions: revenue.transactions,
    );
    final nextConvertibleCustomers = _buildConvertibleCustomers(
      users: users,
      transactions: revenue.transactions,
    );
    final nextPlanUpgradeCandidates = _buildPlanUpgradeCandidates(users);
    final nextConvertedCustomers = _buildConvertedCustomers(
      users: users,
      transactions: revenue.transactions,
    );
    final nextConvertedRiskCustomers = _buildConvertedRiskCustomers(
      users: users,
      transactions: revenue.transactions,
    );
    final nextPlanUpgradedCustomers = _buildPlanUpgradedCustomers(
      users: users,
      transactions: revenue.transactions,
    );

    if (!mounted) return;
    setState(() {
      _dashboardUsers = users;
      _dashboardDevices = devices;
      _dashboardRevenue = revenue;
      _dashboardErrors = errors;
      _dashboardActivities = activities;
      _requestAnalytics = nextRequestAnalytics;
      stats = nextStats;
      chartData = nextChartData;
      recentActivities = nextActivities;
      atRiskCustomers = nextAtRiskCustomers;
      convertibleCustomers = nextConvertibleCustomers;
      planUpgradeCandidates = nextPlanUpgradeCandidates;
      convertedCustomers = nextConvertedCustomers;
      convertedRiskCustomers = nextConvertedRiskCustomers;
      planUpgradedCustomers = nextPlanUpgradedCustomers;
      adminCount = nextAdminCount;
    });
  }

  void _connectAdminSocket() {
    final token = ref.read(adminAuthServiceProvider).token;
    if (token == null || token.isEmpty) return;

    final base = Uri.parse(AppConfig.realtimeBaseUrl);
    final socketUri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: base.path == '/' ? '' : base.path,
    );

    WebSocket.connect(
      socketUri.toString(),
      headers: {'Authorization': 'Bearer $token'},
    ).then((socket) {
      if (!mounted) {
        socket.close();
        return;
      }
      _adminSocket = socket;
      socket.listen(
        (message) {
          final refresh = _dashboardRefreshForSocketMessage(message);
          if (refresh != null) _scheduleLiveReload(refresh);
        },
        onDone: () {
          if (mounted) {
            _adminSocket = null;
            Future.delayed(const Duration(seconds: 3), _connectAdminSocket);
          }
        },
        onError: (_) {
          _adminSocket = null;
        },
      );
    }).catchError((_) {});
  }

  _DashboardRefreshRequest? _dashboardRefreshForSocketMessage(dynamic message) {
    try {
      final decoded = jsonDecode(message.toString()) as Map<String, dynamic>;
      final type = decoded['type']?.toString();
      if (type == 'ADMIN_WS_CONNECTED') {
        return const _DashboardRefreshRequest.full();
      }
      if (type == 'DEVICE_WS_CONNECTED') {
        return const _DashboardRefreshRequest.devices();
      }
      if (type != 'ADMIN_DASHBOARD_UPDATED') return null;

      final data = decoded['data'] is Map<String, dynamic>
          ? decoded['data'] as Map<String, dynamic>
          : const <String, dynamic>{};
      final eventType = data['eventType']?.toString();
      switch (eventType) {
        case 'APP_ERROR_CREATED':
          return const _DashboardRefreshRequest(
            errors: true,
            activities: true,
          );
        case 'USER_REGISTERED':
          return const _DashboardRefreshRequest(
            userSummary: true,
            users: true,
            activities: true,
          );
        case 'BUSINESS_LINKED':
          return const _DashboardRefreshRequest(
            userSummary: true,
            users: true,
            devices: true,
            activities: true,
          );
        case 'BUSINESS_PLAN_EXTENDED':
        case 'BUSINESS_PLAN_OFFER_SENT':
          return const _DashboardRefreshRequest(
            users: true,
            revenue: true,
            activities: true,
          );
        case 'SUBSCRIPTION_PLANS_UPDATED':
          return const _DashboardRefreshRequest.none();
        default:
          return const _DashboardRefreshRequest.full();
      }
    } catch (_) {
      return null;
    }
  }

  void _scheduleLiveReload(_DashboardRefreshRequest refresh) {
    if (!refresh.hasWork) return;
    _pendingLiveRefresh = _pendingLiveRefresh.merge(refresh);
    _liveReloadDebounce?.cancel();
    _liveReloadDebounce = Timer(
      const Duration(milliseconds: 400),
      () {
        final pendingRefresh = _pendingLiveRefresh;
        _pendingLiveRefresh = const _DashboardRefreshRequest.none();
        unawaited(_loadDashboardData(
          refreshUserSummary: pendingRefresh.userSummary,
          refreshUsers: pendingRefresh.users,
          refreshDevices: pendingRefresh.devices,
          refreshRevenue: pendingRefresh.revenue,
          refreshErrors: pendingRefresh.errors,
          refreshActivities: pendingRefresh.activities,
          refreshAdmins: pendingRefresh.admins,
          refreshRequestAnalytics: pendingRefresh.requestAnalytics,
        ));
      },
    );
  }

  double _periodGrowth(List<DateTime> dates) {
    final now = DateTime.now();
    final currentStart = DateTime(now.year, now.month, 1);
    final previousStart = DateTime(now.year, now.month - 1, 1);
    final current = dates.where((date) => !date.isBefore(currentStart)).length;
    final previous = dates
        .where((date) =>
            !date.isBefore(previousStart) && date.isBefore(currentStart))
        .length;
    if (previous == 0) return current == 0 ? 0 : 100;
    return ((current - previous) / previous) * 100;
  }

  double _amountPeriodGrowth(List<PaymentRecord> payments) {
    final now = DateTime.now();
    final currentStart = DateTime(now.year, now.month, 1);
    final previousStart = DateTime(now.year, now.month - 1, 1);
    final successful = payments.where((payment) => payment.status == 'success');
    final current = successful
        .where((payment) => !payment.date.isBefore(currentStart))
        .fold(0.0, (sum, payment) => sum + payment.amount);
    final previous = successful
        .where((payment) =>
            !payment.date.isBefore(previousStart) &&
            payment.date.isBefore(currentStart))
        .fold(0.0, (sum, payment) => sum + payment.amount);
    if (previous == 0) return current == 0 ? 0 : 100;
    return ((current - previous) / previous) * 100;
  }

  DashboardChartData _buildChartData({
    required List<Customer> users,
    required List<DeviceInfo> devices,
    required List<PaymentRecord> transactions,
  }) {
    final months = _lastMonths(8);
    final labels = months.map(_monthLabel).toList();
    final successful =
        transactions.where((payment) => payment.status == 'success').toList();

    return DashboardChartData(
      labels: labels,
      revenue: months
          .map((month) => successful
              .where((payment) => _sameMonth(payment.date, month))
              .fold(0.0, (sum, payment) => sum + payment.amount))
          .toList(),
      users: months
          .map((month) => users
              .where((user) => _sameMonth(user.joinDate, month))
              .length
              .toDouble())
          .toList(),
      devices: months
          .map((month) => devices
              .where((device) => _sameMonth(device.registeredAt, month))
              .length
              .toDouble())
          .toList(),
    );
  }

  List<DashboardActivity> _buildActivityFeed({
    required List<DashboardActivity> activities,
    required List<Customer> users,
    required List<PaymentRecord> transactions,
    required List<ErrorRecord> errors,
  }) {
    final feed = <DashboardActivity>[
      ...activities,
      ...users.map((user) => DashboardActivity(
            title: 'New user registered',
            subtitle: user.businessName.isEmpty
                ? user.name
                : '${user.name} - ${user.businessName}',
            type: 'USER_CREATED',
            timestamp: user.joinDate,
          )),
      ...transactions.map((payment) => DashboardActivity(
            title: payment.status == 'success'
                ? 'Payment received'
                : 'Payment ${payment.status}',
            subtitle:
                '${AppUtils.formatCurrency(payment.amount)} from ${payment.customerName}',
            type: 'PAYMENT_${payment.status.toUpperCase()}',
            timestamp: payment.date,
          )),
      ...transactions
          .where((payment) => payment.plan.trim().isNotEmpty)
          .map((payment) => DashboardActivity(
                title: 'Plan upgraded',
                subtitle: '${payment.customerName} - ${payment.plan}',
                type: 'PLAN_UPGRADED',
                timestamp: payment.date,
              )),
      ...errors.map((error) => DashboardActivity(
            title:
                error.severity == 'critical' ? 'Critical error' : 'New error',
            subtitle: '${error.errorCode} on ${error.deviceName}',
            type: 'APP_ERROR_CREATED',
            timestamp: error.timestamp,
          )),
    ];

    feed.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final seen = <String>{};
    return feed
        .where((activity) {
          final key =
              '${activity.type}-${activity.title}-${activity.subtitle}-${activity.timestamp.toIso8601String()}';
          return seen.add(key);
        })
        .take(8)
        .toList();
  }

  List<_AtRiskCustomer> _buildAtRiskCustomers({
    required List<Customer> users,
    required List<PaymentRecord> transactions,
  }) {
    final successful = transactions
        .where((payment) => payment.status == 'success')
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final now = DateTime.now();

    final customers = users
        .map((customer) {
          PaymentRecord? lastPayment;
          for (final payment in successful) {
            final customerIdMatch = payment.customerId == customer.id;
            final businessIdMatch = customer.businessId != null &&
                customer.businessId!.isNotEmpty &&
                payment.customerId == customer.businessId;
            if (customerIdMatch || businessIdMatch) {
              lastPayment = payment;
              break;
            }
          }

          final lastRechargeAt = lastPayment?.date ?? customer.joinDate;
          final daysSinceRecharge = now.difference(lastRechargeAt).inDays;
          final severity = _riskSeverity(daysSinceRecharge);

          return _AtRiskCustomer(
            customer: customer,
            severity: severity,
            lastRechargeAt: lastRechargeAt,
            amount: lastPayment?.amount,
            plan: lastPayment?.plan,
          );
        })
        .where((risk) => risk.daysSinceRecharge > 0)
        .toList();

    customers.sort((a, b) {
      final severityCompare =
          _riskRank(b.severity).compareTo(_riskRank(a.severity));
      if (severityCompare != 0) return severityCompare;
      return b.daysSinceRecharge.compareTo(a.daysSinceRecharge);
    });

    return customers;
  }

  String _riskSeverity(int daysSinceRecharge) {
    if (daysSinceRecharge > 90) return 'critical';
    if (daysSinceRecharge >= 30) return 'medium';
    return 'low';
  }

  int _riskRank(String severity) {
    switch (severity) {
      case 'critical':
        return 3;
      case 'medium':
        return 2;
      default:
        return 1;
    }
  }

  List<_ConvertibleCustomer> _buildConvertibleCustomers({
    required List<Customer> users,
    required List<PaymentRecord> transactions,
  }) {
    final result = <_ConvertibleCustomer>[];
    final now = DateTime.now();

    for (final customer in users) {
      final related = transactions.where((payment) {
        final customerIdMatch = payment.customerId == customer.id;
        final businessIdMatch = customer.businessId != null &&
            customer.businessId!.isNotEmpty &&
            payment.customerId == customer.businessId;
        return customerIdMatch || businessIdMatch;
      }).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

      final hasSuccessfulUpgrade =
          related.any((payment) => payment.status == 'success');
      if (hasSuccessfulUpgrade) continue;

      PaymentRecord? trialPayment;
      for (final payment in related) {
        final status = payment.status.toLowerCase();
        final plan = payment.plan.toLowerCase();
        if (status == 'trialing' ||
            status == 'trial' ||
            plan.contains('trial')) {
          trialPayment = payment;
          break;
        }
      }

      final planText = customer.plan.toLowerCase();
      final looksTrial =
          planText.contains('trial') || planText == 'free' || related.isEmpty;
      if (trialPayment == null && !looksTrial) continue;

      final trialStartedAt = trialPayment?.date ?? customer.joinDate;
      result.add(_ConvertibleCustomer(
        customer: customer,
        trialStartedAt: trialStartedAt,
        plan: trialPayment?.plan ?? customer.plan,
        daysInTrial: now.difference(trialStartedAt).inDays,
      ));
    }

    result.sort((a, b) => b.daysInTrial.compareTo(a.daysInTrial));
    return result;
  }

  List<_PlanUpgradeCandidate> _buildPlanUpgradeCandidates(
      List<Customer> users) {
    final candidates = <_PlanUpgradeCandidate>[];

    for (final customer in users) {
      final currentTier = _planTier(customer.plan);
      if (currentTier == null || currentTier >= _paidPlanOrder.length - 1) {
        continue;
      }

      candidates.add(_PlanUpgradeCandidate(
        customer: customer,
        currentPlan: _paidPlanOrder[currentTier],
        nextPlan: _paidPlanOrder[currentTier + 1],
      ));
    }

    candidates.sort((a, b) {
      final planCompare = _planTier(a.currentPlan)!.compareTo(
        _planTier(b.currentPlan)!,
      );
      if (planCompare != 0) return planCompare;
      return a.customer.name.compareTo(b.customer.name);
    });
    return candidates;
  }

  List<_ConvertedCustomer> _buildConvertedCustomers({
    required List<Customer> users,
    required List<PaymentRecord> transactions,
  }) {
    final result = <_ConvertedCustomer>[];

    for (final customer in users) {
      final paid = _successfulPaidPayments(customer, transactions);
      if (paid.isEmpty) continue;

      final firstPaid = paid.first;
      result.add(_ConvertedCustomer(
        customer: customer,
        convertedDate: firstPaid.date,
        convertedPlan: _canonicalPaidPlan(firstPaid.plan) ?? firstPaid.plan,
        lastPayment: paid.last,
      ));
    }

    result.sort((a, b) => b.convertedDate.compareTo(a.convertedDate));
    return result;
  }

  List<_ConvertedRiskCustomer> _buildConvertedRiskCustomers({
    required List<Customer> users,
    required List<PaymentRecord> transactions,
  }) {
    final result = <_ConvertedRiskCustomer>[];

    for (final customer in users) {
      final paid = _successfulPaidPayments(customer, transactions);
      if (paid.isEmpty) continue;

      _ConvertedRiskCustomer? latest;
      DateTime previousRecharge = customer.joinDate;
      for (final payment in paid) {
        final gapDays = payment.date.difference(previousRecharge).inDays;
        if (gapDays > 0) {
          latest = _ConvertedRiskCustomer(
            customer: customer,
            convertedDate: payment.date,
            severity: _riskSeverity(gapDays),
            daysAtRisk: gapDays,
            lastPayment: payment,
          );
        }
        previousRecharge = payment.date;
      }

      if (latest != null) result.add(latest);
    }

    result.sort((a, b) {
      final severityCompare =
          _riskRank(b.severity).compareTo(_riskRank(a.severity));
      if (severityCompare != 0) return severityCompare;
      return b.convertedDate.compareTo(a.convertedDate);
    });
    return result;
  }

  List<_PlanUpgradedCustomer> _buildPlanUpgradedCustomers({
    required List<Customer> users,
    required List<PaymentRecord> transactions,
  }) {
    final result = <_PlanUpgradedCustomer>[];

    for (final customer in users) {
      final paid = _successfulPaidPayments(customer, transactions);
      if (paid.length < 2) continue;

      PaymentRecord? latestUpgrade;
      String? fromPlan;
      var highestTier = _planTier(paid.first.plan);
      var highestPlan = _canonicalPaidPlan(paid.first.plan);

      for (final payment in paid.skip(1)) {
        final tier = _planTier(payment.plan);
        if (tier == null || highestTier == null) continue;
        if (tier > highestTier) {
          latestUpgrade = payment;
          fromPlan = highestPlan;
          highestTier = tier;
          highestPlan = _canonicalPaidPlan(payment.plan);
        }
      }

      if (latestUpgrade == null || fromPlan == null || highestPlan == null) {
        continue;
      }

      result.add(_PlanUpgradedCustomer(
        customer: customer,
        convertedDate: latestUpgrade.date,
        fromPlan: fromPlan,
        toPlan: highestPlan,
        lastPayment: paid.last,
      ));
    }

    result.sort((a, b) => b.convertedDate.compareTo(a.convertedDate));
    return result;
  }

  List<PaymentRecord> _successfulPaidPayments(
    Customer customer,
    List<PaymentRecord> transactions,
  ) {
    final payments = _customerPayments(customer, transactions)
        .where((payment) =>
            payment.status.toLowerCase() == 'success' &&
            _planTier(payment.plan) != null)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return payments;
  }

  List<PaymentRecord> _customerPayments(
    Customer customer,
    List<PaymentRecord> transactions,
  ) {
    return transactions.where((payment) {
      final customerIdMatch = payment.customerId == customer.id;
      final businessIdMatch = customer.businessId != null &&
          customer.businessId!.isNotEmpty &&
          payment.customerId == customer.businessId;
      return customerIdMatch || businessIdMatch;
    }).toList();
  }

  static const _paidPlanOrder = ['Clay', 'Metal', 'Steel'];

  int? _planTier(String plan) {
    final normalized = _normalizedPlan(plan);
    if (normalized.isEmpty ||
        normalized.contains('trial') ||
        normalized == 'free') {
      return null;
    }

    for (var i = 0; i < _paidPlanOrder.length; i++) {
      if (normalized == _paidPlanOrder[i].toLowerCase()) return i;
    }
    return null;
  }

  String? _canonicalPaidPlan(String plan) {
    final tier = _planTier(plan);
    if (tier == null) return null;
    return _paidPlanOrder[tier];
  }

  String _normalizedPlan(String plan) {
    return plan.trim().toLowerCase().replaceAll(RegExp(r'\s+plan$'), '');
  }

  List<DateTime> _lastMonths(int count) {
    final now = DateTime.now();
    return List.generate(
      count,
      (index) => DateTime(now.year, now.month - count + 1 + index, 1),
    );
  }

  bool _sameMonth(DateTime date, DateTime month) {
    return date.year == month.year && date.month == month.month;
  }

  String _monthLabel(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return months[date.month - 1];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = ThemeProvider.of(context);
    final currentAdmin = ref.read(adminAuthServiceProvider).currentAdmin ??
        MockData.currentAdmin;
    final showAdminTile = currentAdmin.isSuperAdmin;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildAppBar(isDark, provider),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Greeting
                _buildGreeting(isDark),
                const SizedBox(height: 24),
                // Stat Cards Grid Row 1
                Row(
                  children: [
                    Expanded(
                      child: _animatedCard(
                        0,
                        StatCard(
                          title: 'Total Users',
                          value: AppUtils.formatNumber(stats.totalUsers),
                          subtitle: '+${stats.newUsersThisMonth} this month',
                          growth: stats.userGrowthPercent,
                          gradientColors: const [
                            AppColors.userGrad1,
                            AppColors.userGrad2
                          ],
                          icon: Icons.people_alt_rounded,
                          onTap: () => _navigate(context, const UsersScreen()),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _animatedCard(
                        1,
                        StatCard(
                          title: 'Live Devices',
                          value: AppUtils.formatNumber(stats.liveDevices),
                          subtitle: '${stats.totalDevices} registered',
                          growth: stats.deviceGrowthPercent,
                          gradientColors: const [
                            AppColors.deviceGrad1,
                            AppColors.deviceGrad2
                          ],
                          icon: Icons.devices_rounded,
                          onTap: () =>
                              _navigate(context, const DevicesScreen()),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Stat Cards Grid Row 2
                Row(
                  children: [
                    Expanded(
                      child: _animatedCard(
                        2,
                        StatCard(
                          title: 'Revenue',
                          value:
                              AppUtils.formatCurrency(stats.revenueThisMonth),
                          subtitle: 'Total revenue',
                          growth: stats.revenueGrowthPercent,
                          gradientColors: const [
                            AppColors.incomeGrad1,
                            AppColors.incomeGrad2
                          ],
                          icon: Icons.currency_rupee_rounded,
                          onTap: () => _navigate(context, const IncomeScreen()),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _animatedCard(
                        3,
                        StatCard(
                          title: 'Errors',
                          value: stats.openErrors.toString(),
                          subtitle: '${stats.criticalErrors} critical',
                          growth: stats.errorChangePercent,
                          gradientColors: const [
                            AppColors.errGrad1,
                            AppColors.errGrad2
                          ],
                          icon: Icons.bug_report_rounded,
                          isInverse: true,
                          onTap: () => _navigate(context, const ErrorsScreen()),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _animatedCard(
                        4,
                        StatCard(
                          title: 'Requests',
                          value: AppUtils.formatNumber(
                              _requestAnalytics.totalRequests),
                          subtitle: 'Total till now',
                          growth: 0,
                          gradientColors: const [
                            AppColors.info,
                            AppColors.accent
                          ],
                          icon: Icons.route_rounded,
                          onTap: () => _navigate(
                            context,
                            _RequestAnalyticsScreen(
                              analytics: _requestAnalytics,
                              customers: _dashboardUsers,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (showAdminTile) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _animatedCard(
                          4,
                          StatCard(
                            title: 'Plans',
                            value: '3',
                            subtitle: 'Manage prices',
                            growth: 0,
                            gradientColors: const [
                              AppColors.info,
                              AppColors.accent
                            ],
                            icon: Icons.workspace_premium_rounded,
                            onTap: () =>
                                _navigate(context, const _PlansAdminScreen()),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _animatedCard(
                          5,
                          StatCard(
                            title: 'Notifications',
                            value: AppUtils.formatNumber(
                                _dashboardUsers
                                    .where((user) => user.businessId != null)
                                    .length),
                            subtitle: 'Send app messages',
                            growth: 0,
                            gradientColors: const [
                              AppColors.accent,
                              AppColors.success
                            ],
                            icon: Icons.notifications_active_rounded,
                            onTap: () => _navigate(
                              context,
                              const NotificationsScreen(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _animatedCard(
                          6,
                          StatCard(
                            title: 'Admins',
                            value: AppUtils.formatNumber(adminCount),
                            subtitle: 'Manage admin access',
                            growth: 0,
                            gradientColors: const [
                              AppColors.info,
                              AppColors.accent
                            ],
                            icon: Icons.admin_panel_settings_rounded,
                            onTap: () =>
                                _navigate(context, const AdminsScreen()),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _animatedCard(
                          6,
                          StatCard(
                            title: 'Converted Customers',
                            value: AppUtils.formatNumber(
                                convertedCustomers.length),
                            subtitle: 'Trial to paid plans',
                            growth: 0,
                            gradientColors: const [
                              AppColors.success,
                              AppColors.accent
                            ],
                            icon: Icons.person_add_alt_1_rounded,
                            onTap: () => _navigate(
                              context,
                              _ConvertedCustomersScreen(
                                customers: convertedCustomers,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _animatedCard(
                          7,
                          StatCard(
                            title: 'Converted Risk',
                            value: AppUtils.formatNumber(
                                convertedRiskCustomers.length),
                            subtitle: 'Recharged at-risk users',
                            growth: 0,
                            gradientColors: const [
                              AppColors.warning,
                              AppColors.incomeGrad2
                            ],
                            icon: Icons.health_and_safety_rounded,
                            onTap: () => _navigate(
                              context,
                              _ConvertedRiskCustomersScreen(
                                customers: convertedRiskCustomers,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _animatedCard(
                          8,
                          StatCard(
                            title: 'Plan Upgraded Customers',
                            value: AppUtils.formatNumber(
                                planUpgradedCustomers.length),
                            subtitle: 'Clay to higher plans',
                            growth: 0,
                            gradientColors: const [
                              AppColors.info,
                              AppColors.userGrad1
                            ],
                            icon: Icons.upgrade_rounded,
                            onTap: () => _navigate(
                              context,
                              _PlanUpgradedCustomersScreen(
                                customers: planUpgradedCustomers,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                const SizedBox(height: 28),
                // At Risk Section
                _animatedCard(8, _buildAtRiskSection(isDark)),
                const SizedBox(height: 24),
                // Convertible Customers Section
                _animatedCard(9, _buildConvertibleSection(isDark)),
                const SizedBox(height: 24),
                // Plan Upgrade Section
                _animatedCard(10, _buildPlanUpgradeSection(isDark)),
                const SizedBox(height: 24),
                // Analytics Section
                _animatedCard(
                  11,
                  AnalyticsChart(
                    labels: chartData.labels,
                    revenueData: chartData.revenue,
                    userData: chartData.users,
                    deviceData: chartData.devices,
                  ),
                ),
                const SizedBox(height: 24),
                // Quick Stats Row
                _animatedCard(12, _buildQuickStats(isDark)),
                const SizedBox(height: 24),
                // Recent Activity
                _animatedCard(13, _buildRecentActivity(isDark)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _animatedCard(int index, Widget child) {
    return AnimatedBuilder(
      animation: _staggered(index),
      builder: (_, __) => Opacity(
        opacity: _staggered(index).value,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - _staggered(index).value)),
          child: child,
        ),
      ),
    );
  }

  SliverAppBar _buildAppBar(bool isDark, ThemeProvider? provider) {
    final auth = ref.read(adminAuthServiceProvider);
    final admin = auth.currentAdmin ?? MockData.currentAdmin;
    final initials = admin.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0])
        .join()
        .toUpperCase();

    return SliverAppBar(
      floating: true,
      pinned: false,
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      automaticallyImplyLeading: false,
      titleSpacing: 20,
      title: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.accent, AppColors.accentDeep],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                const Icon(Icons.bolt_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Text(
            'flexit',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              color: isDark ? AppColors.textPrimary : AppColors.textDark,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            size: 22,
            color:
                isDark ? AppColors.textSecondary : AppColors.textDarkSecondary,
          ),
          onPressed: () => provider?.onThemeChanged(
            isDark ? ThemeMode.light : ThemeMode.dark,
          ),
        ),
        PopupMenuButton<String>(
          offset: const Offset(0, 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.accent.withOpacity(0.3)),
              ),
              child: Center(
                child: Text(
                  initials.isEmpty ? 'AD' : initials,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ),
          ),
          onSelected: (v) {
            if (v == 'logout') {
              auth.logout();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            } else if (v == 'system') {
              provider?.onThemeChanged(ThemeMode.system);
            }
          },
          itemBuilder: (_) => [
            _menuItem('profile', Icons.person_outline_rounded, 'Profile'),
            _menuItem('system', Icons.settings_suggest_rounded, 'System theme'),
            _menuItem('logout', Icons.logout_rounded, 'Sign out',
                color: AppColors.error),
          ],
        ),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label,
      {Color? color}) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? AppColors.textSecondary),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 14, color: color)),
        ],
      ),
    );
  }

  Widget _buildGreeting(bool isDark) {
    final admin = ref.read(adminAuthServiceProvider).currentAdmin ??
        MockData.currentAdmin;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$greeting, ${admin.name.split(' ').first} 👋',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: isDark ? AppColors.textPrimary : AppColors.textDark,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Here\'s what\'s happening with Flexit today.',
          style: TextStyle(
            fontSize: 14,
            color:
                isDark ? AppColors.textSecondary : AppColors.textDarkSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildAtRiskSection(bool isDark) {
    final critical =
        atRiskCustomers.where((risk) => risk.severity == 'critical').toList();
    final medium =
        atRiskCustomers.where((risk) => risk.severity == 'medium').toList();
    final low =
        atRiskCustomers.where((risk) => risk.severity == 'low').toList();

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _navigate(
        context,
        _AtRiskCustomersScreen(customers: atRiskCustomers),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'AT RISK',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: isDark
                        ? AppColors.textMuted
                        : AppColors.textDarkSecondary,
                  ),
                ),
                Text(
                  '${atRiskCustomers.length} customers',
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _riskSummary('Critical', critical.length, AppColors.error),
                const SizedBox(width: 8),
                _riskSummary('Medium', medium.length, AppColors.warning),
                const SizedBox(width: 8),
                _riskSummary('Low', low.length, AppColors.info),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    atRiskCustomers.isEmpty
                        ? 'No recharge risks right now'
                        : 'Tap to review customers by risk level',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _riskSummary(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.22)),
        ),
        child: Column(
          children: [
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConvertibleSection(bool isDark) {
    final longestTrial = convertibleCustomers.isEmpty
        ? 0
        : convertibleCustomers
            .map((customer) => customer.daysInTrial)
            .reduce((a, b) => a > b ? a : b);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _navigate(
        context,
        _ConvertibleCustomersScreen(customers: convertibleCustomers),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'CONVERTIBLE CUSTOMERS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: isDark
                        ? AppColors.textMuted
                        : AppColors.textDarkSecondary,
                  ),
                ),
                Text(
                  '${convertibleCustomers.length} customers',
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _conversionSummary(
                  'Trial',
                  convertibleCustomers.length.toString(),
                  AppColors.accent,
                ),
                const SizedBox(width: 8),
                _conversionSummary(
                  'Longest',
                  '${longestTrial}d',
                  AppColors.warning,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    convertibleCustomers.isEmpty
                        ? 'No trial customers waiting to upgrade'
                        : 'Tap to review trial customers',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _conversionSummary(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.22)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanUpgradeSection(bool isDark) {
    final clayCount = planUpgradeCandidates
        .where((candidate) => candidate.currentPlan == 'Clay')
        .length;
    final metalCount = planUpgradeCandidates
        .where((candidate) => candidate.currentPlan == 'Metal')
        .length;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _navigate(
        context,
        _PlanUpgradeCustomersScreen(candidates: planUpgradeCandidates),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'PLAN UPGRADE CUSTOMERS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: isDark
                        ? AppColors.textMuted
                        : AppColors.textDarkSecondary,
                  ),
                ),
                Text(
                  '${planUpgradeCandidates.length} customers',
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _conversionSummary(
                  'Clay',
                  clayCount.toString(),
                  AppColors.success,
                ),
                const SizedBox(width: 8),
                _conversionSummary(
                  'Metal',
                  metalCount.toString(),
                  AppColors.info,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    planUpgradeCandidates.isEmpty
                        ? 'No paid-plan upgrade candidates right now'
                        : 'Tap to review customers by current plan',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStats(bool isDark) {
    final items = [
      ('Active Users', '${stats.activeUsers}', AppColors.success),
      ('Offline Devices', '${stats.offlineDevices}', AppColors.warning),
      (
        'Total Revenue',
        AppUtils.formatCurrency(stats.totalRevenue),
        AppColors.accent
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'QUICK STATS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: isDark ? AppColors.textMuted : AppColors.textDarkSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: items.map((item) {
              return Expanded(
                child: Column(
                  children: [
                    Text(
                      item.$1,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? AppColors.textSecondary
                            : AppColors.textDarkSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.$2,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: item.$3,
                        letterSpacing: -0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivity(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'RECENT ACTIVITY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: isDark
                      ? AppColors.textMuted
                      : AppColors.textDarkSecondary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accent,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (recentActivities.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No recent activity yet',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            )
          else
            ...recentActivities.map(
              (a) => _activityItem(a, isDark, recentActivities.last == a),
            ),
        ],
      ),
    );
  }

  Widget _activityItem(DashboardActivity a, bool isDark, bool isLast) {
    final color = _activityColor(a.type);
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_activityIcon(a.type), size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color:
                            isDark ? AppColors.textPrimary : AppColors.textDark,
                      )),
                  const SizedBox(height: 2),
                  Text(a.subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Text(AppUtils.timeAgo(a.timestamp),
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ],
        ),
        if (!isLast)
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Divider(
              height: 20,
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
      ],
    );
  }

  IconData _activityIcon(String type) {
    final normalized = type.toUpperCase();
    if (normalized.contains('PAYMENT')) return Icons.payments_rounded;
    if (normalized.contains('ERROR')) return Icons.error_rounded;
    if (normalized.contains('DEVICE')) return Icons.device_unknown_rounded;
    if (normalized.contains('PLAN') || normalized.contains('UPGRADE')) {
      return Icons.upgrade_rounded;
    }
    if (normalized.contains('USER') || normalized.contains('BUSINESS')) {
      return Icons.person_add_rounded;
    }
    return Icons.notifications_active_rounded;
  }

  Color _activityColor(String type) {
    final normalized = type.toUpperCase();
    if (normalized.contains('PAYMENT') || normalized.contains('SUCCESS')) {
      return AppColors.success;
    }
    if (normalized.contains('ERROR') || normalized.contains('CRITICAL')) {
      return AppColors.error;
    }
    if (normalized.contains('DEVICE')) return AppColors.warning;
    if (normalized.contains('PLAN') || normalized.contains('UPGRADE')) {
      return AppColors.info;
    }
    return AppColors.accent;
  }
}

class _AtRiskCustomer {
  final Customer customer;
  final String severity;
  final DateTime lastRechargeAt;
  final double? amount;
  final String? plan;

  const _AtRiskCustomer({
    required this.customer,
    required this.severity,
    required this.lastRechargeAt,
    this.amount,
    this.plan,
  });

  int get daysSinceRecharge => DateTime.now().difference(lastRechargeAt).inDays;
}

class _ConvertibleCustomer {
  final Customer customer;
  final DateTime trialStartedAt;
  final String plan;
  final int daysInTrial;

  const _ConvertibleCustomer({
    required this.customer,
    required this.trialStartedAt,
    required this.plan,
    required this.daysInTrial,
  });
}

class _ConvertedCustomer {
  final Customer customer;
  final DateTime convertedDate;
  final String convertedPlan;
  final PaymentRecord lastPayment;

  const _ConvertedCustomer({
    required this.customer,
    required this.convertedDate,
    required this.convertedPlan,
    required this.lastPayment,
  });
}

class _ConvertedRiskCustomer {
  final Customer customer;
  final DateTime convertedDate;
  final String severity;
  final int daysAtRisk;
  final PaymentRecord lastPayment;

  const _ConvertedRiskCustomer({
    required this.customer,
    required this.convertedDate,
    required this.severity,
    required this.daysAtRisk,
    required this.lastPayment,
  });
}

class _PlanUpgradedCustomer {
  final Customer customer;
  final DateTime convertedDate;
  final String fromPlan;
  final String toPlan;
  final PaymentRecord lastPayment;

  const _PlanUpgradedCustomer({
    required this.customer,
    required this.convertedDate,
    required this.fromPlan,
    required this.toPlan,
    required this.lastPayment,
  });
}

class _PlanUpgradeCandidate {
  final Customer customer;
  final String currentPlan;
  final String nextPlan;

  const _PlanUpgradeCandidate({
    required this.customer,
    required this.currentPlan,
    required this.nextPlan,
  });
}

class _PlanUpgradeCustomersScreen extends StatelessWidget {
  final List<_PlanUpgradeCandidate> candidates;

  const _PlanUpgradeCustomersScreen({required this.candidates});

  @override
  Widget build(BuildContext context) {
    final clay = candidates
        .where((candidate) => candidate.currentPlan == 'Clay')
        .toList();
    final metal = candidates
        .where((candidate) => candidate.currentPlan == 'Metal')
        .toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Plan Upgrades'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Clay (${clay.length})'),
              Tab(text: 'Metal (${metal.length})'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _PlanUpgradeList(
              candidates: clay,
              emptyTitle: 'No Clay customers to upgrade',
            ),
            _PlanUpgradeList(
              candidates: metal,
              emptyTitle: 'No Metal customers to upgrade',
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestAnalyticsScreen extends ConsumerStatefulWidget {
  final RequestAnalytics analytics;
  final List<Customer> customers;

  const _RequestAnalyticsScreen({
    required this.analytics,
    required this.customers,
  });

  @override
  ConsumerState<_RequestAnalyticsScreen> createState() =>
      _RequestAnalyticsScreenState();
}

class _RequestAnalyticsScreenState
    extends ConsumerState<_RequestAnalyticsScreen> {
  late RequestAnalytics _analytics = widget.analytics;
  late List<Customer> _customers = widget.customers;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final service = ref.read(adminAuthServiceProvider);
      final analytics = await service.fetchRequestAnalytics();
      var customers = _customers;
      try {
        customers = await service.fetchUsers();
        final dangerousUserIds = analytics.dangerousUsers
            .map(_requestUserId)
            .whereType<String>()
            .toSet();
        final dangerousCustomers = customers
            .where((customer) => dangerousUserIds.contains(customer.id))
            .toList();
        final detailedCustomers = await Future.wait(
          dangerousCustomers.map((customer) => _safeCustomerDetails(customer)),
        );
        final detailsById = {
          for (final customer in detailedCustomers) customer.id: customer,
        };
        customers = customers
            .map((customer) => detailsById[customer.id] ?? customer)
            .toList();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _analytics = analytics;
        _customers = customers;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<Customer> _safeCustomerDetails(Customer customer) async {
    try {
      return await ref
          .read(adminAuthServiceProvider)
          .fetchCustomerDetails(customer);
    } catch (_) {
      return customer;
    }
  }

  String? _requestUserId(DangerousRequestUser user) {
    if (!user.id.startsWith('user:')) return null;
    return user.id.substring('user:'.length);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? AppColors.textPrimary : AppColors.textDark;
    final analytics = _analytics;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Requests'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          FxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.info.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.route_rounded,
                        color: AppColors.info,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total Requests',
                            style: TextStyle(
                              color: titleColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${AppUtils.formatNumber(analytics.totalRequests)} till now',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (analytics.generatedAt != null)
                      Text(
                        AppUtils.timeAgo(analytics.generatedAt!),
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _RequestPeriodSection(
                  title: 'Current Day',
                  period: analytics.currentDay,
                  color: AppColors.info,
                ),
                const SizedBox(height: 14),
                _RequestPeriodSection(
                  title: 'Current Month',
                  period: analytics.currentMonth,
                  color: AppColors.accent,
                ),
                const SizedBox(height: 14),
                _RequestPeriodSection(
                  title: 'Current Year',
                  period: analytics.currentYear,
                  color: AppColors.warning,
                ),
                const SizedBox(height: 14),
                _DangerousUsersSection(
                  users: analytics.dangerousUsers,
                  customers: _customers,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestPeriodSection extends StatelessWidget {
  final String title;
  final RequestAnalyticsPeriod period;
  final Color color;

  const _RequestPeriodSection({
    required this.title,
    required this.period,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final endpoints = period.endpoints;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.10 : 0.08),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                period.bucket.isEmpty ? 'No bucket' : period.bucket,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (endpoints.isEmpty)
            const Text(
              'No requests recorded',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            )
          else
            ...endpoints.map(
              (endpoint) => _RequestMetricRow(
                label: endpoint.endpoint,
                count: endpoint.count,
                color: color,
              ),
            ),
        ],
      ),
    );
  }
}

class _DangerousUsersSection extends StatelessWidget {
  final List<DangerousRequestUser> users;
  final List<Customer> customers;

  const _DangerousUsersSection({
    required this.users,
    required this.customers,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Top 5 Dangerous Users',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          if (users.isEmpty)
            const Text(
              'No high request users recorded',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            )
          else
            ...users.asMap().entries.map(
                  (entry) => _DangerousUserRow(
                    rank: entry.key + 1,
                    user: entry.value,
                    customer: _customerFor(entry.value),
                  ),
                ),
        ],
      ),
    );
  }

  Customer? _customerFor(DangerousRequestUser user) {
    if (!user.id.startsWith('user:')) return null;
    final userId = user.id.substring('user:'.length);
    for (final customer in customers) {
      if (customer.id == userId) return customer;
    }
    return null;
  }
}

class _RequestMetricRow extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _RequestMetricRow({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              AppUtils.formatNumber(count),
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

class _DangerousUserRow extends StatelessWidget {
  final int rank;
  final DangerousRequestUser user;
  final Customer? customer;

  const _DangerousUserRow({
    required this.rank,
    required this.user,
    this.customer,
  });

  @override
  Widget build(BuildContext context) {
    final title = _displayName;
    final subtitle = _subtitle;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              rank.toString(),
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            AppUtils.formatNumber(user.today),
            style: const TextStyle(
              color: AppColors.error,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  String get _displayName {
    final name = customer?.name.trim();
    if (name != null && name.isNotEmpty) return name;
    return user.label;
  }

  String get _subtitle {
    final businessName = customer?.businessName.trim();
    final requests = '${AppUtils.formatNumber(user.month)} this month';
    if (businessName != null &&
        businessName.isNotEmpty &&
        businessName != 'No business linked') {
      return '$businessName - $requests';
    }
    return '${user.role} - $requests';
  }
}

class _PlansAdminScreen extends ConsumerStatefulWidget {
  const _PlansAdminScreen();

  @override
  ConsumerState<_PlansAdminScreen> createState() => _PlansAdminScreenState();
}

class _PlansAdminScreenState extends ConsumerState<_PlansAdminScreen> {
  final _priceCtrls = <String, TextEditingController>{};
  final _discountCtrls = <String, TextEditingController>{};
  final _discountNameCtrl = TextEditingController();
  DateTime? _discountEndsAt;
  List<ManagedPlan> _plans = const [];
  bool _loading = true;
  bool _savingPrices = false;
  bool _savingDiscount = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  @override
  void dispose() {
    for (final controller in _priceCtrls.values) {
      controller.dispose();
    }
    for (final controller in _discountCtrls.values) {
      controller.dispose();
    }
    _discountNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPlans() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plans =
          await ref.read(adminAuthServiceProvider).fetchManagedPlans();
      if (!mounted) return;
      _setPlans(plans);
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _cleanError(e);
      });
    }
  }

  void _setPlans(List<ManagedPlan> plans) {
    _plans = plans;
    for (final plan in _editablePlans) {
      _priceCtrls.putIfAbsent(plan.id, () => TextEditingController()).text =
          plan.amount.toStringAsFixed(0);
      _discountCtrls.putIfAbsent(plan.id, () => TextEditingController()).text =
          (plan.discountAmount ?? plan.amount).toStringAsFixed(0);
    }
    final firstDiscounted = _editablePlans
        .where((plan) => plan.discountName != null)
        .cast<ManagedPlan?>()
        .firstWhere((plan) => plan != null, orElse: () => null);
    _discountNameCtrl.text = firstDiscounted?.discountName ?? '';
    _discountEndsAt = firstDiscounted?.discountEndsAt;
  }

  List<ManagedPlan> get _editablePlans =>
      _plans.where((plan) => plan.id != 'trial').toList();

  bool get _hasActiveDiscount =>
      _editablePlans.any((plan) => plan.hasActiveDiscount);

  Future<void> _savePrices() async {
    final prices = _readPrices(_priceCtrls);
    if (prices == null) {
      _showSnack('Enter a valid price for every plan', AppColors.error);
      return;
    }
    setState(() => _savingPrices = true);
    try {
      final plans = await ref
          .read(adminAuthServiceProvider)
          .updateManagedPlanPrices(prices);
      if (!mounted) return;
      setState(() {
        _setPlans(plans);
        _savingPrices = false;
      });
      _showSnack('Plan prices updated', AppColors.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingPrices = false);
      _showSnack(_cleanError(e), AppColors.error);
    }
  }

  Future<void> _saveDiscount() async {
    final prices = _readPrices(_discountCtrls);
    if (_discountNameCtrl.text.trim().isEmpty) {
      _showSnack('Enter a discount name', AppColors.error);
      return;
    }
    if (_discountEndsAt == null) {
      _showSnack('Choose a discount end date', AppColors.error);
      return;
    }
    if (prices == null) {
      _showSnack(
          'Enter a valid discounted price for every plan', AppColors.error);
      return;
    }
    setState(() => _savingDiscount = true);
    try {
      final plans =
          await ref.read(adminAuthServiceProvider).updateManagedPlanDiscount(
                name: _discountNameCtrl.text.trim(),
                validUntil: _discountEndsAt!,
                prices: prices,
              );
      if (!mounted) return;
      setState(() {
        _setPlans(plans);
        _savingDiscount = false;
      });
      _showSnack('Plan discount saved', AppColors.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingDiscount = false);
      _showSnack(_cleanError(e), AppColors.error);
    }
  }

  Future<void> _deleteDiscount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete discount?'),
        content: const Text(
          'This will remove the active offer from all paid plans and restore regular prices in the customer app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _savingDiscount = true);
    try {
      final plans =
          await ref.read(adminAuthServiceProvider).deleteManagedPlanDiscount();
      if (!mounted) return;
      setState(() {
        _setPlans(plans);
        _savingDiscount = false;
      });
      _showSnack('Plan discount deleted', AppColors.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingDiscount = false);
      _showSnack(_cleanError(e), AppColors.error);
    }
  }

  Map<String, double>? _readPrices(Map<String, TextEditingController> ctrls) {
    final prices = <String, double>{};
    for (final plan in _editablePlans) {
      final amount = double.tryParse(ctrls[plan.id]?.text.trim() ?? '');
      if (amount == null || amount < 0) return null;
      prices[plan.id] = amount;
    }
    return prices;
  }

  Future<void> _pickDiscountDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _discountEndsAt ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _discountEndsAt = DateTime(
          picked.year,
          picked.month,
          picked.day,
          23,
          59,
          59,
        ));
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
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
    final bg = isDark ? AppColors.darkBg : AppColors.lightBg;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Plans'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadPlans,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _loadPlans,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    const SectionHeader(title: 'PLAN PRICES'),
                    const SizedBox(height: 12),
                    ..._editablePlans.map(
                      (plan) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ManagedPlanCard(
                          plan: plan,
                          priceCtrl: _priceCtrls[plan.id]!,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _savingPrices ? null : _savePrices,
                        icon: _savingPrices
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_rounded),
                        label: const Text('Save Prices'),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const SectionHeader(title: 'DISCOUNT'),
                    const SizedBox(height: 12),
                    FxCard(
                      child: Column(
                        children: [
                          TextField(
                            controller: _discountNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Discount name',
                              prefixIcon: Icon(Icons.local_offer_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ..._editablePlans.map(
                            (plan) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: TextField(
                                controller: _discountCtrls[plan.id],
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: InputDecoration(
                                  labelText: '${plan.name} discounted price',
                                  prefixIcon:
                                      const Icon(Icons.currency_rupee_rounded),
                                ),
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: _pickDiscountDate,
                            borderRadius: BorderRadius.circular(12),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Last discount date',
                                prefixIcon: Icon(Icons.event_rounded),
                              ),
                              child: Text(
                                _discountEndsAt == null
                                    ? 'Choose date'
                                    : AppUtils.formatDate(_discountEndsAt!),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed:
                                      _savingDiscount ? null : _saveDiscount,
                                  icon: _savingDiscount
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : const Icon(Icons.sell_rounded),
                                  label: const Text('Save Discount'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton.filledTonal(
                                tooltip: 'Delete Discount',
                                onPressed:
                                    _savingDiscount || !_hasActiveDiscount
                                        ? null
                                        : _deleteDiscount,
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ],
                          ),
                          if (_hasActiveDiscount) ...[
                            const SizedBox(height: 10),
                            Text(
                              'Delete removes this offer from plan prices in the customer app.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _ManagedPlanCard extends StatelessWidget {
  final ManagedPlan plan;
  final TextEditingController priceCtrl;

  const _ManagedPlanCard({required this.plan, required this.priceCtrl});

  @override
  Widget build(BuildContext context) {
    return FxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StatusBadge(plan.tvRangeLabel),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            plan.summary,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (plan.hasActiveDiscount) ...[
            const SizedBox(height: 8),
            Text(
              '${plan.discountName} until ${AppUtils.formatDate(plan.discountEndsAt!)}',
              style: const TextStyle(
                color: AppColors.success,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Plan price',
              prefixIcon: Icon(Icons.currency_rupee_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanUpgradeList extends StatelessWidget {
  final List<_PlanUpgradeCandidate> candidates;
  final String emptyTitle;

  const _PlanUpgradeList({
    required this.candidates,
    required this.emptyTitle,
  });

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) {
      return Center(
        child: Text(
          emptyTitle,
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: candidates.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        return _PlanUpgradeCustomerCard(candidate: candidates[index]);
      },
    );
  }
}

class _PlanUpgradeCustomerCard extends StatelessWidget {
  final _PlanUpgradeCandidate candidate;

  const _PlanUpgradeCustomerCard({required this.candidate});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customer = candidate.customer;
    final color = AppUtils.planColor(candidate.currentPlan);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UserDetailScreen(customer: customer),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  customer.avatarInitials ??
                      customer.name.substring(0, 2).toUpperCase(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color:
                          isDark ? AppColors.textPrimary : AppColors.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    customer.businessName,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${candidate.currentPlan} to ${candidate.nextPlan}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  candidate.currentPlan,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  candidate.nextPlan,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConvertedCustomersScreen extends StatefulWidget {
  final List<_ConvertedCustomer> customers;

  const _ConvertedCustomersScreen({required this.customers});

  @override
  State<_ConvertedCustomersScreen> createState() =>
      _ConvertedCustomersScreenState();
}

class _ConvertedCustomersScreenState extends State<_ConvertedCustomersScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.toLowerCase();
    final filtered = widget.customers.where((item) {
      return _matchesCustomerSearch(
        customer: item.customer,
        query: query,
        terms: [item.convertedPlan, item.lastPayment.transactionId],
      );
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Converted Customers'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(74),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: FxSearchBar(
              hint: 'Search by name, email, business, plan...',
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
      ),
      body: _ConvertedCustomersList(
        customers: filtered,
        emptyTitle: 'No converted customers found',
      ),
    );
  }
}

class _ConvertedCustomersList extends StatelessWidget {
  final List<_ConvertedCustomer> customers;
  final String emptyTitle;

  const _ConvertedCustomersList({
    required this.customers,
    required this.emptyTitle,
  });

  @override
  Widget build(BuildContext context) {
    if (customers.isEmpty) {
      return Center(
        child: Text(
          emptyTitle,
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: customers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        final item = customers[index];
        return _InsightCustomerCard(
          customer: item.customer,
          color: AppUtils.planColor(item.convertedPlan),
          title: item.customer.name,
          subtitle: item.customer.businessName,
          meta: 'Converted ${AppUtils.formatDate(item.convertedDate)}',
          trailingTitle: item.convertedPlan,
          trailingSubtitle: AppUtils.formatCurrency(item.lastPayment.amount),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _CustomerInsightDetailScreen(
                title: 'Converted Customer',
                customer: item.customer,
                eventLabel: 'Converted Date',
                eventDate: item.convertedDate,
                statusLabel: item.convertedPlan,
                lastPayment: item.lastPayment,
                rows: [
                  ('Converted Plan', item.convertedPlan),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ConvertedRiskCustomersScreen extends StatefulWidget {
  final List<_ConvertedRiskCustomer> customers;

  const _ConvertedRiskCustomersScreen({required this.customers});

  @override
  State<_ConvertedRiskCustomersScreen> createState() =>
      _ConvertedRiskCustomersScreenState();
}

class _ConvertedRiskCustomersScreenState
    extends State<_ConvertedRiskCustomersScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.toLowerCase();
    final filtered = widget.customers.where((item) {
      return _matchesCustomerSearch(
        customer: item.customer,
        query: query,
        terms: [
          item.severity,
          item.lastPayment.plan,
          item.lastPayment.transactionId,
        ],
      );
    }).toList();
    final critical =
        filtered.where((item) => item.severity == 'critical').toList();
    final medium = filtered.where((item) => item.severity == 'medium').toList();
    final low = filtered.where((item) => item.severity == 'low').toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Converted Risk'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(122),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: FxSearchBar(
                    hint: 'Search by name, business, severity...',
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                TabBar(
                  tabs: [
                    Tab(text: 'Critical (${critical.length})'),
                    Tab(text: 'Medium (${medium.length})'),
                    Tab(text: 'Low (${low.length})'),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _ConvertedRiskList(
              customers: critical,
              emptyTitle: 'No critical converted risk customers',
              color: AppColors.error,
            ),
            _ConvertedRiskList(
              customers: medium,
              emptyTitle: 'No medium converted risk customers',
              color: AppColors.warning,
            ),
            _ConvertedRiskList(
              customers: low,
              emptyTitle: 'No low converted risk customers',
              color: AppColors.info,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConvertedRiskList extends StatelessWidget {
  final List<_ConvertedRiskCustomer> customers;
  final String emptyTitle;
  final Color color;

  const _ConvertedRiskList({
    required this.customers,
    required this.emptyTitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (customers.isEmpty) {
      return Center(
        child: Text(
          emptyTitle,
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: customers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        final item = customers[index];
        return _InsightCustomerCard(
          customer: item.customer,
          color: color,
          title: item.customer.name,
          subtitle: item.customer.businessName,
          meta:
              'Recharged after ${item.daysAtRisk}d - ${AppUtils.formatDate(item.convertedDate)}',
          trailingTitle: item.severity,
          trailingSubtitle: AppUtils.formatCurrency(item.lastPayment.amount),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _CustomerInsightDetailScreen(
                title: 'Converted Risk',
                customer: item.customer,
                eventLabel: 'Converted Date',
                eventDate: item.convertedDate,
                statusLabel: item.severity,
                lastPayment: item.lastPayment,
                rows: [
                  ('Risk Level', item.severity),
                  ('Days At Risk', '${item.daysAtRisk} days'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlanUpgradedCustomersScreen extends StatefulWidget {
  final List<_PlanUpgradedCustomer> customers;

  const _PlanUpgradedCustomersScreen({required this.customers});

  @override
  State<_PlanUpgradedCustomersScreen> createState() =>
      _PlanUpgradedCustomersScreenState();
}

class _PlanUpgradedCustomersScreenState
    extends State<_PlanUpgradedCustomersScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.toLowerCase();
    final filtered = widget.customers.where((item) {
      return _matchesCustomerSearch(
        customer: item.customer,
        query: query,
        terms: [
          item.fromPlan,
          item.toPlan,
          item.lastPayment.transactionId,
        ],
      );
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan Upgraded Customers'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(74),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: FxSearchBar(
              hint: 'Search by name, business, plan...',
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
      ),
      body: _PlanUpgradedList(
        customers: filtered,
        emptyTitle: 'No plan upgraded customers found',
      ),
    );
  }
}

class _PlanUpgradedList extends StatelessWidget {
  final List<_PlanUpgradedCustomer> customers;
  final String emptyTitle;

  const _PlanUpgradedList({
    required this.customers,
    required this.emptyTitle,
  });

  @override
  Widget build(BuildContext context) {
    if (customers.isEmpty) {
      return Center(
        child: Text(
          emptyTitle,
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: customers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        final item = customers[index];
        return _InsightCustomerCard(
          customer: item.customer,
          color: AppUtils.planColor(item.toPlan),
          title: item.customer.name,
          subtitle: item.customer.businessName,
          meta:
              '${item.fromPlan} to ${item.toPlan} - ${AppUtils.formatDate(item.convertedDate)}',
          trailingTitle: item.toPlan,
          trailingSubtitle: AppUtils.formatCurrency(item.lastPayment.amount),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _CustomerInsightDetailScreen(
                title: 'Plan Upgraded Customer',
                customer: item.customer,
                eventLabel: 'Converted Date',
                eventDate: item.convertedDate,
                statusLabel: item.toPlan,
                lastPayment: item.lastPayment,
                rows: [
                  ('From Plan', item.fromPlan),
                  ('To Plan', item.toPlan),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InsightCustomerCard extends StatelessWidget {
  final Customer customer;
  final Color color;
  final String title;
  final String subtitle;
  final String meta;
  final String trailingTitle;
  final String trailingSubtitle;
  final VoidCallback onTap;

  const _InsightCustomerCard({
    required this.customer,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.trailingTitle,
    required this.trailingSubtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        child: Row(
          children: [
            FxAvatar(
              initials: customer.avatarInitials ??
                  customer.name.substring(0, 2).toUpperCase(),
              size: 44,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color:
                          isDark ? AppColors.textPrimary : AppColors.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    meta,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  trailingTitle,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  trailingSubtitle,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerInsightDetailScreen extends StatelessWidget {
  final String title;
  final Customer customer;
  final String eventLabel;
  final DateTime eventDate;
  final String statusLabel;
  final PaymentRecord lastPayment;
  final List<(String, String)> rows;

  const _CustomerInsightDetailScreen({
    required this.title,
    required this.customer,
    required this.eventLabel,
    required this.eventDate,
    required this.statusLabel,
    required this.lastPayment,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppUtils.planColor(lastPayment.plan);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          FxCard(
            child: Row(
              children: [
                FxAvatar(
                  initials: customer.avatarInitials ??
                      customer.name.substring(0, 2).toUpperCase(),
                  size: 54,
                  color: color,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        customer.businessName,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      StatusBadge(statusLabel),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FxDetailSection(
            title: 'Customer',
            children: [
              InfoRow(label: 'Full Name', value: customer.name),
              InfoRow(label: 'Email', value: _display(customer.email)),
              InfoRow(label: 'Phone', value: _display(customer.phone)),
              InfoRow(
                  label: 'Business', value: _display(customer.businessName)),
              InfoRow(label: 'Current Plan', value: customer.plan),
            ],
          ),
          const SizedBox(height: 16),
          FxDetailSection(
            title: 'Conversion',
            children: [
              InfoRow(label: eventLabel, value: AppUtils.formatDate(eventDate)),
              ...rows.map((row) => InfoRow(label: row.$1, value: row.$2)),
            ],
          ),
          const SizedBox(height: 16),
          FxDetailSection(
            title: 'Last Payment',
            children: [
              InfoRow(
                label: 'Amount',
                value: AppUtils.formatCurrency(lastPayment.amount),
              ),
              InfoRow(label: 'Plan', value: lastPayment.plan),
              InfoRow(label: 'Status', value: lastPayment.status),
              InfoRow(
                  label: 'Date',
                  value: AppUtils.formatDateTime(lastPayment.date)),
              InfoRow(
                  label: 'Transaction ID', value: lastPayment.transactionId),
              InfoRow(label: 'Invoice ID', value: lastPayment.invoiceId),
              InfoRow(label: 'Method', value: lastPayment.method.toUpperCase()),
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UserDetailScreen(customer: customer),
              ),
            ),
            icon: const Icon(Icons.open_in_full_rounded),
            label: const Text('Open Full Customer Details'),
          ),
        ],
      ),
    );
  }

  String _display(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'Not available' : trimmed;
  }
}

bool _matchesCustomerSearch({
  required Customer customer,
  required String query,
  required List<String> terms,
}) {
  if (query.trim().isEmpty) return true;
  final haystack = [
    customer.id,
    customer.name,
    customer.email,
    customer.phone,
    customer.businessName,
    customer.plan,
    ...terms,
  ].join(' ').toLowerCase();
  return haystack.contains(query.trim().toLowerCase());
}

class _ConvertibleCustomersScreen extends StatelessWidget {
  final List<_ConvertibleCustomer> customers;

  const _ConvertibleCustomersScreen({required this.customers});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Convertible Customers'),
      ),
      body: customers.isEmpty
          ? const Center(
              child: Text(
                'No trial customers waiting to upgrade',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: customers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, index) {
                return _ConvertibleCustomerCard(
                  item: customers[index],
                );
              },
            ),
    );
  }
}

class _ConvertibleCustomerCard extends StatelessWidget {
  final _ConvertibleCustomer item;

  const _ConvertibleCustomerCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customer = item.customer;
    const color = AppColors.accent;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UserDetailScreen(customer: customer),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  customer.avatarInitials ??
                      customer.name.substring(0, 2).toUpperCase(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color:
                          isDark ? AppColors.textPrimary : AppColors.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    customer.businessName,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Trial started ${AppUtils.formatDate(item.trialStartedAt)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${item.daysInTrial}d',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.plan.isEmpty ? 'Trial' : item.plan,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ],
        ),
      ),
    );
  }
}

class _AtRiskCustomersScreen extends StatelessWidget {
  final List<_AtRiskCustomer> customers;

  const _AtRiskCustomersScreen({required this.customers});

  @override
  Widget build(BuildContext context) {
    final critical =
        customers.where((risk) => risk.severity == 'critical').toList();
    final medium =
        customers.where((risk) => risk.severity == 'medium').toList();
    final low = customers.where((risk) => risk.severity == 'low').toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('At Risk'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Critical (${critical.length})'),
              Tab(text: 'Medium (${medium.length})'),
              Tab(text: 'Low (${low.length})'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _RiskList(
              customers: critical,
              color: AppColors.error,
              emptyTitle: 'No critical risk customers',
            ),
            _RiskList(
              customers: medium,
              color: AppColors.warning,
              emptyTitle: 'No medium risk customers',
            ),
            _RiskList(
              customers: low,
              color: AppColors.info,
              emptyTitle: 'No low risk customers',
            ),
          ],
        ),
      ),
    );
  }
}

class _RiskList extends StatelessWidget {
  final List<_AtRiskCustomer> customers;
  final Color color;
  final String emptyTitle;

  const _RiskList({
    required this.customers,
    required this.color,
    required this.emptyTitle,
  });

  @override
  Widget build(BuildContext context) {
    if (customers.isEmpty) {
      return Center(
        child: Text(
          emptyTitle,
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: customers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        final risk = customers[index];
        return _RiskCustomerCard(risk: risk, color: color);
      },
    );
  }
}

class _RiskCustomerCard extends StatelessWidget {
  final _AtRiskCustomer risk;
  final Color color;

  const _RiskCustomerCard({required this.risk, required this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customer = risk.customer;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UserDetailScreen(customer: customer),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  customer.avatarInitials ??
                      customer.name.substring(0, 2).toUpperCase(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color:
                          isDark ? AppColors.textPrimary : AppColors.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    customer.businessName,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    risk.amount == null
                        ? 'No recharge found'
                        : 'Last recharge ${AppUtils.formatDate(risk.lastRechargeAt)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${risk.daysSinceRecharge}d',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  risk.plan == null || risk.plan!.isEmpty
                      ? 'Recharge due'
                      : risk.plan!,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardRefreshRequest {
  const _DashboardRefreshRequest({
    this.userSummary = false,
    this.users = false,
    this.devices = false,
    this.revenue = false,
    this.errors = false,
    this.activities = false,
    this.admins = false,
    this.requestAnalytics = false,
  });

  const _DashboardRefreshRequest.none() : this();

  const _DashboardRefreshRequest.full()
      : this(
          userSummary: true,
          users: true,
          devices: true,
          revenue: true,
          errors: true,
          activities: true,
          admins: true,
          requestAnalytics: true,
        );

  const _DashboardRefreshRequest.devices() : this(devices: true);

  final bool userSummary;
  final bool users;
  final bool devices;
  final bool revenue;
  final bool errors;
  final bool activities;
  final bool admins;
  final bool requestAnalytics;

  bool get hasWork =>
      userSummary ||
      users ||
      devices ||
      revenue ||
      errors ||
      activities ||
      admins ||
      requestAnalytics;

  _DashboardRefreshRequest merge(_DashboardRefreshRequest other) {
    return _DashboardRefreshRequest(
      userSummary: userSummary || other.userSummary,
      users: users || other.users,
      devices: devices || other.devices,
      revenue: revenue || other.revenue,
      errors: errors || other.errors,
      activities: activities || other.activities,
      admins: admins || other.admins,
      requestAnalytics: requestAnalytics || other.requestAnalytics,
    );
  }
}
