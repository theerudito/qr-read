import 'dart:io';
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR Reader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6C63FF),
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F0F1A),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
      ),
      home: const QrCropScannerPage(),
    );
  }
}

// ─────────────────────────── ENUM DE PASOS ───────────────────────────
enum AppStep { select, crop, result }

class QrCropScannerPage extends StatefulWidget {
  const QrCropScannerPage({super.key});

  @override
  State<QrCropScannerPage> createState() => _QrCropScannerPageState();
}

class _QrCropScannerPageState extends State<QrCropScannerPage>
    with TickerProviderStateMixin {
  // ── Estado principal ──
  final ImagePicker _picker = ImagePicker();
  final CropController _cropController = CropController();

  AppStep _step = AppStep.select;
  Uint8List? _originalImageBytes;
  Uint8List? _croppedImageBytes;

  bool _isCropping = false;
  bool _isScanning = false;

  String? _qrResult;
  String? _errorMessage;

  // ── Animaciones ──
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    // CropController no tiene dispose() en crop_your_image 2.0.0
    _pulseController.dispose();
    super.dispose();
  }

  // ─────────────────────────── LÓGICA ───────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 100,
      );
      if (pickedFile == null) return;

      final Uint8List bytes = await pickedFile.readAsBytes();

      setState(() {
        _originalImageBytes = bytes;
        _croppedImageBytes = null;
        _qrResult = null;
        _errorMessage = null;
        _isCropping = false;
        _isScanning = false;
        _step = AppStep.crop;
      });
    } catch (e) {
      _showError('Error al cargar la imagen: $e');
    }
  }

  void _triggerCrop() {
    if (_originalImageBytes == null) return;
    setState(() {
      _isCropping = true;
      _errorMessage = null;
    });
    _cropController.crop();
  }

  Future<void> _scanQr(Uint8List imageBytes) async {
    setState(() {
      _isScanning = true;
      _errorMessage = null;
      _qrResult = null;
    });

    final BarcodeScanner scanner = BarcodeScanner(
      formats: [BarcodeFormat.qrCode],
    );

    try {
      final Directory tempDir = await getTemporaryDirectory();
      final String filePath =
          '${tempDir.path}/qr_scan_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(filePath).writeAsBytes(imageBytes);

      final InputImage inputImage = InputImage.fromFilePath(filePath);
      final List<Barcode> barcodes = await scanner.processImage(inputImage);

      if (barcodes.isEmpty) {
        setState(() {
          _errorMessage =
              'No se encontró ningún QR en el área seleccionada.\nIntenta ajustar mejor el recorte.';
          _step = AppStep.result;
        });
        return;
      }

      final String? value =
          barcodes.first.rawValue ?? barcodes.first.displayValue;
      setState(() {
        _qrResult = value ?? 'QR leído, pero sin contenido de texto.';
        _step = AppStep.result;
      });
    } catch (e) {
      _showError('Error al leer el QR: $e');
      setState(() => _step = AppStep.result);
    } finally {
      await scanner.close();
      if (mounted) {
        setState(() {
          _isScanning = false;
          _isCropping = false;
        });
      }
    }
  }

  void _showError(String msg) {
    setState(() => _errorMessage = msg);
  }

  void _reset() {
    setState(() {
      _originalImageBytes = null;
      _croppedImageBytes = null;
      _qrResult = null;
      _errorMessage = null;
      _isCropping = false;
      _isScanning = false;
      _step = AppStep.select;
    });
  }

  void _backToCrop() {
    setState(() {
      _step = AppStep.crop;
      _croppedImageBytes = null;
      _qrResult = null;
      _errorMessage = null;
    });
  }

  // ─────────────────────────── BUILD PRINCIPAL ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Reader'),
        leading: _step != AppStep.select
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: _step == AppStep.result ? _backToCrop : _reset,
              )
            : null,
        actions: [
          if (_step != AppStep.select)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Empezar de nuevo',
              onPressed: _reset,
            ),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: switch (_step) {
            AppStep.select => _SelectPage(
              key: const ValueKey('select'),
              onCamera: () => _pickImage(ImageSource.camera),
              onGallery: () => _pickImage(ImageSource.gallery),
            ),
            AppStep.crop => _CropPage(
              key: const ValueKey('crop'),
              imageBytes: _originalImageBytes!,
              cropController: _cropController,
              isCropping: _isCropping,
              onCrop: _triggerCrop,
              onCropped: (Uint8List cropped) {
                setState(() => _croppedImageBytes = cropped);
                _scanQr(cropped);
              },
              onError: (String err) {
                _showError('Error al recortar: $err');
                setState(() {
                  _isCropping = false;
                  _step = AppStep.result;
                });
              },
            ),
            AppStep.result => _ResultPage(
              key: const ValueKey('result'),
              croppedImageBytes: _croppedImageBytes,
              isScanning: _isScanning,
              qrResult: _qrResult,
              errorMessage: _errorMessage,
              onRetry: _backToCrop,
              onReset: _reset,
              pulseAnim: _pulseAnim,
            ),
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════ PÁGINA 1: SELECCIÓN ═══════════════════════════

class _SelectPage extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  const _SelectPage({
    super.key,
    required this.onCamera,
    required this.onGallery,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          // ── Header ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF9C27B0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Colors.white,
                  size: 48,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Escanea tu QR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Toma una foto o selecciona de la galería,\nrecorta el área del QR y obtén el resultado.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          const Text(
            'Elige una imagen',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),

          // ── Botón Cámara ──
          _BigOptionButton(
            icon: Icons.camera_alt_rounded,
            label: 'Tomar foto',
            subtitle: 'Usa la cámara del dispositivo',
            gradient: const LinearGradient(
              colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
            ),
            accentColor: const Color(0xFF6C63FF),
            onTap: onCamera,
          ),
          const SizedBox(height: 14),

          // ── Botón Galería ──
          _BigOptionButton(
            icon: Icons.photo_library_rounded,
            label: 'Abrir galería',
            subtitle: 'Elige una imagen guardada',
            gradient: const LinearGradient(
              colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
            ),
            accentColor: const Color(0xFF9C27B0),
            onTap: onGallery,
          ),
        ],
      ),
    );
  }
}

