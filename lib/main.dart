import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Request permissions BEFORE anything else
  await [Permission.camera, Permission.photos].request();
  
  // Get cameras after permission is granted
  cameras = await availableCameras();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Email & Phone Scanner',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ScannerScreen(),
    );
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  CameraController? _controller;
  final TextRecognizer _textRecognizer = TextRecognizer();
  final ImagePicker _imagePicker = ImagePicker();
  String _rawText = '';
  List<String> _emails = [];
  List<String> _phones = [];
  List<String> _urls = [];
  bool _isProcessing = false;
  bool _showCamera = true;
  String _displayMode = 'all';
  bool _isChinese = false;

  final String contactName = 'Miftah B.';
  final String contactPhone = '13804325010';

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (cameras.isEmpty) return;
    _controller = CameraController(cameras[0], ResolutionPreset.high);
    await _controller?.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _processImage(File imageFile) async {
    setState(() {
      _isProcessing = true;
      _showCamera = false;
      _displayMode = 'all';
    });

    try {
      final InputImage inputImage = InputImage.fromFile(imageFile);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      _rawText = recognizedText.text;
      _emails = _extractEmails(_rawText);
      _phones = _extractPhones(_rawText);
      _urls = _extractUrls(_rawText);

      setState(() {
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _rawText = 'Error: $e';
        _isProcessing = false;
      });
    }
  }

  Future<void> _captureFromCamera() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final XFile picture = await _controller!.takePicture();
      await _processImage(File(picture.path));
    } catch (e) {
      setState(() {
        _rawText = 'Error: $e';
        _isProcessing = false;
      });
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        await _processImage(File(pickedFile.path));
      }
    } catch (e) {
      setState(() {
        _rawText = 'Error: $e';
        _isProcessing = false;
      });
    }
  }

  List<String> _extractEmails(String text) {
    final RegExp emailRegExp = RegExp(r'\b[\w\.-]+@[\w\.-]+\.\w{2,}\b');
    return emailRegExp.allMatches(text).map((m) => m.group(0)!).toList();
  }

  List<String> _extractPhones(String text) {
    final RegExp phoneRegExp = RegExp(r'(?<!\d)(?:\+?\d{1,3}[-.\s]?)?\(?\d{2,4}\)?[-.\s]?\d{3,4}[-.\s]?\d{3,4}(?!\d)');
    return phoneRegExp.allMatches(text)
        .map((m) => m.group(0)!.replaceAll(RegExp(r'[^\d+]'), ''))
        .where((p) {
          if (RegExp(r'^\d{4}[-/]\d{1,2}[-/]\d{1,2}$').hasMatch(p)) return false;
          if (RegExp(r'^\d{1,2}[-/]\d{1,2}[-/]\d{4}$').hasMatch(p)) return false;
          if (p.replaceAll(RegExp(r'\D'), '').length < 8) return false;
          return true;
        })
        .toSet()
        .toList();
  }

  List<String> _extractUrls(String text) {
    final RegExp urlRegExp = RegExp(r'https?://[^\s]+');
    return urlRegExp.allMatches(text).map((m) => m.group(0)!).toList();
  }

  void _resetScanner() {
    setState(() {
      _showCamera = true;
      _rawText = '';
      _emails = [];
      _phones = [];
      _urls = [];
      _displayMode = 'all';
    });
  }

  void _closeApp() {
    SystemNavigator.pop();
  }

  void _setDisplayMode(String mode) {
    setState(() {
      _displayMode = mode;
    });
  }

  void _copyToClipboard(String text, String type) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_isChinese ? '$type 已复制' : '$type copied to clipboard!')),
    );
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber.replaceAll(RegExp(r'[^\d+]'), ''));
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isChinese ? '无法打开拨号器' : 'Could not launch dialer')),
      );
    }
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_isChinese ? '帮助' : 'Help'),
        content: Text(
          _isChinese
              ? '1. 点击"扫描文本"拍照，或点击"从相册选取"选择图片\n'
                '2. 应用会自动识别文字并提取邮件地址和电话号码\n'
                '3. 点击"仅邮件"或"仅电话"筛选结果\n'
                '4. 点击任何识别结果可以复制\n'
                '5. 点击电话号码旁边的电话图标可直接拨打'
              : '1. Tap "SCAN TEXT" to take a photo, or "PICK FROM GALLERY" to select an image\n'
                '2. The app will automatically recognize text and extract emails and phone numbers\n'
                '3. Tap "Emails Only" or "Phones Only" to filter results\n'
                '4. Tap any extracted item to copy it\n'
                '5. Tap the phone icon next to a phone number to call directly',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_isChinese ? '关闭' : 'Close'),
          ),
        ],
      ),
    );
  }

  void _showFeedbackDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_isChinese ? '反馈' : 'Feedback'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TextField(
              decoration: InputDecoration(hintText: 'Enter your feedback...'),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Text(
              _isChinese ? '或直接联系我：' : 'Or contact me directly:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _makePhoneCall(contactPhone),
              child: Text(
                '$contactName: $contactPhone',
                style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_isChinese ? '取消' : 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(_isChinese ? '感谢您的反馈！' : 'Thank you for your feedback!')),
              );
              Navigator.pop(context);
            },
            child: Text(_isChinese ? '提交' : 'Submit'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(''),
        centerTitle: false,
        actions: [
          TextButton(
            onPressed: () => setState(() => _isChinese = !_isChinese),
            child: Text(
              _isChinese ? 'EN' : '中',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showHelpDialog,
            tooltip: _isChinese ? '帮助' : 'Help',
          ),
        ],
      ),
      body: _showCamera
          ? Column(
              children: [
                Container(
                  margin: const EdgeInsets.all(12),
                  height: MediaQuery.of(context).size.height * 0.42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade300, width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _controller != null && _controller!.value.isInitialized
                      ? CameraPreview(_controller!)
                      : const Center(child: Text('Initializing camera...')),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.blue.shade200, width: 1.5),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _isChinese ? '邮件电话扫描器' : 'Email & Phone Scanner',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isChinese
                            ? '拍照或从相册选取图片，自动提取邮件地址和电话号码'
                            : 'Take photo or pick from gallery to extract emails and phone numbers',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _captureFromCamera,
                          icon: const Icon(Icons.camera_alt, size: 22),
                          label: Text(
                            _isChinese ? '扫描文本' : 'SCAN TEXT',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isProcessing ? null : _pickFromGallery,
                          icon: const Icon(Icons.photo_library, size: 22),
                          label: Text(
                            _isChinese ? '从相册选取' : 'PICK FROM GALLERY',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: const BorderSide(color: Colors.green, width: 2),
                            foregroundColor: Colors.green,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton.icon(
                    onPressed: _closeApp,
                    icon: const Icon(Icons.close, size: 18),
                    label: Text(_isChinese ? '关闭应用' : 'CLOSE APP', style: const TextStyle(fontSize: 14)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      foregroundColor: Colors.redAccent,
                    ),
                  ),
                ),
              ],
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilterChip(
                          label: Text(_isChinese ? '全部' : 'All'),
                          selected: _displayMode == 'all',
                          onSelected: (_) => _setDisplayMode('all'),
                          backgroundColor: Colors.grey[200],
                          selectedColor: Colors.blue[100],
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilterChip(
                          label: Text(_isChinese ? '📧 仅邮件' : '📧 Emails Only'),
                          selected: _displayMode == 'emails',
                          onSelected: (_) => _setDisplayMode('emails'),
                          backgroundColor: Colors.grey[200],
                          selectedColor: Colors.blue[100],
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilterChip(
                          label: Text(_isChinese ? '📞 仅电话' : '📞 Phones Only'),
                          selected: _displayMode == 'phones',
                          onSelected: (_) => _setDisplayMode('phones'),
                          backgroundColor: Colors.grey[200],
                          selectedColor: Colors.blue[100],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_displayMode == 'all' && _rawText.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_isChinese ? '📝 完整文本：' : '📝 Full Text:',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: () => _copyToClipboard(_rawText, _isChinese ? '完整文本' : 'Full Text'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(_rawText),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_displayMode == 'all') ...[
                    if (_emails.isNotEmpty) ...[
                      Text(_isChinese ? '📧 邮件地址：' : '📧 Emails:',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
                      const SizedBox(height: 4),
                      ..._emails.map((e) => _buildCopyableItem(e, _isChinese ? '邮件' : 'Email')),
                      const SizedBox(height: 8),
                    ],
                    if (_phones.isNotEmpty) ...[
                      Text(_isChinese ? '📞 电话号码：' : '📞 Phone Numbers:',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                      const SizedBox(height: 4),
                      ..._phones.map((p) => _buildPhoneItem(p)),
                      const SizedBox(height: 8),
                    ],
                    if (_urls.isNotEmpty) ...[
                      Text(_isChinese ? '🔗 网址：' : '🔗 URLs:',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.purple)),
                      const SizedBox(height: 4),
                      ..._urls.map((u) => _buildCopyableItem(u, _isChinese ? '网址' : 'URL')),
                      const SizedBox(height: 8),
                    ],
                  ],
                  if (_displayMode == 'emails') ...[
                    if (_emails.isNotEmpty) ...[
                      Text(_isChinese ? '📧 邮件地址：' : '📧 Emails:',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue)),
                      const SizedBox(height: 8),
                      ..._emails.map((e) => _buildCopyableItem(e, _isChinese ? '邮件' : 'Email')),
                    ] else ...[
                      Text(_isChinese ? '未找到邮件地址。' : 'No emails found.',
                          style: const TextStyle(fontSize: 16, color: Colors.grey)),
                    ],
                  ],
                  if (_displayMode == 'phones') ...[
                    if (_phones.isNotEmpty) ...[
                      Text(_isChinese ? '📞 电话号码：' : '📞 Phone Numbers:',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
                      const SizedBox(height: 8),
                      ..._phones.map((p) => _buildPhoneItem(p)),
                    ] else ...[
                      Text(_isChinese ? '未找到电话号码。' : 'No phone numbers found.',
                          style: const TextStyle(fontSize: 16, color: Colors.grey)),
                    ],
                  ],
                  const SizedBox(height: 16),
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _resetScanner,
                          icon: const Icon(Icons.camera_alt),
                          label: Text(_isChinese ? '扫描另一张图片' : 'SCAN ANOTHER IMAGE'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _showFeedbackDialog,
                          icon: const Icon(Icons.feedback),
                          label: Text(_isChinese ? '反馈' : 'Feedback'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _closeApp,
                          icon: const Icon(Icons.close),
                          label: Text(_isChinese ? '关闭应用' : 'CLOSE APP'),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.redAccent),
                            foregroundColor: Colors.redAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
      bottomNavigationBar: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'By Miftah B. [明泰]',
              style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => _makePhoneCall(contactPhone),
              child: Text(
                '📞 $contactPhone',
                style: const TextStyle(fontSize: 12, color: Colors.green, decoration: TextDecoration.underline),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCopyableItem(String text, String type) {
    return GestureDetector(
      onTap: () => _copyToClipboard(text, type),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(child: Text(text)),
            const Icon(Icons.copy, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneItem(String phoneNumber) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(phoneNumber)),
          IconButton(
            icon: const Icon(Icons.call, size: 18, color: Colors.green),
            onPressed: () => _makePhoneCall(phoneNumber),
            tooltip: _isChinese ? '拨打' : 'Call',
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18, color: Colors.grey),
            onPressed: () => _copyToClipboard(phoneNumber, _isChinese ? '电话号码' : 'Phone number'),
          ),
        ],
      ),
    );
  }
}