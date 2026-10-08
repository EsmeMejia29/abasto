import 'package:flutter/material.dart';
import '../main.dart';
import '../config/session_manager.dart';
import '../theme/app_theme.dart';
import 'welcome_screen.dart';
import '../utils/error_handler.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  bool _isSaving = false;

  final _businessNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _decisionMakerCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();

  final _categoryCtrl = TextEditingController();
  final _coverageCtrl = TextEditingController();
  final _deliveryDaysCtrl = TextEditingController();

  final bool _isRestaurant = SessionManager.currentRole.value == UserRole.restaurant;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    setState(() => _isLoading = true);
    final userId = supabase.auth.currentUser?.id ?? SessionManager.currentUserId;

    try {
      final profile = await supabase
          .from('profiles')
          .select('*')
          .eq('id', userId)
          .maybeSingle();

      if (profile != null) {
        _businessNameCtrl.text = profile['business_name'] ?? '';
        _phoneCtrl.text = profile['phone'] ?? '';
        _addressCtrl.text = profile['address'] ?? '';
      }

      if (_isRestaurant) {
        final restData = await supabase
            .from('restaurant_details')
            .select('*')
            .eq('profile_id', userId)
            .maybeSingle();
        if (restData != null) {
          _decisionMakerCtrl.text = restData['contact_decision_maker'] ?? '';
          _budgetCtrl.text = (restData['monthly_budget'] as num?)?.toString() ?? '0.00';
        }
      } else {
        final suppData = await supabase
            .from('supplier_details')
            .select('*')
            .eq('profile_id', userId)
            .maybeSingle();
        if (suppData != null) {
          _categoryCtrl.text = suppData['category'] ?? '';
          _coverageCtrl.text = suppData['delivery_coverage'] ?? '';
          _deliveryDaysCtrl.text = suppData['delivery_days'] ?? '';
        }
      }
    } catch (_) {}

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    final userId = supabase.auth.currentUser?.id ?? SessionManager.currentUserId;

    try {
      // 1. Guardar en profiles
      await supabase.from('profiles').upsert({
        'id': userId,
        'email': supabase.auth.currentUser?.email ?? 'correo@demo.sv',
        'business_name': _businessNameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'role': _isRestaurant ? 'restaurant' : 'supplier',
        'updated_at': DateTime.now().toIso8601String(),
      });

      // 2. Guardar en detalles
      if (_isRestaurant) {
        await supabase.from('restaurant_details').upsert({
          'profile_id': userId,
          'contact_decision_maker': _decisionMakerCtrl.text.trim(),
          'monthly_budget': double.tryParse(_budgetCtrl.text) ?? 0.00,
        });
      } else {
        await supabase.from('supplier_details').upsert({
          'profile_id': userId,
          'category': _categoryCtrl.text.trim(),
          'delivery_coverage': _coverageCtrl.text.trim(),
          'delivery_days': _deliveryDaysCtrl.text.trim(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Cambios guardados con éxito!'),
            backgroundColor: AppColors.tealMint,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final friendlyMessage = ErrorHandler.parse(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyMessage),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmLogout() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar Sesión'),
        content: const Text('¿Estás seguro de que deseas salir de tu cuenta?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar Sesión', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (leave == true) {
      await supabase.auth.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const WelcomeScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isRestaurant ? 'Perfil del Restaurante' : 'Perfil del Distribuidor'),
        actions: [
          IconButton(
            tooltip: 'Cerrar Sesión',
            icon: const Icon(Icons.exit_to_app, color: Colors.redAccent),
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cabecera de Identidad
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: AppColors.logoGradient,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.white,
                          child: Icon(
                            _isRestaurant ? Icons.restaurant : Icons.local_shipping,
                            size: 32,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _businessNameCtrl.text.isEmpty ? 'Mi Negocio' : _businessNameCtrl.text,
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isRestaurant ? 'Cuenta Restaurante / Comprador' : 'Cuenta Distribuidor / Mayorista',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Text('Información General', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.navyDark)),
                  const SizedBox(height: 12),

                  TextField(
                    controller: _businessNameCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre Comercial', prefixIcon: Icon(Icons.store), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 14),

                  TextField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(labelText: 'Teléfono de Contacto (WhatsApp)', prefixIcon: Icon(Icons.phone), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 14),

                  TextField(
                    controller: _addressCtrl,
                    decoration: InputDecoration(
                      labelText: _isRestaurant ? 'Dirección del Local' : 'Base / Zona de Salida',
                      prefixIcon: const Icon(Icons.location_on),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (_isRestaurant) ...[
                    const Text('Operación de Abastecimiento', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.navyDark)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _decisionMakerCtrl,
                      decoration: const InputDecoration(labelText: 'Encargado de Compras / Decisor', prefixIcon: Icon(Icons.person), border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _budgetCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Presupuesto Mensual Estimado (\$ USD)', prefixIcon: Icon(Icons.attach_money), border: OutlineInputBorder()),
                    ),
                  ] else ...[
                    const Text('Logística y Distribución', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.navyDark)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _categoryCtrl,
                      decoration: const InputDecoration(labelText: 'Rubro / Categoría Principal', prefixIcon: Icon(Icons.category), border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _coverageCtrl,
                      decoration: const InputDecoration(labelText: 'Zonas de Cobertura', prefixIcon: Icon(Icons.map), border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _deliveryDaysCtrl,
                      decoration: const InputDecoration(labelText: 'Días y Horarios de Entrega', prefixIcon: Icon(Icons.schedule), border: OutlineInputBorder()),
                    ),
                  ],

                  const SizedBox(height: 26),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
                      onPressed: _isSaving ? null : _saveProfile,
                      icon: const Icon(Icons.save, color: Colors.white),
                      label: Text(_isSaving ? 'Guardando...' : 'Guardar Cambios', style: const TextStyle(color: Colors.white)),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Botón explícito de Cerrar Sesión
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                      ),
                      onPressed: _confirmLogout,
                      icon: const Icon(Icons.logout),
                      label: const Text('Cerrar Sesión'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}