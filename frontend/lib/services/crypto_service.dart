import 'dart:io';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';

class CryptoService {
  static final CryptoService _instance = CryptoService._internal();

  factory CryptoService() {
    return _instance;
  }

  CryptoService._internal();

  enc.Key? _sessionKey;
  enc.IV? _sessionIV;
  bool _isAuthorized = false;

  bool get isAuthorized => _isAuthorized;

  // Initialize the session with keys received from the server (Base64 Encoded)
  void initializeSession(String keyBase64, String ivBase64) {
    _sessionKey = enc.Key.fromBase64(keyBase64);
    _sessionIV = enc.IV.fromBase64(ivBase64);
    _isAuthorized = true;
    debugPrint("Session Authorized. Key in memory.");
  }

  void clearSession() {
    _sessionKey = null;
    _sessionIV = null;
    _isAuthorized = false;
    debugPrint("Session Cleared.");
  }

  // Decrypts a file stream or bytes.
  // For the video player, we might need to serve a local HTTP stream or use a custom MediaKit resource.
  // MediaKit supports playing from `Stream<List<int>>`.

  // Decrypts a chunk of data.
  // Note: AES-CBC is block based. Random access is hard without re-initializing the cipher for the specific block.
  // However, `encrypt` package is high-level.
  // If we just want to play the file, efficient streaming decryption is needed.
  // For this MVP, we will try to decrypt the PRELOADED bytes if small enough, or stream.
  // Given: "Never save decrypted content to disk".
  // Node.js implementation uses AES-256-CBC.

  // NOTE: Standard CBC decryption requires the previous block to decrypt the current one.
  // This means seeking is difficult without an index or decrypting from start.
  // For this prototype, we'll assume linear playback or small enough files to load in memory (RAM).
  // If files are large (GBs), we'd need CTR mode or HLS with keys.
  // Sticking to the requirements: "Decrypt video in memory only".

  Future<Uint8List> decryptFileToMemory(String filePath) async {
    if (!_isAuthorized || _sessionKey == null || _sessionIV == null) {
      throw Exception("Session not authorized");
    }

    final file = File(filePath);
    final encryptedBytes = await file.readAsBytes();

    final encrypter = enc.Encrypter(
      enc.AES(_sessionKey!, mode: enc.AESMode.cbc, padding: 'PKCS7'),
    );

    final decrypted = encrypter.decryptBytes(
      enc.Encrypted(encryptedBytes),
      iv: _sessionIV,
    );

    return Uint8List.fromList(decrypted);
  }
}
