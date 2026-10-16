import 'dart:ui_web' as ui_web;
import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../config/session_manager.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../utils/error_handler.dart';

class RestaurantOnboardingScreen extends StatefulWidget {
  final String restaurantId;

  const RestaurantOnboardingScreen({super.key, required this.restaurantId});

  @override
  State<RestaurantOnboardingScreen> createState() =>
      _RestaurantOnboardingScreenState();
}

class _RestaurantOnboardingScreenState
    extends State<RestaurantOnboardingScreen> {
  int _currentStep = 0;
  bool _isSaving = false;
  bool _isLoadingInitialData = true;

  // Paso 1: Perfil y Datos Comerciales (Campos solicitados)
  final _businessNameCtrl = TextEditingController(text: 'Mi Restaurante');
  final _phoneCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _nrcNitCtrl = TextEditingController();
  final _businessHoursCtrl =
      TextEditingController(text: 'Lunes a Sábado: 7:00 AM - 5:00 PM');

  // Especialidad / Giro
  final _restaurantTypeCtrl =
      TextEditingController(text: 'Pupusería / Típico');
  final List<String> _commonTypes = [
    'Pupusería / Típico',
    'Cafetería & Pastelería',
    'Pizzería & Pastas',
    'Restaurante de Carnes / Parrilla',
    'Taquería / Comida Mexicana',
    'Comida Rápida / Hamburguesas',
    'Mariscos',
    'Comedor / Almuerzos Ejecutivos',
  ];

  // Paso 2: Ubicación & Logística de Recepción
  String _selectedZone = 'Santa Tecla';
  final _customZoneCtrl = TextEditingController();
  final List<String> _zonesSV = [
    'Santa Tecla',
    'Antiguo Cuscatlán',
    'San Salvador (San Benito / Escalón)',
    'San Salvador Centro',
    'Soyapango / Ilopango',
    'Lourdes Colón',
    'Ciudad Delgado',
    'La Libertad (Costa / Surf City)',
    'Otro (especificar)',
  ];

  final _restaurantAddressCtrl =
      TextEditingController(text: 'Paseo el Carmen');
  bool _sameAddressForDelivery = true;
  final _deliveryAddressCtrl = TextEditingController();
  final _deliveryInstructionsCtrl = TextEditingController(
      text: 'Entrada de proveedores por portón lateral de servicio');

  // Buscador y Mapa de Google embebido
  final _searchLocationCtrl =
      TextEditingController(text: 'Mauritas, Paseo el Carmen, Santa Tecla');
  String _currentMapQuery = 'Mauritas, Paseo el Carmen, Santa Tecla, El Salvador';
  final String _viewId =
      'google-maps-onboarding-${DateTime.now().millisecondsSinceEpoch}';

  String _deliveryWindow = 'Mañanas (7:00 AM - 11:00 AM)';
  final List<String> _deliveryWindows = [
    'Temprano (6:00 AM - 9:00 AM)',
    'Mañanas (7:00 AM - 11:00 AM)',
    'Tardes (2:00 PM - 5:00 PM)',
    'Cualquier horario hábil',
  ];

  // Paso 3: Insumos Frecuentes
  final List<String> _availableSupplies = [
    'Verduras y Hortalizas',
    'Lácteos y Quesillo',
    'Carnes y Aves',
    'Mariscos frescos',
    'Harinas y Granos Básicos',
    'Abarrotes y Especias',
    'Desechables y Empaques',
  ];
  final Set<String> _selectedSupplies = {
    'Lácteos y Quesillo',
    'Harinas y Granos Básicos',
  };

  @override
  void initState() {
    super.initState();
    _registerMapElement();
    _loadExistingProfileData();
  }

  void _registerMapElement() {
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
      final iframe = html.IFrameElement()
        ..src =
            'https://maps.google.com/maps?q=${Uri.encodeComponent(_currentMapQuery)}&t=&z=15&ie=UTF8&iwloc=&output=embed'
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allowFullscreen = false;
      return iframe;
    });
  }

  Future<void> _loadExistingProfileData() async {
    final currentAuthId = supabase.auth.currentUser?.id;
    final userId = (widget.restaurantId.isNotEmpty)
        ? widget.restaurantId
        : (currentAuthId ?? SessionManager.currentUserId);

    if (userId.isNotEmpty) {
      try {
        final profile = await supabase
            .from('profiles')
            .select()
            .eq('id', userId)
            .maybeSingle();

        if (profile != null && mounted) {
          setState(() {
            if ((profile['business_name'] ?? '').toString().isNotEmpty) {
              _businessNameCtrl.text = profile['business_name'];
            }
            if ((profile['phone'] ?? '').toString().isNotEmpty) {
              _phoneCtrl.text = profile['phone'];
            }
            if ((profile['address'] ?? '').toString().isNotEmpty) {
              _restaurantAddressCtrl.text = profile['address'];
              _currentMapQuery = '${profile['address']}, El Salvador';
              _searchLocationCtrl.text = profile['address'];
            }
            if ((profile['website'] ?? '').toString().isNotEmpty) {
              _websiteCtrl.text = profile['website'];
            }
            if ((profile['nrc_nit'] ?? '').toString().isNotEmpty) {
              _nrcNitCtrl.text = profile['nrc_nit'];
            }
            if ((profile['business_hours'] ?? '').toString().isNotEmpty) {
              _businessHoursCtrl.text = profile['business_hours'];
            }
            if ((profile['location'] ?? '').toString().isNotEmpty) {
              final loc = profile['location'].toString();
              if (_zonesSV.contains(loc)) {
                _selectedZone = loc;
              } else {
                _selectedZone = 'Otro (especificar)';
                _customZoneCtrl.text = loc;
              }
            }
          });
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() => _isLoadingInitialData = false);
    }
  }

  void _updateMapSearch(String query) {
    final clean = query.trim();
    if (clean.isEmpty) return;

    setState(() {
      _currentMapQuery = '$clean, El Salvador';
      _restaurantAddressCtrl.text = clean;
    });

    final element = html.document.getElementById(_viewId) as html.IFrameElement?;
    if (element != null) {
      element.src =
          'https://maps.google.com/maps?q=${Uri.encodeComponent(_currentMapQuery)}&t=&z=15&ie=UTF8&iwloc=&output=embed';
    }
  }

  @override
  void dispose() {
    _businessNameCtrl.dispose();
    _phoneCtrl.dispose();
    _websiteCtrl.dispose();
    _nrcNitCtrl.dispose();
    _businessHoursCtrl.dispose();
    _restaurantTypeCtrl.dispose();
    _customZoneCtrl.dispose();
    _restaurantAddressCtrl.dispose();
    _deliveryAddressCtrl.dispose();
    _deliveryInstructionsCtrl.dispose();
    _searchLocationCtrl.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    setState(() => _isSaving = true);

    final currentAuthId = supabase.auth.currentUser?.id;
    final userId = (widget.restaurantId.isNotEmpty)
        ? widget.restaurantId
        : (currentAuthId ?? SessionManager.currentUserId);

    if (userId.isEmpty) {
      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const MainNavigationHolder()),
          (route) => false,
        );
      }
      return;
    }

    final effectiveZone = _selectedZone == 'Otro (especificar)'
        ? _customZoneCtrl.text.trim()
        : _selectedZone;

    final finalDeliveryAddress = _sameAddressForDelivery
        ? _restaurantAddressCtrl.text.trim()
        : _deliveryAddressCtrl.text.trim();

    try {
      // 1. Guardar todos los datos comerciales en la tabla profiles
      await supabase.from('profiles').upsert({
        'id': userId,
        'business_name': _businessNameCtrl.text.trim().isNotEmpty
            ? _businessNameCtrl.text.trim()
            : 'Mi Restaurante',
        'phone': _phoneCtrl.text.trim(),
        'address': _restaurantAddressCtrl.text.trim(),
        'website': _websiteCtrl.text.trim(),
        'nrc_nit': _nrcNitCtrl.text.trim(),
        'business_hours': _businessHoursCtrl.text.trim(),
        'location': effectiveZone.isNotEmpty ? effectiveZone : 'Santa Tecla',
        'role': 'restaurant',
      });

      // 2. Guardar detalles operativos en restaurant_details
      await supabase.from('restaurant_details').upsert({
        'profile_id': userId,
        'restaurant_type': _restaurantTypeCtrl.text.trim(),
        'needed_supplies': _selectedSupplies.toList(),
        'delivery_zone': effectiveZone,
        'delivery_window': _deliveryWindow,
        'restaurant_address': _restaurantAddressCtrl.text.trim(),
        'delivery_address': finalDeliveryAddress,
        'delivery_instructions': _deliveryInstructionsCtrl.text.trim(),
        'onboarding_completed': true,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Datos guardados con éxito! Bienvenido a Abasto.'),
            backgroundColor: AppColors.tealMint,
          ),
        );

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const MainNavigationHolder()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = ErrorHandler.parse(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildStepIndicator() {
    final steps = ['Perfil Comercial', 'Ubicación & Entrega', 'Insumos'];
    return Row(
      children: List.generate(steps.length, (index) {
        final isActive = _currentStep == index;
        final isDone = _currentStep > index;

        return Expanded(
          child: InkWell(
            onTap: isDone ? () => setState(() => _currentStep = index) : null,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: isDone
                      ? AppColors.tealMint
                      : (isActive ? AppColors.primaryBlue : Colors.grey.shade300),
                  child: isDone
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isActive ? Colors.white : Colors.grey.shade700,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    steps[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isActive || isDone
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isActive ? AppColors.navyDark : AppColors.subtitleGrey,
                    ),
                  ),
                ),
                if (index < steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      color: isDone ? AppColors.tealMint : Colors.grey.shade300,
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }

  // PASO 1: Perfil y Datos Comerciales
  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Información del Restaurante',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.navyDark),
        ),
        const SizedBox(height: 4),
        const Text(
          'Estos datos aparecerán en tu perfil y facilitarán el contacto con los distribuidores.',
          style: TextStyle(fontSize: 13, color: AppColors.subtitleGrey),
        ),
        const SizedBox(height: 18),

        // Nombre Comercial
        TextField(
          controller: _businessNameCtrl,
          decoration: const InputDecoration(
            labelText: 'Nombre Comercial / Marca',
            prefixIcon: Icon(Icons.storefront),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),

        // Teléfono / WhatsApp
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Teléfono / WhatsApp de Compras',
            hintText: 'Ej. 7000-0000',
            prefixIcon: Icon(Icons.phone),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),

        // Página Web o Red Social
        TextField(
          controller: _websiteCtrl,
          decoration: const InputDecoration(
            labelText: 'Página Web o Red Social (Instagram / Facebook)',
            hintText: 'Ej. @mirestaurante o https://...',
            prefixIcon: Icon(Icons.language),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),

        // Número de Registro (NRC / NIT)
        TextField(
          controller: _nrcNitCtrl,
          decoration: const InputDecoration(
            labelText: 'Número de Registro (NRC / NIT / DTE)',
            hintText: 'Opcional (para fines fiscales)',
            prefixIcon: Icon(Icons.badge_outlined),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),

        // Horario de Atención
        TextField(
          controller: _businessHoursCtrl,
          decoration: const InputDecoration(
            labelText: 'Horario de Atención',
            hintText: 'Ej. Lunes a Sábado: 7:00 AM - 5:00 PM',
            prefixIcon: Icon(Icons.access_time),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 20),

        const Text(
          'Especialidad o Giro Culinario:',
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.navyDark),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _commonTypes.map((type) {
            final isSelected = _restaurantTypeCtrl.text == type;
            return ChoiceChip(
              label: Text(type),
              selected: isSelected,
              selectedColor: AppColors.tealMint.withOpacity(0.2),
              labelStyle: TextStyle(
                color: isSelected ? AppColors.primaryBlue : AppColors.subtitleGrey,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
              onSelected: (selected) {
                if (selected) {
                  setState(() => _restaurantTypeCtrl.text = type);
                }
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _restaurantTypeCtrl,
          decoration: const InputDecoration(
            labelText: 'Otra especialidad personalizada',
            prefixIcon: Icon(Icons.restaurant_menu),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  // PASO 2: Ubicación & Logística de Recepción
  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '¿Dónde recibes tus pedidos?',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.navyDark),
        ),
        const SizedBox(height: 4),
        const Text(
          'Asegura que los camiones de reparto lleguen a la puerta correcta.',
          style: TextStyle(fontSize: 13, color: AppColors.subtitleGrey),
        ),
        const SizedBox(height: 18),

        // Zona o Municipio
        DropdownButtonFormField<String>(
          value: _selectedZone,
          decoration: const InputDecoration(
            labelText: 'Zona o Municipio',
            prefixIcon: Icon(Icons.location_city),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: _zonesSV
              .map((z) => DropdownMenuItem(value: z, child: Text(z)))
              .toList(),
          onChanged: (val) {
            setState(() {
              _selectedZone = val ?? _selectedZone;
              if (_selectedZone != 'Otro (especificar)') {
                _searchLocationCtrl.text = _selectedZone;
                _updateMapSearch(_selectedZone);
              }
            });
          },
        ),

        if (_selectedZone == 'Otro (especificar)') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _customZoneCtrl,
            decoration: const InputDecoration(
              labelText: 'Ingresa tu municipio o zona',
              hintText: 'Ej. Apopa, Santa Ana, Sonsonate...',
              prefixIcon: Icon(Icons.edit_location_alt_outlined),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (val) {
              if (val.trim().length > 3) {
                _updateMapSearch(val);
              }
            },
          ),
        ],

        const SizedBox(height: 14),

        // Dirección Comercial
        TextField(
          controller: _restaurantAddressCtrl,
          decoration: const InputDecoration(
            labelText: 'Dirección Comercial y Municipio',
            hintText: 'Ej. Mauritas, Paseo el Carmen',
            prefixIcon: Icon(Icons.storefront_outlined),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) {
            _searchLocationCtrl.text = v;
          },
        ),
        const SizedBox(height: 8),

        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text(
            'Recibir los insumos en esta misma dirección',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          value: _sameAddressForDelivery,
          activeColor: AppColors.primaryBlue,
          onChanged: (val) {
            setState(() => _sameAddressForDelivery = val ?? true);
          },
        ),

        if (!_sameAddressForDelivery) ...[
          const SizedBox(height: 6),
          TextField(
            controller: _deliveryAddressCtrl,
            decoration: const InputDecoration(
              labelText: 'Dirección alterna de descarga / bodega',
              prefixIcon: Icon(Icons.local_shipping_outlined),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
        ],

        TextField(
          controller: _deliveryInstructionsCtrl,
          decoration: const InputDecoration(
            labelText: 'Instrucciones para el repartidor',
            hintText: 'Ej. Entrar por portón lateral, llamar a cocina',
            prefixIcon: Icon(Icons.notes_outlined),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 16),

        // Mapa de Google interactivo
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.location_on, color: AppColors.primaryBlue, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Ubicación en Google Maps',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navyDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Escribe el nombre de tu restaurante o tu calle para situarlo en el mapa:',
                style: TextStyle(fontSize: 12, color: AppColors.subtitleGrey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchLocationCtrl,
                onSubmitted: _updateMapSearch,
                decoration: InputDecoration(
                  hintText: 'Ej. Mauritas Paseo el Carmen, Santa Tecla...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: IconButton(
                    tooltip: 'Buscar en mapa',
                    icon: const Icon(Icons.arrow_forward,
                        size: 20, color: AppColors.primaryBlue),
                    onPressed: () => _updateMapSearch(_searchLocationCtrl.text),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 220,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: HtmlElementView(
                    key: ValueKey(_currentMapQuery),
                    viewType: _viewId,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        DropdownButtonFormField<String>(
          value: _deliveryWindow,
          decoration: const InputDecoration(
            labelText: 'Horario ideal de descarga en cocina',
            prefixIcon: Icon(Icons.schedule_outlined),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: _deliveryWindows
              .map((w) => DropdownMenuItem(value: w, child: Text(w)))
              .toList(),
          onChanged: (val) =>
              setState(() => _deliveryWindow = val ?? _deliveryWindow),
        ),
      ],
    );
  }

  // PASO 3: Insumos Frecuentes
  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '¿Qué insumos compras frecuentemente?',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.navyDark),
        ),
        const SizedBox(height: 4),
        const Text(
          'Personalizaremos el catálogo inicial con tus prioridades.',
          style: TextStyle(fontSize: 13, color: AppColors.subtitleGrey),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _availableSupplies.map((supply) {
            final isChecked = _selectedSupplies.contains(supply);
            return FilterChip(
              label: Text(supply),
              selected: isChecked,
              selectedColor: AppColors.tealMint.withOpacity(0.25),
              checkmarkColor: AppColors.primaryBlue,
              onSelected: (val) {
                setState(() {
                  if (val) {
                    _selectedSupplies.add(supply);
                  } else {
                    _selectedSupplies.remove(supply);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingInitialData) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text(
          'Configura tu Restaurante',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildStepIndicator(),
                      const SizedBox(height: 24),
                      const Divider(height: 1),
                      const SizedBox(height: 24),

                      if (_currentStep == 0) _buildStep1(),
                      if (_currentStep == 1) _buildStep2(),
                      if (_currentStep == 2) _buildStep3(),

                      const SizedBox(height: 28),
                      Row(
                        children: [
                          if (_currentStep > 0) ...[
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: () =>
                                  setState(() => _currentStep -= 1),
                              child: const Text('Atrás'),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryBlue,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: _isSaving
                                  ? null
                                  : () {
                                      if (_currentStep < 2) {
                                        setState(() => _currentStep += 1);
                                      } else {
                                        _completeOnboarding();
                                      }
                                    },
                              child: _isSaving
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      _currentStep == 2
                                          ? 'Empezar a Comprar'
                                          : 'Continuar',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
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
        ),
      ),
    );
  }
}