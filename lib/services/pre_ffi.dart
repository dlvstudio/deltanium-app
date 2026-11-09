/// Conditional Umbral PRE bindings:
/// - Native (IO + FFI): [pre_ffi_native.dart]
/// - Web / no FFI: [pre_ffi_stub.dart]
export 'pre_ffi_stub.dart' if (dart.library.ffi) 'pre_ffi_native.dart';
