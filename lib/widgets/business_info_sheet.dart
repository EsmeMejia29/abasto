import 'package:flutter/material.dart';
import '../../main.dart';
import '../../theme/app_theme.dart';

class BusinessInfoSheet extends StatefulWidget {
  final String businessId;
  final String defaultName;
  final String role; // 'supplier' o 'restaurant'

  const BusinessInfoSheet({
    super.key,
    required this.businessId,
    required this.defaultName,
    required this.role,
  });

  static void show(BuildContext context, {
    required String businessId,
    required String defaultName,
    required String role,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => BusinessInfoSheet(
        businessId: businessId,
        defaultName: defaultName,
        role: role,
      ),
    );
  }

  @override
  State<BusinessInfoSheet> createState() => _BusinessInfoSheetState();
}

class _BusinessInfoSheetState extends State<BusinessInfoSheet> {
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _reviews = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final bid = widget.businessId.toString();

      // 1. Perfil
      final p = await supabase
          .from('profiles')
          .select('*')
          .eq('id', bid)
          .maybeSingle();

      // 2. Traer reseñas dirigidas a este negocio
      final r = await supabase
          .from('reviews')
          .select('*')
          .or('target_id.eq.$bid,restaurant_id.eq.$bid,supplier_id.eq.$bid')
          .order('created_at', ascending: false);

      final list = (r as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList();

      if (mounted) {
        setState(() {
          _profile = p;
          _reviews = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando BusinessInfoSheet: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final p = _profile ?? {};
    final name = p['business_name'] ?? widget.defaultName;
    final address = p['address'] ?? 'Dirección no especificada';
    final phone = p['phone'] ?? 'No registrado';
    final website = p['website'] ?? '';
    final nrcNit = p['nrc_nit'] ?? 'En trámite de registro';
    final hours = p['business_hours'] ?? 'Lunes a Sábado: 7:00 AM - 5:00 PM';
    final avatarUrl = p['avatar_url'];
    final rating = (p['rating'] as num?)?.toDouble() ?? 5.0;
    final reviewsCount = (p['reviews_count'] as num?)?.toInt() ?? _reviews.length;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollCtrl) => SingleChildScrollView(
        controller: scrollCtrl,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.primaryBlue.withOpacity(0.12),
                  backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: (avatarUrl == null || avatarUrl.isEmpty)
                      ? Text(
                          name.isNotEmpty ? name[0].toUpperCase() : 'B',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryBlue,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.navyDark,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.verified, color: AppColors.tealMint, size: 18),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            '$rating ($reviewsCount reseñas)',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 10),
            const Text(
              'Información Legal y Contacto',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.navyDark,
              ),
            ),
            const SizedBox(height: 12),
            _buildInfoTile(Icons.badge_outlined, 'NRC / NIT Comercial', nrcNit),
            _buildInfoTile(Icons.phone_outlined, 'Teléfono / WhatsApp', phone),
            _buildInfoTile(Icons.location_on_outlined, 'Dirección Física', address),
            if (website.isNotEmpty)
              _buildInfoTile(Icons.language_outlined, 'Página Web / Red', website, isLink: true),
            _buildInfoTile(Icons.access_time_outlined, 'Horario de Atención', hours),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 10),
            Text(
              'Opiniones y Reseñas (${_reviews.length})',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.navyDark,
              ),
            ),
            const SizedBox(height: 10),
            if (_reviews.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Este negocio aún no tiene comentarios públicos.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              )
            else
              ..._reviews.map((rev) {
                final rRating = (rev['rating'] as num?)?.toDouble() ?? 5.0;
                final rAuthor = rev['author_name'] ?? 'Usuario Verificado';
                final rComment = rev['comment'] ?? '';

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(rAuthor, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Row(
                            children: List.generate(5, (sIdx) {
                              return Icon(
                                sIdx < rRating ? Icons.star : Icons.star_border,
                                color: Colors.amber,
                                size: 14,
                              );
                            }),
                          ),
                        ],
                      ),
                      if (rComment.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(rComment, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                      ],
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String value, {bool isLink = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primaryBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 11, color: AppColors.subtitleGrey)),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isLink ? AppColors.primaryBlue : Colors.black87,
                    decoration: isLink ? TextDecoration.underline : TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}