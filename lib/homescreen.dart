import 'dart:convert';

import 'package:chatapp/videocall_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

Future<void> showCallkitIncoming(Map<String, dynamic> data) async {
  final params = CallKitParams(
    id: data['channelName'] as String,
    nameCaller: data['callerId'] as String,
    appName: 'Video Call App',
    avatar: '',
    handle: data['channelName'] as String,
    type: 1, // Video call
    duration: 30000,
    textAccept: 'Accept',
    textDecline: 'Decline',
    extra: data,
    android: AndroidParams(
      isCustomNotification: true,
      ringtonePath: 'system_ringtone_default',
      backgroundColor: '#0955fa',
      actionColor: '#4CAF50',
    ),
  );
  await FlutterCallkitIncoming.showCallkitIncoming(params);
}

class HomeScreen extends StatefulWidget {
  final String currentUserId;

  const HomeScreen({super.key, required this.currentUserId});


  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _otherUserId;
  String? _fcmToken;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Video Call App',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Logged in as ${widget.currentUserId}',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 50),
              if (_otherUserId != null)
                ListTile(
                  leading: const Icon(Icons.person, color: Colors.blue, size: 40),
                  title: Text(
                    _otherUserId!,
                    style: const TextStyle(color: Colors.white, fontSize: 20),
                  ),
                  onTap: _initiateCall,
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _initializeFCM();
    _setOtherUser();
    _listenForCallEvents();
  }

 Future<void> _initializeFCM() async {
    final prefs = await SharedPreferences.getInstance();
    _fcmToken = await FirebaseMessaging.instance.getToken();
    await prefs.setString('fcmToken', _fcmToken!);
    // Save FCM token to Firestore
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.currentUserId)
        .set({'fcmToken': _fcmToken}, SetOptions(merge: true));
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.data['type'] == 'call') {
        showCallkitIncoming(message.data);
      }
    });
  }

  Future<void> _initiateCall() async {
    final channelName = '${widget.currentUserId}_${_otherUserId}_${DateTime.now().millisecondsSinceEpoch}';
    await FirebaseFirestore.instance.collection('calls').doc(channelName).set({
      'caller': widget.currentUserId,
      'receiver': _otherUserId,
      'status': 'Calling',
      'timestamp': DateTime.now(),
    });

    final prefs = await SharedPreferences.getInstance();
    final otherFcmToken = await FirebaseFirestore.instance
        .collection('users')
        .doc(_otherUserId)
        .get()
        .then((doc) => doc.data()?['fcmToken']);

    if (otherFcmToken != null) {
      await http.post(
        Uri.parse('https://your-fcm-server/send'), // Replace with your server URL
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'to': otherFcmToken,
          'data': {
            'type': 'call',
            'callerId': widget.currentUserId,
            'channelName': channelName,
          },
        }),
      );
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoCallScreen(
          channelName: channelName,
          userId: widget.currentUserId == 'UserA' ? 1 : 2,
        ),
      ),
    );
  }

  Future<void> _listenForCallEvents() async {
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
      if (event == null) return;

      // Use string constants for event types
      switch (event.event) {
        case 'CALL_ACCEPT':
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VideoCallScreen(
                channelName: event.body['channelName'] as String,
                userId: widget.currentUserId == 'UserA' ? 1 : 2,
              ),
            ),
          );
          await FirebaseFirestore.instance
              .collection('calls')
              .doc(event.body['channelName'] as String)
              .update({'status': 'Connected'});
          break;
        case 'CALL_DECLINE':
          await FirebaseFirestore.instance
              .collection('calls')
              .doc(event.body['channelName'] as String)
              .update({'status': 'Ended'});
          break;
        default:
          break;
      }
    });
  }

  void _setOtherUser() {
    _otherUserId = widget.currentUserId == 'UserA' ? 'UserB' : 'UserA';
  }
}