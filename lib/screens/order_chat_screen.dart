import 'package:flutter/material.dart';
import '../main.dart';
import '../models/order.dart';
import '../theme/app_theme.dart';
import '../config/session_manager.dart';

class OrderChatScreen extends StatefulWidget {
  final OrderModel order;

  const OrderChatScreen({super.key, required this.order});

  @override
  State<OrderChatScreen> createState() => _OrderChatScreenState();
}

class _OrderChatScreenState extends State<OrderChatScreen> {
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;

  String _userRole = 'restaurant';
  String _myBusinessName = '';

  String get _currentUserId =>
      supabase.auth.currentUser?.id ?? SessionManager.currentUserId;

  bool get _isSupplier => _userRole == 'supplier';

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _initChat() async {
    await _detectUserRole();
    await _fetchMessages();
  }

  Future<void> _detectUserRole() async {
    try {
      final res = await supabase
          .from('profiles')
          .select('role, business_name')
          .eq('id', _currentUserId)
          .maybeSingle();

      if (res != null && mounted) {
        setState(() {
          _userRole = res['role']?.toString().toLowerCase() ?? 'restaurant';
          _myBusinessName = res['business_name']?.toString() ?? '';
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchMessages() async {
    try {
      final res = await supabase
          .from('order_messages')
          .select('*')
          .eq('order_id', widget.order.id)
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(res);
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;

    _msgCtrl.clear();

    final senderRole = _isSupplier ? 'supplier' : 'restaurant';
    final senderName = _myBusinessName.isNotEmpty
        ? _myBusinessName
        : (_isSupplier ? widget.order.supplierName : widget.order.restaurantName);

    final tempMessage = {
      'order_id': widget.order.id,
      'sender_id': _currentUserId,
      'sender_name': senderName,
      'sender_role': senderRole,
      'message': text,
      'created_at': DateTime.now().toIso8601String(),
    };

    setState(() {
      _messages.add(tempMessage);
    });
    _scrollToBottom();

    try {
      await supabase.from('order_messages').insert({
        'order_id': widget.order.id,
        'sender_id': _currentUserId,
        'sender_name': senderName,
        'sender_role': senderRole,
        'message': text,
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Si soy distribuidor, la contraparte que veo arriba es el Restaurante.
    // Si soy restaurante, la contraparte es el Proveedor/Distribuidor.
    final headerTitle = _isSupplier
        ? (widget.order.restaurantName.isNotEmpty ? widget.order.restaurantName : 'Restaurante')
        : (widget.order.supplierName.isNotEmpty ? widget.order.supplierName : 'Distribuidor');

    final inputHint = _isSupplier
        ? 'Escribe un mensaje al restaurante...'
        : 'Escribe un mensaje al distribuidor...';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              headerTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              'Pedido ${widget.order.code}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchMessages,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.amber.shade50,
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: Colors.amber.shade900),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Canal directo para coordinar horario, factura o cambios del pedido.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber.shade900,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Text(
                          'No hay mensajes aún.\nEscribe para iniciar la coordinación.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMe = msg['sender_id'] == _currentUserId ||
                              msg['sender_role'] == (_isSupplier ? 'supplier' : 'restaurant');

                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.75,
                              ),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? AppColors.primaryBlue
                                    : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: isMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    msg['sender_name'] ?? (isMe ? 'Tú' : 'Contacto'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isMe
                                          ? Colors.white70
                                          : AppColors.subtitleGrey,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    msg['message'] ?? '',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isMe ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      decoration: InputDecoration(
                        hintText: inputHint,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: AppColors.primaryBlue,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 18),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}