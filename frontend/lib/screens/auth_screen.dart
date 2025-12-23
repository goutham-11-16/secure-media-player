import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import '../services/crypto_service.dart';
import 'player_screen.dart';
import 'package:google_fonts/google_fonts.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _fileController = TextEditingController();
  File? _selectedFile;
  String? _fileHash;
  String _statusMessage = "Initializing...";
  bool _isLoading = false;
  String? _serverUrl;

  @override
  void initState() {
    super.initState();
    _discoverServer();
  }

  Future<void> _discoverServer() async {
    setState(() {
      _statusMessage = "Discovering Server...";
      _isLoading = true;
    });

    try {
      debugPrint("Fetching server config from GitHub...");
      final response = await http.get(
        Uri.parse(
          'https://raw.githubusercontent.com/goutham-11-16/tv/main/server_endpoint.json',
        ),
      );

      if (response.statusCode == 200) {
        debugPrint("Discovery Response: ${response.body}");
        final data = jsonDecode(response.body);

        if (data is Map) {
          if (data.containsKey('server_url')) {
            _serverUrl = data['server_url'];
          } else if (data.containsKey('auth_server')) {
            _serverUrl = data['auth_server'];
          }
        }

        if (_serverUrl == null) {
          if (!response.body.trim().startsWith('{')) {
            _serverUrl = response.body.trim();
          } else {
            throw Exception(
              "Could not find 'server_url' or 'auth_server' in JSON config",
            );
          }
        }

        if (_serverUrl != null && _serverUrl!.contains("trycloudflare.com")) {
          debugPrint(
            "Detected unstable Cloudflare URL. Forcing localhost for stability.",
          );
          _serverUrl = "http://localhost:3000";
        }

        if (_serverUrl != null &&
            _serverUrl!.contains("localhost") &&
            Platform.isAndroid) {
          _serverUrl = _serverUrl!.replaceFirst("localhost", "10.0.2.2");
        }

        setState(() {
          _statusMessage =
              "Connected to Server: $_serverUrl\nSelect File & Enter Token.";
          _isLoading = false;
        });
      } else {
        throw Exception("Failed to fetch config: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Discovery failed, defaulting to localhost. Error: $e");
      _serverUrl = "http://localhost:3000";
      if (Platform.isAndroid) _serverUrl = "http://10.0.2.2:3000";

      setState(() {
        _statusMessage = "Discovery Failed. Defaulting to: $_serverUrl";
        _isLoading = false;
      });
    }
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result != null) {
        File file = File(result.files.single.path!);
        setState(() {
          _selectedFile = file;
          _fileController.text = file.path.split(Platform.pathSeparator).last;
          _statusMessage = "Calculating File ID...";
          _isLoading = true;
        });

        // Compute Hash
        final hash = await _calculateFileHash(file);

        setState(() {
          _fileHash = hash;
          _statusMessage = "File ID Generated.\nReady to Authenticate.";
          _isLoading = false;
        });
        debugPrint("File Hash: $_fileHash");
      }
    } catch (e) {
      debugPrint("Error picking file: $e");
      setState(() {
        _statusMessage = "Error selecting file";
      });
    }
  }

  Future<String> _calculateFileHash(File file) async {
    // For large files, streaming hash
    final stream = file.openRead();
    final digest = await sha256.bind(stream).first;
    return digest.toString();
  }

  Future<void> _authenticate() async {
    if (_serverUrl == null) return;

    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please enter a token")));
      return;
    }

    if (_selectedFile == null || _fileHash == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please select a file")));
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = "Authenticating...";
    });

    try {
      final response = await http.post(
        Uri.parse('$_serverUrl/auth'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token, 'file_id': _fileHash}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final key = data['session_key'];
        final iv = data['iv'];

        CryptoService().initializeSession(key, iv);

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const PlayerScreen()),
          );
        }
      } else {
        setState(() {
          final msg = response.statusCode == 403
              ? "Unauthorized File ID"
              : response.reasonPhrase;
          _statusMessage = "Auth Failed: $msg";
        });
      }
    } catch (e) {
      if (!_serverUrl!.contains("localhost") &&
          !_serverUrl!.contains("127.0.0.1")) {
        debugPrint("Primary URL failed. Trying localhost fallback...");
        setState(() {
          _statusMessage = "Primary failed. Trying localhost...";
        });

        try {
          final fallbackUrl = 'http://localhost:3000';
          final response = await http.post(
            Uri.parse('$fallbackUrl/auth'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'token': token, 'file_id': _fileHash}),
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final key = data['session_key'];
            final iv = data['iv'];

            CryptoService().initializeSession(key, iv);

            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const PlayerScreen()),
              );
            }
            return;
          }
        } catch (fallbackError) {
          debugPrint("Fallback failed: $fallbackError");
        }
      }

      setState(() {
        _statusMessage = "Connection Error: $e";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_person,
                size: 64,
                color: Colors.blueAccent.shade200,
              ),
              const SizedBox(height: 24),
              Text(
                "System Authorized Player",
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _fileController,
                readOnly: true,
                onTap: _pickFile,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Select Encrypted File",
                  labelStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF2C2C2C),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(
                    Icons.file_present,
                    color: Colors.grey,
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.folder_open, color: Colors.blue),
                    onPressed: _pickFile,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _tokenController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Session Token",
                  labelStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF2C2C2C),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.key, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed:
                      _serverUrl != null &&
                          !_isLoading &&
                          _selectedFile != null &&
                          _fileHash != null
                      ? _authenticate
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          "Authenticate Session",
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
