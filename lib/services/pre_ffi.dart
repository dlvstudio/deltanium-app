import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart' as pkg_ffi;
import 'dart:io' show Platform, File;
import 'dart:typed_data';

class _Symbols {
  static const encapsulate = 'umbral_encapsulate_with_tag';
  static const generateRekey = 'umbral_generate_rekey';
  static const reencrypt = 'umbral_reencrypt';
  static const decapsulate = 'umbral_decapsulate_for_recipient';
  static const free = 'umbral_free';
}

class PreFfi {
  late final ffi.DynamicLibrary _lib;

  PreFfi._(this._lib) {
    _bind();
  }

  static PreFfi? _instance;
  static PreFfi instance() {
    _instance ??= PreFfi._(_open());
    return _instance!;
  }

  // C signatures
  late final int Function(
    ffi.Pointer<ffi.Uint8>, int,
    ffi.Pointer<ffi.Uint8>, int,
    ffi.Pointer<ffi.Uint8>, int,
    ffi.Pointer<ffi.Pointer<ffi.Uint8>>, ffi.Pointer<ffi.Int32>
  ) _encapsulateWithTag;

  late final int Function(
    ffi.Pointer<ffi.Uint8>, int,
    ffi.Pointer<ffi.Uint8>, int,
    ffi.Pointer<ffi.Uint8>, int,
    ffi.Pointer<ffi.Pointer<ffi.Uint8>>, ffi.Pointer<ffi.Int32>
  ) _generateRekey;

  late final int Function(
    ffi.Pointer<ffi.Uint8>, int,
    ffi.Pointer<ffi.Uint8>, int,
    ffi.Pointer<ffi.Pointer<ffi.Uint8>>, ffi.Pointer<ffi.Int32>
  ) _reencrypt;

  late final int Function(
    ffi.Pointer<ffi.Uint8>, int,
    ffi.Pointer<ffi.Uint8>, int,
    ffi.Pointer<ffi.Uint8>, int,
    ffi.Pointer<ffi.Pointer<ffi.Uint8>>, ffi.Pointer<ffi.Int32>
  ) _decapsulateForRecipient;

  late final void Function(ffi.Pointer<ffi.Uint8>) _free;

  void _bind() {
    _encapsulateWithTag = _lib.lookupFunction<
      ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Int32, ffi.Pointer<ffi.Pointer<ffi.Uint8>>, ffi.Pointer<ffi.Int32>),
      int Function(ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Pointer<ffi.Uint8>>, ffi.Pointer<ffi.Int32>)
    >(_Symbols.encapsulate);

