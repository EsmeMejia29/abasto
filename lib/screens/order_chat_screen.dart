import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../models/order.dart';
import '../theme/app_theme.dart';

import '../config/session_manager.dart';
import 'dart:typed_data';

class OrderChatScreen extends StatefulWidget {
  final OrderModel? order;
  final String? orderId;
  final String? orderCode;
  final String? otherPartyName;

  const OrderChatScreen({
    super.key,
    this.order,
    this.orderId,
    this.orderCode,
    this.otherPartyName,
  });

  @override
  State<OrderChatScreen> createState() => _OrderChatScreenState();
}

class _OrderChatScreenState extends State<OrderChatScreen> {
  final TextEditingController _messageCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isSending = false;
  bool _isUploadingMedia = false;
  bool _isLocating = false;
  bool _isOtherPartyOnline = false;

  RealtimeChannel? _presenceChannel;
  String _effectiveOrderId = '';
  String _effectiveCode = '';
  String _effectivePartyName = 'Chat del Pedido';
  String _senderBusinessName = 'Usuario';
  String _userRole = 'restaurant';
  Map<String, dynamic>? _orderMeta;
  Map<String, dynamic>? _myProfile;

  final Set<String> _registeredMapViews = {};

  String get _currentUserId =>
      supabase.auth.currentUser?.id ?? SessionManager.currentUserId;

  final List<String> _restaurantQuickReplies = [
    '¿A qué hora estiman llegar?',
    'Favor adjuntar el CCF / Factura DTE',
    'Recibir por portón de proveedores',
    'Pedido recibido conforme, ¡gracias!',
  ];

  final List<String> _supplierQuickReplies = [
    'Ya vamos en ruta hacia su cocina',
    'Llegamos en aproximadamente 20 min',
    'Ya adjuntamos el DTE en la orden',
    'Estamos en la entrada del local',
  ];

  void _markOrderChatAsRead() {
    if (_effectiveOrderId.isEmpty || _currentUserId.isEmpty) return;
    html.window.localStorage['abasto_chat_read_${_currentUserId}_$_effectiveOrderId'] =
        DateTime.now().toUtc().toIso8601String();
  }

  @override
  void initState() {
    super.initState();
    _setupOrderIdentifiers();
    _markOrderChatAsRead();
    _loadContextData();
    _setupPresence();
  }

