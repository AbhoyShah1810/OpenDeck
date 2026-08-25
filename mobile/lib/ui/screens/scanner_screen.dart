import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/ble/ble_manager.dart';

class DiscoveredDevice {
  final BluetoothDevice device;
  final String name;
  final int rssi;

  DiscoveredDevice({
    required this.device,
    required this.name,
    required this.rssi,
  });
}

/// Dedicated Mobile Bluetooth Scanner UI filtering strictly for OpenDeck Primary Service UUID
class ScannerScreen extends StatefulWidget {
  final BleManager bleManager;
  final Function(BluetoothDevice device) onConnect;

  const ScannerScreen({
    super.key,
    required this.bleManager,
    required this.onConnect,
  });

  static Future<BluetoothDevice?> show(
    BuildContext context, {
    required BleManager bleManager,
  }) {
    return Navigator.push<BluetoothDevice>(
      context,
      MaterialPageRoute(
        builder: (context) => ScannerScreen(
          bleManager: bleManager,
          onConnect: (device) => Navigator.pop(context, device),
        ),
      ),
    );
  }

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final Map<String, DiscoveredDevice> _discoveredDevices = {};
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _startScanning();
  }

  void _startScanning() async {
    setState(() {
      _isScanning = true;
      _discoveredDevices.clear();
    });

    await widget.bleManager.startScan(
      onDeviceDiscovered: (device, name) {
        if (!mounted) return;
        setState(() {
          _discoveredDevices[device.remoteId.str] = DiscoveredDevice(
            device: device,
            name: name,
            rssi: -50, // default RSSI representation
          );
        });
      },
    );
  }

  void _stopScanning() async {
    await widget.bleManager.stopScan();
    if (!mounted) return;
    setState(() => _isScanning = false);
  }

  @override
  void dispose() {
    widget.bleManager.stopScan();
    super.dispose();
  }

  Widget _buildRssiIndicator(int rssi) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.wifi_tethering_rounded,
          size: 18,
          color: Color(0xFF10B981),
        ),
        const SizedBox(width: 4),
        Text(
          '$rssi dBm',
          style: GoogleFonts.inter(
            fontSize: 12,
            color: const Color(0xFF94A3B8),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final devicesList = _discoveredDevices.values.toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      appBar: AppBar(
        title: Text(
          'Connect Desktop Host',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1A1A24),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              _isScanning ? Icons.stop_rounded : Icons.refresh_rounded,
              color: const Color(0xFF6366F1),
            ),
            onPressed: _isScanning ? _stopScanning : _startScanning,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Notice Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF1A1A24),
            child: Row(
              children: [
                const Icon(
                  Icons.filter_alt_rounded,
                  size: 16,
                  color: Color(0xFF6366F1),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Filtering strictly for OpenDeck Service UUID (13370001-...)',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ),
                if (_isScanning)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                    ),
                  ),
              ],
            ),
          ),

          Expanded(
            child: devicesList.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.bluetooth_searching_rounded,
                          size: 64,
                          color: Color(0xFF6366F1),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isScanning
                              ? 'Scanning for OpenDeck Desktop Agent...'
                              : 'No OpenDeck Servers Found',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Ensure OpenDeck is running on your Mac or PC',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _startScanning,
                          icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                          label: Text(
                            'Scan Again',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: devicesList.length,
                    itemBuilder: (context, i) {
                      final item = devicesList[i];
                      return Card(
                        color: const Color(0xFF1A1A24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.desktop_windows_rounded,
                              color: Color(0xFF6366F1),
                            ),
                          ),
                          title: Text(
                            item.name,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.device.remoteId.str,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11,
                                    color: const Color(0xFF94A3B8),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                _buildRssiIndicator(item.rssi),
                              ],
                            ),
                          ),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () {
                              _stopScanning();
                              widget.onConnect(item.device);
                            },
                            child: Text(
                              'Connect',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
