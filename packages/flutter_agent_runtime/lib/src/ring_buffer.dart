class RingBuffer<T> {
  RingBuffer(this.capacity) : assert(capacity > 0);

  final int capacity;
  final List<T> _items = <T>[];

  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;

  void add(T item) {
    if (_items.length == capacity) {
      _items.removeAt(0);
    }
    _items.add(item);
  }

  List<T> toList() => List<T>.unmodifiable(_items);

  List<T> where(bool Function(T item) test) =>
      List<T>.unmodifiable(_items.where(test));

  void clear() => _items.clear();
}
