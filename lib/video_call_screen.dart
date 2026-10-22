
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'doctor_create_prescription_screen.dart';
import 'api_service.dart';

class VideoCallScreen extends StatefulWidget {
  final int appointmentId;
  final int participantId;
  final String participantRole;

  const VideoCallScreen({
    super.key,
    required this.appointmentId,
    required this.participantId,
    required this.participantRole,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  late RtcEngine _engine;

  bool _engineCreated = false;
  bool _isLoading = true;
  bool _isJoined = false;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = true;
  bool _isLeaving = false;

  int? _remoteUid;

  String? _errorMessage;
  String _channelName = '';

  @override
  void initState() {
    super.initState();
    _startCall();
  }

  Future<void> _startCall() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Request camera and microphone permissions.
      final permissions = await [
        Permission.camera,
        Permission.microphone,
      ].request();

      if (permissions[Permission.camera] != PermissionStatus.granted ||
          permissions[Permission.microphone] != PermissionStatus.granted) {
        throw Exception(
          'Camera and microphone permissions are required.',
        );
      }

      // Get Agora token from the Flask backend.
      final tokenResponse = await ApiService.getAgoraVideoToken(
        appointmentId: widget.appointmentId,
        participantId: widget.participantId,
        participantRole: widget.participantRole,
      );

      if (tokenResponse['success'] != true) {
        throw Exception(
          tokenResponse['message'] ?? 'Unable to get video call token.',
        );
      }

      final String appId = tokenResponse['agora_app_id'];
      final String token = tokenResponse['token'];
      final String channelName = tokenResponse['channel_name'];
      final int agoraUid = tokenResponse['agora_uid'];

      _channelName = channelName;

      // Create Agora engine.
      _engine = createAgoraRtcEngine();
      _engineCreated = true;

      await _engine.initialize(
        RtcEngineContext(
          appId: appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      // Listen for Agora call events.
      _engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) {
            if (!mounted) return;

            setState(() {
              _isJoined = true;
              _isLoading = false;
            });
          },
          onUserJoined: (connection, remoteUid, elapsed) {
            if (!mounted) return;

            setState(() {
              _remoteUid = remoteUid;
            });
          },
          onUserOffline: (connection, remoteUid, reason) {
            if (!mounted) return;

            setState(() {
              _remoteUid = null;
            });
          },
          onLeaveChannel: (connection, stats) {
            if (!mounted) return;

            setState(() {
              _isJoined = false;
              _remoteUid = null;
            });
          },
          onError: (errorCode, message) {
            debugPrint('Agora error: $errorCode - $message');
          },
        ),
      );

      // Enable audio and video.
      await _engine.enableVideo();
      await _engine.enableAudio();
      await _engine.startPreview();

      // Join the appointment's video channel.
      await _engine.joinChannel(
        token: token,
        channelId: channelName,
        uid: agoraUid,
        options: const ChannelMediaOptions(),
      );
    } catch (e) {
      debugPrint('Video call error: $e');

      if (_engineCreated) {
        await _cleanupEngine();
      }

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // Turn microphone on/off.
  Future<void> _toggleMicrophone() async {
    if (!_engineCreated) return;

    final newValue = !_isMuted;

    await _engine.muteLocalAudioStream(newValue);

    if (!mounted) return;

    setState(() {
      _isMuted = newValue;
    });
  }

  // Turn camera on/off.
  Future<void> _toggleCamera() async {
    if (!_engineCreated) return;

    final newValue = !_isCameraOff;

    await _engine.enableLocalVideo(!newValue);

    if (!newValue) {
      await _engine.startPreview();
    }

    if (!mounted) return;

    setState(() {
      _isCameraOff = newValue;
    });
  }

  // Switch front/back camera.
  Future<void> _switchCamera() async {
    if (!_engineCreated) return;

    await _engine.switchCamera();
  }

  // Turn speaker on/off.
  Future<void> _toggleSpeaker() async {
    if (!_engineCreated) return;

    final newValue = !_isSpeakerOn;

    await _engine.setEnableSpeakerphone(newValue);

    if (!mounted) return;

    setState(() {
      _isSpeakerOn = newValue;
    });
  }

  // End the video call.
  Future<void> _endCall() async {
    if (_isLeaving) return;

    _isLeaving = true;

    await _cleanupEngine();

    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _cleanupEngine() async {
    if (!_engineCreated) return;

    try {
      await _engine.leaveChannel();
      await _engine.release();
    } catch (e) {
      debugPrint('Agora cleanup error: $e');
    }

    _engineCreated = false;
  }

  @override
  void dispose() {
    if (_engineCreated) {
      _cleanupEngine();
    }

    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
  if (widget.participantRole.toLowerCase() == 'doctor') {
    return _buildDoctorLayout();
  }

  return _buildPatientLayout();
}

Widget _buildPatientLayout() {
  return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Remote participant video.
            Positioned.fill(
              child: _remoteUid != null && _engineCreated
                  ? AgoraVideoView(
                      controller: VideoViewController.remote(
                        rtcEngine: _engine,
                        canvas: VideoCanvas(uid: _remoteUid!),
                        connection: RtcConnection(
                          channelId: _channelName,
                        ),
                      ),
                    )
                  : _waitingScreen(),
            ),

            // Top call information.
            Positioned(
              top: 20,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Video Consultation',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isJoined
                        ? (_remoteUid != null
                            ? 'Doctor / Patient connected'
                            : 'Waiting for the other participant...')
                        : 'Connecting...',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            // Local camera preview.
            Positioned(
              top: 100,
              right: 16,
              child: Container(
                width: 115,
                height: 155,
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white54,
                    width: 1.5,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: _isCameraOff
                    ? const Center(
                        child: Icon(
                          Icons.videocam_off,
                          color: Colors.white,
                          size: 35,
                        ),
                      )
                    : _engineCreated
                        ? AgoraVideoView(
                            controller: VideoViewController(
                              rtcEngine: _engine,
                              canvas: const VideoCanvas(uid: 0),
                            ),
                          )
                        : const Center(
                            child: CircularProgressIndicator(),
                          ),
              ),
            ),

            // Loading indicator.
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(
                  color: Colors.tealAccent,
                ),
              ),

            // Error message.
            if (_errorMessage != null)
              Center(
                child: Container(
                  margin: const EdgeInsets.all(25),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.redAccent,
                        size: 45,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _startCall,
                        child: const Text('Try Again'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Go Back'),
                      ),
                    ],
                  ),
                ),
              ),

            // Call controls.
            if (!_isLoading && _errorMessage == null)
              Positioned(
                bottom: 30,
                left: 15,
                right: 15,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _controlButton(
                      icon: _isMuted ? Icons.mic_off : Icons.mic,
                      label: _isMuted ? 'Unmute' : 'Mute',
                      onPressed: _toggleMicrophone,
                      color: _isMuted ? Colors.red : Colors.white24,
                    ),
                    _controlButton(
                      icon: _isCameraOff
                          ? Icons.videocam_off
                          : Icons.videocam,
                      label: 'Camera',
                      onPressed: _toggleCamera,
                      color: _isCameraOff ? Colors.red : Colors.white24,
                    ),
                    _controlButton(
                      icon: Icons.cameraswitch,
                      label: 'Flip',
                      onPressed: _switchCamera,
                      color: Colors.white24,
                    ),
                    _controlButton(
                      icon: _isSpeakerOn
                          ? Icons.volume_up
                          : Icons.volume_off,
                      label: 'Speaker',
                      onPressed: _toggleSpeaker,
                      color: Colors.white24,
                    ),
                    _controlButton(
                      icon: Icons.call_end,
                      label: 'End',
                      onPressed: _endCall,
                      color: Colors.red,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _waitingScreen() {
    return Container(
      color: Colors.blueGrey.shade900,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircleAvatar(
              radius: 48,
              backgroundColor: Colors.white24,
              child: Icon(
                Icons.person,
                size: 55,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _isJoined
                  ? 'Waiting for the other participant'
                  : 'Connecting to consultation...',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 25,
          backgroundColor: color,
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(
              icon,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
  // New layout shown only to the doctor.

Widget _buildDoctorLayout() {
  const navy = Color(0xFF10182F);
  const blue = Color(0xFF2864E8);
  const pageColor = Color(0xFFF5F7FB);

  return Scaffold(
    backgroundColor: navy,
    body: SafeArea(
      child: Column(
        children: [
          // Back button
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: IconButton(
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(
                  Icons.arrow_back,
                  color: navy,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ),

          // Scrollable doctor consultation content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                // Video panel
                Container(
                  height: 245,
                  decoration: BoxDecoration(
                    color: navy,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: blue,
                      width: 2,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _remoteUid != null && _engineCreated
                            ? AgoraVideoView(
                                controller: VideoViewController.remote(
                                  rtcEngine: _engine,
                                  canvas: VideoCanvas(uid: _remoteUid!),
                                  connection: RtcConnection(
                                    channelId: _channelName,
                                  ),
                                ),
                              )
                            : _waitingScreen(),
                      ),

                      // Patient details: replace with real appointment data later
                      Positioned(
                        top: 16,
                        left: 16,
                        right: 16,
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Patient consultation',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _isJoined ? 'LIVE' : 'CONNECTING',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Small local camera preview
                      Positioned(
                        right: 12,
                        top: 52,
                        width: 72,
                        height: 88,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF273149),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white54),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _isCameraOff
                              ? const Icon(
                                  Icons.videocam_off,
                                  color: Colors.white,
                                )
                              : _engineCreated
                                  ? AgoraVideoView(
                                      controller: VideoViewController(
                                        rtcEngine: _engine,
                                        canvas: const VideoCanvas(uid: 0),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.person,
                                      color: Colors.white,
                                    ),
                        ),
                      ),

                      // Call controls
                      Positioned(
                        bottom: 12,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _doctorCallButton(
                              icon: _isMuted ? Icons.mic_off : Icons.mic,
                              label: '',
                              onPressed: _toggleMicrophone,
                            ),
                            const SizedBox(width: 14),
                            _doctorCallButton(
                              icon: _isCameraOff
                                  ? Icons.videocam_off
                                  : Icons.videocam,
                              label: '',
                              onPressed: _toggleCamera,
                            ),
                            const SizedBox(width: 14),
                            _doctorCallButton(
                              icon: Icons.call_end,
                              label: '',
                              onPressed: _endCall,
                              isEnd: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                  TextButton(
                    onPressed: _startCall,
                    child: const Text(
                      'Try Again',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Examination intake
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: pageColor,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Examination Intake',
                              style: TextStyle(
                                color: navy,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'EHR history screen will be connected later.',
                                  ),
                                ),
                              );
                            },
                            child: const Text(
                              'View EHR History',
                              style: TextStyle(
                                color: blue,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),

                      _intakeField(
                        'Symptoms Reported',
                        'Patient symptoms will appear here',
                      ),
                      _intakeField(
                        'Examination Findings',
                        'Enter examination findings',
                      ),
                      _intakeField(
                        'Diagnosis',
                        'Enter diagnosis',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Clinical action buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                       onPressed: () {
                       Navigator.push(
                          context,
                        MaterialPageRoute(
                        builder: (context) => DoctorCreatePrescriptionScreen(
                        // In the doctor's call screen, participantId is the doctor's ID.
                        // "widget." lets this code read the values given to VideoCallScreen.
                           doctorId: widget.participantId,
                        ),
                       ),
                      );
                     },
                        icon: const Icon(Icons.check),
                        label: const Text('Write Rx'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Lab-order screen will be connected later.',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Order Lab'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white70),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// Compact controls used inside the doctor's video panel.
Widget _doctorCallButton({
  required IconData icon,
  required String label,
  required VoidCallback onPressed,
  bool isEnd = false,
}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
        style: IconButton.styleFrom(
          backgroundColor: isEnd ? Colors.red : Colors.white24,
        ),
      ),
      Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
        ),
      ),
    ],
  );
}

// Reusable field for the examination intake card.
Widget _intakeField(String title, String hint) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Color(0xFF334E68),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFFF3F6FA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    ),
  );
}
}