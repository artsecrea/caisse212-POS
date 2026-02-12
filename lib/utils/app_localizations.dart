import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  static final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      // Common
      'app_title': 'POS System',
      'ok': 'OK',
      'cancel': 'Cancel',
      'close': 'Close',
      'save': 'Save',
      'delete': 'Delete',
      'edit': 'Edit',
      'add': 'Add',
      'search': 'Search',
      'filter': 'Filter',
      'refresh': 'Refresh',
      'loading': 'Loading...',
      'error': 'Error',
      'success': 'Success',
      'confirm': 'Confirm',
      'yes': 'Yes',
      'no': 'No',
      'back': 'Back',
      'next': 'Next',
      'previous': 'Previous',
      'first': 'First',
      'last': 'Last',
      'page': 'Page',
      'of': 'of',
      'for': 'for',
      'showing': 'Showing',

      // Login
      'login': 'Login',
      'logout': 'Logout',
      'username': 'Username',
      'password': 'Password',
      'sign_in': 'Sign In',
      'starting_balance': 'Starting Balance',
      'invalid_credentials': 'Invalid credentials',
      'login_failed': 'Login failed',
      'exit_to_tenant': 'Exit to Tenant Login',
      'username_required': 'Username is required',
      'password_required': 'Password is required',

      // Tenant
      'tenant_id': 'Tenant ID',
      'tenant_password': 'Tenant Password',
      'continue': 'Continue',
      'enter_tenant_id': 'Enter your tenant ID',
      'enter_password': 'Enter a password',
      'password_min_length': 'Password must be at least 4 characters',
      'verify': 'Verify',
      'verify_logout': 'Verify & Logout',
      'invalid_tenant_password': 'Invalid tenant password',

      // Users
      'users_management': 'Users Management',
      'user_id': 'User ID',
      'user_type': 'User Type',
      'full_name': 'Full Name',
      'first_name': 'First Name',
      'last_name': 'Last Name',
      'created_at': 'Created At',
      'updated_at': 'Updated At',
      'last_login': 'Last Login',
      'never': 'Never',
      'actions': 'Actions',
      'view_details': 'View Details',
      'user_details': 'User Details',
      'basic_information': 'Basic Information',
      'activity_information': 'Activity Information',
      'permissions': 'Permissions',
      'no_permissions': 'No permissions set',
      'invalid_permissions': 'Invalid permissions format',
      'all_types': 'All Types',
      'admin': 'Admin',
      'cashier': 'Cashier',
      'waiter': 'Waiter',
      'no_users_found': 'No users found',
      'try_adjusting_filters': 'Try adjusting your filters',
      'error_loading_users': 'Error loading users',
      'search_by_name': 'Search by name, username...',

      // Main Screen
      'categories': 'Categories',
      'products': 'Products',
      'current_order': 'Current Order',
      'no_items': 'No items in order',
      'add_items': 'Add items to start',
      'subtotal': 'Subtotal',
      'tax': 'Tax',
      'discount': 'Discount',
      'total': 'Total',
      'hold': 'Hold',
      'clear': 'Clear',
      'proceed': 'Proceed',
      'print': 'Print',

      // Tables
      'table': 'Table',
      'tables': 'Tables',
      'select_table': 'Select Table',
      'clear_table': 'Clear Table',
      'table_cleared': 'Table cleared',

      // Orders
      'orders': 'Orders',
      'order': 'Order',
      'orders_management': 'Orders Management',
      'order_id': 'Order ID',
      'order_status': 'Order Status',
      'order_type': 'Order Type',
      'order_date': 'Order Date',
      'order_total': 'Order Total',
      'pending': 'Pending',
      'completed': 'Completed',
      'cancelled': 'Cancelled',
      'dine_in': 'Dine In',
      'take_away': 'Take Away',
      'no_orders_found': 'No orders found',

      // Order Confirmation
      'confirm_order': 'Confirm Order',
      'confirm_and_pay': 'Confirm & Pay',
      'order_on_hold': 'Order On Hold',
      'no_onhold_orders': 'No orders on hold',
      'select_order_to_confirm': 'Select an order to confirm',
      'search_by_code': 'Search by code...',
      'items': 'Items',
      'type': 'Type',

      // Customers
      'customer': 'Customer',
      'customers': 'Customers',
      'select_customer': 'Select Customer',
      'customer_name': 'Customer Name',
      'customer_phone': 'Customer Phone',

      // Commercial
      'commercial': 'Commercial',
      'select_commercial': 'Select Commercial',

      // Products
      'product_name': 'Product Name',
      'product_price': 'Product Price',
      'quantity': 'Quantity',
      'price': 'Price',
      'category': 'Category',
      'all_categories': 'All Categories',

      // Discount
      'manual_discount': 'Manual Discount',
      'discount_percentage': 'Discount Percentage',
      'apply_discount': 'Apply Discount',
      'remove_discount': 'Remove Discount',
      'discount_applied': 'Discount Applied',

      // Payment
      'payment': 'Payment',
      'pay': 'Pay',
      'cash': 'Cash',
      'card': 'Card',
      'amount_paid': 'Amount Paid',
      'change': 'Change',
      'payment_successful': 'Payment Successful',

      // Session
      'session': 'Session',
      'sessions': 'Sessions',
      'session_management': 'Session Management',
      'start_session': 'Start Session',
      'end_session': 'End Session',
      'pause_session': 'Pause Session',
      'resume_session': 'Resume Session',
      'active': 'Active',
      'paused': 'Paused',
      'ended': 'Ended',
      'session_details': 'Session Details',
      'cash_at_start': 'Cash at Start',
      'cash_at_end': 'Cash at End',
      'expected_cash': 'Expected Cash',

      // Settings
      'settings': 'Settings',
      'general_settings': 'General Settings',
      'appearance': 'Appearance',
      'dark_mode': 'Dark Mode',
      'language': 'Language',
      'currency': 'Currency',
      'tax_rate': 'Tax Rate',
      'default_order_type': 'Default Order Type',
      'show_product_images': 'Show Product Images',
      'printing': 'Printing',
      'enable_auto_print': 'Enable Auto Print',
      'printer_settings': 'Printer Settings',

      // Devices
      'devices': 'Devices',
      'devices_management': 'Devices Management',
      'device_name': 'Device Name',
      'device_type': 'Device Type',
      'device_status': 'Device Status',

      // Tickets
      'tickets': 'Tickets',
      'ticket': 'Ticket',
      'ticket_id': 'Ticket ID',
      'ticket_status': 'Ticket Status',
      'paid': 'Paid',
      'unpaid': 'Unpaid',

      // Sync
      'sync': 'Sync',
      'syncing': 'Syncing...',
      'sync_successful': 'Sync Successful',
      'sync_failed': 'Sync Failed',
      'last_sync': 'Last Sync',
      'auto_sync': 'Auto Sync',

      // Full Logout
      'full_logout': 'Full Logout',
      'full_logout_confirm': 'This will clear all server authentication data and local database.\n\nYou will need to reconnect to the server or use demo mode again.\n\nAre you sure?',
      'verify_tenant_password': 'Verify Tenant Password',
      'full_logout_warning': 'This will clear ALL data and disconnect from the server.',

      // Demo
      'demo_mode': 'Demo Mode',
      'demo_login': 'Demo Login',
      'server_login': 'Server Login',

      // Errors
      'error_occurred': 'An error occurred',
      'try_again': 'Try again',
      'no_internet': 'No internet connection',

      // Time
      'today': 'Today',
      'yesterday': 'Yesterday',
      'this_week': 'This Week',
      'this_month': 'This Month',

      // Status
      'online': 'Online',
      'offline': 'Offline',
      'connected': 'Connected',
      'disconnected': 'Disconnected',

      // Numbers
      'number_of_persons': 'Number of Persons',
      'person': 'Person',
      'persons': 'Persons',

      // Additional Login & Tenant
      'enter_username': 'Enter your username',
      'enter_tenant_password': 'Enter tenant password to continue',
      'are_you_sure': 'Are you sure?',
      'database_error': 'Database Error',
      'database_empty': 'Database is empty. Please reconnect to server or use demo mode.',
      'reconnect': 'Reconnect',
      'session_resumed': 'Session resumed successfully',
      'session_created': 'New session created',
      'welcome_back': 'Welcome back',

      // Main Screen
      'new_order': 'New Order',
      'held_orders': 'Held Orders',
      'no_category_selected': 'No Category Selected',
      'select_category': 'Select a category to view products',
      'no_products_available': 'No products available',
      'no_products_in_category': 'No products in this category',
      'set': 'Set',
      'unset': 'Unset',
      'apply': 'Apply',
      'coupon': 'Coupon',
      'coupons': 'Coupons',

      // Payment Screen
      'payment_methods': 'Payment Methods',
      'split_payment': 'Split Payment',
      'amount_to_pay': 'Amount to Pay',
      'amount_remaining': 'Remaining',
      'enter_amount': 'Enter amount',
      'complete_payment': 'Complete Payment',
      'add_payment_method': 'Add Payment Method',
      'payment_method': 'Payment Method',
      'remove': 'Remove',
      'insufficient_amount': 'Insufficient amount paid',
      'please_pay_full_amount': 'Please pay the full amount',
      'overpaid': 'Overpaid',
      'payment_complete': 'Payment Complete',
      'change_to_return': 'Change to Return',
      'receipt': 'Receipt',
      'print_receipt': 'Print Receipt',
      'new_sale': 'New Sale',
      'return_to_order': 'Return to Order',

      // Session Screen
      'current_session': 'Current Session',
      'no_active_session': 'No Active Session',
      'start_new_session': 'Start New Session',
      'session_info': 'Session Information',
      'session_started': 'Session Started',
      'session_ended': 'Session Ended',
      'duration': 'Duration',
      'total_sales': 'Total Sales',
      'total_transactions': 'Total Transactions',
      'end_session_confirm': 'Are you sure you want to end this session?',
      'end_session_warning': 'This will close the current session and logout.',

      // Tenant Login Screen
      'server_url': 'Server URL',
      'pos_name': 'POS Name',
      'server_login': 'Server Login',
      'loading_data': 'Loading data...',
      'authenticating': 'Authenticating...',
      'syncing_data': 'Syncing data...',
      'setup_complete': 'Setup complete!',

      // Settings Page
      'reset_settings': 'Reset Settings',
      'reset_to_defaults': 'Reset to Defaults',
      'reset_confirm': 'Are you sure you want to reset all settings to defaults?',
      'settings_reset': 'Settings reset successfully',
      'data_retention': 'Data Retention',
      'days': 'Days',
      'bulk_sync_size': 'Bulk Sync Size',
      'items': 'Items',
      'category_display': 'Category Display',
      'top_bar': 'Top Bar',
      'full_page': 'Full Page',

      // API Tester
      'api_tester': 'API Tester',
      'endpoint': 'Endpoint',
      'method': 'Method',
      'request': 'Request',
      'response': 'Response',
      'send': 'Send',
      'clear_response': 'Clear Response',

      // Dialogs & Confirmations
      'select_option': 'Select Option',
      'no_options_available': 'No options available',
      'clear_confirm': 'Are you sure you want to clear the current order?',
      'delete_confirm': 'Are you sure you want to delete this item?',
      'hold_order': 'Hold Order',
      'resume_order': 'Resume Order',
      'order_held': 'Order held successfully',
      'order_resumed': 'Order resumed successfully',

      // Product Modifications
      'product_details': 'Product Details',
      'components': 'Components',
      'special_instructions': 'Special Instructions',
      'add_to_order': 'Add to Order',
      'update_item': 'Update Item',
      'required': 'Required',
      'optional': 'Optional',
      'select_components': 'Select Components',

      // Tables
      'table_number': 'Table Number',
      'occupied': 'Occupied',
      'available': 'Available',
      'clear_table_confirm': 'Are you sure you want to clear this table?',
      'pay_first': 'Pay First',
      'just_clear': 'Just Clear',
      'table_has_items': 'This table has unpaid items. What would you like to do?',

      // Calculator & Payment
      'loaded': 'Loaded',
      'to': 'to',
      'calculator': 'Calculator',
      'new_ticket': 'New Ticket',
      'item_discount': 'Item Discount',
      'reprint': 'Reprint',
      'quick_amounts': 'Quick Amounts',

      // Issue Reporting
      'report_issue': 'Report Issue',
      'issue_type': 'Issue Type',
      'issue_title': 'Issue Title',
      'issue_description': 'Issue Description',
      'submit_issue': 'Submit Issue',
      'issue_submitted': 'Issue submitted successfully',
      'issue_submit_failed': 'Failed to submit issue',
      'issue_type_general': 'General',
      'issue_type_bug': 'Bug',
      'issue_type_feature': 'Feature Request',
      'issue_type_hardware': 'Hardware',
      'issue_type_network': 'Network',
      'issue_type_printer': 'Printer',
      'issue_type_other': 'Other',
      'enter_issue_title': 'Enter issue title',
      'enter_issue_description': 'Describe the issue (optional)',
      'title_required': 'Title is required',
    },
    'ar': {
      // Common - Arabic
      'app_title': 'نظام نقاط البيع',
      'ok': 'موافق',
      'cancel': 'إلغاء',
      'close': 'إغلاق',
      'save': 'حفظ',
      'delete': 'حذف',
      'edit': 'تعديل',
      'add': 'إضافة',
      'search': 'بحث',
      'filter': 'تصفية',
      'refresh': 'تحديث',
      'loading': 'جاري التحميل...',
      'error': 'خطأ',
      'success': 'نجح',
      'confirm': 'تأكيد',
      'yes': 'نعم',
      'no': 'لا',
      'back': 'رجوع',
      'next': 'التالي',
      'previous': 'السابق',
      'first': 'الأول',
      'last': 'الأخير',
      'page': 'صفحة',
      'of': 'من',
      'for': 'لـ',
      'showing': 'عرض',

      // Login
      'login': 'تسجيل الدخول',
      'logout': 'تسجيل الخروج',
      'username': 'اسم المستخدم',
      'password': 'كلمة المرور',
      'sign_in': 'دخول',
      'starting_balance': 'الرصيد الافتتاحي',
      'invalid_credentials': 'بيانات اعتماد غير صالحة',
      'login_failed': 'فشل تسجيل الدخول',
      'exit_to_tenant': 'الخروج إلى تسجيل دخول المستأجر',

      // Tenant
      'tenant_id': 'معرف المستأجر',
      'tenant_password': 'كلمة مرور المستأجر',
      'continue': 'متابعة',
      'enter_tenant_id': 'أدخل معرف المستأجر الخاص بك',
      'enter_password': 'أدخل كلمة المرور',
      'password_min_length': 'يجب أن تكون كلمة المرور 4 أحرف على الأقل',
      'verify': 'تحقق',
      'verify_logout': 'تحقق وتسجيل الخروج',
      'invalid_tenant_password': 'كلمة مرور المستأجر غير صحيحة',

      // Users
      'users_management': 'إدارة المستخدمين',
      'user_id': 'معرف المستخدم',
      'user_type': 'نوع المستخدم',
      'full_name': 'الاسم الكامل',
      'first_name': 'الاسم الأول',
      'last_name': 'اسم العائلة',
      'created_at': 'تاريخ الإنشاء',
      'updated_at': 'تاريخ التحديث',
      'last_login': 'آخر تسجيل دخول',
      'never': 'أبداً',
      'actions': 'الإجراءات',
      'view_details': 'عرض التفاصيل',
      'user_details': 'تفاصيل المستخدم',
      'basic_information': 'المعلومات الأساسية',
      'activity_information': 'معلومات النشاط',
      'permissions': 'الصلاحيات',
      'no_permissions': 'لا توجد صلاحيات محددة',
      'invalid_permissions': 'تنسيق الصلاحيات غير صالح',
      'all_types': 'جميع الأنواع',
      'admin': 'مدير',
      'cashier': 'أمين الصندوق',
      'waiter': 'نادل',
      'no_users_found': 'لم يتم العثور على مستخدمين',
      'try_adjusting_filters': 'حاول تعديل المرشحات',
      'error_loading_users': 'خطأ في تحميل المستخدمين',
      'search_by_name': 'البحث بالاسم، اسم المستخدم...',

      // Main Screen
      'categories': 'الفئات',
      'products': 'المنتجات',
      'current_order': 'الطلب الحالي',
      'no_items': 'لا توجد عناصر في الطلب',
      'add_items': 'أضف عناصر للبدء',
      'subtotal': 'المجموع الفرعي',
      'tax': 'الضريبة',
      'discount': 'الخصم',
      'total': 'الإجمالي',
      'hold': 'تعليق',
      'clear': 'مسح',
      'proceed': 'متابعة',
      'print': 'طباعة',

      // Tables
      'table': 'طاولة',
      'tables': 'الطاولات',
      'select_table': 'اختر طاولة',
      'clear_table': 'مسح الطاولة',
      'table_cleared': 'تم مسح الطاولة',

      // Orders
      'orders': 'الطلبات',
      'order': 'طلب',
      'orders_management': 'إدارة الطلبات',
      'order_id': 'رقم الطلب',
      'order_status': 'حالة الطلب',
      'order_type': 'نوع الطلب',
      'order_date': 'تاريخ الطلب',
      'order_total': 'إجمالي الطلب',
      'pending': 'قيد الانتظار',
      'completed': 'مكتمل',
      'cancelled': 'ملغى',

      // Order Confirmation
      'confirm_order': 'تأكيد الطلب',
      'confirm_and_pay': 'تأكيد والدفع',
      'order_on_hold': 'طلب معلق',
      'no_onhold_orders': 'لا توجد طلبات معلقة',
      'select_order_to_confirm': 'اختر طلبًا لتأكيده',
      'search_by_code': 'البحث بالرمز...',
      'items': 'العناصر',
      'type': 'النوع',
      'dine_in': 'تناول الطعام في المكان',
      'take_away': 'وجبات جاهزة',
      'no_orders_found': 'لم يتم العثور على طلبات',

      // Customers
      'customer': 'عميل',
      'customers': 'العملاء',
      'select_customer': 'اختر عميل',
      'customer_name': 'اسم العميل',
      'customer_phone': 'هاتف العميل',

      // Commercial
      'commercial': 'تجاري',
      'select_commercial': 'اختر تجاري',

      // Products
      'product_name': 'اسم المنتج',
      'product_price': 'سعر المنتج',
      'quantity': 'الكمية',
      'price': 'السعر',
      'category': 'الفئة',
      'all_categories': 'جميع الفئات',

      // Discount
      'manual_discount': 'خصم يدوي',
      'discount_percentage': 'نسبة الخصم',
      'apply_discount': 'تطبيق الخصم',
      'remove_discount': 'إزالة الخصم',
      'discount_applied': 'تم تطبيق الخصم',

      // Payment
      'payment': 'الدفع',
      'pay': 'دفع',
      'cash': 'نقداً',
      'card': 'بطاقة',
      'amount_paid': 'المبلغ المدفوع',
      'change': 'الباقي',
      'payment_successful': 'تم الدفع بنجاح',

      // Session
      'session': 'جلسة',
      'sessions': 'الجلسات',
      'session_management': 'إدارة الجلسات',
      'start_session': 'بدء جلسة',
      'end_session': 'إنهاء الجلسة',
      'pause_session': 'إيقاف الجلسة مؤقتاً',
      'resume_session': 'استئناف الجلسة',
      'active': 'نشط',
      'paused': 'متوقف مؤقتاً',
      'ended': 'منتهي',
      'session_details': 'تفاصيل الجلسة',
      'cash_at_start': 'النقد في البداية',
      'cash_at_end': 'النقد في النهاية',
      'expected_cash': 'النقد المتوقع',

      // Settings
      'settings': 'الإعدادات',
      'general_settings': 'الإعدادات العامة',
      'appearance': 'المظهر',
      'dark_mode': 'الوضع الليلي',
      'language': 'اللغة',
      'currency': 'العملة',
      'tax_rate': 'معدل الضريبة',
      'default_order_type': 'نوع الطلب الافتراضي',
      'show_product_images': 'عرض صور المنتجات',
      'printing': 'الطباعة',
      'enable_auto_print': 'تفعيل الطباعة التلقائية',
      'printer_settings': 'إعدادات الطابعة',

      // Devices
      'devices': 'الأجهزة',
      'devices_management': 'إدارة الأجهزة',
      'device_name': 'اسم الجهاز',
      'device_type': 'نوع الجهاز',
      'device_status': 'حالة الجهاز',

      // Tickets
      'tickets': 'التذاكر',
      'ticket': 'تذكرة',
      'ticket_id': 'رقم التذكرة',
      'ticket_status': 'حالة التذكرة',
      'paid': 'مدفوع',
      'unpaid': 'غير مدفوع',

      // Sync
      'sync': 'مزامنة',
      'syncing': 'جاري المزامنة...',
      'sync_successful': 'تمت المزامنة بنجاح',
      'sync_failed': 'فشلت المزامنة',
      'last_sync': 'آخر مزامنة',
      'auto_sync': 'مزامنة تلقائية',

      // Full Logout
      'full_logout': 'تسجيل خروج كامل',
      'full_logout_confirm': 'سيؤدي هذا إلى مسح جميع بيانات مصادقة الخادم وقاعدة البيانات المحلية.\n\nستحتاج إلى إعادة الاتصال بالخادم أو استخدام الوضع التجريبي مرة أخرى.\n\nهل أنت متأكد؟',
      'verify_tenant_password': 'تحقق من كلمة مرور المستأجر',
      'full_logout_warning': 'سيؤدي هذا إلى مسح جميع البيانات وقطع الاتصال بالخادم.',

      // Demo
      'demo_mode': 'الوضع التجريبي',
      'demo_login': 'تسجيل دخول تجريبي',
      'server_login': 'تسجيل دخول الخادم',

      // Errors
      'error_occurred': 'حدث خطأ',
      'try_again': 'حاول مرة أخرى',
      'no_internet': 'لا يوجد اتصال بالإنترنت',

      // Time
      'today': 'اليوم',
      'yesterday': 'أمس',
      'this_week': 'هذا الأسبوع',
      'this_month': 'هذا الشهر',

      // Status
      'online': 'متصل',
      'offline': 'غير متصل',
      'connected': 'متصل',
      'disconnected': 'غير متصل',

      // Numbers
      'number_of_persons': 'عدد الأشخاص',
      'person': 'شخص',
      'persons': 'أشخاص',

      // Additional Login & Tenant
      'enter_username': 'أدخل اسم المستخدم',
      'enter_tenant_password': 'أدخل كلمة مرور المستأجر للمتابعة',
      'are_you_sure': 'هل أنت متأكد؟',
      'database_error': 'خطأ في قاعدة البيانات',
      'database_empty': 'قاعدة البيانات فارغة. يرجى إعادة الاتصال بالخادم أو استخدام الوضع التجريبي.',
      'reconnect': 'إعادة الاتصال',
      'session_resumed': 'تم استئناف الجلسة بنجاح',
      'session_created': 'تم إنشاء جلسة جديدة',
      'welcome_back': 'مرحباً بعودتك',

      // Main Screen
      'new_order': 'طلب جديد',
      'held_orders': 'الطلبات المعلقة',
      'no_category_selected': 'لم يتم اختيار فئة',
      'select_category': 'اختر فئة لعرض المنتجات',
      'no_products_available': 'لا توجد منتجات متاحة',
      'no_products_in_category': 'لا توجد منتجات في هذه الفئة',
      'set': 'تعيين',
      'unset': 'إلغاء التعيين',
      'apply': 'تطبيق',
      'coupon': 'قسيمة',
      'coupons': 'القسائم',

      // Payment Screen
      'payment_methods': 'طرق الدفع',
      'split_payment': 'تقسيم الدفع',
      'amount_to_pay': 'المبلغ المطلوب دفعه',
      'amount_remaining': 'المتبقي',
      'enter_amount': 'أدخل المبلغ',
      'complete_payment': 'إتمام الدفع',
      'add_payment_method': 'إضافة طريقة دفع',
      'payment_method': 'طريقة الدفع',
      'remove': 'إزالة',
      'insufficient_amount': 'المبلغ المدفوع غير كافٍ',
      'please_pay_full_amount': 'يرجى دفع المبلغ الكامل',
      'overpaid': 'دفع زائد',
      'payment_complete': 'اكتمل الدفع',
      'change_to_return': 'الباقي للعودة',
      'receipt': 'إيصال',
      'print_receipt': 'طباعة الإيصال',
      'new_sale': 'بيع جديد',
      'return_to_order': 'العودة إلى الطلب',

      // Session Screen
      'current_session': 'الجلسة الحالية',
      'no_active_session': 'لا توجد جلسة نشطة',
      'start_new_session': 'بدء جلسة جديدة',
      'session_info': 'معلومات الجلسة',
      'session_started': 'بدأت الجلسة',
      'session_ended': 'انتهت الجلسة',
      'duration': 'المدة',
      'total_sales': 'إجمالي المبيعات',
      'total_transactions': 'إجمالي المعاملات',
      'end_session_confirm': 'هل أنت متأكد أنك تريد إنهاء هذه الجلسة؟',
      'end_session_warning': 'سيؤدي هذا إلى إغلاق الجلسة الحالية وتسجيل الخروج.',

      // Tenant Login Screen
      'server_url': 'عنوان الخادم',
      'pos_name': 'اسم نقطة البيع',
      'server_login': 'تسجيل دخول الخادم',
      'loading_data': 'جاري تحميل البيانات...',
      'authenticating': 'جاري المصادقة...',
      'syncing_data': 'جاري مزامنة البيانات...',
      'setup_complete': 'اكتمل الإعداد!',

      // Settings Page
      'reset_settings': 'إعادة تعيين الإعدادات',
      'reset_to_defaults': 'إعادة تعيين للافتراضيات',
      'reset_confirm': 'هل أنت متأكد أنك تريد إعادة تعيين جميع الإعدادات للافتراضيات؟',
      'settings_reset': 'تم إعادة تعيين الإعدادات بنجاح',
      'data_retention': 'الاحتفاظ بالبيانات',
      'days': 'أيام',
      'bulk_sync_size': 'حجم المزامنة الجماعية',
      'items': 'عناصر',
      'category_display': 'عرض الفئة',
      'top_bar': 'الشريط العلوي',
      'full_page': 'صفحة كاملة',

      // API Tester
      'api_tester': 'مختبر API',
      'endpoint': 'نقطة النهاية',
      'method': 'الطريقة',
      'request': 'الطلب',
      'response': 'الاستجابة',
      'send': 'إرسال',
      'clear_response': 'مسح الاستجابة',

      // Dialogs & Confirmations
      'select_option': 'اختر خياراً',
      'no_options_available': 'لا توجد خيارات متاحة',
      'clear_confirm': 'هل أنت متأكد أنك تريد مسح الطلب الحالي؟',
      'delete_confirm': 'هل أنت متأكد أنك تريد حذف هذا العنصر؟',
      'hold_order': 'تعليق الطلب',
      'resume_order': 'استئناف الطلب',
      'order_held': 'تم تعليق الطلب بنجاح',
      'order_resumed': 'تم استئناف الطلب بنجاح',

      // Product Modifications
      'product_details': 'تفاصيل المنتج',
      'components': 'المكونات',
      'special_instructions': 'تعليمات خاصة',
      'add_to_order': 'إضافة إلى الطلب',
      'update_item': 'تحديث العنصر',
      'required': 'مطلوب',
      'optional': 'اختياري',
      'select_components': 'اختر المكونات',

      // Tables
      'table_number': 'رقم الطاولة',
      'occupied': 'مشغولة',
      'available': 'متاحة',
      'clear_table_confirm': 'هل أنت متأكد أنك تريد مسح هذه الطاولة؟',
      'pay_first': 'ادفع أولاً',
      'just_clear': 'امسح فقط',
      'table_has_items': 'هذه الطاولة بها عناصر غير مدفوعة. ماذا تريد أن تفعل؟',

      // Calculator & Payment
      'loaded': 'تم التحميل',
      'to': 'إلى',
      'calculator': 'الحاسبة',
      'new_ticket': 'تذكرة جديدة',
      'item_discount': 'خصم العناصر',
      'reprint': 'إعادة الطباعة',
      'quick_amounts': 'مبالغ سريعة',

      // Issue Reporting
      'report_issue': 'الإبلاغ عن مشكلة',
      'issue_type': 'نوع المشكلة',
      'issue_title': 'عنوان المشكلة',
      'issue_description': 'وصف المشكلة',
      'submit_issue': 'إرسال المشكلة',
      'issue_submitted': 'تم إرسال المشكلة بنجاح',
      'issue_submit_failed': 'فشل إرسال المشكلة',
      'issue_type_general': 'عام',
      'issue_type_bug': 'خطأ برمجي',
      'issue_type_feature': 'طلب ميزة',
      'issue_type_hardware': 'عتاد',
      'issue_type_network': 'شبكة',
      'issue_type_printer': 'طابعة',
      'issue_type_other': 'أخرى',
      'enter_issue_title': 'أدخل عنوان المشكلة',
      'enter_issue_description': 'صف المشكلة (اختياري)',
      'title_required': 'العنوان مطلوب',
    },
    'fr': {
      // Common - French
      'app_title': 'Système de Point de Vente',
      'ok': 'OK',
      'cancel': 'Annuler',
      'close': 'Fermer',
      'save': 'Enregistrer',
      'delete': 'Supprimer',
      'edit': 'Modifier',
      'add': 'Ajouter',
      'search': 'Rechercher',
      'filter': 'Filtrer',
      'refresh': 'Actualiser',
      'loading': 'Chargement...',
      'error': 'Erreur',
      'success': 'Succès',
      'confirm': 'Confirmer',
      'yes': 'Oui',
      'no': 'Non',
      'back': 'Retour',
      'next': 'Suivant',
      'previous': 'Précédent',
      'first': 'Premier',
      'last': 'Dernier',
      'page': 'Page',
      'of': 'de',
      'for': 'pour',
      'showing': 'Affichage',

      // Login
      'login': 'Connexion',
      'logout': 'Déconnexion',
      'username': 'Nom d\'utilisateur',
      'password': 'Mot de passe',
      'sign_in': 'Se connecter',
      'starting_balance': 'Solde de départ',
      'invalid_credentials': 'Identifiants invalides',
      'login_failed': 'Échec de la connexion',
      'exit_to_tenant': 'Retour à la connexion locataire',

      // Tenant
      'tenant_id': 'ID Locataire',
      'tenant_password': 'Mot de passe locataire',
      'continue': 'Continuer',
      'enter_tenant_id': 'Entrez votre ID locataire',
      'enter_password': 'Entrez un mot de passe',
      'password_min_length': 'Le mot de passe doit contenir au moins 4 caractères',
      'verify': 'Vérifier',
      'verify_logout': 'Vérifier et déconnecter',
      'invalid_tenant_password': 'Mot de passe locataire invalide',

      // Users
      'users_management': 'Gestion des utilisateurs',
      'user_id': 'ID Utilisateur',
      'user_type': 'Type d\'utilisateur',
      'full_name': 'Nom complet',
      'first_name': 'Prénom',
      'last_name': 'Nom de famille',
      'created_at': 'Créé le',
      'updated_at': 'Mis à jour le',
      'last_login': 'Dernière connexion',
      'never': 'Jamais',
      'actions': 'Actions',
      'view_details': 'Voir les détails',
      'user_details': 'Détails de l\'utilisateur',
      'basic_information': 'Informations de base',
      'activity_information': 'Informations d\'activité',
      'permissions': 'Permissions',
      'no_permissions': 'Aucune permission définie',
      'invalid_permissions': 'Format de permissions invalide',
      'all_types': 'Tous les types',
      'admin': 'Administrateur',
      'cashier': 'Caissier',
      'waiter': 'Serveur',
      'no_users_found': 'Aucun utilisateur trouvé',
      'try_adjusting_filters': 'Essayez d\'ajuster vos filtres',
      'error_loading_users': 'Erreur de chargement des utilisateurs',
      'search_by_name': 'Rechercher par nom, nom d\'utilisateur...',

      // Main Screen
      'categories': 'Catégories',
      'products': 'Produits',
      'current_order': 'Commande en cours',
      'no_items': 'Aucun article dans la commande',
      'add_items': 'Ajouter des articles pour commencer',
      'subtotal': 'Sous-total',
      'tax': 'Taxe',
      'discount': 'Réduction',
      'total': 'Total',
      'hold': 'Mettre en attente',
      'clear': 'Effacer',
      'proceed': 'Continuer',
      'print': 'Imprimer',

      // Tables
      'table': 'Table',
      'tables': 'Tables',
      'select_table': 'Sélectionner une table',
      'clear_table': 'Vider la table',
      'table_cleared': 'Table vidée',

      // Orders
      'orders': 'Commandes',
      'order': 'Commande',
      'orders_management': 'Gestion des commandes',
      'order_id': 'Numéro de commande',
      'order_status': 'Statut de la commande',
      'order_type': 'Type de commande',
      'order_date': 'Date de la commande',
      'order_total': 'Total de la commande',
      'pending': 'En attente',
      'completed': 'Terminé',
      'cancelled': 'Annulé',
      'dine_in': 'Sur place',
      'take_away': 'À emporter',
      'no_orders_found': 'Aucune commande trouvée',

      // Order Confirmation
      'confirm_order': 'Confirmer la commande',
      'confirm_and_pay': 'Confirmer et payer',
      'order_on_hold': 'Commande en attente',
      'no_onhold_orders': 'Aucune commande en attente',
      'select_order_to_confirm': 'Sélectionner une commande à confirmer',
      'search_by_code': 'Rechercher par code...',
      'items': 'Articles',
      'type': 'Type',

      // Customers
      'customer': 'Client',
      'customers': 'Clients',
      'select_customer': 'Sélectionner un client',
      'customer_name': 'Nom du client',
      'customer_phone': 'Téléphone du client',

      // Commercial
      'commercial': 'Commercial',
      'select_commercial': 'Sélectionner un commercial',

      // Products
      'product_name': 'Nom du produit',
      'product_price': 'Prix du produit',
      'quantity': 'Quantité',
      'price': 'Prix',
      'category': 'Catégorie',
      'all_categories': 'Toutes les catégories',

      // Discount
      'manual_discount': 'Réduction manuelle',
      'discount_percentage': 'Pourcentage de réduction',
      'apply_discount': 'Appliquer la réduction',
      'remove_discount': 'Retirer la réduction',
      'discount_applied': 'Réduction appliquée',

      // Payment
      'payment': 'Paiement',
      'pay': 'Payer',
      'cash': 'Espèces',
      'card': 'Carte',
      'amount_paid': 'Montant payé',
      'change': 'Monnaie',
      'payment_successful': 'Paiement réussi',

      // Session
      'session': 'Session',
      'sessions': 'Sessions',
      'session_management': 'Gestion des sessions',
      'start_session': 'Démarrer une session',
      'end_session': 'Terminer la session',
      'pause_session': 'Mettre la session en pause',
      'resume_session': 'Reprendre la session',
      'active': 'Actif',
      'paused': 'En pause',
      'ended': 'Terminé',
      'session_details': 'Détails de la session',
      'cash_at_start': 'Espèces au début',
      'cash_at_end': 'Espèces à la fin',
      'expected_cash': 'Espèces attendues',

      // Settings
      'settings': 'Paramètres',
      'general_settings': 'Paramètres généraux',
      'appearance': 'Apparence',
      'dark_mode': 'Mode sombre',
      'language': 'Langue',
      'currency': 'Devise',
      'tax_rate': 'Taux de taxe',
      'default_order_type': 'Type de commande par défaut',
      'show_product_images': 'Afficher les images des produits',
      'printing': 'Impression',
      'enable_auto_print': 'Activer l\'impression automatique',
      'printer_settings': 'Paramètres d\'impression',

      // Devices
      'devices': 'Appareils',
      'devices_management': 'Gestion des appareils',
      'device_name': 'Nom de l\'appareil',
      'device_type': 'Type d\'appareil',
      'device_status': 'Statut de l\'appareil',

      // Tickets
      'tickets': 'Tickets',
      'ticket': 'Ticket',
      'ticket_id': 'Numéro de ticket',
      'ticket_status': 'Statut du ticket',
      'paid': 'Payé',
      'unpaid': 'Non payé',

      // Sync
      'sync': 'Synchroniser',
      'syncing': 'Synchronisation...',
      'sync_successful': 'Synchronisation réussie',
      'sync_failed': 'Échec de la synchronisation',
      'last_sync': 'Dernière synchronisation',
      'auto_sync': 'Synchronisation automatique',

      // Full Logout
      'full_logout': 'Déconnexion complète',
      'full_logout_confirm': 'Cela effacera toutes les données d\'authentification du serveur et la base de données locale.\n\nVous devrez vous reconnecter au serveur ou utiliser à nouveau le mode démo.\n\nÊtes-vous sûr?',
      'verify_tenant_password': 'Vérifier le mot de passe locataire',
      'full_logout_warning': 'Cela effacera TOUTES les données et déconnectera du serveur.',

      // Demo
      'demo_mode': 'Mode démo',
      'demo_login': 'Connexion démo',
      'server_login': 'Connexion au serveur',

      // Errors
      'error_occurred': 'Une erreur s\'est produite',
      'try_again': 'Réessayer',
      'no_internet': 'Pas de connexion Internet',

      // Time
      'today': 'Aujourd\'hui',
      'yesterday': 'Hier',
      'this_week': 'Cette semaine',
      'this_month': 'Ce mois-ci',

      // Status
      'online': 'En ligne',
      'offline': 'Hors ligne',
      'connected': 'Connecté',
      'disconnected': 'Déconnecté',

      // Numbers
      'number_of_persons': 'Nombre de personnes',
      'person': 'Personne',
      'persons': 'Personnes',

      // Additional Login & Tenant
      'enter_username': 'Entrez votre nom d\'utilisateur',
      'enter_tenant_password': 'Entrez le mot de passe locataire pour continuer',
      'are_you_sure': 'Êtes-vous sûr?',
      'database_error': 'Erreur de base de données',
      'database_empty': 'La base de données est vide. Veuillez vous reconnecter au serveur ou utiliser le mode démo.',
      'reconnect': 'Reconnecter',
      'session_resumed': 'Session reprise avec succès',
      'session_created': 'Nouvelle session créée',
      'welcome_back': 'Bon retour',

      // Main Screen
      'new_order': 'Nouvelle commande',
      'held_orders': 'Commandes en attente',
      'no_category_selected': 'Aucune catégorie sélectionnée',
      'select_category': 'Sélectionnez une catégorie pour voir les produits',
      'no_products_available': 'Aucun produit disponible',
      'no_products_in_category': 'Aucun produit dans cette catégorie',
      'set': 'Définir',
      'unset': 'Annuler',
      'apply': 'Appliquer',
      'coupon': 'Coupon',
      'coupons': 'Coupons',

      // Payment Screen
      'payment_methods': 'Méthodes de paiement',
      'split_payment': 'Paiement fractionné',
      'amount_to_pay': 'Montant à payer',
      'amount_remaining': 'Restant',
      'enter_amount': 'Entrez le montant',
      'complete_payment': 'Terminer le paiement',
      'add_payment_method': 'Ajouter une méthode de paiement',
      'payment_method': 'Méthode de paiement',
      'remove': 'Retirer',
      'insufficient_amount': 'Montant insuffisant',
      'please_pay_full_amount': 'Veuillez payer le montant total',
      'overpaid': 'Trop payé',
      'payment_complete': 'Paiement terminé',
      'change_to_return': 'Monnaie à rendre',
      'receipt': 'Reçu',
      'print_receipt': 'Imprimer le reçu',
      'new_sale': 'Nouvelle vente',
      'return_to_order': 'Retour à la commande',

      // Session Screen
      'current_session': 'Session actuelle',
      'no_active_session': 'Aucune session active',
      'start_new_session': 'Démarrer une nouvelle session',
      'session_info': 'Informations de session',
      'session_started': 'Session démarrée',
      'session_ended': 'Session terminée',
      'duration': 'Durée',
      'total_sales': 'Ventes totales',
      'total_transactions': 'Transactions totales',
      'end_session_confirm': 'Êtes-vous sûr de vouloir terminer cette session?',
      'end_session_warning': 'Cela fermera la session actuelle et vous déconnectera.',

      // Tenant Login Screen
      'server_url': 'URL du serveur',
      'pos_name': 'Nom du PDV',
      'server_login': 'Connexion au serveur',
      'loading_data': 'Chargement des données...',
      'authenticating': 'Authentification...',
      'syncing_data': 'Synchronisation des données...',
      'setup_complete': 'Configuration terminée!',

      // Settings Page
      'reset_settings': 'Réinitialiser les paramètres',
      'reset_to_defaults': 'Réinitialiser aux valeurs par défaut',
      'reset_confirm': 'Êtes-vous sûr de vouloir réinitialiser tous les paramètres aux valeurs par défaut?',
      'settings_reset': 'Paramètres réinitialisés avec succès',
      'data_retention': 'Rétention des données',
      'days': 'Jours',
      'bulk_sync_size': 'Taille de synchronisation groupée',
      'items': 'Éléments',
      'category_display': 'Affichage des catégories',
      'top_bar': 'Barre supérieure',
      'full_page': 'Page complète',

      // API Tester
      'api_tester': 'Testeur API',
      'endpoint': 'Point de terminaison',
      'method': 'Méthode',
      'request': 'Demande',
      'response': 'Réponse',
      'send': 'Envoyer',
      'clear_response': 'Effacer la réponse',

      // Dialogs & Confirmations
      'select_option': 'Sélectionner une option',
      'no_options_available': 'Aucune option disponible',
      'clear_confirm': 'Êtes-vous sûr de vouloir effacer la commande actuelle?',
      'delete_confirm': 'Êtes-vous sûr de vouloir supprimer cet élément?',
      'hold_order': 'Mettre en attente',
      'resume_order': 'Reprendre la commande',
      'order_held': 'Commande mise en attente avec succès',
      'order_resumed': 'Commande reprise avec succès',

      // Product Modifications
      'product_details': 'Détails du produit',
      'components': 'Composants',
      'special_instructions': 'Instructions spéciales',
      'add_to_order': 'Ajouter à la commande',
      'update_item': 'Mettre à jour l\'élément',
      'required': 'Requis',
      'optional': 'Optionnel',
      'select_components': 'Sélectionner les composants',

      // Tables
      'table_number': 'Numéro de table',
      'occupied': 'Occupée',
      'available': 'Disponible',
      'clear_table_confirm': 'Êtes-vous sûr de vouloir vider cette table?',
      'pay_first': 'Payer d\'abord',
      'just_clear': 'Juste vider',
      'table_has_items': 'Cette table a des éléments non payés. Que voulez-vous faire?',

      // Calculator & Payment
      'loaded': 'Chargé',
      'to': 'à',
      'calculator': 'Calculatrice',
      'new_ticket': 'Nouveau Ticket',
      'item_discount': 'Remise sur articles',
      'reprint': 'Réimprimer',
      'quick_amounts': 'Montants rapides',

      // Issue Reporting
      'report_issue': 'Signaler un problème',
      'issue_type': 'Type de problème',
      'issue_title': 'Titre du problème',
      'issue_description': 'Description du problème',
      'submit_issue': 'Soumettre le problème',
      'issue_submitted': 'Problème soumis avec succès',
      'issue_submit_failed': 'Échec de la soumission du problème',
      'issue_type_general': 'Général',
      'issue_type_bug': 'Bug',
      'issue_type_feature': 'Demande de fonctionnalité',
      'issue_type_hardware': 'Matériel',
      'issue_type_network': 'Réseau',
      'issue_type_printer': 'Imprimante',
      'issue_type_other': 'Autre',
      'enter_issue_title': 'Entrez le titre du problème',
      'enter_issue_description': 'Décrivez le problème (optionnel)',
      'title_required': 'Le titre est requis',
    },
  };

  String translate(String key) {
    return _localizedValues[locale.languageCode]?[key] ?? key;
  }

  // Convenience getters
  String get appTitle => translate('app_title');
  String get ok => translate('ok');
  String get cancel => translate('cancel');
  String get close => translate('close');
  String get save => translate('save');
  String get delete => translate('delete');
  String get edit => translate('edit');
  String get add => translate('add');
  String get search => translate('search');
  String get refresh => translate('refresh');
  String get loading => translate('loading');
  String get error => translate('error');
  String get success => translate('success');
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'ar', 'fr'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

