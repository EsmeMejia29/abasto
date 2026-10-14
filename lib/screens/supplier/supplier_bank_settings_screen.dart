import 'package:flutter/material.dart';
import '../../main.dart';
import '../../theme/app_theme.dart';
import '../../config/session_manager.dart';

class SupplierBankSettingsScreen extends StatefulWidget {
  const SupplierBankSettingsScreen({super.key});

  @override
  State<SupplierBankSettingsScreen> createState() => _SupplierBankSettingsScreenState();
}

class _SupplierBankSettingsScreenState extends State<SupplierBankSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _holderCtrl = TextEditingController();
  final _docCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();

  String _selectedBank = 'Banco Agrícola';
  String _selectedAccountType = 'Ahorros';
  bool _isLoading = true;
  bool _isSaving = false;

  final List<String> _banks = [
    'Banco Agrícola',
    'BAC Credomatic',
    'Banco Cuscatlán',
    'Davivienda',
    'Banco Promerica',
    'Banco Hipotecario',
    'Banco Azul',
    'Fedecrédito',
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentBankInfo();
  }

  Future<void> _loadCurrentBankInfo() async {
    final userId = supabase.auth.currentUser?.id ?? SessionManager.currentUserId;
    try {
      final res = await supabase
          .from('profiles')
          .select('bank_name, account_type, account_number, account_holder_name, account_holder_document')
          .eq('id', userId)
          .maybeSingle();

      if (res != null) {
        _holderCtrl.text = res['account_holder_name'] ?? '';
        _docCtrl.text = res['account_holder_document'] ?? '';
        _accountNumberCtrl.text = res['account_number'] ?? '';
        if (res['bank_name'] != null && _banks.contains(res['bank_name'])) {
          _selectedBank = res['bank_name'];
        }
        if (res['account_type'] != null) {
          _selectedAccountType = res['account_type'];
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveBankInfo() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final userId = supabase.auth.currentUser?.id ?? SessionManager.currentUserId;

    try {
      await supabase.from('profiles').update({
        'bank_name': _selectedBank,
        'account_type': _selectedAccountType,
        'account_number': _accountNumberCtrl.text.trim(),
        'account_holder_name': _holderCtrl.text.trim(),
        'account_holder_document': _docCtrl.text.trim(),
      }).eq('id', userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cuenta bancaria actualizada exitosamente.'),
            backgroundColor: AppColors.tealMint,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar datos: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración de Cobros y Liquidación'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primaryBlue.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.security, color: AppColors.primaryBlue, size: 24),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Abasto liquida los pedidos pagados directamente a esta cuenta bancaria en las fechas de corte establecidas.',
                              style: TextStyle(fontSize: 12, color: AppColors.navyDark),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Banco
                    const Text('Banco Receptor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _selectedBank,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      items: _banks.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                      onChanged: (val) => setState(() => _selectedBank = val!),
                    ),
                    const SizedBox(height: 16),

                    // Tipo de Cuenta
                    const Text('Tipo de Cuenta', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _selectedAccountType,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Ahorros', child: Text('Cuenta de Ahorros')),
                        DropdownMenuItem(value: 'Corriente', child: Text('Cuenta Corriente')),
                      ],
                      onChanged: (val) => setState(() => _selectedAccountType = val!),
                    ),
                    const SizedBox(height: 16),

                    // Número de cuenta
                    const Text('Número de Cuenta', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _accountNumberCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'Ej. 0000000000',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa el número de cuenta' : null,
                    ),
                    const SizedBox(height: 16),

                    // Titular de la cuenta
                    const Text('Nombre del Titular de la Cuenta', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _holderCtrl,
                      decoration: InputDecoration(
                        hintText: 'Exactamente como aparece en el banco',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa el nombre del titular' : null,
                    ),
                    const SizedBox(height: 16),

                    // DUI / NIT del titular
                    const Text('DUI o NIT del Titular', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _docCtrl,
                      decoration: InputDecoration(
                        hintText: '00000000-0',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa el documento del titular' : null,
                    ),
                    const SizedBox(height: 24),

                    // Botón Guardar
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _isSaving ? null : _saveBankInfo,
                        icon: _isSaving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save_outlined),
                        label: Text(_isSaving ? 'Guardando...' : 'Guardar Información Bancaria',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}