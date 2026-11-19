import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../config/session_manager.dart';
import '../utils/error_handler.dart';
import 'admin/admin_settlements_screen.dart';
import 'supplier/supplier_bank_settings_screen.dart';
import 'welcome_screen.dart';



class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _businessNameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  final TextEditingController _websiteCtrl = TextEditingController();
  final TextEditingController _legalNameCtrl = TextEditingController();
  final TextEditingController _nrcCtrl = TextEditingController();
  final TextEditingController _nitCtrl = TextEditingController();
  final TextEditingController _economicActivityCtrl = TextEditingController();
  final TextEditingController _hoursCtrl = TextEditingController();

  String? _avatarUrl;
  String _role = 'restaurant';
  String _userEmail = '';
  double _rating = 5.0;
  int _reviewsCount = 0;
  String _referralCode = '';
  int _freeCommissionOrders = 0;
  List<Map<String, dynamic>> _myReviews = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;
  int _monthlyReferralsUsed = 0;

  String get _currentUserId =>
      supabase.auth.currentUser?.id ?? SessionManager.currentUserId;

  bool get _isAdmin =>
      _role.toLowerCase() == 'admin' ||
      _userEmail.toLowerCase().trim() == 'esmejia.ramos@gmail.com'; // O el rol configurado en tu perfil

  @override
  void initState() {
    super.initState();
    _loadProfileAndReviews();
  }

  @override
  void dispose() {
    _businessNameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _websiteCtrl.dispose();
    _legalNameCtrl.dispose(); 
    _nrcCtrl.dispose(); 
    _nitCtrl.dispose(); 
    _economicActivityCtrl.dispose();
    _hoursCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfileAndReviews() async {
    try {
      final user = supabase.auth.currentUser;
      _userEmail = user?.email ?? '';

      final res = await supabase
          .from('profiles')
          .select('*')
          .eq('id', _currentUserId)
          .maybeSingle();

      if (res != null && mounted) {
        setState(() {
          _businessNameCtrl.text = res['business_name'] ?? '';
          _phoneCtrl.text = res['phone'] ?? '';
          _addressCtrl.text = res['address'] ?? '';
          _websiteCtrl.text = res['website'] ?? '';
          _legalNameCtrl.text = res['legal_name'] ?? '';
          _nrcCtrl.text = res['nrc'] ?? res['nrc_nit'] ?? '';
          _nitCtrl.text = res['nit'] ?? '';
          _economicActivityCtrl.text = res['economic_activity'] ?? '';
          _hoursCtrl.text =
              res['business_hours'] ?? 'Lunes a Sábado: 7:00 AM - 5:00 PM';
          _avatarUrl = res['avatar_url'];
          _role = res['role'] ?? 'restaurant';
          _rating = (res['rating'] as num?)?.toDouble() ?? 5.0;
          _reviewsCount = (res['reviews_count'] as num?)?.toInt() ?? 0;
          _referralCode = res['referral_code']?.toString() ?? '';
          _freeCommissionOrders =
              (res['free_commission_orders'] as num?)?.toInt() ?? 0;
        });
        final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1).toUtc().toIso8601String();
      final refsThisMonth = await supabase
          .from('profiles')
          .select('id')
          .eq('referred_by', _currentUserId)
          .eq('referral_reward_claimed', true)
          .gte('referral_reward_claimed_at', monthStart);

      if (mounted) {
        setState(() {
          _monthlyReferralsUsed = (refsThisMonth as List).length;
        });
      }
      }

      // Cargar reseñas recibidas
      final reviewsRes = await supabase
          .from('reviews')
          .select('*')
          .eq('target_id', _currentUserId)
          .neq('author_id', _currentUserId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _myReviews = List<Map<String, dynamic>>.from(reviewsRes);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 600,
    );

    if (picked == null) return;

    setState(() => _isUploadingPhoto = true);

    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
      final fileName =
          'avatar_${_currentUserId}_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await supabase.storage.from('product-images').uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: true),
          );

      final url =
          supabase.storage.from('product-images').getPublicUrl(fileName);

      await supabase
          .from('profiles')
          .update({'avatar_url': url}).eq('id', _currentUserId);

      if (mounted) {
        setState(() {
          _avatarUrl = url;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto de perfil actualizada correctamente'),
            backgroundColor: AppColors.tealMint,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = ErrorHandler.parse(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $msg'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final nrcVal = _nrcCtrl.text.trim();
      final nitVal = _nitCtrl.text.trim();
      final combinedLegacy = [
        if (nrcVal.isNotEmpty) 'NRC: $nrcVal',
        if (nitVal.isNotEmpty) 'NIT: $nitVal',
      ].join(' | ');

      await supabase.from('profiles').update({
        'business_name': _businessNameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'website': _websiteCtrl.text.trim(),
        'legal_name': _legalNameCtrl.text.trim(),
        'nrc': nrcVal,
        'nit': nitVal,
        'economic_activity': _economicActivityCtrl.text.trim(),
        'nrc_nit': combinedLegacy,
        'business_hours': _hoursCtrl.text.trim(),
        'is_verified': true,
      }).eq('id', _currentUserId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Datos del negocio guardados correctamente'),
            backgroundColor: AppColors.tealMint,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = ErrorHandler.parse(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al guardar: $msg'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar Sesión'),
        content: const Text('¿Estás seguro de que deseas salir de tu cuenta?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar Sesión',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await supabase.auth.signOut();
    } catch (_) {}

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const WelcomeScreen(),
        ),
        (route) => false,
      );
    }
  }

  Widget _buildReferralCard() {
    if (_referralCode.isEmpty) return const SizedBox.shrink();

    final targetRoleText = _role == 'supplier'
        ? 'un Restaurante'
        : 'un Distribuidor';

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.tealMint.withOpacity(0.55)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navyDark.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.tealMint.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.card_giftcard_rounded,
                    color: Color(0xFF0F766E), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Invita y Gana 1 Pedido Sin Comisión',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                        color: AppColors.navyDark,
                      ),
                    ),
                    Text(
                      'Invita a $targetRoleText nuevo (primera vez en Abasto) y ambos ganan 0% tarifa en 1 pedido. Máximo 3 referidos por mes ($_monthlyReferralsUsed/3 usados este mes).',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.subtitleGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TU CÓDIGO DE INVITACIÓN',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.subtitleGrey,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _referralCode,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: AppColors.navyDark,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Copiar código',
                      icon: const Icon(Icons.copy_rounded,
                          size: 19, color: AppColors.navyDark),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _referralCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Código copiado al portapapeles'),
                            backgroundColor: AppColors.tealMint,
                          ),
                        );
                      },
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.navyDark,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.share_outlined, size: 16),
                      label: const Text('Invitar',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.bold)),
                      onPressed: () {
                        final msg = Uri.encodeComponent(
                          '¡Hola! Te invito a unirte a Abasto B2B usando mi código $_referralCode. Cuando completes tu primer pedido, ¡ambos tendremos 1 pedido sin comisión! Regístrate aquí: https://abasto-flame.vercel.app/',
                        );
                        html.window
                            .open('https://wa.me/?text=$msg', '_blank');
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_freeCommissionOrders > 0) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.tealMint.withOpacity(0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      size: 16, color: Color(0xFF0F766E)),
                  const SizedBox(width: 6),
                  Text(
                    'Tienes $_freeCommissionOrders pedido(s) sin comisión disponible(s)',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001A2C),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.tealMint.withOpacity(0.16),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.storefront_rounded,
                  color: AppColors.tealMint, size: 19),
            ),
            const SizedBox(width: 10),
            const Text(
              'Mi Perfil y Negocio',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Cerrar Sesión',
            icon: const Icon(Icons.logout_rounded, color: Color(0xFFFCA5A5)),
            onPressed: _logout,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar con botón de cámara y margen superior
              const SizedBox(height: 8),
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: AppColors.primaryBlue.withOpacity(0.12),
                    backgroundImage:
                        (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                            ? NetworkImage(_avatarUrl!)
                            : null,
                    child: (_avatarUrl == null || _avatarUrl!.isEmpty)
                        ? (_isUploadingPhoto
                            ? const CircularProgressIndicator()
                            : Text(
                                _businessNameCtrl.text.isNotEmpty
                                    ? _businessNameCtrl.text[0].toUpperCase()
                                    : 'A',
                                style: const TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryBlue,
                                ),
                              ))
                        : (_isUploadingPhoto
                            ? const CircularProgressIndicator()
                            : null),
                  ),
                  InkWell(
                    onTap: _isUploadingPhoto ? null : _pickAndUploadAvatar,
                    child: const CircleAvatar(
                      radius: 17,
                      backgroundColor: AppColors.primaryBlue,
                      child: Icon(Icons.camera_alt,
                          color: Colors.white, size: 17),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    '$_rating ($_reviewsCount reseñas)',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.verified,
                      color: AppColors.tealMint, size: 18),
                  const SizedBox(width: 4),
                  const Text(
                    'Verificado',
                    style: TextStyle(
                      color: AppColors.tealMint,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _isAdmin
                    ? 'Administrador Abasto'
                    : (_role == 'supplier'
                        ? 'Distribuidor Mayorista'
                        : 'Restaurante / Cafetería'),
                style: const TextStyle(
                    color: AppColors.subtitleGrey, fontSize: 13),
              ),

              const SizedBox(height: 20),

              _buildReferralCard(),

              // ACCESO A CUENTA BANCARIA PARA DISTRIBUIDOR
              if (_role == 'supplier') ...[
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.account_balance,
                        color: AppColors.primaryBlue),
                    title: const Text(
                      'Configurar Cuenta Bancaria',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Datos para recibir tus pagos los viernes',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.subtitleGrey),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const SupplierBankSettingsScreen(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],

              TextFormField(
                controller: _businessNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre Comercial / Marca',
                  prefixIcon: Icon(Icons.storefront_outlined),
                ),
                validator: (val) =>
                    val == null || val.trim().isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono / WhatsApp',
                  prefixIcon: Icon(Icons.phone_outlined),
                  hintText: '+503 7000-0000',
                ),
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Dirección Comercial y Municipio',
                  prefixIcon: Icon(Icons.location_on_outlined),
                  hintText: 'Ej. Santa Tecla, La Libertad',
                ),
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _websiteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Página Web o Red Social',
                  prefixIcon: Icon(Icons.language_outlined),
                  hintText: 'ej. https://abasto.sv o @mi_negocio',
                ),
              ),
              const SizedBox(height: 14),

              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Datos Fiscales (Ministerio de Hacienda - DTE)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navyDark,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: _legalNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Razón Social / Denominación Legal',
                  prefixIcon: Icon(Icons.account_balance_outlined),
                  hintText: 'Ej. Inversiones Gastronómicas S.A.S. de C.V.',
                ),
              ),
              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _nrcCtrl,
                      decoration: const InputDecoration(
                        labelText: 'NRC (Contribuyente IVA)',
                        prefixIcon: Icon(Icons.receipt_long_outlined),
                        hintText: 'Ej. 123456-7',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _nitCtrl,
                      decoration: const InputDecoration(
                        labelText: 'NIT / DUI Homologado',
                        prefixIcon: Icon(Icons.badge_outlined),
                        hintText: 'Ej. 0614-120595-102-3',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _economicActivityCtrl,
                decoration: const InputDecoration(
                  labelText: 'Giro / Actividad Económica',
                  prefixIcon: Icon(Icons.work_outline),
                  hintText: 'Ej. Restaurantes y servicio móvil de comidas',
                ),
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _hoursCtrl,
                decoration: const InputDecoration(
                  labelText: 'Horario de Atención',
                  prefixIcon: Icon(Icons.access_time_outlined),
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _isSaving ? null : _saveProfile,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined, color: Colors.white),
                  label: Text(
                    _isSaving ? 'Guardando...' : 'Guardar Información',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 10),

              // Reseñas recibidas
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Reseñas Recibidas ($_reviewsCount)',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navyDark,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              if (_myReviews.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: const Center(
                    child: Text(
                      'Aún no tienes reseñas registradas.',
                      style: TextStyle(
                          color: AppColors.subtitleGrey, fontSize: 13),
                    ),
                  ),
                )
              else
                ..._myReviews.map((rev) {
                  final rating = (rev['rating'] as num?)?.toDouble() ?? 5.0;
                  final author = rev['author_name'] ?? 'Cliente';
                  final comment = rev['comment'] ?? '';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(author,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Row(
                              children: List.generate(5, (starIdx) {
                                return Icon(
                                  starIdx < rating
                                      ? Icons.star
                                      : Icons.star_border,
                                  color: Colors.amber,
                                  size: 16,
                                );
                              }),
                            ),
                          ],
                        ),
                        if (comment.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(comment,
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.black87)),
                        ],
                      ],
                    ),
                  );
                }),

              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),

              // Botón de Cerrar Sesión inferior
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 20),
                  label: const Text(
                    'Cerrar Sesión',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _logout,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}