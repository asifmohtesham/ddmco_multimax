/// Interface for checking network connectivity
abstract class NetworkInfo {
  Future<bool> get isConnected;
}

/// Implementation using connectivity_plus package
/// TODO: Implement actual network checking when connectivity_plus is added
class NetworkInfoImpl implements NetworkInfo {
  @override
  Future<bool> get isConnected async {
    // For now, always return true
    // In production, use connectivity_plus package
    return true;
  }
}
