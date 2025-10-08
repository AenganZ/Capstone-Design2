import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  static WebSocketChannel? _channel;
  static StreamController<Map<String, dynamic>>? _controller;
  static bool _isConnected = false;

  static void connect(Function(Map<String, dynamic>) onMessage) {
    if (_isConnected) return;

    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('ws://localhost:8001/ws/admin'),
      );

      _controller = StreamController<Map<String, dynamic>>.broadcast();

      _channel!.stream.listen(
        (message) {
          try {
            final data = json.decode(message.toString());
            _controller?.add(data);
            onMessage(data);
          } catch (e) {
            print('메시지 파싱 오류: $e');
          }
        },
        onError: (error) {
          print('WebSocket 오류: $error');
          _isConnected = false;
          Future.delayed(const Duration(seconds: 5), () => connect(onMessage));
        },
        onDone: () {
          print('WebSocket 연결 종료');
          _isConnected = false;
          Future.delayed(const Duration(seconds: 5), () => connect(onMessage));
        },
      );

      _isConnected = true;
      print('WebSocket 연결됨');
    } catch (e) {
      print('WebSocket 연결 실패: $e');
      _isConnected = false;
    }
  }

  static void disconnect() {
    _channel?.sink.close();
    _controller?.close();
    _isConnected = false;
  }

  static bool get isConnected => _isConnected;
}