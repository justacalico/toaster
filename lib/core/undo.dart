/// Snapshot-based undo stack. Stores opaque states pushed before a mutation.
class UndoStack<T> {
  final int maxDepth;
  final List<T> _undo = [];
  final List<T> _redo = [];

  UndoStack({this.maxDepth = 64});

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get undoCount => _undo.length;
  int get redoCount => _redo.length;

  /// Call BEFORE mutating, with a snapshot of the current state.
  void push(T snapshot) {
    _undo.add(snapshot);
    if (_undo.length > maxDepth) _undo.removeAt(0);
    _redo.clear();
  }

  /// Returns the state to restore. Caller must push its current state
  /// onto the redo side via [pushRedo].
  T? pop() => _undo.isEmpty ? null : _undo.removeLast();

  void pushRedo(T snapshot) => _redo.add(snapshot);

  /// Returns the state to re-apply. Caller pushes current state via [push].
  T? popRedo() => _redo.isEmpty ? null : _redo.removeLast();

  /// Like [pop] but also records the outgoing state for redo.
  T? undo(T current) {
    final s = pop();
    if (s == null) return null;
    _redo.add(current);
    return s;
  }

  /// Like [popRedo] but also records the outgoing state for undo.
  T? redo(T current) {
    final s = popRedo();
    if (s == null) return null;
    _undo.add(current);
    return s;
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}
