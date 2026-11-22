import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class TutorialCoachTooltip extends StatefulWidget {
  final GlobalKey targetKey;
  final String storageKey;

  const TutorialCoachTooltip({
    super.key,
    required this.targetKey,
    required this.storageKey,
  });

  @override
  State<TutorialCoachTooltip> createState() => _TutorialCoachTooltipState();
}

class _TutorialCoachTooltipState extends State<TutorialCoachTooltip> {
  bool _visible = false;
  Rect? _targetRect;

  @override
  void initState() {
    super.initState();
    final alreadySeen = html.window.localStorage[widget.storageKey] == 'true';
    if (!alreadySeen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureTarget());
    }
  }

  void _measureTarget() {
    if (!mounted) return;
    final ctx = widget.targetKey.currentContext;
    if (ctx == null) {
      Future.delayed(const Duration(milliseconds: 250), _measureTarget);
      return;
    }
    final box = ctx.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final offset = box.localToGlobal(Offset.zero);
      setState(() {
        _targetRect = offset & box.size;
        _visible = true;
      });
    }
  }

  void _dismiss() {
    html.window.localStorage[widget.storageKey] = 'true';
    setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible || _targetRect == null) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    const double bubbleWidth = 260;
    final double targetCenterX = _targetRect!.center.dx;

    // Mantener el globo dentro de los márgenes de pantalla
    final double left = (targetCenterX - bubbleWidth + 28)
        .clamp(12.0, screenWidth - bubbleWidth - 12.0);
    final double top = _targetRect!.bottom + 8;
    final double arrowLeftInBubble =
        (targetCenterX - left - 8).clamp(18.0, bubbleWidth - 30.0);

    return Positioned.fill(
      child: Stack(
        children: [
          // Fondo sutil tocable para cerrar
          GestureDetector(
            onTap: _dismiss,
            behavior: HitTestBehavior.translucent,
            child: Container(color: Colors.black.withOpacity(0.18)),
          ),
          Positioned(
            left: left,
            top: top,
            width: bubbleWidth,
            child: Material(
              color: Colors.transparent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Flecha apuntando al botón Tutorial de arriba
                  Padding(
                    padding: EdgeInsets.only(left: arrowLeftInBubble),
                    child: CustomPaint(
                      size: const Size(16, 9),
                      painter: _UpArrowPainter(color: const Color(0xFF001A2C)),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF001A2C),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.tealMint, width: 1.4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.help_outline_rounded,
                                color: AppColors.tealMint, size: 17),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '¿Necesitas ayuda?',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Mira un tutorial aquí arriba para aprender a usar todas las funciones rápido.',
                          style: TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.tealMint,
                              foregroundColor: const Color(0xFF001A2C),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: _dismiss,
                            child: const Text(
                              'Entendido',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
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
        ],
      ),
    );
  }
}

class _UpArrowPainter extends CustomPainter {
  final Color color;
  const _UpArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}