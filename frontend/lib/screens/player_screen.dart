import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../services/crypto_service.dart';
import 'auth_screen.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player player;
  late final VideoController controller;

  String? _currentFileName;
  bool _isFileLoaded = false;
  bool _isDecrypting = false;
  HttpServer? _server;

  @override
  void initState() {
    super.initState();
    if (!CryptoService().isAuthorized) {
      // Security check: Redirect if not authorized
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
        );
      });
    }

    player = Player();
    controller = VideoController(player);
  }

  @override
  void dispose() {
    _server?.close(force: true);
    player.dispose();
    super.dispose();
  }

  Future<void> _pickAndPlayVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['enc', 'bin'],
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        setState(() {
          _currentFileName = result.files.single.name;
          _isDecrypting = true;
          _isFileLoaded = false;
        });

        // DECRYPTION LOGIC
        // We get bytes in memory.
        // WARNING: Large files will crash the app (OOM).
        // For production, we need a local HTTP server that decrypts chunks on the fly.
        // Or specific MediaKit "Stream" resources.
        // MediaPlayable can accept a 'Playlist' or 'Media'.
        // 'Media' can take 'Stream'.

        try {
          final decryptedBytes = await CryptoService().decryptFileToMemory(
            path,
          );

          // We cannot pass bytes directly to MediaKit easily without writing to file (forbidden)
          // OR using a custom resource protocol if supported.
          // However, MediaKit supports "memory" via 'Media.memory' in newer versions,
          // or we can use a specialized approach.
          // Let's check if `Media.memory` is available or if we need to serve it.
          // Since I am using MediaKit, I'll try `Media.memory`.

          /* 
             NOTE: 'Media.memory' might require the byte array to be passed.
             If not available in the specific version, we might fall back to a local http server.
             Let's hope MediaKit supports it or I'll implement a fallback.
          */

          // Constructing Media from bytes is not standard in raw MediaKit without a plugin
          // or using a specific URI scheme.
          // BUT, we can start a micro HTTP server within the app that serves the decrypted bytes.
          // This keeps the data in memory (in the server buffer).

          // SIMPLIFICATION for MVP:
          // We will use a unique trick: Date URI? No, too big.
          // We will implementing a quick LocalServer if needed, but for now
          // let's try to assume a hypothetical "Media.memory" exists or simple workaround.
          // Checking docs (mental): MediaKit usually takes a URI.

          // ACTUAL SOLUTION:
          // Since I cannot spawn a full streaming server easily in one file without deps,
          // I will use `Media("memory://...")` if supported or just `Media.network` to localhost.
          // Let's implement a minimal HTTP server here that serves the ONE file from memory.

          // Close previous server if running
          await _server?.close(force: true);

          // Use ephemeral port (0) to avoid conflicts
          _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

          final port = _server!.port;
          debugPrint("Stream Server running on port: $port");

          _server!.listen((HttpRequest request) {
            request.response.headers.contentType = ContentType("video", "mp4");
            request.response.add(decryptedBytes);
            request.response.close();
          });

          await player.open(Media('http://127.0.0.1:$port/stream'));

          setState(() {
            _isFileLoaded = true;
            _isDecrypting = false;
          });
        } catch (e) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Decryption Failed: $e")));
          setState(() {
            _isDecrypting = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error picking file: $e");
    }
  }

  void _logout() {
    CryptoService().clearSession();
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const AuthScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "Secure Player",
          style: GoogleFonts.outfit(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: _logout,
            tooltip: "End Session",
          ),
        ],
      ),
      body: Center(
        child: _isDecrypting
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.blueAccent),
                  const SizedBox(height: 16),
                  Text(
                    "Decrypting in Memory...",
                    style: GoogleFonts.outfit(color: Colors.grey),
                  ),
                ],
              )
            : _isFileLoaded
            ? Column(
                children: [
                  Expanded(child: Video(controller: controller)),
                  if (_currentFileName != null)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        _currentFileName!,
                        style: GoogleFonts.outfit(color: Colors.white70),
                      ),
                    ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_open, size: 80, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    "Session Active",
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Select an encrypted (.enc) file to play",
                    style: GoogleFonts.outfit(color: Colors.grey),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: _pickAndPlayVideo,
                    icon: const Icon(Icons.folder_open),
                    label: const Text("Open Encrypted Video"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
