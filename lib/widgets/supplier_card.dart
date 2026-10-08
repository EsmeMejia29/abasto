import 'package:flutter/material.dart';
import '../models/supplier.dart';
import '../screens/supplier_detail_screen.dart';

class SupplierCard extends StatelessWidget {
  final Supplier supplier;

  const SupplierCard({super.key, required this.supplier});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SupplierDetailScreen(supplier: supplier),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      supplier.name,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star, size: 16, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          '${supplier.rating} (${supplier.reviewsCount})',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                supplier.category,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.local_shipping_outlined, size: 16, color: Colors.blueGrey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Ruta: ${supplier.deliveryDays}',
                      style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                    ),
                  ),
                ],
              ),
              if (supplier.offersFinancing) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.teal.shade300),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.credit_score, size: 14, color: Colors.teal),
                      SizedBox(width: 4),
                      Text(
                        'Admite Financiamiento Abasto (Cuotas)',
                        style: TextStyle(fontSize: 11, color: Colors.teal, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}