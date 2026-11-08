/// Only checkpoints, IDs, hashes and evidence offsets are written.
/// Full TXT/FB2 text stays in the host application's private library.
/// Implement this port in any headless or UI host; it has no disk, network,
/// platform preferences or cloud credentials.
abstract class SourceAnalysisCheckpointRepository {
  Future<String?> read(String sourceFingerprint);
  Future<void> write(String sourceFingerprint, String checkpoint);
  Future<void> delete(String sourceFingerprint);
}