class _BigOptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final LinearGradient gradient;
  final Color accentColor;
  final VoidCallback onTap;

  const _BigOptionButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.gradient,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        splashColor: accentColor.withValues(alpha: 0.2),
        child: Ink(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: accentColor, size: 28),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Icon(
                  Icons.chevron_right_rounded,
                  color: accentColor.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════ PÁGINA 2: RECORTE ═══════════════════════════

class _CropPage extends StatelessWidget {
  final Uint8List imageBytes;
  final CropController cropController;
  final bool isCropping;
  final VoidCallback onCrop;
  final ValueChanged<Uint8List> onCropped;
  final ValueChanged<String> onError;

  const _CropPage({
    super.key,
    required this.imageBytes,
    required this.cropController,
    required this.isCropping,
    required this.onCrop,
    required this.onCropped,
    required this.onError,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Instrucción ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.touch_app_rounded,
                      color: Color(0xFF6C63FF),
                      size: 16,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Selecciona el área del QR',
                      style: TextStyle(
                        color: Color(0xFF6C63FF),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── Área de recorte ──
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Crop(
                image: imageBytes,
                controller: cropController,
                interactive: true,
                radius: 8,
                baseColor: Colors.black,
                maskColor: Colors.black.withValues(alpha: 0.6),
                progressIndicator: const Center(
                  child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
                ),
                onCropped: (CropResult result) {
                  if (result is CropSuccess) {
                    onCropped(result.croppedImage);
                  } else if (result is CropFailure) {
                    onError(result.cause.toString());
                  }
                },
              ),
            ),
          ),
        ),

        // ── Botón de recortar ──
        Padding(
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: isCropping
                ? Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Color(0xFF6C63FF),
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Recortando y escaneando...',
                            style: TextStyle(
                              color: Color(0xFF6C63FF),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6C63FF), Color(0xFF9C27B0)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: onCrop,
                      icon: const Icon(
                        Icons.qr_code_scanner_rounded,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Recortar y leer QR',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════ PÁGINA 3: RESULTADO ═══════════════════════════

class _ResultPage extends StatelessWidget {
  final Uint8List? croppedImageBytes;
  final bool isScanning;
  final String? qrResult;
  final String? errorMessage;
  final VoidCallback onRetry;
  final VoidCallback onReset;
  final Animation<double> pulseAnim;

  const _ResultPage({
    super.key,
    required this.croppedImageBytes,
    required this.isScanning,
    required this.qrResult,
    required this.errorMessage,
    required this.onRetry,
    required this.onReset,
    required this.pulseAnim,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── Imagen recortada ──
        if (croppedImageBytes != null) ...[
          const Text(
            'Área escaneada',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
              ),
              color: Colors.black,
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.memory(croppedImageBytes!, fit: BoxFit.contain),
          ),
          const SizedBox(height: 24),
        ],

        // ── Estado: escaneando ──
        if (isScanning) _buildScanning(),

        // ── Error ──
        if (!isScanning && errorMessage != null)
          _buildError(context, errorMessage!),

        // ── Resultado exitoso ──
        if (!isScanning && qrResult != null) _buildSuccess(context, qrResult!),

        const SizedBox(height: 28),

        // ── Botones de acción ──
        if (!isScanning) ...[
          _ActionButton(
            label: 'Recortar de nuevo',
            icon: Icons.crop_rounded,
            onTap: onRetry,
            color: const Color(0xFF6C63FF),
          ),
          const SizedBox(height: 12),
          _ActionButton(
            label: 'Nueva imagen',
            icon: Icons.add_photo_alternate_rounded,
            onTap: onReset,
            color: Colors.white24,
            textColor: Colors.white70,
          ),
        ],
      ],
    );
  }

  Widget _buildScanning() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 20),
          ScaleTransition(
            scale: pulseAnim,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF).withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
                  width: 2,
                ),
              ),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF6C63FF),
                  strokeWidth: 3,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Leyendo código QR...',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, String message) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1020),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.qr_code_2_rounded,
            color: Colors.redAccent,
            size: 48,
          ),
          const SizedBox(height: 12),
          const Text(
            'No se pudo leer el QR',
            style: TextStyle(
              color: Colors.redAccent,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.red.shade200,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(BuildContext context, String result) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D2818), Color(0xFF0F3020)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.greenAccent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'QR detectado',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white12),
          const SizedBox(height: 12),
          SelectableText(
            result,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              height: 1.6,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.greenAccent,
                side: BorderSide(
                  color: Colors.greenAccent.withValues(alpha: 0.4),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: result));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Icon(Icons.copy_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text('Copiado al portapapeles'),
                      ],
                    ),
                    backgroundColor: const Color(0xFF1A1A2E),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copiar contenido'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final Color textColor;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.color,
    this.textColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
