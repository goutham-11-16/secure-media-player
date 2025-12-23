import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:crypto/crypto.dart';
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
  enc.Key? get sessionKey => _sessionKey;
  enc.IV? get sessionIV => _sessionIV;

  // Initialize the session with keys received from the server (Base64 Encoded)
  void initializeSession(String keyBase64, String ivBase64) {
    _sessionKey = enc.Key.fromBase64(keyBase64);
    _sessionIV = enc.IV.fromBase64(ivBase64);
    _isAuthorized = true;
    debugPrint("Session Authorized. Key in memory.");
  }

  // Initialize with raw keys (for Creator)
  void setKeys(enc.Key key, enc.IV iv) {
    _sessionKey = key;
    _sessionIV = iv;
    _isAuthorized = true;
  }

  void clearSession() {
    _sessionKey = null;
    _sessionIV = null;
    _isAuthorized = false;
    debugPrint("Session Cleared.");
  }

  void deriveKeyFromPassword(String password) {
    var keyDigest = sha256.convert(utf8.encode(password));
    var ivDigest = md5.convert(utf8.encode(password));

    _sessionKey = enc.Key(Uint8List.fromList(keyDigest.bytes));
    _sessionIV = enc.IV(Uint8List.fromList(ivDigest.bytes));
    _isAuthorized = true;
    debugPrint("Keys derived from password.");
  }

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

  Future<void> encryptFile(String inputPath, String outputPath) async {
    if (!_isAuthorized || _sessionKey == null || _sessionIV == null) {
      throw Exception("Keys not set");
    }

    final inputFile = File(inputPath);
    final inputBytes = await inputFile.readAsBytes();

    final encrypter = enc.Encrypter(
      enc.AES(_sessionKey!, mode: enc.AESMode.cbc, padding: 'PKCS7'),
    );

    final encrypted = encrypter.encryptBytes(inputBytes, iv: _sessionIV);

    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(encrypted.bytes);
    debugPrint("Encrypted $inputPath to $outputPath");
  }

  Future<String> calculateFileId(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
