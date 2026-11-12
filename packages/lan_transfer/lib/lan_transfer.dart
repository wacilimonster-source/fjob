/// Encrypted, one-shot LAN transfer for `.fjob` ledger bundles.
///
/// The phone hosts a short-lived HTTP session and displays its LAN address plus
/// a one-time pairing code. The PC joins with that address/code and either
/// pulls the phone's ledger or pushes its own. Payloads are encrypted with a
/// key derived from the pairing code; the session stops after one successful
/// transfer, a timeout, or repeated authentication failures.
library;

export 'src/address.dart';
export 'src/client.dart';
export 'src/code.dart';
export 'src/crypto.dart';
export 'src/protocol.dart';
export 'src/server.dart';
