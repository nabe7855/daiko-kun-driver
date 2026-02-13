import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class ChatScreen extends StatefulWidget {
  final String rideId;
  final String senderId;
  final String senderType; // 'customer' or 'driver'

  const ChatScreen({
    super.key,
    required this.rideId,
    required this.senderId,
    required this.senderType,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<dynamic> _messages = [];
  Timer? _pollingTimer;
  final ScrollController _scrollController = ScrollController();

  ImagePicker? _picker;
  ImagePicker get picker => _picker ??= ImagePicker();

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _getApiUrl(String path) {
    String baseUrl = 'http://localhost:8080';
    return '$baseUrl$path';
  }

  Future<void> _fetchMessages() async {
    try {
      final response = await http.get(
        Uri.parse(_getApiUrl('/ride-requests/${widget.rideId}/messages')),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (data.length != _messages.length) {
          setState(() {
            _messages.clear();
            _messages.addAll(data);
          });
          _scrollToBottom();
        }
      }
    } catch (e) {
      debugPrint('Error fetching messages: $e');
    }
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) {
        _fetchMessages();
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    _messageController.clear();
    try {
      final response = await http.post(
        Uri.parse(_getApiUrl('/ride-requests/${widget.rideId}/messages')),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'sender_id': widget.senderId,
          'sender_type': widget.senderType,
          'content': content,
        }),
      );
      if (response.statusCode == 201) {
        _fetchMessages();
      }
    } catch (e) {
      debugPrint('Error sending message: $e');
    }
  }

  Future<void> _pickImage() async {
    if (kIsWeb) {
      _pickImageWeb();
    } else {
      try {
        final XFile? image = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 70,
        );
        if (image != null) {
          await _uploadAndSendMessage(image.name, await image.readAsBytes());
        }
      } catch (e) {
        _showError('エラーが発生しました: $e');
      }
    }
  }

  void _pickImageWeb() {
    debugPrint('_pickImageWeb called');
    final html.FileUploadInputElement uploadInput =
        html.FileUploadInputElement();
    uploadInput.accept = 'image/*';
    uploadInput.click();

    uploadInput.onChange.listen((e) {
      debugPrint('File selected');
      final files = uploadInput.files;
      if (files!.isNotEmpty) {
        final file = files[0];
        debugPrint('File name: ${file.name}, size: ${file.size}');
        final reader = html.FileReader();
        reader.readAsArrayBuffer(file);
        reader.onLoadEnd.listen((e) {
          debugPrint('File read complete, starting upload');
          _uploadAndSendMessage(file.name, reader.result as Uint8List);
        });
      }
    });
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _uploadAndSendMessage(String filename, Uint8List bytes) async {
    try {
      debugPrint(
        'Starting upload for file: $filename, size: ${bytes.length} bytes',
      );
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(_getApiUrl('/ride-requests/${widget.rideId}/upload')),
      );

      request.files.add(
        http.MultipartFile.fromBytes('image', bytes, filename: filename),
      );

      debugPrint('Sending multipart request...');
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      debugPrint('Upload response status: ${response.statusCode}');
      debugPrint('Upload response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final imageUrl = data['url'];

        await http.post(
          Uri.parse(_getApiUrl('/ride-requests/${widget.rideId}/messages')),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'sender_id': widget.senderId,
            'sender_type': widget.senderType,
            'content': '',
            'image_url': imageUrl,
          }),
        );
        _fetchMessages();
      } else {
        debugPrint('Upload failed with status: ${response.statusCode}');
        debugPrint('Response body: ${response.body}');
        _showError('アップロードに失敗しました (${response.statusCode})');
      }
    } catch (e) {
      debugPrint('Error uploading image: $e');
      _showError('アップロード中にエラーが発生しました: $e');
    }
  }

  void _showReportDialog() {
    final TextEditingController reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('通報する'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('不適切な言動やマナー違反がありましたか？事務局で確認いたします。'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                hintText: '通報理由を入力してください（具体的に）',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (reasonController.text.trim().isEmpty) return;
              Navigator.pop(context);
              await _submitReport(reasonController.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('通報を送信', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _submitReport(String reason) async {
    try {
      final response = await http.post(
        Uri.parse(_getApiUrl('/ride-requests/${widget.rideId}/report')),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'reporter_id': widget.senderId,
          'reported_user_id': 'unknown',
          'reporter_role': widget.senderType,
          'reason': reason,
        }),
      );

      if (response.statusCode == 201 && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('通報を送信しました。事務局で確認いたします。')));
      }
    } catch (e) {
      debugPrint('Error reporting user: $e');
      _showError('通報の送信に失敗しました');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('メッセージ'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.report_problem_outlined,
              color: Colors.white,
            ),
            tooltip: '通報する',
            onPressed: _showReportDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMe = msg['sender_id'] == widget.senderId;
                final imageUrl = msg['image_url'];

                return Align(
                  alignment: isMe
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.indigo : Colors.grey[300],
                      borderRadius: BorderRadius.circular(20).copyWith(
                        bottomRight: isMe
                            ? const Radius.circular(0)
                            : const Radius.circular(20),
                        bottomLeft: isMe
                            ? const Radius.circular(20)
                            : const Radius.circular(0),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: isMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        if (imageUrl != null && imageUrl.isNotEmpty) ...[
                          GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (context) => Dialog(
                                  backgroundColor: Colors.transparent,
                                  insetPadding: EdgeInsets.zero,
                                  child: Stack(
                                    children: [
                                      Center(
                                        child: Image.network(
                                          _getApiUrl(imageUrl),
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                      Positioned(
                                        right: 20,
                                        top: 20,
                                        child: IconButton(
                                          icon: const Icon(
                                            Icons.close,
                                            color: Colors.white,
                                            size: 30,
                                          ),
                                          onPressed: () =>
                                              Navigator.pop(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                _getApiUrl(imageUrl),
                                width: 200,
                                fit: BoxFit.cover,
                                errorBuilder: (ctx, err, stack) =>
                                    const Icon(Icons.error),
                              ),
                            ),
                          ),
                          if (msg['content'] != null &&
                              msg['content'].isNotEmpty)
                            const SizedBox(height: 8),
                        ],
                        if (msg['content'] != null && msg['content'].isNotEmpty)
                          Text(
                            msg['content'],
                            style: TextStyle(
                              color: isMe ? Colors.white : Colors.black,
                              fontSize: 16,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: 24,
              top: 8,
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.add_a_photo, color: Colors.grey),
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'メッセージを入力...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send, color: Colors.indigo),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
