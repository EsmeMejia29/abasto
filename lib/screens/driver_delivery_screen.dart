import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../models/order.dart';
import '../theme/app_theme.dart';
import 'order_chat_screen.dart';
import 'welcome_screen.dart';

class DriverDeliveryScreen extends StatefulWidget {
  final String supplierId;
  final String supplierName;
  final String accessCode;

  const DriverDeliveryScreen({
    super.key,
    required this.supplierId,
    required this.supplierName,
    required this.accessCode,
  });

  @override
  State<DriverDeliveryScreen> createState() => _DriverDeliveryScreenState();
}

class _DriverDeliveryScreenState extends State<DriverDeliveryScreen> {
  bool _isLoading = true;
  List<dynamic> _activeDeliveries = [];
  RealtimeChannel? _ordersChannel;

  @override
  void initState() {
    super.initState();
    _loadDeliveries();
    _ordersChannel = supabase
        .channel('public:driver_route_${widget.supplierId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) {
            if (mounted) _loadDeliveries();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _ordersChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadDeliveries() async {
    try {
      final res = await supabase
          .from('orders')
          .select('*, order_items(product_name, quantity)')
          .eq('supplier_id', widget.supplierId)
          .order('created_at', ascending: true);

      final orders = List<dynamic>.from(res).where((o) {
        final st = (o['status'] ?? '').toString().toLowerCase().trim();
        return st == 'confirmado' || st == 'enruta' || st == 'en ruta';
      }).toList();
      final restIds = orders
          .map((o) => o['restaurant_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      Map<String, dynamic> profMap = {};
      Map<String, dynamic> detMap = {};

      if (restIds.isNotEmpty) {
        try {
          final profs = await supabase
              .from('profiles')
              .select('id, business_name, phone, address, location')
              .filter('id', 'in', restIds);
          profMap = {
            for (final p in (profs as List<dynamic>))
              p['id'].toString(): p as Map<String, dynamic>
          };
        } catch (_) {}

        try {
          final dets = await supabase
              .from('restaurant_details')
              .select(
                  'profile_id, delivery_address, delivery_zone, delivery_instructions, delivery_latitude, delivery_longitude')
              .filter('profile_id', 'in', restIds);
          detMap = {
            for (final d in (dets as List<dynamic>))
              d['profile_id'].toString(): d as Map<String, dynamic>
          };
        } catch (_) {}
      }

      for (final o in orders) {
        final rId = o['restaurant_id']?.toString() ?? '';
        final p = profMap[rId];
        final d = detMap[rId];
        o['restaurant_name'] =
            p?['business_name'] ?? o['restaurant_name'] ?? 'Restaurante';
        o['restaurant_phone'] = p?['phone'] ?? '';
        o['delivery_address'] = d?['delivery_address'] ??
            p?['address'] ??
            'Dirección registrada en pedido';
        o['delivery_zone'] = d?['delivery_zone'] ?? p?['location'] ?? '';
        o['delivery_instructions'] = d?['delivery_instructions'] ??
            'Entrada de proveedores / recepción de cocina';
        o['delivery_latitude'] = d?['delivery_latitude'];
        o['delivery_longitude'] = d?['delivery_longitude'];
      }

      if (mounted) {
        setState(() {
          _activeDeliveries = orders;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markEnRuta(Map<String, dynamic> order) async {
    try {
      final currentHistory =
          (order['status_history'] as List<dynamic>?) ?? [];
      final newHistory = List<dynamic>.from(currentHistory)
        ..add({
          'status': 'enRuta',
          'changed_at': DateTime.now().toUtc().toIso8601String(),
          'note': 'Despachado en ruta por motorista',
        });

      await supabase.from('orders').update({
        'status': 'enRuta',
        'status_history': newHistory,
      }).eq('id', order['id'].toString());

      await supabase.from('order_messages').insert({
        'order_id': order['id'].toString(),
        'sender_id': widget.supplierId,
        'sender_name': 'Motorista • ${widget.supplierName}',
        'message': '[ETA]|En camino hacia el restaurante 🚚',
      });

      _loadDeliveries();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Estado actualizado a En Ruta y cliente notificado'),
            backgroundColor: AppColors.tealMint,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _completeDeliveryWithPinAndPhoto(
      Map<String, dynamic> order) async {
    final pinCtrl = TextEditingController();
    final expectedPin = (order['delivery_pin'] ?? '').toString().trim();
    String? photoUrl;
    bool isUploadingPhoto = false;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text(
            'Confirmar Entrega Conforme',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 390,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cliente: ${order['restaurant_name']} (${order['code']})',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 46),
                    side: BorderSide(
                      color: photoUrl != null
                          ? const Color(0xFF16A34A)
                          : AppColors.primaryBlue,
                    ),
                  ),
                  icon: Icon(
                    photoUrl != null
                        ? Icons.check_circle
                        : Icons.camera_alt_outlined,
                    color: photoUrl != null
                        ? const Color(0xFF16A34A)
                        : AppColors.primaryBlue,
                  ),
                  label: Text(
                    isUploadingPhoto
                        ? 'Subiendo foto de entrega...'
                        : (photoUrl != null
                            ? 'Foto de Entrega Lista ✓ (Cambiar)'
                            : '1. Tomar Foto de Entrega Conforme'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: isUploadingPhoto
                      ? null
                      : () {
                          final input = html.FileUploadInputElement()
                            ..accept = 'image/*'
                            ..setAttribute('capture', 'environment');
                          input.click();
                          input.onChange.listen((_) async {
                            final file = input.files?.first;
                            if (file == null) return;
                            setDialogState(() => isUploadingPhoto = true);
                            try {
                              final reader = html.FileReader();
                              reader.readAsArrayBuffer(file);
                              await reader.onLoad.first;
                              final bytes = reader.result as Uint8List;
                              final path =
                                  'deliveries/${order['id']}_${DateTime.now().millisecondsSinceEpoch}.jpg';
                              await supabase.storage
                                  .from('product-images')
                                  .uploadBinary(
                                    path,
                                    bytes,
                                    fileOptions: const FileOptions(
                                      contentType: 'image/jpeg',
                                      upsert: true,
                                    ),
                                  );
                              final url = supabase.storage
                                  .from('product-images')
                                  .getPublicUrl(path);
                              setDialogState(() {
                                photoUrl = url;
                                isUploadingPhoto = false;
                              });
                            } catch (e) {
                              setDialogState(() => isUploadingPhoto = false);
                            }
                          });
                        },
                ),
                if (expectedPin.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    '2. Pide el PIN de 4 dígitos al restaurante:',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: pinCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6,
                    ),
                    decoration: const InputDecoration(
                      hintText: '0000',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  isUploadingPhoto ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A)),
              onPressed: isUploadingPhoto
                  ? null
                  : () {
                      if (expectedPin.isNotEmpty &&
                          pinCtrl.text.trim() != expectedPin) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('PIN incorrecto. Verifica con el cliente.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      Navigator.pop(ctx, true);
                    },
              child: const Text(
                'Finalizar Entrega',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      try {
        final orderId = order['id'].toString();
        final currentHistory =
            (order['status_history'] as List<dynamic>?) ?? [];
        final newHistory = List<dynamic>.from(currentHistory)
          ..add({
            'status': 'entregado',
            'changed_at': DateTime.now().toUtc().toIso8601String(),
            'note': 'Entregado y validado con PIN por motorista',
          });

        await supabase.from('orders').update({
          'status': 'entregado',
          if (photoUrl != null) 'delivery_photo_url': photoUrl,
          'status_history': newHistory,
        }).eq('id', orderId);

        if (photoUrl != null) {
          await supabase.from('order_messages').insert({
            'order_id': orderId,
            'sender_id': widget.supplierId,
            'sender_name': 'Motorista • ${widget.supplierName}',
            'message': '[IMAGE]|$photoUrl',
          });
        }

        _loadDeliveries();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('¡Entrega confirmada con éxito!'),
              backgroundColor: AppColors.tealMint,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001A2C),
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: 'Salir de vista motorista',
          icon: const Icon(Icons.logout_rounded),
          onPressed: () => Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const WelcomeScreen()),
            (route) => false,
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ruta • ${widget.supplierName}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Vista de Reparto (Sin datos financieros)',
              style: TextStyle(fontSize: 11, color: AppColors.tealMint),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadDeliveries,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _activeDeliveries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.check_circle_outline,
                          size: 64, color: AppColors.tealMint),
                      SizedBox(height: 12),
                      Text(
                        'No tienes entregas pendientes en este momento.',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.navyDark),
                      ),
                    ],
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _activeDeliveries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (_, idx) {
                        final ord = _activeDeliveries[idx];
                        final st = (ord['status'] ?? '').toString().toLowerCase();
                        final isEnRuta = st == 'enruta' || st == 'en ruta';
                        final items =
                            (ord['order_items'] as List<dynamic>?) ?? [];
                        final lat = ord['delivery_latitude'];
                        final lng = ord['delivery_longitude'];
                        final addr = ord['delivery_address'] ?? '';
                        final zone = ord['delivery_zone'] ?? '';

                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isEnRuta
                                  ? AppColors.primaryBlue
                                  : const Color(0xFFE2E8F0),
                              width: isEnRuta ? 1.5 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${ord['code']} • ${ord['restaurant_name']}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.navyDark,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isEnRuta
                                          ? const Color(0xFFDBEAFE)
                                          : const Color(0xFFDCFCE7),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      isEnRuta ? 'EN RUTA' : 'LISTO PARA SALIR',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isEnRuta
                                            ? const Color(0xFF1D4ED8)
                                            : const Color(0xFF15803D),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.location_on,
                                      color: Colors.redAccent, size: 18),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '$addr ${zone.isNotEmpty ? '($zone)' : ''}',
                                      style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Nota descarga: ${ord['delivery_instructions']}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.subtitleGrey),
                              ),
                              const Divider(height: 18),
                              const Text(
                                'Bultos / Insumos a entregar:',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.navyDark),
                              ),
                              const SizedBox(height: 4),
                              ...items.map((it) => Text(
                                    '• ${it['quantity']} x ${it['product_name']}',
                                    style: const TextStyle(fontSize: 13),
                                  )),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.navigation,
                                          size: 16),
                                      label: const Text('Abrir GPS'),
                                      onPressed: () async {
                                        String originParam = '';
                                        try {
                                          final pos = await html.window
                                              .navigator.geolocation
                                              .getCurrentPosition(
                                            enableHighAccuracy: true,
                                            timeout:
                                                const Duration(seconds: 5),
                                          );
                                          final myLat = pos.coords?.latitude;
                                          final myLng = pos.coords?.longitude;
                                          if (myLat != null && myLng != null) {
                                            originParam =
                                                '&origin=$myLat,$myLng';
                                          }
                                        } catch (_) {}

                                        final destParam = (lat != null &&
                                                lng != null)
                                            ? '$lat,$lng'
                                            : Uri.encodeComponent(
                                                '$addr, $zone, El Salvador');

                                        final url = Uri.parse(
                                            'https://www.google.com/maps/dir/?api=1$originParam&destination=$destParam&travelmode=driving');
                                        if (await canLaunchUrl(url)) {
                                          await launchUrl(url,
                                              mode: LaunchMode
                                                  .externalApplication);
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(
                                          Icons.chat_bubble_outline,
                                          size: 16),
                                      label: const Text('Chat Cliente'),
                                      onPressed: () {
                                        final orderObj = OrderModel(
                                          id: ord['id'].toString(),
                                          code: ord['code'] ?? '',
                                          restaurantName:
                                              ord['restaurant_name'] ?? '',
                                          supplierName: widget.supplierName,
                                          supplierPhone: '',
                                          items: const [],
                                          totalAmount: 0,
                                          status: OrderStatus.enRuta,
                                          deliveryDate: DateTime.now(),
                                        );
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => OrderChatScreen(
                                              order: orderObj,
                                              otherPartyName:
                                                  ord['restaurant_name'] ??
                                                      'Restaurante',
                                              overrideSenderId:
                                                  widget.supplierId,
                                              overrideSenderName:
                                                  'Motorista • ${widget.supplierName}',
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (!isEnRuta)
                                SizedBox(
                                  width: double.infinity,
                                  height: 44,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primaryBlue,
                                      foregroundColor: Colors.white,
                                    ),
                                    icon: const Icon(Icons.local_shipping),
                                    label: const Text(
                                      'Iniciar Ruta / Avisar Salida',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    onPressed: () => _markEnRuta(ord),
                                  ),
                                )
                              else
                                SizedBox(
                                  width: double.infinity,
                                  height: 44,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF16A34A),
                                      foregroundColor: Colors.white,
                                    ),
                                    icon: const Icon(Icons.verified_outlined),
                                    label: const Text(
                                      'Entregar con Foto y PIN',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    onPressed: () =>
                                        _completeDeliveryWithPinAndPhoto(ord),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
    );
  }
}