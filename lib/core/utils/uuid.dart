import 'dart:math';
String simpleId([int length = 12]) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final rnd = Random();
  return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
}
