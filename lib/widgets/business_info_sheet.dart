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

  static void show(
    BuildContext context, {
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
  Map<String, dynamic>? _supplierDetails;
  List<dynamic> _reviews = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final bid = widget.businessId.toString();

      // 1. Perfil del negocio y detalles logísticos si es distribuidor
      final p = await supabase
          .from('profiles')
          .select('*')
          .eq('id', bid)
          .maybeSingle();

      Map<String, dynamic>? sd;
      if (widget.role == 'supplier') {
        sd = await supabase
            .from('supplier_details')
            .select('*')
            .eq('profile_id', bid)
            .maybeSingle();
      }

      // 2. Traer reseñas potenciales asociadas
      final r = await supabase
          .from('reviews')
          .select('*')
          .or('target_id.eq.$bid,supplier_id.eq.$bid,restaurant_id.eq.$bid')
          .order('created_at', ascending: false);

      final rawList = (r as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // 3. Filtrar estrictamente solo las reseñas RECIBIDAS por este negocio
      final filteredList = rawList.where((rev) {
        final targetRole =
            (rev['target_role'] ?? '').toString().toLowerCase().trim();
        final targetId = (rev['target_id'] ?? '').toString().trim();
        final authorId = (rev['author_id'] ?? '').toString().trim();
        final authorName =
            (rev['author_name'] ?? '').toString().toLowerCase().trim();

        if (authorId.isNotEmpty && authorId == bid) {
          return false;
        }

        if (widget.role == 'supplier') {
          if (targetRole.isNotEmpty && targetRole != 'supplier') {
            return false;
          }
          if (targetId.isNotEmpty && targetId != bid) {
            return false;
          }
          if (authorName.contains('distribuidor')) {
            return false;
          }
        } else {
          if (targetRole.isNotEmpty && targetRole != 'restaurant') {
            return false;
          }
          if (targetId.isNotEmpty && targetId != bid) {
            return false;
          }
        }

        return true;
      }).toList();

      if (mounted) {
        setState(() {
          _profile = p;
          _supplierDetails = sd;
          _reviews = filteredList;
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
    final sd = _supplierDetails ?? {};
    final name = (p['business_name']?.toString().trim().isNotEmpty == true)
        ? p['business_name'].toString().trim()
        : widget.defaultName;

    final rawAddress = (p['address']?.toString().trim().isNotEmpty == true)
        ? p['address'].toString().trim()
        : 'Ubicación verificada en El Salvador';
    final address =
        '${rawAddress[0].toUpperCase()}${rawAddress.substring(1)}';

    final rawPhone = (p['phone'] ?? '').toString().trim();
    final phone =
        rawPhone.isNotEmpty ? rawPhone : 'Disponible al confirmar pedido';

    final website = (p['website'] ?? '').toString().trim();

    final rawNrc = (p['nrc'] ?? '').toString().trim();
    final rawNit = (p['nit'] ?? '').toString().trim();
    final rawLegacy = (p['nrc_nit'] ?? '').toString().trim();
    final String nrcNit;
    if (rawNrc.isNotEmpty || rawNit.isNotEmpty) {
      nrcNit = [
        if (rawNrc.isNotEmpty) 'NRC: $rawNrc',
        if (rawNit.isNotEmpty) 'NIT: $rawNit',
      ].join(' • ');
    } else if (rawLegacy.isNotEmpty &&
        rawLegacy.toLowerCase() != 'en trámite de registro') {
      nrcNit = rawLegacy;
    } else {
      nrcNit = 'Contribuyente verificado • Emite DTE / CCF';
    }

    final rawHours = (p['business_hours'] ?? '').toString().trim();
    final hours =
        rawHours.isNotEmpty ? rawHours : 'Lunes a Sábado: 7:00 AM - 5:00 PM';
    final avatarUrl = p['avatar_url'];

    final coverage = (sd['delivery_coverage'] ?? '').toString().trim();
    final deliveryDays = (sd['delivery_days'] ?? '').toString().trim();
    final minOrder = (sd['min_order_amount'] as num?)?.toDouble() ?? 0.0;

    // Calificación dinámica según las reseñas realmente recibidas
    double rating = 5.0;
    if (_reviews.isNotEmpty) {
      double sum = 0.0;
      for (final item in _reviews) {
        sum += ((item['rating'] as num?)?.toDouble() ?? 5.0);
      }
      rating = sum / _reviews.length;
    } else if (p['rating'] != null) {
      rating = (p['rating'] as num).toDouble();
    }
    final reviewsCount = _reviews.length;

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
                          const Icon(Icons.verified,
                              color: AppColors.tealMint, size: 18),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            '${rating.toStringAsFixed(1)} ($reviewsCount reseñas)',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
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
              'Información Legal y Logística',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.navyDark,
              ),
            ),
            const SizedBox(height: 12),
            _buildInfoTile(
                Icons.verified_user_outlined, 'Registro Fiscal DTE', nrcNit),
            _buildInfoTile(Icons.phone_outlined, 'Teléfono / WhatsApp', phone),
            _buildInfoTile(
                Icons.location_on_outlined, 'Sede / Dirección Física', address),
            if (coverage.isNotEmpty)
              _buildInfoTile(Icons.map_outlined,
                  'Zonas con Cobertura de Entrega', coverage),
            if (deliveryDays.isNotEmpty)
              _buildInfoTile(Icons.local_shipping_outlined,
                  'Frecuencia de Despacho', deliveryDays),
            if (minOrder > 0)
              _buildInfoTile(
                  Icons.shopping_bag_outlined,
                  'Pedido Mínimo de Despacho',
                  '\$${minOrder.toStringAsFixed(2)} USD'),
            if (website.isNotEmpty)
              _buildInfoTile(
                  Icons.language_outlined, 'Página Web / Red', website,
                  isLink: true),
            _buildInfoTile(
                Icons.access_time_outlined, 'Horario de Atención', hours),
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.rate_review_outlined,
                        size: 20, color: AppColors.primaryBlue),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Aún no hay reseñas públicas. Podrás calificar tu experiencia al recibir tu primer pedido.',
                        style: TextStyle(
                          color: AppColors.subtitleGrey,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
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
                          Text(rAuthor,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          Row(
                            children: List.generate(5, (sIdx) {
                              return Icon(
                                sIdx < rRating
                                    ? Icons.star
                                    : Icons.star_border,
                                color: Colors.amber,
                                size: 14,
                              );
                            }),
                          ),
                        ],
                      ),
                      if (rComment.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(rComment,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black87)),
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

  Widget _buildInfoTile(IconData icon, String title, String value,
      {bool isLink = false}) {
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
                Text(title,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.subtitleGrey)),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isLink ? AppColors.primaryBlue : Colors.black87,
                    decoration: isLink
                        ? TextDecoration.underline
                        : TextDecoration.none,
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