import 'dart:async';
import 'package:flutter/material.dart';

class DebugLogService extends ChangeNotifier {
  static final DebugLogService _instance = DebugLogService._internal();
  factory DebugLogService() => _instance;
  DebugLogService._internal();

  final List<String> _logs = [];
  bool _isEnabled = false;
  final int _maxLogs = 50;
  Timer? _throttleTimer;
  bool _pendingNotify = false;

  List<String> get logs => List.unmodifiable(_logs);
  bool get isEnabled => _isEnabled;

  void enable() {
    _isEnabled = true;
    notifyListeners();
  }

  void disable() {
    _isEnabled = false;
    _logs.clear();
    _throttleTimer?.cancel();
    _pendingNotify = false;
    notifyListeners();
  }

  void toggle() {
    if (_isEnabled) {
      disable();
    } else {
      enable();
    }
  }

  void log(String message) {
    if (!_isEnabled) return;

    final timestamp = DateTime.now().toString().substring(11, 19);
    _logs.add('[$timestamp] $message');

    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }

    // 节流：最多每100ms通知一次，避免UI线程阻塞
    if (_throttleTimer == null || !_throttleTimer!.isActive) {
      _pendingNotify = false;
      notifyListeners();
      _throttleTimer = Timer(const Duration(milliseconds: 100), () {
        if (_pendingNotify) {
          notifyListeners();
          _pendingNotify = false;
        }
      });
    } else {
      _pendingNotify = true;
    }
  }

  void clear() {
    _logs.clear();
    notifyListeners();
  }
}

class DebugLogOverlay extends StatefulWidget {
  final Widget child;

  const DebugLogOverlay({super.key, required this.child});

  @override
  State<DebugLogOverlay> createState() => _DebugLogOverlayState();
}

class _DebugLogOverlayState extends State<DebugLogOverlay> {
  final DebugLogService _debugLogService = DebugLogService();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _debugLogService.addListener(_onLogUpdate);
  }

  @override
  void dispose() {
    _debugLogService.removeListener(_onLogUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void _onLogUpdate() {
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_debugLogService.isEnabled)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  onVerticalDragUpdate: (details) {},
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withOpacity(0.5)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.bug_report,
                                color: Colors.green, size: 14),
                            const SizedBox(width: 4),
                            const Text(
                              '调试日志',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: () => _debugLogService.clear(),
                              child: const Icon(Icons.clear_all,
                                  color: Colors.grey, size: 14),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => _debugLogService.disable(),
                              child: const Icon(Icons.close,
                                  color: Colors.red, size: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Flexible(
                          child: _debugLogService.logs.isEmpty
                              ? const Center(
                                  child: Text(
                                    '暂无日志',
                                    style: TextStyle(
                                        color: Colors.grey, fontSize: 10),
                                  ),
                                )
                              : ListView.builder(
                                  controller: _scrollController,
                                  shrinkWrap: true,
                                  itemCount: _debugLogService.logs.length,
                                  itemBuilder: (context, index) {
                                    return Text(
                                      _debugLogService.logs[index],
                                      style: const TextStyle(
                                        color: Colors.greenAccent,
                                        fontSize: 9,
                                        fontFamily: 'monospace',
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