  @override
  void dispose() {
    _presenceChannel?.untrack();
    _presenceChannel?.unsubscribe();
    _messageCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _setupPresence() {
    if (_effectiveOrderId.isEmpty || _currentUserId.isEmpty) return;

    _presenceChannel = supabase.channel('chat-presence-$_effectiveOrderId');
    _presenceChannel!
        .onPresenceSync((_) {
          if (!mounted) return;
          final states = _presenceChannel!.presenceState();
          bool otherOnline = false;
          for (final state in states) {
            for (final presence in state.presences) {
              final uid = presence.payload['user_id']?.toString() ?? '';
              if (uid.isNotEmpty && uid != _currentUserId) {
                otherOnline = true;
              }
            }
          }
          setState(() => _isOtherPartyOnline = otherOnline);
        })
        .subscribe((status, [_]) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            await _presenceChannel!.track({
              'user_id': _currentUserId,
              'online_at': DateTime.now().toUtc().toIso8601String(),
            });
          }
        });
  }

  void _setupOrderIdentifiers() {
    if (widget.order != null) {
      _effectiveOrderId = widget.order!.id;
      _effectiveCode = widget.order!.code;
      // Si supplierName es 'Mi Empresa', quien abrió el chat es el distribuidor
      if (widget.order!.supplierName == 'Mi Empresa') {
        _userRole = 'supplier';
      }
      _effectivePartyName = widget.otherPartyName ??
          (widget.order!.supplierName.isNotEmpty &&
                  widget.order!.supplierName != 'Mi Empresa'
              ? widget.order!.supplierName
              : widget.order!.restaurantName);
    } else {
      _effectiveOrderId = widget.orderId ?? '';
      _effectiveCode = widget.orderCode ??
          (widget.orderId?.startsWith('ORD-') == true ? widget.orderId! : '');
      _effectivePartyName = widget.otherPartyName ?? 'Chat del Pedido';
    }
  }

  Future<void> _loadContextData() async {
    try {
      if (_currentUserId.isNotEmpty) {
        final prof = await supabase
            .from('profiles')
            .select('business_name, full_name, role, address, location')
            .eq('id', _currentUserId)
            .maybeSingle();

        if (prof != null && mounted) {
          setState(() {
            _myProfile = prof;
            final dbRole = (prof['role'] ?? '').toString().toLowerCase().trim();
            if (dbRole.isNotEmpty) {
              _userRole = dbRole;
            }
            final resolved = prof['business_name'] ?? prof['full_name'];
            if (resolved != null && resolved.toString().trim().isNotEmpty) {
              _senderBusinessName = resolved.toString().trim();
            }
          });
        }
      }

      if (_effectiveOrderId.isNotEmpty) {
        final ord = await supabase
            .from('orders')
            .select('*, order_items(*)')
            .eq('id', _effectiveOrderId)
            .maybeSingle();

        if (ord != null && mounted) {
          setState(() {
            _orderMeta = ord;
            if (_effectiveCode.isEmpty && ord['code'] != null) {
              _effectiveCode = ord['code'].toString();
            }
          });

          // Si el título quedó genérico ("Mi Restaurante"), resolvemos el nombre real del otro comercio
          if (_effectivePartyName == 'Mi Restaurante' ||
              _effectivePartyName == 'Chat del Pedido') {
            final otherId = _userRole == 'supplier'
                ? ord['restaurant_id']?.toString()
                : ord['supplier_id']?.toString();
            if (otherId != null && otherId.isNotEmpty) {
              final otherProf = await supabase
                  .from('profiles')
                  .select('business_name, full_name')
                  .eq('id', otherId)
                  .maybeSingle();
              final realName =
                  otherProf?['business_name'] ?? otherProf?['full_name'];
              if (realName != null &&
                  realName.toString().trim().isNotEmpty &&
                  mounted) {
                setState(() {
                  _effectivePartyName = realName.toString().trim();
                });
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Nota cargando contexto de chat: $e');
    }
  }

  void _scrollToBottom() {
    _markOrderChatAsRead();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _insertRawMessage(String rawPayloadText) async {
    if (_effectiveOrderId.isEmpty) return;

    try {
      await supabase.from('order_messages').insert({
        'order_id': _effectiveOrderId,
        'sender_id': _currentUserId,
        'sender_name': _senderBusinessName,
        'message': rawPayloadText,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo enviar: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _sendMessage([String? presetText]) async {
    final text = (presetText ?? _messageCtrl.text).trim();
    if (text.isEmpty || _isSending) return;

    if (presetText == null) _messageCtrl.clear();
    setState(() => _isSending = true);

    try {
      await _insertRawMessage(text);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _sendExactLocation() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);

    try {
      final geo = html.window.navigator.geolocation;
      final pos = await geo.getCurrentPosition(
        enableHighAccuracy: true,
        timeout: const Duration(seconds: 10),
      );

      final lat = pos.coords?.latitude;
      final lng = pos.coords?.longitude;

      if (lat != null && lng != null) {
        final label = (_myProfile?['address'] ??
                _myProfile?['location'] ??
                'Ubicación GPS en tiempo real')
            .toString()
            .replaceAll('|', '-');
        await _insertRawMessage('[LOCATION]|$lat|$lng|$label');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ubicación GPS exacta enviada en el chat'),
              backgroundColor: Color(0xFF0F766E),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    } catch (_) {
      // Si el navegador bloquea GPS, usamos la ubicación registrada del perfil del comercio
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }

    // Respaldo con dirección comercial registrada si GPS no está disponible
    try {
      final det = await supabase
          .from('restaurant_details')
          .select('delivery_latitude, delivery_longitude, delivery_address')
          .eq('profile_id', _currentUserId)
          .maybeSingle();

      final lat = det?['delivery_latitude'];
      final lng = det?['delivery_longitude'];
      final addr = (det?['delivery_address'] ??
              _myProfile?['address'] ??
              _myProfile?['location'] ??
              '')
          .toString()
          .trim();

      if (lat != null && lng != null) {
        await _insertRawMessage(
            '[LOCATION]|$lat|$lng|${addr.isNotEmpty ? addr : 'Punto de entrega registrado'}');
      } else if (addr.isNotEmpty) {
        await _insertRawMessage('[ADDRESS]|$addr, El Salvador');
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Activa el permiso de ubicación en tu navegador o guarda tu dirección en Mi Perfil.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (_) {}
  }

  Future<Uint8List?> _openLiveCameraDialog() async {
    html.MediaStream? activeStream;
    html.VideoElement? videoEl;
    final String viewId =
        'live-cam-${DateTime.now().millisecondsSinceEpoch}';

    ui_web.platformViewRegistry.registerViewFactory(viewId, (int id) {
      videoEl = html.VideoElement()
        ..autoplay = true
        ..muted = true
        ..setAttribute('playsinline', 'true')
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover';

      html.window.navigator.mediaDevices
          ?.getUserMedia({
            'video': {'facingMode': 'environment'},
            'audio': false,
          })
          .then((stream) {
            activeStream = stream;
            videoEl?.srcObject = stream;
          })
          .catchError((err) {
            debugPrint('Error accediendo a cámara: $err');
          });

      return videoEl!;
    });

    Uint8List? capturedBytes;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: const Color(0xFF001A2C),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.camera_alt_rounded,
                              color: AppColors.tealMint, size: 19),
                          SizedBox(width: 8),
                          Text(
                            'Cámara en Vivo • Abasto',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          capturedBytes = null;
                          Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 320,
                  width: double.infinity,
                  child: capturedBytes != null
                      ? Image.memory(capturedBytes!, fit: BoxFit.cover)
                      : HtmlElementView(viewType: viewId),
                ),
                Container(
                  padding: const EdgeInsets.all(14),
                  color: Colors.white,
                  child: capturedBytes == null
                      ? SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF001A2C),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.camera,
                                color: AppColors.tealMint),
                            label: const Text(
                              'Capturar Foto',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            onPressed: () async {
                              if (videoEl == null ||
                                  videoEl!.videoWidth == 0) {
                                return;
                              }
                              final canvas = html.CanvasElement(
                                width: videoEl!.videoWidth,
                                height: videoEl!.videoHeight,
                              );
                              canvas.context2D.drawImage(videoEl!, 0, 0);
                              final blob =
                                  await canvas.toBlob('image/jpeg', 0.85);
                              final reader = html.FileReader();
                              reader.readAsArrayBuffer(blob);
                              await reader.onLoad.first;
                              setDialogState(() {
                                capturedBytes =
                                    (reader.result as List<int>) is Uint8List
                                        ? reader.result as Uint8List
                                        : Uint8List.fromList(
                                            reader.result as List<int>);
                              });
                            },
                          ),
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  setDialogState(() => capturedBytes = null);
                                },
                                icon: const Icon(Icons.refresh),
                                label: const Text('Repetir'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF001A2C),
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => Navigator.pop(ctx),
                                icon: const Icon(Icons.send_rounded,
                                    color: AppColors.tealMint, size: 17),
                                label: const Text(
                                  'Enviar Foto',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Apagar la cámara al cerrar el modal
    activeStream?.getTracks().forEach((track) => track.stop());
    return capturedBytes;
  }

  Future<void> _pickAndSendImage() async {
    if (_isUploadingMedia) return;

    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enviar Evidencia Fotográfica',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.navyDark,
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: AppColors.navyDark,
                child: const Icon(Icons.camera_alt_rounded,
                    color: AppColors.tealMint, size: 20),
              ),
              title: const Text('Tomar Foto Ahora',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text(
                  'Usa la cámara para fotografiar entrega, recibo o producto'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: AppColors.primaryBlue.withOpacity(0.12),
                child: const Icon(Icons.photo_library_outlined,
                    color: AppColors.primaryBlue, size: 20),
              ),
              title: const Text('Elegir de Galería / Archivos',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Selecciona una imagen guardada'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    Uint8List? bytes;
    String ext = 'jpg';

    if (source == ImageSource.camera) {
      bytes = await _openLiveCameraDialog();
      if (bytes == null) return;
    } else {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 78,
        maxWidth: 1200,
      );
      if (picked == null) return;
      bytes = await picked.readAsBytes();
      if (picked.name.contains('.')) {
        ext = picked.name.split('.').last.toLowerCase();
      }
    }

    setState(() => _isUploadingMedia = true);

    try {
      final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
      final path =
          'chat_${_effectiveOrderId}_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await supabase.storage.from('product-images').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: true),
          );

      final url =
          supabase.storage.from('product-images').getPublicUrl(path);
      await _insertRawMessage('[IMAGE]|$url');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error enviando foto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingMedia = false);
    }
  }

  void _showEtaPicker() {
    final options = [
      {'label': '15 minutos', 'sub': 'Muy cerca del punto de entrega'},
      {'label': '30 minutos', 'sub': 'En tránsito dentro de la zona'},
      {'label': '45 minutos', 'sub': 'Preparando salida de ruta'},
      {'label': '1 hora', 'sub': 'Próxima parada programada'},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.local_shipping_rounded, color: AppColors.navyDark),
                SizedBox(width: 8),
                Text(
                  'Enviar Tiempo Estimado de Llegada',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navyDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...options.map((opt) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.tealMint.withOpacity(0.16),
                    child: const Icon(Icons.schedule_rounded,
                        color: Color(0xFF0F766E), size: 20),
                  ),
                  title: Text(
                    'Llegada en ${opt['label']}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(opt['sub']!,
                      style: const TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.send_rounded,
                      size: 18, color: AppColors.navyDark),
                  onTap: () {
                    Navigator.pop(ctx);
                    _insertRawMessage('[ETA]|${opt['label']}');
                  },
                )),
          ],
        ),
      ),
    );
  }

  void _showOrderSummarySheet() {
    final items = (_orderMeta?['order_items'] as List<dynamic>?) ??
        widget.order?.items
            .map((i) => {
                  'product_name': i.productName,
                  'quantity': i.quantity,
                  'unit_price': i.unitPrice,
                })
            .toList() ??
        [];
    final total = (_orderMeta?['total_amount'] as num?)?.toDouble() ??
        widget.order?.totalAmount ??
        0.0;
    final status =
        (_orderMeta?['status'] ?? widget.order?.status.name ?? 'pendiente')
            .toString();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Resumen • $_effectiveCode',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navyDark,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.tealMint.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No hay detalle de insumos disponible.'),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, idx) {
                    final it = items[idx];
                    final qty = (it['quantity'] as num?)?.toInt() ?? 1;
                    final price = (it['unit_price'] as num?)?.toDouble() ?? 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '$qty x ${it['product_name'] ?? 'Insumo'}',
                              style: const TextStyle(fontSize: 13.5),
                            ),
                          ),
                          Text(
                            '\$${(qty * price).toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.navyDark,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total de la Orden:',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppColors.navyDark),
                ),
                Text(
                  '\$${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: AppColors.navyDark),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = DateTime.parse(timestamp.toString()).toLocal();
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '$hour:$min $period';
    } catch (_) {
      return '';
    }
  }

  String _ensureMapRegistered(String msgId, String query) {
    final viewId = 'chat-map-$msgId-${query.hashCode}';
    if (!_registeredMapViews.contains(viewId)) {
      _registeredMapViews.add(viewId);
      ui_web.platformViewRegistry.registerViewFactory(viewId, (int id) {
        return html.IFrameElement()
          ..src =
              'https://maps.google.com/maps?q=$query&t=&z=16&ie=UTF8&iwloc=&output=embed'
          ..style.border = '0'
          ..style.width = '100%'
          ..style.height = '100%'
          ..allowFullscreen = false;
      });
    }
    return viewId;
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg) {
    final msgId = (msg['id'] ?? DateTime.now().millisecondsSinceEpoch).toString();
    final senderId = msg['sender_id']?.toString() ?? '';
    final isMe = senderId == _currentUserId;
    final rawText = (msg['message'] ?? msg['content'] ?? '').toString();
    final time = _formatTime(msg['created_at']);

    // 1. Tarjeta de Ubicación GPS Exacta
    if (rawText.startsWith('[LOCATION]|')) {
      final parts = rawText.split('|');
      final lat = parts.length > 1 ? parts[1] : '13.6929';
      final lng = parts.length > 2 ? parts[2] : '-89.2182';
      final label = parts.length > 3 ? parts[3] : 'Ubicación compartida';
      final mapViewId = _ensureMapRegistered(msgId, '$lat,$lng');
      final mapsUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 300,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isMe ? AppColors.navyDark : const Color(0xFFCBD5E1),
              width: 1.3,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF001A2C).withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 145,
                width: double.infinity,
                child: HtmlElementView(viewType: mapViewId),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.location_on_rounded,
                              size: 16, color: Color(0xFFDC2626)),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Ubicación Exacta de Entrega',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppColors.navyDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF475569)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'GPS: $lat, $lng',
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.subtitleGrey),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 34,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.navyDark,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.directions_rounded,
                            size: 16, color: AppColors.tealMint),
                        label: const Text('Abrir Ruta en Maps',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () => html.window.open(mapsUrl, '_blank'),
                      ),
                    ),
                    if (time.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          time,
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey.shade500),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 2. Tarjeta de Dirección Comercial (cuando no hay GPS)
    if (rawText.startsWith('[ADDRESS]|')) {
      final addr = rawText.replaceFirst('[ADDRESS]|', '');
      final mapsUrl =
          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(addr)}';

      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.pin_drop_rounded,
                      color: Color(0xFFDC2626), size: 18),
                  SizedBox(width: 6),
                  Text(
                    'Dirección de Entrega',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: AppColors.navyDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(addr,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF334155))),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 34,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navyDark,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.map_outlined,
                      size: 16, color: AppColors.tealMint),
                  label: const Text('Ver en Google Maps',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () => html.window.open(mapsUrl, '_blank'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 3. Tarjeta de Fotografía adjunta
    if (rawText.startsWith('[IMAGE]|')) {
      final url = rawText.replaceFirst('[IMAGE]|', '').trim();
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isMe ? AppColors.navyDark : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: isMe ? null : Border.all(color: const Color(0xFFE2E8F0)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              InkWell(
                onTap: () => html.window.open(url, '_blank'),
                child: Image.network(
                  url,
                  height: 190,
                  width: 280,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(20),
                    child: Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),
              ),
              if (time.isNotEmpty)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: Text(
                    time,
                    style: TextStyle(
                      fontSize: 10,
                      color: isMe
                          ? Colors.white.withOpacity(0.75)
                          : Colors.grey.shade500,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // 4. Tarjeta de Tiempo Estimado de Llegada (ETA)
    if (rawText.startsWith('[ETA]|')) {
      final etaLabel = rawText.replaceFirst('[ETA]|', '').trim();
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 310),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF001A2C), Color(0xFF1B3452)],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF001A2C).withOpacity(0.12),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.tealMint.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.local_shipping_rounded,
                    color: AppColors.tealMint, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ACTUALIZACIÓN DE RUTA',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                        color: AppColors.tealMint,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Llegada estimada: $etaLabel',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (time.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Enviado a las $time',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 5. Burbuja estándar de texto Abasto
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF001A2C) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: isMe ? null : Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF001A2C).withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              rawText,
              style: TextStyle(
                color: isMe ? Colors.white : const Color(0xFF1E293B),
                fontSize: 14,
                height: 1.35,
              ),
            ),
            if (time.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    time,
                    style: TextStyle(
                      color: isMe
                          ? Colors.white.withOpacity(0.7)
                          : Colors.grey.shade500,
                      fontSize: 10,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.done_all_rounded,
                        size: 13, color: AppColors.tealMint),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quickReplies = _userRole == 'supplier'
        ? _supplierQuickReplies
        : _restaurantQuickReplies;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001A2C),
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.tealMint.withOpacity(0.18),
              child: Text(
                _effectivePartyName.isNotEmpty
                    ? _effectivePartyName[0].toUpperCase()
                    : 'A',
                style: const TextStyle(
                  color: AppColors.tealMint,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _effectivePartyName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: _isOtherPartyOnline
                              ? AppColors.tealMint
                              : const Color(0xFF94A3B8),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _effectiveCode.isNotEmpty
                            ? 'Pedido $_effectiveCode • ${_isOtherPartyOnline ? 'En línea' : 'Desconectado'}'
                            : (_isOtherPartyOnline ? 'En línea' : 'Desconectado'),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: _isOtherPartyOnline
                              ? AppColors.tealMint
                              : const Color(0xFFCBD5E1),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Ver resumen del pedido',
            icon: const Icon(Icons.receipt_long_outlined,
                color: AppColors.tealMint),
            onPressed: _showOrderSummarySheet,
          ),
          if ((widget.order?.supplierPhone ?? '').isNotEmpty)
            IconButton(
              tooltip: 'Llamar por teléfono',
              icon: const Icon(Icons.phone_outlined),
              onPressed: () =>
                  html.window.open('tel:${widget.order!.supplierPhone}', '_self'),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              children: [
                // Banner informativo sutil de Abasto
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE0F2FE),
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFBAE6FD)),
                    ),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.verified_user_outlined,
                          size: 16, color: Color(0xFF0369A1)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Respaldo Abasto: Todo lo acordado aquí (ubicación GPS, horarios y DTE) queda guardado en la orden.',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF0C4A6E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Lista de mensajes en tiempo real
                Expanded(
                  child: StreamBuilder<List<dynamic>>(
                    stream: supabase
                        .from('order_messages')
                        .stream(primaryKey: ['id'])
                        .eq('order_id', _effectiveOrderId)
                        .order('created_at', ascending: true),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Error al cargar mensajes: ${snapshot.error}',
                            style: const TextStyle(color: Colors.red),
                          ),
                        );
                      }

                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final rawMessages = snapshot.data ?? [];
                      final seenIds = <String>{};
                      final List<dynamic> messages = [];
                      for (var m in rawMessages) {
                        final id = m['id']?.toString() ?? '';
                        if (id.isEmpty || !seenIds.contains(id)) {
                          if (id.isNotEmpty) seenIds.add(id);
                          messages.add(m);
                        }
                      }

                      if (messages.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: AppColors.navyDark.withOpacity(0.06),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.forum_outlined,
                                      size: 42, color: AppColors.navyDark),
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  'Coordina tu entrega directamente aquí',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.navyDark,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Envía tu ubicación GPS exacta, fotos de entrega o selecciona una respuesta rápida abajo.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.subtitleGrey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => _scrollToBottom());

                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        itemCount: messages.length,
                        itemBuilder: (ctx, index) =>
                            _buildMessageBubble(messages[index]),
                      );
                    },
                  ),
                ),

                // Chips de Respuestas Rápidas B2B
                Container(
                  height: 42,
                  color: Colors.white,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    itemCount: quickReplies.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, idx) {
                      final qText = quickReplies[idx];
                      return ActionChip(
                        backgroundColor: const Color(0xFFF1F5F9),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        label: Text(
                          qText,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.navyDark,
                          ),
                        ),
                        onPressed: () => _sendMessage(qText),
                      );
                    },
                  ),
                ),

                // Barra de herramientas + Caja de texto
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 6, 12, 10),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Botón Ubicación GPS Exacta
                      IconButton(
                        tooltip: 'Enviar ubicación GPS exacta',
                        icon: _isLocating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.location_on_outlined,
                                color: Color(0xFFDC2626), size: 23),
                        onPressed: _isLocating ? null : _sendExactLocation,
                      ),

                      // Botón Cámara / Galería
                      IconButton(
                        tooltip: 'Tomar foto o adjuntar imagen',
                        icon: _isUploadingMedia
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.photo_camera_outlined,
                                color: AppColors.primaryBlue, size: 22),
                        onPressed:
                            _isUploadingMedia ? null : _pickAndSendImage,
                      ),

                      // Botón Tiempo Estimado de Llegada (ETA) - Solo Distribuidor
                      if (_userRole == 'supplier')
                        IconButton(
                          tooltip: 'Enviar tiempo estimado de llegada (ETA)',
                          icon: const Icon(Icons.local_shipping_outlined,
                              color: Color(0xFF0F766E), size: 22),
                          onPressed: _showEtaPicker,
                        ),

                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: TextField(
                            controller: _messageCtrl,
                            textCapitalization: TextCapitalization.sentences,
                            maxLines: 4,
                            minLines: 1,
                            keyboardType: TextInputType.multiline,
                            decoration: const InputDecoration(
                              hintText: 'Escribe un mensaje...',
                              hintStyle: TextStyle(fontSize: 13.5),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: _isSending ? null : () => _sendMessage(),
                        borderRadius: BorderRadius.circular(24),
                        child: CircleAvatar(
                          radius: 22,
                          backgroundColor: const Color(0xFF001A2C),
                          child: _isSending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.tealMint,
                                  ),
                                )
                              : const Icon(Icons.send_rounded,
                                  color: AppColors.tealMint, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}