import 'package:flutter/material.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../config/session_manager.dart';

class ReviewDialog extends StatefulWidget {
  final String targetId;
  final String targetName;
  final String targetRole; // 'supplier' o 'restaurant'
  final String? orderId;

  const ReviewDialog({
    super.key,
    required this.targetId,
    required this.targetName,
    required this.targetRole,
    this.orderId,
  });

  @override
  State<ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<ReviewDialog> {
  int _selectedRating = 5;
  final TextEditingController _commentCtrl = TextEditingController();
  bool _isLoadingInitial = true;
  bool _isSending = false;
  String? _existingReviewId;

  String get _currentUserId =>
      supabase.auth.currentUser?.id ?? SessionManager.currentUserId;

  @override
  void initState() {
    super.initState();
    _fetchExistingReview();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchExistingReview() async {
    try {
      final myId = _currentUserId;

      // Buscamos si ya existe una reseña hecha por este autor para esta orden o para este destinatario
      var query = supabase
          .from('reviews')
          .select('id, rating, comment, order_id, target_id')
          .eq('author_id', myId);

      if (widget.orderId != null && widget.orderId!.isNotEmpty) {
        query = query.eq('order_id', widget.orderId!);
      } else {
        query = query.eq('target_id', widget.targetId);
      }

      final resList = await query.limit(1);

      if (resList.isNotEmpty && mounted) {
        final res = resList.first as Map<String, dynamic>;
        setState(() {
          _existingReviewId = res['id']?.toString();
          _selectedRating = (res['rating'] as num?)?.toInt() ?? 5;
          _commentCtrl.text = res['comment']?.toString() ?? '';
        });
      }
    } catch (e) {
      debugPrint('Error buscando reseña previa: $e');
    } finally {
      if (mounted) setState(() => _isLoadingInitial = false);
    }
  }

  Future<void> _submitReview() async {
    setState(() => _isSending = true);

    try {
      final myId = _currentUserId;

      // Obtener el nombre comercial del autor
      String authorName = 'Usuario Abasto';
      try {
        final profile = await supabase
            .from('profiles')
            .select('business_name')
            .eq('id', myId)
            .maybeSingle();
        if (profile != null && profile['business_name'] != null) {
          authorName = profile['business_name'];
        }
      } catch (_) {}

      final String restaurantId =
          widget.targetRole == 'restaurant' ? widget.targetId : myId;
      final String supplierId =
          widget.targetRole == 'supplier' ? widget.targetId : myId;

      final reviewPayload = {
        if (_existingReviewId != null) 'id': _existingReviewId,
        if (widget.orderId != null) 'order_id': widget.orderId,
        'restaurant_id': restaurantId,
        'supplier_id': supplierId,
        'author_id': myId,
        'author_name': authorName,
        'target_id': widget.targetId,
        'target_role': widget.targetRole,
        'rating': _selectedRating,
        'comment': _commentCtrl.text.trim(),
      };

      // Si ya existía se actualiza con su id, sino se inserta
      if (_existingReviewId != null) {
        await supabase
            .from('reviews')
            .update(reviewPayload)
            .eq('id', _existingReviewId!);
      } else {
        await supabase.from('reviews').insert(reviewPayload);
      }

      // Recalcular estadísticas del negocio calificado
      try {
        final allTargetReviews = await supabase
            .from('reviews')
            .select('rating')
            .eq('target_id', widget.targetId)
            .neq('author_id', widget.targetId);

        final list = allTargetReviews as List<dynamic>;
        final count = list.length;
        final sum = list.fold<double>(
            0.0,
            (acc, curr) =>
                acc + ((curr['rating'] as num?)?.toDouble() ?? 5.0));
        final avg = count > 0 ? (sum / count) : _selectedRating.toDouble();
        final finalRating = double.parse(avg.toStringAsFixed(1));

        await supabase.from('profiles').update({
          'rating': finalRating,
          'reviews_count': count,
        }).eq('id', widget.targetId);

        if (widget.targetRole == 'supplier') {
          await supabase.from('supplier_details').update({
            'rating': finalRating,
            'reviews_count': count,
          }).eq('profile_id', widget.targetId);
        }
      } catch (_) {}

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_existingReviewId != null
                ? '¡Reseña actualizada con éxito!'
                : '¡Reseña publicada con éxito!'),
            backgroundColor: AppColors.tealMint,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al procesar reseña: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = _existingReviewId != null;

    return AlertDialog(
      title: Text(isEditing
          ? 'Tu calificación a ${widget.targetName}'
          : 'Calificar a ${widget.targetName}'),
      content: _isLoadingInitial
          ? const SizedBox(
              height: 140,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    isEditing
                        ? 'Puedes modificar tu puntuación o comentario:'
                        : '¿Cómo calificarías el servicio y puntualidad?',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.subtitleGrey),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final starNum = index + 1;
                      return IconButton(
                        iconSize: 32,
                        icon: Icon(
                          starNum <= _selectedRating
                              ? Icons.star
                              : Icons.star_border,
                          color: Colors.amber,
                        ),
                        onPressed: () {
                          setState(() => _selectedRating = starNum);
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _commentCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText:
                          'Escribe un comentario sobre la experiencia (opcional)...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        if (!_isLoadingInitial)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue),
            onPressed: _isSending ? null : _submitReview,
            child: _isSending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(isEditing ? 'Actualizar' : 'Publicar',
                    style: const TextStyle(color: Colors.white)),
          ),
      ],
    );
  }
}