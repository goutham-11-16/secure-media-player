import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import '../services/crypto_service.dart';

class CreatorDashboard extends StatefulWidget {
  final String? password;
  const CreatorDashboard({super.key, this.password});

  @override
  State<CreatorDashboard> createState() => _CreatorDashboardState();
}

class _CreatorDashboardState extends State<CreatorDashboard> {
  bool _isProcessing = false;
  String _status = "Ready";
  String? _lastSessionCode;

  File? _currentFile;
  String? _currentFileId;

  // In a real app, these would be configurable
  final String _serverUrl = "http://localhost:3000";
  final String _adminToken = "admin-secret";

  @override
  void initState() {
    super.initState();
    if (widget.password != null) {
      CryptoService().deriveKeyFromPassword(widget.password!);
    } else {
      // Fallback for dev/testing if accessed directly (shouldn't happen in flow)
      CryptoService().deriveKeyFromPassword("Goutham@111620");
    }
  }

  Future<void> _encryptVideo() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
      );
      if (result != null) {
        File file = File(result.files.single.path!);
        setState(() {
          _isProcessing = true;
          _status =
              "Encrypting ${file.path.split(Platform.pathSeparator).last}...";
          _currentFile = null;
          _currentFileId = null;
          _lastSessionCode = null;
        });

        // Output to same directory with .bin extension
        String outputPath = "${file.path}.bin";

        await CryptoService().encryptFile(file.path, outputPath);

        setState(() => _status = "Calculating ID...");
        String fileId = await CryptoService().calculateFileId(outputPath);

        setState(() => _status = "Registering with Server...");
        // Register with Server (Auto-allow)
        await http.post(
          Uri.parse('$_serverUrl/api/registry/add'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'fileId': fileId}),
        );

        setState(() {
          _status = "Success! File Ready.";
          _isProcessing = false;
          _currentFile = File(outputPath);
          _currentFileId = fileId;
        });
      }
    } catch (e) {
      setState(() {
        _status = "Error: $e";
        _isProcessing = false;
      });
    }
  }

  Future<void> _pickEncryptedFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      ); // .bin usually
      if (result != null) {
        File file = File(result.files.single.path!);
        setState(() {
          _isProcessing = true;
          _status = "Verifying File...";
          _lastSessionCode = null;
        });

        String fileId = await CryptoService().calculateFileId(file.path);

        setState(() {
          _currentFile = file;
          _currentFileId = fileId;
          _status = "File Selected. ID: ${fileId.substring(0, 8)}...";
          _isProcessing = false;
        });
      }
    } catch (e) {
      setState(() {
        _status = "Error: $e";
        _isProcessing = false;
      });
    }
  }

  Future<void> _generateCode() async {
    if (_currentFileId == null) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final response = await http.post(
        Uri.parse('$_serverUrl/api/session/create'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': _adminToken,
          'fileId': _currentFileId,
          'validityMinutes': 10,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _lastSessionCode = data['code'];
          // Parse expiry if needed
          _status = "Session Active";
        });
      } else {
        setState(() => _status = "Server Data Error: ${response.statusCode}");
      }
    } catch (e) {
      setState(() => _status = "Network Error: $e");
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: Text(
          "Creator Dashboard",
          style: GoogleFonts.outfit(color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Bar
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
              ),
              child: Text(
                _status,
                style: GoogleFonts.outfit(
                  color: Colors.blueAccent,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(height: 30),

            // Actions
            Row(
              children: [
                _ActionButton(
                  label: "Encrypt New Video",
                  icon: Icons.lock_outline,
                  color: Colors.purpleAccent,
                  onTap: _isProcessing ? null : _encryptVideo,
                ),
                const SizedBox(width: 20),
                _ActionButton(
                  label: "Manage Existing File",
                  icon: Icons.folder_open,
                  color: Colors.orangeAccent,
                  onTap: _isProcessing ? null : _pickEncryptedFile,
                ),
              ],
            ),

            const SizedBox(height: 40),

            // Active File Details
            if (_currentFile != null) ...[
              Text(
                "Selected File",
                style: GoogleFonts.outfit(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 10),
              Text(
                _currentFile!.path.split(Platform.pathSeparator).last,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "ID: $_currentFileId",
                style: GoogleFonts.outfit(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 30),

              // Session Gen
              Center(
                child: Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _generateCode,
                      icon: const Icon(Icons.key),
                      label: Text(
                        "Generate Session Code",
                        style: GoogleFonts.outfit(fontSize: 18),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 20,
                        ),
                      ),
                    ),
                    if (_lastSessionCode != null) ...[
                      const SizedBox(height: 30),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 20,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.blueAccent),
                        ),
                        child: Column(
                          children: [
                            Text(
                              "SESSION CODE",
                              style: GoogleFonts.outfit(
                                color: Colors.blueAccent,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 10),
                            SelectableText(
                              _lastSessionCode!,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              "Valid for 10 minutes",
                              style: GoogleFonts.outfit(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 10),
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
