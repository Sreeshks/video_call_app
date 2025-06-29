import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:vcapp/services/call_services.dart';
import 'package:vcapp/services/notification_services.dart';

import 'auth_screen.dart';
import 'video_call_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  User? _currentUser;
  int? _currentUserId;
  String? _currentUserFcmToken;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f0f), // Matches AuthScreen background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'CallSync',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.logout,
              color: Colors.white.withOpacity(0.8),
            ),
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your User ID: ${_currentUserId ?? 'Loading...'}',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withOpacity(0.6),
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Available Users',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error loading users',
                          style: TextStyle(
                            color: Colors.red.shade600,
                            fontSize: 16,
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF00d4aa),
                          strokeWidth: 2,
                        ),
                      );
                    }

                    final users = snapshot.data!.docs
                        .where((doc) => doc.id != _currentUser?.uid)
                        .toList();

                    if (users.isEmpty) {
                      return Center(
                        child: Text(
                          'No other users found',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 16,
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final user = users[index];
                        final email = user['email'] as String;
                        final userId = user['userId'].toString();
                        final fcmToken = user['fcmToken'] as String;

                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1a1a1a).withOpacity(0.8),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF00d4aa).withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF00d4aa).withOpacity(0.2),
                              radius: 24,
                              child: const Icon(
                                Icons.person,
                                color: Color(0xFF00d4aa),
                                size: 28,
                              ),
                            ),
                            title: Text(
                              email,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              'User ID: $userId',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 14,
                              ),
                            ),
                            trailing: Material(
                              color: const Color(0xFF00d4aa),
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _startCall(userId, fcmToken, email),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.video_call,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Call',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
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
    _currentUser = FirebaseAuth.instance.currentUser;
    _setupUserData();
    _setupFirebaseMessaging();
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AuthScreen()),
      );
    }
  }

  Future<void> _setupFirebaseMessaging() async {
    final fcmToken = await FirebaseMessaging.instance.getToken();
    if (_currentUser != null && fcmToken != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .update({'fcmToken': fcmToken});
      debugPrint('FCM Token updated for user ${_currentUser!.uid}: $fcmToken');
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Foreground message received: ${message.data}');
      if (message.data['type'] == 'call' && mounted) {
        NotificationService.showCallNotification(
          message.data,
          context: context,
          currentUserId: _currentUserId,
        );
      }
    });

    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null && message.data['type'] == 'call' && mounted) {
        debugPrint('Initial message received: ${message.data}');
        NotificationService.showCallNotification(
          message.data,
          context: context,
          currentUserId: _currentUserId,
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (message.data['type'] == 'call' && mounted) {
        debugPrint('App opened from notification: ${message.data}');
        NotificationService.showCallNotification(
          message.data,
          context: context,
          currentUserId: _currentUserId,
        );
      }
    });
  }

  Future<void> _setupUserData() async {
    if (_currentUser != null) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .get();
      if (mounted) {
        setState(() {
          _currentUserId = userDoc.data()?['userId'];
          _currentUserFcmToken = userDoc.data()?['fcmToken'];
        });
      }
    }
  }

  void _startCall(String targetUserId, String targetFcmToken, String email) async {
    if (_currentUserId != null) {
      const channelName = 'fringe';
      await CallService.initiateCall(
        callerId: _currentUserId.toString(),
        targetUserId: targetUserId,
        channelName: channelName,
        targetFcmToken: targetFcmToken,
      );
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoCallScreen(
              channelName: channelName,
              userId: _currentUserId!,
            ),
          ),
        );
      }
    }
  }
}