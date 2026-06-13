import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

class AdminAuthService {
  AdminAuthService({
    required this.baseUrl,
    required this.authBaseUrl,
    required this.contentDeviceBaseUrl,
    required this.errorBaseUrl,
    required this.activityBaseUrl,
  });

  final String baseUrl;
  final String authBaseUrl;
  final String contentDeviceBaseUrl;
  final String errorBaseUrl;
  final String activityBaseUrl;
  String? _token;
  AdminUser? _currentAdmin;

  String? get token => _token;
  AdminUser? get currentAdmin => _currentAdmin;

  Future<AdminUser?> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
      }),
    );

    final data = _decode(response);
    if (response.statusCode == 401) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Login failed'));
    }

    final payload = data['data'] as Map<String, dynamic>;
    _token = payload['token']?.toString();
    _currentAdmin = _adminFromJson(payload['admin'] as Map<String, dynamic>);
    return _currentAdmin;
  }

  Future<DashboardStats> fetchUserSummary(DashboardStats fallback) async {
    final response = await http.get(
      Uri.parse('$authBaseUrl/admin/summary'),
      headers: _authHeaders(),
    );

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to load user summary'));
    }

    final payload = data['data'] as Map<String, dynamic>;
    return DashboardStats(
      totalUsers: _intValue(payload['totalUsers']),
      activeUsers: _intValue(payload['activeUsers']),
      newUsersThisMonth: _intValue(payload['newUsersThisMonth']),
      userGrowthPercent: fallback.userGrowthPercent,
      liveDevices: fallback.liveDevices,
      totalDevices: fallback.totalDevices,
      offlineDevices: fallback.offlineDevices,
      deviceGrowthPercent: fallback.deviceGrowthPercent,
      totalRevenue: fallback.totalRevenue,
      revenueThisMonth: fallback.revenueThisMonth,
      revenueGrowthPercent: fallback.revenueGrowthPercent,
      totalErrors: fallback.totalErrors,
      openErrors: fallback.openErrors,
      criticalErrors: fallback.criticalErrors,
      errorChangePercent: fallback.errorChangePercent,
    );
  }

  Future<List<Customer>> fetchUsers({
    String? search,
    String? status,
  }) async {
    final query = <String, String>{};
    if (search != null && search.trim().isNotEmpty) {
      query['search'] = search.trim();
    }
    if (status != null && status != 'All') {
      query['status'] = status;
    }

    final uri = Uri.parse('$authBaseUrl/admin/list').replace(
      queryParameters: query.isEmpty ? null : query,
    );
    final response = await http.get(uri, headers: _authHeaders());

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to load users'));
    }

    final payload = data['data'] as Map<String, dynamic>;
    final users = payload['users'] as List<dynamic>? ?? const [];
    return users
        .map((item) => _customerFromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<AdminUser>> fetchAdmins({String? search}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admins'),
      headers: _authHeaders(),
    );

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to load admins'));
    }

    final payload = data['data'] as Map<String, dynamic>? ?? const {};
    final admins = (payload['admins'] as List<dynamic>? ?? const [])
        .map((item) => _adminFromJson(item as Map<String, dynamic>))
        .toList();
    final query = search?.trim().toLowerCase() ?? '';
    if (query.isEmpty) return admins;

    return admins.where((admin) {
      return admin.name.toLowerCase().contains(query) ||
          admin.email.toLowerCase().contains(query) ||
          admin.mobile.toLowerCase().contains(query) ||
          admin.id.toLowerCase().contains(query) ||
          admin.role.toLowerCase().contains(query);
    }).toList();
  }

  Future<AdminUser> fetchAdminDetails(AdminUser admin) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admins/${admin.id}'),
      headers: _authHeaders(),
    );

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to load admin details'));
    }

    final payload = data['data'] as Map<String, dynamic>? ?? const {};
    return _adminFromJson(payload['admin'] as Map<String, dynamic>);
  }

  Future<AdminUser> createAdmin({
    required String firstName,
    required String lastName,
    required String mobile,
    required String email,
    required String password,
    int? age,
    String address = '',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admins'),
      headers: _authHeaders(),
      body: jsonEncode({
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'mobile': mobile.trim(),
        'email': email.trim(),
        'password': password,
        if (age != null) 'age': age,
        'address': address.trim(),
      }),
    );

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to create admin'));
    }

    final payload = data['data'] as Map<String, dynamic>? ?? const {};
    return _adminFromJson(payload['admin'] as Map<String, dynamic>);
  }

  Future<AdminUser> updateAdmin({
    required AdminUser admin,
    required String firstName,
    required String lastName,
    required String mobile,
    required String email,
    int? age,
    String address = '',
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/admins/${admin.id}'),
      headers: _authHeaders(),
      body: jsonEncode({
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'mobile': mobile.trim(),
        'email': email.trim(),
        if (age != null) 'age': age,
        'address': address.trim(),
      }),
    );

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to update admin'));
    }

    final payload = data['data'] as Map<String, dynamic>? ?? const {};
    return _adminFromJson(payload['admin'] as Map<String, dynamic>);
  }

  Future<AdminUser> changeAdminPassword({
    required AdminUser admin,
    required String password,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/admins/${admin.id}/password'),
      headers: _authHeaders(),
      body: jsonEncode({'password': password}),
    );

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to update password'));
    }

    final payload = data['data'] as Map<String, dynamic>? ?? const {};
    return _adminFromJson(payload['admin'] as Map<String, dynamic>);
  }

  Future<AdminUser> setAdminBlocked(AdminUser admin, bool blocked) async {
    final action = blocked ? 'block' : 'unblock';
    final response = await http.patch(
      Uri.parse('$baseUrl/admins/${admin.id}/$action'),
      headers: _authHeaders(),
    );

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to update admin'));
    }

    final payload = data['data'] as Map<String, dynamic>? ?? const {};
    return _adminFromJson(payload['admin'] as Map<String, dynamic>);
  }

  Future<void> deleteAdmin(AdminUser admin) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/admins/${admin.id}'),
      headers: _authHeaders(),
    );

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to delete admin'));
    }
  }

  Future<List<DeviceInfo>> fetchRegisteredDevices() async {
    final response = await http.get(
      Uri.parse('$contentDeviceBaseUrl/admin/devices/overview'),
      headers: _authHeaders(),
    );

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to load registered devices'));
    }

    final payload = data['data'] as Map<String, dynamic>? ?? const {};
    final rawDevices = payload['devices'] as List<dynamic>? ?? const [];
    return rawDevices
        .map((item) => _deviceFromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<RevenueOverview> fetchRevenueOverview() async {
    final response = await http.get(
      Uri.parse('$contentDeviceBaseUrl/../business/admin/revenue/overview')
          .normalizePath(),
      headers: _authHeaders(),
    );

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to load revenue'));
    }

    final payload = data['data'] as Map<String, dynamic>? ?? const {};
    final rawTransactions =
        payload['transactions'] as List<dynamic>? ?? const [];
    return RevenueOverview(
      totalRevenue: _doubleValue(payload['totalRevenue']),
      revenueThisMonth: _doubleValue(payload['revenueThisMonth']),
      transactions: rawTransactions
          .map((item) => _paymentFromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<List<ManagedPlan>> fetchManagedPlans() async {
    final response = await http.get(
      Uri.parse('$contentDeviceBaseUrl/../business/plans').normalizePath(),
      headers: _authHeaders(),
    );

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to load plans'));
    }

    final payload = data['data'] as Map<String, dynamic>? ?? const {};
    final rawPlans = payload['plans'] as List<dynamic>? ?? const [];
    return rawPlans
        .map((item) => _managedPlanFromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<RequestAnalytics> fetchRequestAnalytics() async {
    final response = await http.get(
      Uri.parse('$baseUrl/request-analytics'),
      headers: _authHeaders(),
    );

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to load request analytics'));
    }

    final payload = data['data'] as Map<String, dynamic>? ?? const {};
    return _requestAnalyticsFromJson(payload);
  }

  Future<List<ManagedPlan>> updateManagedPlanPrices(
    Map<String, double> prices,
  ) async {
    final response = await http.patch(
      Uri.parse('$contentDeviceBaseUrl/../business/admin/plans/prices')
          .normalizePath(),
      headers: _authHeaders(),
      body: jsonEncode({'prices': prices}),
    );

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to update plan prices'));
    }

    final payload = data['data'] as Map<String, dynamic>? ?? const {};
    final rawPlans = payload['plans'] as List<dynamic>? ?? const [];
    return rawPlans
        .map((item) => _managedPlanFromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<ManagedPlan>> updateManagedPlanDiscount({
    required String name,
    required DateTime validUntil,
    required Map<String, double> prices,
  }) async {
    final response = await http.patch(
      Uri.parse('$contentDeviceBaseUrl/../business/admin/plans/discount')
          .normalizePath(),
      headers: _authHeaders(),
      body: jsonEncode({
        'name': name,
        'validUntil': validUntil.toIso8601String(),
        'prices': prices,
      }),
    );

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to save plan discount'));
    }

    final payload = data['data'] as Map<String, dynamic>? ?? const {};
    final rawPlans = payload['plans'] as List<dynamic>? ?? const [];
    return rawPlans
        .map((item) => _managedPlanFromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<ManagedPlan>> deleteManagedPlanDiscount() async {
    final response = await http.delete(
      Uri.parse('$contentDeviceBaseUrl/../business/admin/plans/discount')
          .normalizePath(),
      headers: _authHeaders(),
    );

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to delete plan discount'));
    }

    final payload = data['data'] as Map<String, dynamic>? ?? const {};
    final rawPlans = payload['plans'] as List<dynamic>? ?? const [];
    return rawPlans
        .map((item) => _managedPlanFromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<MobileNotification>> fetchMobileNotifications() async {
    final response = await http.get(
      Uri.parse('$contentDeviceBaseUrl/../business/admin/notifications')
          .normalizePath(),
      headers: _authHeaders(),
    );

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to load notifications'));
    }

    final payload = data['data'] as Map<String, dynamic>? ?? const {};
    final rawNotifications =
        payload['notifications'] as List<dynamic>? ?? const [];
    return rawNotifications
        .map((item) =>
            _mobileNotificationFromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<MobileNotification> sendMobileNotification({
    String title = '',
    required String message,
  }) async {
    final response = await http.post(
      Uri.parse('$contentDeviceBaseUrl/../business/admin/notifications')
          .normalizePath(),
      headers: _authHeaders(),
      body: jsonEncode({
        'title': title.trim(),
        'message': message.trim(),
      }),
    );

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to send notification'));
    }

    final payload = data['data'] as Map<String, dynamic>? ?? const {};
    return _mobileNotificationFromJson(
      payload['notification'] as Map<String, dynamic>,
    );
  }

  Future<MobileNotification> resendMobileNotification(int id) async {
    final response = await http.post(
      Uri.parse('$contentDeviceBaseUrl/../business/admin/notifications/$id/resend')
          .normalizePath(),
      headers: _authHeaders(),
    );

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to resend notification'));
    }

    final payload = data['data'] as Map<String, dynamic>? ?? const {};
    return _mobileNotificationFromJson(
      payload['notification'] as Map<String, dynamic>,
    );
  }

  Future<void> deleteMobileNotification(int id) async {
    final response = await http.delete(
      Uri.parse('$contentDeviceBaseUrl/../business/admin/notifications/$id')
          .normalizePath(),
      headers: _authHeaders(),
    );

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to delete notification'));
    }
  }

  Future<List<ErrorRecord>> fetchErrors() async {
    final response = await http.get(
      Uri.parse(errorBaseUrl),
      headers: _authHeaders(),
    );
    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to load errors'));
    }

    final payload = data['data'] as Map<String, dynamic>? ?? const {};
    final rawErrors = payload['errors'] as List<dynamic>? ?? const [];
    return rawErrors
        .map((item) => _errorFromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<DashboardActivity>> fetchUserActivities() async {
    final response = await http.get(
      Uri.parse(activityBaseUrl),
      headers: _authHeaders(),
    );
    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to load activity'));
    }

    final payload = data['data'] as Map<String, dynamic>? ?? const {};
    final rawActivities = payload['activities'] as List<dynamic>? ?? const [];
    return rawActivities
        .map((item) => _activityFromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Customer> fetchCustomerDetails(Customer customer) async {
    final businessId = customer.businessId;
    if (businessId == null || businessId.isEmpty) return customer;

    final response = await http.get(
      Uri.parse('$contentDeviceBaseUrl/admin/business/$businessId/overview'),
      headers: _authHeaders(),
    );

    final data = _decode(response);
    if (response.statusCode == 404) return customer;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to load user details'));
    }

    final payload = data['data'] as Map<String, dynamic>;
    final business = payload['business'] as Map<String, dynamic>? ?? const {};
    final rawDevices = payload['devices'] as List<dynamic>? ?? const [];
    final devices = rawDevices
        .map((item) => _deviceFromJson(
              item as Map<String, dynamic>,
              customer: customer,
              business: business,
            ))
        .toList();

    final subscription =
        business['subscriptionPlan'] as Map<String, dynamic>? ?? const {};
    final rawOffers = <dynamic>[
      ...?subscription['offers'] as List<dynamic>?,
      ...?business['adminOffers'] as List<dynamic>?,
    ];
    final offers = rawOffers
        .whereType<Map<String, dynamic>>()
        .map(_offerFromJson)
        .toList();
    final fallbackOffer = subscription['offer'] is Map<String, dynamic>
        ? _offerFromJson(subscription['offer'] as Map<String, dynamic>)
        : _offerFromBusinessColumns(business);
    if (fallbackOffer != null &&
        !offers.any((offer) =>
            offer.isPlanOffer &&
            offer.planId == fallbackOffer.planId &&
            offer.offerAmount == fallbackOffer.offerAmount)) {
      offers.insert(0, fallbackOffer);
    }
    final planName = business['subscriptionPlanName']?.toString() ??
        subscription['name']?.toString() ??
        customer.plan;
    final planEndsAt = DateTime.tryParse(
          business['subscriptionTrialEndsAt']?.toString() ??
              subscription['trialEndsAt']?.toString() ??
              '',
        ) ??
        customer.nextPaymentDate;

    return Customer(
      id: customer.id,
      name: customer.name,
      email: customer.email,
      phone: customer.phone.isNotEmpty
          ? customer.phone
          : (business['mobile']?.toString() ?? ''),
      address: business['address']?.toString() ?? customer.address,
      city: customer.city,
      country: customer.country,
      plan: planName,
      status: customer.status,
      isOnline: devices.any((device) => device.isOnline),
      deviceCount: devices.length,
      totalUsageGB: customer.totalUsageGB,
      monthlyUsageGB: customer.monthlyUsageGB,
      joinDate: customer.joinDate,
      nextPaymentDate: planEndsAt,
      monthlyCharge: _doubleValue(
          business['subscriptionAmount'] ?? subscription['amount']),
      errorCount: customer.errorCount,
      paymentHistory: customer.paymentHistory,
      devices: devices,
      offers: offers,
      avatarInitials: customer.avatarInitials,
      businessName: business['name']?.toString() ?? customer.businessName,
      businessId: customer.businessId,
    );
  }

  Future<Customer> extendCustomerPlan({
    required Customer customer,
    required int days,
  }) async {
    final businessId = customer.businessId;
    if (businessId == null || businessId.isEmpty) {
      throw Exception('Business is not linked for this user');
    }

    final response = await http.patch(
      Uri.parse(
              '$contentDeviceBaseUrl/../business/admin/business/$businessId/extend-plan')
          .normalizePath(),
      headers: _authHeaders(),
      body: jsonEncode({'days': days}),
    );

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to extend plan'));
    }

    return fetchCustomerDetails(customer);
  }

  Future<Customer> sendCustomerPlanOffer({
    required Customer customer,
    required String planId,
    required String planName,
    required double originalAmount,
    required double offerAmount,
    required DateTime validUntil,
  }) async {
    final businessId = customer.businessId;
    if (businessId == null || businessId.isEmpty) {
      throw Exception('Business is not linked for this user');
    }

    final response = await http.patch(
      Uri.parse(
              '$contentDeviceBaseUrl/../business/admin/business/$businessId/plan-offer')
          .normalizePath(),
      headers: _authHeaders(),
      body: jsonEncode({
        'planId': planId,
        'planName': planName,
        'originalAmount': originalAmount,
        'offerAmount': offerAmount,
        'validUntil': validUntil.toIso8601String(),
      }),
    );

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(data, 'Failed to send plan offer'));
    }

    final updated = await fetchCustomerDetails(customer);
    final sentOffer = CustomerOffer(
      id: 'active-offer',
      type: 'PLAN_OFFER',
      planId: planId,
      planName: planName,
      originalAmount: originalAmount,
      offerAmount: offerAmount,
      currency: 'INR',
      validUntil: validUntil,
      createdAt: DateTime.now(),
    );
    final hasSentOffer = updated.offers.any(
      (offer) =>
          offer.isPlanOffer &&
          offer.planId == sentOffer.planId &&
          offer.offerAmount == sentOffer.offerAmount,
    );
    if (hasSentOffer) return updated;
    return _customerWithOffers(updated, [sentOffer, ...updated.offers]);
  }

  void logout() {
    _token = null;
    _currentAdmin = null;
  }

  Map<String, String> _authHeaders() {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception('Admin token is missing');
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) return const {};
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  String _errorMessage(Map<String, dynamic> data, String fallback) {
    return data['error']?.toString() ?? data['message']?.toString() ?? fallback;
  }

  AdminUser _adminFromJson(Map<String, dynamic> json) {
    final firstName = json['firstName']?.toString() ?? '';
    final lastName = json['lastName']?.toString() ?? '';
    final name = json['name']?.toString() ??
        [firstName, lastName].where((part) => part.isNotEmpty).join(' ');
    return AdminUser(
      id: json['id'].toString(),
      name: name.trim().isEmpty ? 'Admin' : name.trim(),
      firstName: firstName,
      lastName: lastName,
      mobile: json['mobile']?.toString() ?? '',
      age: _nullableInt(json['age']),
      address: json['address']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? 'ADMIN',
      isActive: json['isActive'] != false,
      createdById: json['createdById']?.toString(),
      lastLoginAt: DateTime.tryParse(json['lastLoginAt']?.toString() ?? ''),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }

  ManagedPlan _managedPlanFromJson(Map<String, dynamic> json) {
    return ManagedPlan(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Plan',
      summary: json['summary']?.toString() ?? '',
      minTvDevices: _intValue(json['minTvDevices']),
      maxTvDevices: _intValue(json['maxTvDevices']),
      amount: _doubleValue(json['amount']),
      currency: json['currency']?.toString() ?? 'INR',
      trialDays: _nullableInt(json['trialDays']),
      features: (json['features'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      discountName: json['discountName']?.toString(),
      discountAmount: _nullableDouble(json['discountAmount']),
      discountEndsAt:
          DateTime.tryParse(json['discountEndsAt']?.toString() ?? ''),
    );
  }

  RequestAnalytics _requestAnalyticsFromJson(Map<String, dynamic> json) {
    return RequestAnalytics(
      generatedAt: DateTime.tryParse(json['generatedAt']?.toString() ?? ''),
      totalRequests: _intValue(json['totalRequests']),
      currentDay: _requestPeriodFromJson(json['currentDay']),
      currentMonth: _requestPeriodFromJson(json['currentMonth']),
      currentYear: _requestPeriodFromJson(json['currentYear']),
      dangerousUsers: (json['dangerousUsers'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_dangerousRequestUserFromJson)
          .toList(),
      users: (json['users'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_userRequestAnalyticsFromJson)
          .toList(),
    );
  }

  RequestAnalyticsPeriod _requestPeriodFromJson(dynamic value) {
    final json =
        value is Map<String, dynamic> ? value : const <String, dynamic>{};
    return RequestAnalyticsPeriod(
      bucket: json['bucket']?.toString() ?? '',
      endpoints: (json['endpoints'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((item) => ApiRequestCount(
                endpoint: item['endpoint']?.toString() ?? 'Unknown API',
                count: _intValue(item['count']),
              ))
          .toList(),
    );
  }

  DangerousRequestUser _dangerousRequestUserFromJson(
      Map<String, dynamic> json) {
    return DangerousRequestUser(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? 'Unknown user',
      role: json['role']?.toString() ?? 'UNKNOWN',
      today: _intValue(json['today']),
      month: _intValue(json['month']),
      year: _intValue(json['year']),
      total: _intValue(json['total']),
      lastSeenAt: DateTime.tryParse(json['lastSeenAt']?.toString() ?? ''),
    );
  }

  UserRequestAnalytics _userRequestAnalyticsFromJson(
      Map<String, dynamic> json) {
    return UserRequestAnalytics(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? 'Unknown user',
      role: json['role']?.toString() ?? 'UNKNOWN',
      today: _intValue(json['today']),
      month: _intValue(json['month']),
      year: _intValue(json['year']),
      total: _intValue(json['total']),
      lastSeenAt: DateTime.tryParse(json['lastSeenAt']?.toString() ?? ''),
      currentDay: _requestPeriodFromJson(json['currentDay']),
      currentMonth: _requestPeriodFromJson(json['currentMonth']),
      currentYear: _requestPeriodFromJson(json['currentYear']),
    );
  }

  Customer _customerFromJson(Map<String, dynamic> json) {
    final firstName = json['firstName']?.toString();
    final lastName = json['lastName']?.toString();
    final name = json['name']?.toString() ??
        [firstName, lastName].whereType<String>().join(' ').trim();
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now();
    final id = json['id']?.toString() ?? '';
    final email = json['email']?.toString() ?? '';
    final status = json['status']?.toString() ??
        ((json['isActive'] == false) ? 'Banned' : 'Active');

    return Customer(
      id: id,
      name: name.isEmpty ? (json['username']?.toString() ?? 'User $id') : name,
      email: email,
      phone: json['phone']?.toString() ?? '',
      address: '',
      city: '',
      country: '',
      plan: 'Free',
      status: status,
      isOnline: false,
      deviceCount: 0,
      totalUsageGB: 0,
      monthlyUsageGB: 0,
      joinDate: createdAt,
      nextPaymentDate: createdAt,
      monthlyCharge: 0,
      errorCount: 0,
      paymentHistory: const [],
      devices: const [],
      offers: const [],
      avatarInitials: _initials(name.isEmpty ? email : name),
      businessName: json['businessId'] == null
          ? 'No business linked'
          : 'Business #${json['businessId']}',
      businessId: json['businessId']?.toString(),
    );
  }

  DeviceInfo _deviceFromJson(
    Map<String, dynamic> json, {
    Customer? customer,
    Map<String, dynamic>? business,
  }) {
    final deviceCode = json['deviceCode']?.toString() ?? json['id'].toString();
    final name = json['name']?.toString();
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now();
    final online = json['online'] == true;
    final businessJson =
        business ?? (json['business'] as Map<String, dynamic>? ?? const {});
    final businessName = businessJson['name']?.toString() ??
        customer?.businessName ??
        'Business #${businessJson['id'] ?? ''}'.trim();
    final ownerId = customer?.id ?? businessJson['id']?.toString() ?? '';
    final ownerName = customer?.name ?? businessName;

    return DeviceInfo(
      deviceId: deviceCode,
      deviceName: name == null || name.isEmpty ? 'Display $deviceCode' : name,
      macAddress: json['macAddress']?.toString() ?? 'Not available',
      androidVersion: json['androidVersion']?.toString() ?? 'Not available',
      osName: 'TV Display',
      model: json['model']?.toString() ?? json['mode']?.toString() ?? 'Display',
      manufacturer: json['manufacturer']?.toString() ?? 'Not available',
      isOnline: online,
      isActive: json['isActive'] != false,
      ownerId: ownerId,
      ownerName: ownerName,
      businessName: businessName,
      registeredAt: createdAt,
      lastSeen: online ? DateTime.now() : null,
      appVersion: json['appVersion']?.toString() ?? 'Not available',
      ipAddress: json['ipAddress']?.toString() ?? 'Not available',
      location: businessJson['address']?.toString() ?? '',
      storageUsedGB: 0,
      storageTotalGB: 0,
      batteryLevel: 0,
      firmwareVersion: json['buildDisplay']?.toString() ?? 'Not available',
      serialNumber: json['serialNumber']?.toString() ??
          json['id']?.toString() ??
          deviceCode,
      extraDetails: _stringDetails({
        'Device Code': deviceCode,
        'Display Name': name ?? '',
        'Manufacturer': json['manufacturer'],
        'Brand': json['brand'],
        'Model': json['model'],
        'Product': json['product'],
        'Android Device': json['deviceName'],
        'Board': json['board'],
        'Hardware': json['hardware'],
        'Android Version': json['androidVersion'],
        'SDK': json['sdkInt'],
        'Build ID': json['buildId'],
        'Build Display': json['buildDisplay'],
        'Fingerprint': json['fingerprint'],
        'Serial Number': json['serialNumber'],
        'Android ID': json['androidId'],
        'MAC Address': json['macAddress'],
        'IP Address': json['ipAddress'],
        'Screen Width': json['screenWidth'],
        'Screen Height': json['screenHeight'],
        'Pixel Ratio': json['screenPixelRatio'],
        'Platform': json['platform'],
        'OS Version': json['osVersion'],
        'App Version': json['appVersion'],
        'Display Mode': json['mode'],
        'Orientation': json['orientation'],
        'Menu Theme': json['menuTheme'],
        'Theme Color': json['themeColor'],
        'Display Language': json['displayLanguage'],
        'Content Mode': json['displayContentMode'],
        'Selected Category ID': json['selectedCategoryId'],
        'Selected Media ID': json['selectedMediaId'],
        'Transition Style': json['transitionStyle'],
        'Transition Speed': json['transitionSpeedSeconds'],
        'Auto Scroll Interval': json['autoScrollIntervalSeconds'],
        'Schedule Enabled': json['scheduleEnabled'],
        'Always On': json['alwaysOn'],
        'Schedule Start': json['scheduleStartTime'],
        'Schedule End': json['scheduleEndTime'],
        'Show Price': json['showPrice'],
        'Show Description': json['showDescription'],
        'Show Logo': json['showLogo'],
        'Show Company Name': json['showCompanyName'],
        'Show Product Image': json['showProductImage'],
        'Show Diet Tags': json['showDietTags'],
        'Show Combo Quantity': json['showComboItemQuantity'],
        'Heading Font Scale': json['headingFontScale'],
        'Name Font Scale': json['nameFontScale'],
        'Description Font Scale': json['descriptionFontScale'],
        'Price Font Scale': json['priceFontScale'],
        'Online': online,
        'Business ID': businessJson['id'],
        'Business Name': businessName,
        'Business Mobile': businessJson['mobile'],
        'Business Email': businessJson['email'],
        'Business Active': businessJson['isActive'],
        'Created At': json['createdAt'],
      }),
    );
  }

  Map<String, String> _stringDetails(Map<String, dynamic> values) {
    return values.map((key, value) {
      final text = value?.toString() ?? '';
      return MapEntry(key, text.isEmpty ? 'Not available' : text);
    });
  }

  int _intValue(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int? _nullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  double _doubleValue(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  CustomerOffer _offerFromJson(Map<String, dynamic> json) {
    final hasPlanOfferShape = json['planId'] != null &&
        (json['offerAmount'] ?? json['amount']) != null;
    return CustomerOffer(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? (hasPlanOfferShape ? 'PLAN_OFFER' : ''),
      planId: json['planId']?.toString(),
      planName: json['planName']?.toString(),
      originalAmount: _nullableDouble(json['originalAmount']),
      offerAmount: _nullableDouble(json['offerAmount'] ?? json['amount']),
      currency: json['currency']?.toString() ?? 'INR',
      extensionDays: _nullableInt(json['extensionDays']),
      previousEndsAt:
          DateTime.tryParse(json['previousEndsAt']?.toString() ?? ''),
      newEndsAt: DateTime.tryParse(json['newEndsAt']?.toString() ?? ''),
      validUntil: DateTime.tryParse(
        (json['validUntil'] ?? json['expiresAt'])?.toString() ?? '',
      ),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }

  CustomerOffer? _offerFromBusinessColumns(Map<String, dynamic> business) {
    final planId = business['subscriptionOfferPlanId']?.toString();
    final amount = _nullableDouble(business['subscriptionOfferAmount']);
    if (planId == null || planId.isEmpty || amount == null) return null;
    return CustomerOffer(
      id: 'active-offer',
      type: 'PLAN_OFFER',
      planId: planId,
      planName: business['subscriptionOfferPlanName']?.toString(),
      originalAmount:
          _nullableDouble(business['subscriptionOfferOriginalAmount']),
      offerAmount: amount,
      currency: business['subscriptionOfferCurrency']?.toString() ?? 'INR',
      validUntil: DateTime.tryParse(
        business['subscriptionOfferExpiresAt']?.toString() ?? '',
      ),
      createdAt: DateTime.tryParse(
        business['subscriptionOfferCreatedAt']?.toString() ?? '',
      ),
    );
  }

  Customer _customerWithOffers(Customer customer, List<CustomerOffer> offers) {
    return Customer(
      id: customer.id,
      name: customer.name,
      email: customer.email,
      phone: customer.phone,
      address: customer.address,
      city: customer.city,
      country: customer.country,
      plan: customer.plan,
      status: customer.status,
      isOnline: customer.isOnline,
      deviceCount: customer.deviceCount,
      totalUsageGB: customer.totalUsageGB,
      monthlyUsageGB: customer.monthlyUsageGB,
      joinDate: customer.joinDate,
      nextPaymentDate: customer.nextPaymentDate,
      monthlyCharge: customer.monthlyCharge,
      errorCount: customer.errorCount,
      paymentHistory: customer.paymentHistory,
      devices: customer.devices,
      offers: offers,
      avatarInitials: customer.avatarInitials,
      businessName: customer.businessName,
      businessId: customer.businessId,
    );
  }

  double? _nullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  PaymentRecord _paymentFromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now();
    final transactionId =
        json['transactionId']?.toString() ?? 'TXN-${json['id'] ?? ''}';
    final customerName = json['customerName']?.toString();
    final businessName = json['businessName']?.toString() ?? '';
    final planName = json['planName']?.toString() ?? 'Plan';

    return PaymentRecord(
      transactionId: transactionId,
      date: createdAt,
      amount: _doubleValue(json['amount']),
      currency: json['currency']?.toString() ?? 'INR',
      status: (json['status']?.toString() ?? 'success').toLowerCase(),
      method: json['method']?.toString() ?? 'plan',
      customerId: json['customerId']?.toString() ??
          json['businessId']?.toString() ??
          '',
      customerName: customerName == null || customerName.isEmpty
          ? (businessName.isEmpty ? 'Customer' : businessName)
          : customerName,
      businessName: businessName,
      plan: planName,
      description: json['description']?.toString() ??
          '$planName plan purchase for $businessName',
      invoiceId: json['invoiceId']?.toString() ?? transactionId,
      extraDetails: _stringDetails({
        'Transaction ID': transactionId,
        'Invoice ID': json['invoiceId'],
        'Amount': json['amount'],
        'Currency': json['currency'],
        'Status': json['status'],
        'Method': json['method'],
        'Plan ID': json['planId'],
        'Plan Name': json['planName'],
        'Customer ID': json['customerId'],
        'Customer Name': json['customerName'],
        'Customer Email': json['customerEmail'],
        'Customer Phone': json['customerPhone'],
        'Business ID': json['businessId'],
        'Business Name': json['businessName'],
        'Business Email': json['businessEmail'],
        'Business Mobile': json['businessMobile'],
        'Business Address': json['businessAddress'],
        'Created At': json['createdAt'],
        'Updated At': json['updatedAt'],
        'Environment': json['environment'],
        'Raw Details': json['rawDetails'],
      }),
    );
  }

  ErrorRecord _errorFromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now();
    final errorId = json['errorId']?.toString() ?? 'ERR-${json['id'] ?? ''}';
    final source = json['source']?.toString() ?? 'unknown';
    final errorType = json['errorType']?.toString() ?? 'backend';
    final severity = (json['severity']?.toString() ?? 'medium').toLowerCase();
    final status = (json['status']?.toString() ?? 'open').toLowerCase();
    final message = json['message']?.toString() ?? 'Unknown error';
    final businessId = json['businessId']?.toString() ?? '';
    final businessName = json['businessName']?.toString() ?? source;
    final ownerId = json['ownerId']?.toString() ??
        json['customerId']?.toString() ??
        businessId;

    return ErrorRecord(
      errorId: errorId,
      timestamp: createdAt,
      errorCode: json['errorCode']?.toString() ?? errorId,
      errorType: errorType,
      severity: severity == 'lower' ? 'low' : severity,
      message: message,
      stackTrace: json['stackTrace']?.toString() ?? 'Not available',
      deviceId: json['deviceId']?.toString() ?? 'Not available',
      deviceName: json['deviceName']?.toString() ?? source,
      ownerId: ownerId.isEmpty ? 'Not available' : ownerId,
      ownerName: json['ownerName']?.toString() ??
          json['customerName']?.toString() ??
          businessName,
      businessName: businessName,
      appVersion: json['appVersion']?.toString() ?? 'Not available',
      osVersion: json['osVersion']?.toString() ?? 'Not available',
      status: status,
      resolvedAt: json['resolvedAt']?.toString(),
      resolvedBy: json['resolvedBy']?.toString(),
      extraDetails: _stringDetails({
        'Error ID': errorId,
        'Source': source,
        'Error Code': json['errorCode'],
        'Type': errorType,
        'Severity': severity,
        'Status': status,
        'Message': message,
        'Device ID': json['deviceId'],
        'Device Name': json['deviceName'],
        'Owner ID': json['ownerId'],
        'Owner Name': json['ownerName'],
        'Customer ID': json['customerId'],
        'Business ID': json['businessId'],
        'Business Name': json['businessName'],
        'App Version': json['appVersion'],
        'OS Version': json['osVersion'],
        'Created At': json['createdAt'],
        'Updated At': json['updatedAt'],
      }),
    );
  }

  MobileNotification _mobileNotificationFromJson(Map<String, dynamic> json) {
    return MobileNotification(
      id: _intValue(json['id']),
      target: json['target']?.toString() ?? 'ALL',
      businessName: json['businessName']?.toString(),
      title: json['title']?.toString() ?? 'teX notification',
      message: json['message']?.toString() ?? '',
      category: json['category']?.toString() ?? 'GENERAL',
      sentAt: DateTime.tryParse(json['sentAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  DashboardActivity _activityFromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now();
    final action = json['action']?.toString() ?? 'ACTIVITY';
    final description = json['description']?.toString() ?? action;
    final readable = action
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) =>
            '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
        .join(' ');

    return DashboardActivity(
      title: readable.isEmpty ? 'Activity' : readable,
      subtitle: description,
      type: action,
      timestamp: createdAt,
    );
  }

  String _initials(String value) {
    final parts = value.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'US';
    if (parts.length == 1) {
      final end = parts.first.length < 2 ? parts.first.length : 2;
      return parts.first.substring(0, end).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
