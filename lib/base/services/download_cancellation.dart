/// A download that can be called off from the queue UI.
///
/// The transfer belongs to a client that speaks dio, so cancelling means
/// handing the client something it can wire into its own cancel token. A client
/// that streams by hand (chunk by chunk) simply watches [isCancelled] instead.
class DownloadCancellation {
  /// Set once the listener asked for the download to stop.
  bool isCancelled = false;

  void Function()? _abort;

  /// Called by the client with the only thing it can do about a running
  /// transfer: abort it. If the cancel already arrived, it fires immediately,
  /// so a cancel racing the start of a request cannot slip through.
  void bind(void Function() abort) {
    _abort = abort;
    if (isCancelled) {
      abort();
    }
  }

  void cancel() {
    isCancelled = true;
    _abort?.call();
  }
}
