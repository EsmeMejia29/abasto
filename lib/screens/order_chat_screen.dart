import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../models/order.dart';
import '../theme/app_theme.dart';

class OrderChatScreen extends StatefulWidget {
  final Order? order;
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
  String _effectiveOrderId = '';
  String _effectiveCode = '';
  String _effectivePartyName = 'Chat del Pedido';

  String get _currentUserId => supabase.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _setupOrderIdentifiers();
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _setupOrderIdentifiers() {
    if (widget.order != null) {
      _effectiveOrderId = widget.order!.id;
      _effectiveCode = widget.order!.code;
      _effectivePartyName = widget.otherPartyName ?? widget.order!.restaurantName ?? 'Pedido $_effectiveCode';
    } else {
      _effectiveOrderId = widget.orderId ?? '';
      _effectiveCode = widget.orderCode ?? (widget.orderId?.startsWith('ORD-') == true ? widget.orderId! : '');
      _effectivePartyName = widget.otherPartyName ?? 'Chat del Pedido';
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty || _isSending) return;

    final targetId = _effectiveOrderId;
    if (targetId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontró el ID de la orden')),
      );
      return;
    }

    _messageCtrl.clear();
    setState(() => _isSending = true);

    try {
      String senderName = 'Usuario';
      try {
        final profile = await supabase
            .from('profiles')
            .select('business_name, full_name')
            .eq('id', _currentUserId)
            .maybeSingle();

        final resolved = profile?['business_name'] ?? profile?['full_name'];
        if (resolved != null && resolved.toString().trim().isNotEmpty) {
          senderName = resolved.toString().trim();
        }
      } catch (e) {
        debugPrint("Nota obteniendo sender_name: $e");
      }

      final payload = {
        'order_id': targetId,
        'sender_id': _currentUserId,
        'sender_name': senderName,
        'message': text,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      await supabase.from('order_messages').insert(payload);
      _scrollToBottom();
    } catch (e) {
      debugPrint("Error enviando mensaje: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo enviar el mensaje: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _effectivePartyName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            if (_effectiveCode.isNotEmpty)
              Text(
                'Pedido $_effectiveCode',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.85),
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  color: Colors.amber.shade50,
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: Colors.orange.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Canal directo para coordinar horario, factura o cambios del pedido.',
                          style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
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

                      // Deduplicación estricta por id para evitar mensajes dobles
                      final seenIds = <String>{};
                      final messages = <Map<String, dynamic>>[];
                      for (var m in rawMessages) {
                        final id = m['id']?.toString() ?? '';
                        if (id.isEmpty || !seenIds.contains(id)) {
                          if (id.isNotEmpty) seenIds.add(id);
                          messages.add(m);
                        }
                      }

                      if (messages.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.chat_bubble_outline,
                                  size: 54, color: AppColors.subtitleGrey),
                              SizedBox(height: 12),
                              Text(
                                'No hay mensajes aún.',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.subtitleGrey,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Escribe para iniciar la coordinación.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.subtitleGrey,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        itemCount: messages.length,
                        itemBuilder: (ctx, index) {
                          final msg = messages[index];
                          final senderId = msg['sender_id']?.toString() ?? '';
                          final isMe = senderId == _currentUserId;
                          final text = msg['message'] ?? msg['content'] ?? '';
                          final time = _formatTime(msg['created_at']);

                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 480),
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isMe ? AppColors.primaryBlue : Colors.white,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                                  bottomRight: Radius.circular(isMe ? 4 : 16),
                                ),
                                border: isMe ? null : Border.all(color: Colors.grey.shade200),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 3,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    text,
                                    style: TextStyle(
                                      color: isMe ? Colors.white : Colors.black87,
                                      fontSize: 14,
                                      height: 1.3,
                                    ),
                                  ),
                                  if (time.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      time,
                                      style: TextStyle(
                                        color: isMe
                                            ? Colors.white.withOpacity(0.7)
                                            : Colors.grey.shade500,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        offset: const Offset(0, -1),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: TextField(
                            controller: _messageCtrl,
                            textCapitalization: TextCapitalization.sentences,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            decoration: const InputDecoration(
                              hintText: 'Escribe un mensaje...',
                              border: InputBorder.none,
                              contentPadding:
                                  EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: _isSending ? null : _sendMessage,
                        borderRadius: BorderRadius.circular(24),
                        child: CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.primaryBlue,
                          child: _isSending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send, color: Colors.white, size: 20),
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