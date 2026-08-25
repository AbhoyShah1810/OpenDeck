import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/ble/ble_manager.dart';
import '../../core/protocol/schema.dart';

/// Out-of-band PIN handshake screen.
/// Displayed after BLE connection is established with an unknown device.
/// The user must type the 4-digit PIN shown on the desktop tray menu.
class PinEntryScreen extends StatefulWidget {
  final BleManager bleManager;
  final String deviceName;

  const PinEntryScreen({
    super.key,
    required this.bleManager,
    required this.deviceName,
  });

  /// Push and await the result. Returns true if authentication succeeded.
  static Future<bool> show(
    BuildContext context, {
    required BleManager bleManager,
    required String deviceName,
  }) async {
    final result = await Navigator.push<bool>(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => PinEntryScreen(
          bleManager: bleManager,
          deviceName: deviceName,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          );
        },
      ),
    );
    return result ?? false;
  }

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen>
    with TickerProviderStateMixin {
  final List<String> _digits = ['', '', '', ''];
  int _focusedIndex = 0;

  bool _isSubmitting = false;
  bool _hasError = false;
  String _errorMessage = '';

  StreamSubscription<TelemetryPayload>? _telemetrySub;
  StreamSubscription<BleConnectionStatus>? _statusSub;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  late AnimationController _successController;

  @override
  void initState() {
    super.initState();

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticOut),
    );

    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _statusSub = widget.bleManager.statusStream.listen((status) {
      if (status == BleConnectionStatus.disconnected && mounted) {
        Navigator.of(context).pop(false);
      }
    });

    _telemetrySub = widget.bleManager.telemetryStream.listen((telemetry) {
      if (!mounted) return;
      if (telemetry.status == 'AUTH_OK') {
        _handleAuthSuccess();
      } else if (telemetry.status == 'AUTH_FAIL') {
        _handleAuthFailure('Incorrect PIN. Please try again.');
      }
    });
  }

  @override
  void dispose() {
    _telemetrySub?.cancel();
    _statusSub?.cancel();
    _shakeController.dispose();
    _successController.dispose();
    super.dispose();
  }

  void _onDigitInput(String digit) {
    if (_focusedIndex >= 4 || _isSubmitting) return;
    HapticFeedback.selectionClick();
    setState(() {
      _digits[_focusedIndex] = digit;
      _hasError = false;
      if (_focusedIndex < 3) _focusedIndex++;
    });
    if (_digits.every((d) => d.isNotEmpty)) {
      _submitPin();
    }
  }

  void _onBackspace() {
    if (_isSubmitting) return;
    HapticFeedback.selectionClick();
    setState(() {
      _hasError = false;
      if (_digits[_focusedIndex].isNotEmpty) {
        _digits[_focusedIndex] = '';
      } else if (_focusedIndex > 0) {
        _focusedIndex--;
        _digits[_focusedIndex] = '';
      }
    });
  }

  void _onDigitTap(int index) {
    setState(() => _focusedIndex = index);
  }

  Future<void> _submitPin() async {
    final pin = _digits.join();
    if (pin.length < 4) return;

    setState(() {
      _isSubmitting = true;
      _hasError = false;
    });

    try {
      final clientId = _buildClientId();
      final handshake = HandshakePayload(
        clientId: clientId,
        clientPublicKey: _generatePublicKey(clientId),
        authCode: pin,
      );
      await widget.bleManager.sendAuthPayload(handshake);

      // Fallback timeout — in case desktop is unresponsive
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted && _isSubmitting) {
          _handleAuthFailure('No response from desktop. Please retry.');
        }
      });
    } catch (e) {
      _handleAuthFailure('Failed to send PIN: $e');
    }
  }

  void _handleAuthSuccess() async {
    HapticFeedback.heavyImpact();
    await _successController.forward();
    if (mounted) Navigator.of(context).pop(true);
  }

  void _handleAuthFailure(String message) {
    HapticFeedback.vibrate();
    _shakeController.reset();
    _shakeController.forward();
    setState(() {
      _isSubmitting = false;
      _hasError = true;
      _errorMessage = message;
      for (int i = 0; i < _digits.length; i++) {
        _digits[i] = '';
      }
      _focusedIndex = 0;
    });
  }

  String _buildClientId() {
    final platform = Platform.isIOS ? 'ios' : 'android';
    return 'opendeck-$platform-${DateTime.now().millisecondsSinceEpoch}';
  }

  String _generatePublicKey(String clientId) {
    return 'pk-${clientId.hashCode.abs()}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
            _buildNumpad(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A24),
        border: Border(
          bottom: BorderSide(color: Color(0xFF2A2A36), width: 1),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(false),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pair Device',
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                widget.deviceName,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          children: [
            const SizedBox(height: 40),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.lock_rounded,
                color: Colors.white,
                size: 38,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Enter Pairing PIN',
              style: GoogleFonts.inter(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Check your desktop system tray for the\n4-digit PIN displayed by OpenDeck.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: const Color(0xFF94A3B8),
                height: 1.6,
              ),
            ),
            const SizedBox(height: 40),
            AnimatedBuilder(
              animation: _shakeAnimation,
              builder: (context, child) {
                final progress = _shakeAnimation.value;
                final dx = _hasError
                    ? 14 * (progress < 0.5
                          ? progress * 2
                          : (1 - progress) * 2) *
                        ((progress * 6).round().isEven ? 1 : -1)
                    : 0.0;
                return Transform.translate(
                  offset: Offset(dx, 0),
                  child: child,
                );
              },
              child: _buildPinBoxes(),
            ),
            const SizedBox(height: 16),
            AnimatedOpacity(
              opacity: _hasError ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 16,
                      color: Color(0xFFEF4444),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _errorMessage.isEmpty ? ' ' : _errorMessage,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: const Color(0xFFEF4444),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            AnimatedOpacity(
              opacity: _isSubmitting ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Verifying with desktop...',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinBoxes() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final isFilled = _digits[i].isNotEmpty;
        final isFocused = _focusedIndex == i && !_isSubmitting;

        return GestureDetector(
          onTap: () => _onDigitTap(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: 64,
            height: 72,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: _hasError
                  ? const Color(0xFFEF4444).withValues(alpha: 0.1)
                  : isFilled
                      ? const Color(0xFF6366F1).withValues(alpha: 0.12)
                      : const Color(0xFF1A1A24),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _hasError
                    ? const Color(0xFFEF4444).withValues(alpha: 0.6)
                    : isFocused
                        ? const Color(0xFF6366F1)
                        : isFilled
                            ? const Color(0xFF6366F1).withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.1),
                width: isFocused ? 2 : 1,
              ),
              boxShadow: isFocused
                  ? [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: isFilled
                ? Text(
                    '•',
                    style: GoogleFonts.inter(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: _hasError
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF6366F1),
                    ),
                  )
                : isFocused
                    ? Container(
                        width: 2,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      )
                    : null,
          ),
        );
      }),
    );
  }

  Widget _buildNumpad() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          for (final row in [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: row
                    .map((d) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: _buildNumpadKey(d),
                          ),
                        ))
                    .toList(),
              ),
            ),
          Row(
            children: [
              const Expanded(child: SizedBox()),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _buildNumpadKey('0'),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _buildBackspaceKey(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNumpadKey(String digit) {
    return GestureDetector(
      onTap: () => _onDigitInput(digit),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A24),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        alignment: Alignment.center,
        child: Text(
          digit,
          style: GoogleFonts.inter(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceKey() {
    return GestureDetector(
      onTap: _onBackspace,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A24),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.backspace_outlined,
          color: Color(0xFF94A3B8),
          size: 22,
        ),
      ),
    );
  }
}
