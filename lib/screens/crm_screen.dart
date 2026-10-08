import 'package:flutter/material.dart';
import '../main.dart';
import '../theme/app_theme.dart';

class CrmScreen extends StatefulWidget {
  const CrmScreen({super.key});

  @override
  State<CrmScreen> createState() => _CrmScreenState();
}

class _CrmScreenState extends State<CrmScreen> {
  late Future<List<Map<String, dynamic>>> _crmContactsFuture;

  @override
  void initState() {
    super.initState();
    _crmContactsFuture = _fetchCrmContacts();
  }

  Future<List<Map<String, dynamic>>> _fetchCrmContacts() async {
    final response = await supabase
        .from('restaurant_crm_contacts')
        .select('*')
        .order('last_interaction', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> _showAddNoteDialog(Map<String, dynamic> contact) async {
    final controller = TextEditingController(text: contact['internal_notes'] ?? '');

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Nota sobre ${contact['supplier_name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Anota detalles de acuerdos, calidad recibida o requerimientos de entrega:',
              style: TextStyle(fontSize: 12, color: AppColors.subtitleGrey),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Ej. Llega temprano los miércoles. Pedir que traigan factura con CCF.',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
            onPressed: () async {
              await supabase
                  .from('restaurant_crm_contacts')
                  .update({'internal_notes': controller.text})
                  .eq('id', contact['id']);

              if (mounted) {
                Navigator.pop(context);
                setState(() {
                  _crmContactsFuture = _fetchCrmContacts();
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Nota actualizada en tu CRM')),
                );
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CRM de Proveedores'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _crmContactsFuture = _fetchCrmContacts();
              });
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _crmContactsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final contacts = snapshot.data ?? [];
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Resumen del directorio CRM
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: AppColors.logoGradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryBlue.withOpacity(0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.contacts, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Directorio y Gestión de Insumos',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${contacts.length} proveedores habituales registrados para tu restaurante',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                const Text(
                  'Mis Proveedores Habituales',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.navyDark),
                ),
                const SizedBox(height: 10),

                if (contacts.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    alignment: Alignment.center,
                    child: const Text('Aún no has registrado proveedores en tu libreta CRM.'),
                  )
                else
                  ...contacts.map((c) {
                    final notes = c['internal_notes'] ?? 'Sin notas guardadas.';
                    final phone = c['contact_phone'] ?? 'Sin teléfono';
                    final category = c['category'] ?? 'General';

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 1.5,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    c['supplier_name'],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: AppColors.navyDark,
                                    ),
                                  ),
                                ),
                                Chip(
                                  label: Text(category, style: const TextStyle(fontSize: 11, color: AppColors.primaryBlue)),
                                  backgroundColor: AppColors.tealMint.withOpacity(0.15),
                                  padding: EdgeInsets.zero,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.phone, size: 14, color: AppColors.subtitleGrey),
                                const SizedBox(width: 6),
                                Text(phone, style: const TextStyle(fontSize: 13, color: AppColors.subtitleGrey)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Caja de Notas Internas de Negocio
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Bitácora / Notas Internas:',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.subtitleGrey),
                                      ),
                                      InkWell(
                                        onTap: () => _showAddNoteDialog(c),
                                        child: const Text(
                                          'Editar nota',
                                          style: TextStyle(fontSize: 11, color: AppColors.primaryBlue, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    notes,
                                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }
}