    _generateRekey = _lib.lookupFunction<
      ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Int32, ffi.Pointer<ffi.Pointer<ffi.Uint8>>, ffi.Pointer<ffi.Int32>),
      int Function(ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Pointer<ffi.Uint8>>, ffi.Pointer<ffi.Int32>)
    >(_Symbols.generateRekey);

    _reencrypt = _lib.lookupFunction<
      ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Int32, ffi.Pointer<ffi.Pointer<ffi.Uint8>>, ffi.Pointer<ffi.Int32>),
      int Function(ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Pointer<ffi.Uint8>>, ffi.Pointer<ffi.Int32>)
    >(_Symbols.reencrypt);

    _decapsulateForRecipient = _lib.lookupFunction<
      ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Int32, ffi.Pointer<ffi.Pointer<ffi.Uint8>>, ffi.Pointer<ffi.Int32>),
      int Function(ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Uint8>, int, ffi.Pointer<ffi.Pointer<ffi.Uint8>>, ffi.Pointer<ffi.Int32>)
    >(_Symbols.decapsulate);

    _free = _lib.lookupFunction<
      ffi.Void Function(ffi.Pointer<ffi.Uint8>),
      void Function(ffi.Pointer<ffi.Uint8>)
    >(_Symbols.free);
  }

  static ffi.DynamicLibrary _open() {
    if (Platform.isMacOS) {
      // Try direct load first
      try {
        return ffi.DynamicLibrary.open('libumbral_pre.dylib');
      } catch (e) {
        // Try bundle Frameworks path: @executable_path/../Frameworks/libumbral_pre.dylib
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final fallback = exeDir + '/../Frameworks/libumbral_pre.dylib';
        final fallbackFile = File(fallback);
        
        if (!fallbackFile.existsSync()) {
          throw Exception(
            'Failed to load libumbral_pre.dylib:\n'
            '  - Direct load failed: ${e.toString()}\n'
            '  - Fallback path does not exist: $fallback\n'
            '  - Please ensure the library is copied to: $fallback\n'
            '  - And signed with: codesign --force --deep --sign - "$fallback"'
          );
        }
        
        try {
          return ffi.DynamicLibrary.open(fallback);
        } catch (e2) {
          throw Exception(
            'Failed to load libumbral_pre.dylib from fallback path:\n'
            '  - Direct load failed: ${e.toString()}\n'
            '  - Fallback path exists but load failed: ${e2.toString()}\n'
            '  - Path: $fallback\n'
            '  - Please ensure the library is properly signed with: codesign --force --deep --sign - "$fallback"'
          );
        }
      }
    } else if (Platform.isLinux) {
      return ffi.DynamicLibrary.open('libumbral_pre.so');
    } else if (Platform.isWindows) {
      return ffi.DynamicLibrary.open('umbral_pre.dll');
    } else if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libumbral_pre.so');
    } else if (Platform.isIOS) {
      // For iOS, the symbol is linked into the app binary; use DynamicLibrary.process()
      return ffi.DynamicLibrary.process();
    }
    throw UnsupportedError('Unsupported platform for Umbral PRE');
  }

  Uint8List _copyOutAndFree(ffi.Pointer<ffi.Uint8> ptr, int len) {
    if (ptr == ffi.Pointer.fromAddress(0) || len <= 0) {
      return Uint8List(0);
    }
    final out = Uint8List(len);
    final view = out.buffer.asUint8List();
    final nativeList = ptr.asTypedList(len);
    view.setAll(0, nativeList);
    _free(ptr);
    return out;
  }

  Uint8List encapsulateWithTag({required Uint8List pkAuthor, required String tag, required Uint8List key}) {
    final pkPtr = pkg_ffi.malloc<ffi.Uint8>(pkAuthor.length);
    final tagBytes = Uint8List.fromList(tag.codeUnits);
    final tagPtr = pkg_ffi.malloc<ffi.Uint8>(tagBytes.length);
    final keyPtr = pkg_ffi.malloc<ffi.Uint8>(key.length);
    pkPtr.asTypedList(pkAuthor.length).setAll(0, pkAuthor);
    tagPtr.asTypedList(tagBytes.length).setAll(0, tagBytes);
    keyPtr.asTypedList(key.length).setAll(0, key);
    final outPtrPtr = pkg_ffi.malloc<ffi.Pointer<ffi.Uint8>>();
    final outLenPtr = pkg_ffi.malloc<ffi.Int32>();
    try {
      final rc = _encapsulateWithTag(pkPtr, pkAuthor.length, tagPtr, tagBytes.length, keyPtr, key.length, outPtrPtr, outLenPtr);
      if (rc != 0) {
        throw StateError('umbral_encapsulate_with_tag failed rc=$rc');
      }
      return _copyOutAndFree(outPtrPtr.value, outLenPtr.value);
    } finally {
      pkg_ffi.malloc.free(pkPtr);
      pkg_ffi.malloc.free(tagPtr);
      pkg_ffi.malloc.free(keyPtr);
      pkg_ffi.malloc.free(outPtrPtr);
      pkg_ffi.malloc.free(outLenPtr);
    }
  }

  Uint8List generateRekey({required Uint8List skAuthor, required Uint8List pkRecipient, required String tag}) {
    final skPtr = pkg_ffi.malloc<ffi.Uint8>(skAuthor.length);
    final pkPtr = pkg_ffi.malloc<ffi.Uint8>(pkRecipient.length);
    final tagBytes = Uint8List.fromList(tag.codeUnits);
    final tagPtr = pkg_ffi.malloc<ffi.Uint8>(tagBytes.length);
    skPtr.asTypedList(skAuthor.length).setAll(0, skAuthor);
    pkPtr.asTypedList(pkRecipient.length).setAll(0, pkRecipient);
    tagPtr.asTypedList(tagBytes.length).setAll(0, tagBytes);
    final outPtrPtr = pkg_ffi.malloc<ffi.Pointer<ffi.Uint8>>();
    final outLenPtr = pkg_ffi.malloc<ffi.Int32>();
    try {
      final rc = _generateRekey(skPtr, skAuthor.length, pkPtr, pkRecipient.length, tagPtr, tagBytes.length, outPtrPtr, outLenPtr);
      if (rc != 0) {
        throw StateError('umbral_generate_rekey failed rc=$rc');
      }
      return _copyOutAndFree(outPtrPtr.value, outLenPtr.value);
    } finally {
      pkg_ffi.malloc.free(skPtr);
      pkg_ffi.malloc.free(pkPtr);
      pkg_ffi.malloc.free(tagPtr);
      pkg_ffi.malloc.free(outPtrPtr);
      pkg_ffi.malloc.free(outLenPtr);
    }
  }

  Uint8List reencrypt({required Uint8List encapsulatedForAuthor, required Uint8List rekey}) {
    final capPtr = pkg_ffi.malloc<ffi.Uint8>(encapsulatedForAuthor.length);
    final rkPtr = pkg_ffi.malloc<ffi.Uint8>(rekey.length);
    capPtr.asTypedList(encapsulatedForAuthor.length).setAll(0, encapsulatedForAuthor);
    rkPtr.asTypedList(rekey.length).setAll(0, rekey);
    final outPtrPtr = pkg_ffi.malloc<ffi.Pointer<ffi.Uint8>>();
    final outLenPtr = pkg_ffi.malloc<ffi.Int32>();
    try {
      final rc = _reencrypt(capPtr, encapsulatedForAuthor.length, rkPtr, rekey.length, outPtrPtr, outLenPtr);
      if (rc != 0) {
        throw StateError('umbral_reencrypt failed rc=$rc');
      }
      return _copyOutAndFree(outPtrPtr.value, outLenPtr.value);
    } finally {
      pkg_ffi.malloc.free(capPtr);
      pkg_ffi.malloc.free(rkPtr);
      pkg_ffi.malloc.free(outPtrPtr);
      pkg_ffi.malloc.free(outLenPtr);
    }
  }

  Uint8List decapsulateForRecipient({required Uint8List encapsulatedForRecipient, required Uint8List skRecipient, required String tag}) {
    final capPtr = pkg_ffi.malloc<ffi.Uint8>(encapsulatedForRecipient.length);
    final skPtr = pkg_ffi.malloc<ffi.Uint8>(skRecipient.length);
    final tagBytes = Uint8List.fromList(tag.codeUnits);
    final tagPtr = pkg_ffi.malloc<ffi.Uint8>(tagBytes.length);
    capPtr.asTypedList(encapsulatedForRecipient.length).setAll(0, encapsulatedForRecipient);
    skPtr.asTypedList(skRecipient.length).setAll(0, skRecipient);
    tagPtr.asTypedList(tagBytes.length).setAll(0, tagBytes);
    final outPtrPtr = pkg_ffi.malloc<ffi.Pointer<ffi.Uint8>>();
    final outLenPtr = pkg_ffi.malloc<ffi.Int32>();
    try {
      final rc = _decapsulateForRecipient(capPtr, encapsulatedForRecipient.length, skPtr, skRecipient.length, tagPtr, tagBytes.length, outPtrPtr, outLenPtr);
      if (rc != 0) {
        throw StateError('umbral_decapsulate_for_recipient failed rc=$rc');
      }
      return _copyOutAndFree(outPtrPtr.value, outLenPtr.value);
    } finally {
      pkg_ffi.malloc.free(capPtr);
      pkg_ffi.malloc.free(skPtr);
      pkg_ffi.malloc.free(tagPtr);
      pkg_ffi.malloc.free(outPtrPtr);
      pkg_ffi.malloc.free(outLenPtr);
    }
  }
}
