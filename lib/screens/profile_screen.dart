import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../config/session_manager.dart';
import '../utils/error_handler.dart';
import 'auth_screen.dart';
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
  final TextEditingController _nrcNitCtrl = TextEditingController();
  final TextEditingController _hoursCtrl = TextEditingController();

  String? _avatarUrl;
  String _role = 'restaurant';
  double _rating = 5.0;
  int _reviewsCount = 0;
  List<Map<String, dynamic>> _myReviews = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;

  String get _currentUserId =>
      supabase.auth.currentUser?.id ?? SessionManager.currentUserId;

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
    _nrcNitCtrl.dispose();
    _hoursCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfileAndReviews() async {
    try {
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
          _nrcNitCtrl.text = res['nrc_nit'] ?? '';
          _hoursCtrl.text = res['business_hours'] ?? 'Lunes a Sábado: 7:00 AM - 5:00 PM';
          _avatarUrl = res['avatar_url'];
          _role = res['role'] ?? 'restaurant';
          _rating = (res['rating'] as num?)?.toDouble() ?? 5.0;
          _reviewsCount = (res['reviews_count'] as num?)?.toInt() ?? 0;
        });
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
      final fileName = 'avatar_${_currentUserId}_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await supabase.storage.from('product-images').uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: true),
          );

      final url = supabase.storage.from('product-images').getPublicUrl(fileName);

      await supabase.from('profiles').update({'avatar_url': url}).eq('id', _currentUserId);

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
      await supabase.from('profiles').update({
        'business_name': _businessNameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'website': _websiteCtrl.text.trim(),
        'nrc_nit': _nrcNitCtrl.text.trim(),
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
          SnackBar(content: Text('Error al guardar: $msg'), backgroundColor: Colors.red),
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar Sesión', style: TextStyle(color: Colors.white)),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Perfil y Negocio'),
        actions: [
          IconButton(
            tooltip: 'Cerrar Sesión',
            icon: const Icon(Icons.logout_rounded, color: Colors.red),
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
                    backgroundImage: (_avatarUrl != null && _avatarUrl!.isNotEmpty)
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
                    child: CircleAvatar(
                      radius: 17,
                      backgroundColor: AppColors.primaryBlue,
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 17),
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
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.verified, color: AppColors.tealMint, size: 18),
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
                _role == 'supplier' ? 'Distribuidor Mayorista' : 'Restaurante / Cafetería',
                style: const TextStyle(color: AppColors.subtitleGrey, fontSize: 13),
              ),

              const SizedBox(height: 24),

              TextFormField(
                controller: _businessNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre Comercial / Marca',
                  prefixIcon: Icon(Icons.storefront_outlined),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Requerido' : null,
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

              TextFormField(
                controller: _nrcNitCtrl,
                decoration: const InputDecoration(
                  labelText: 'Número de Registro (NRC / NIT)',
                  prefixIcon: Icon(Icons.badge_outlined),
                  hintText: 'Ej. 123456-7',
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
                      style: TextStyle(color: AppColors.subtitleGrey, fontSize: 13),
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
                            Text(author, style: const TextStyle(fontWeight: FontWeight.bold)),
                            Row(
                              children: List.generate(5, (starIdx) {
                                return Icon(
                                  starIdx < rating ? Icons.star : Icons.star_border,
                                  color: Colors.amber,
                                  size: 16,
                                );
                              }),
                            ),
                          ],
                        ),
                        if (comment.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(comment, style: const TextStyle(fontSize: 13, color: Colors.black87)),
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
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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