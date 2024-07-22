import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:uuid/uuid.dart';


import 'dart:html' as html;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: JoinPage(),
    );
  }
}

class JoinPage extends StatelessWidget {
  final TextEditingController _roomController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Join Room'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: _roomController,
                decoration: InputDecoration(
                  labelText: 'Room ID',
                ),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          VideoConference(roomId: _roomController.text),
                    ),
                  );
                },
                child: Text('Join'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VideoConference extends StatefulWidget {
  final String roomId;

  VideoConference({required this.roomId});

  @override
  _VideoConferenceState createState() => _VideoConferenceState();
}

class _VideoConferenceState extends State<VideoConference> {
  late html.WindowBase _popupWindow;
  late IO.Socket socket;
  late RTCPeerConnection _peerConnection;
  late MediaStream _localStream;
  Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final _localRenderer = RTCVideoRenderer();
  final _uuid = Uuid();
  late String _id;
  bool _isAudioEnabled = true;

  @override
  void initState() {
    super.initState();
    _localRenderer.initialize();
    _id = _uuid.v4();
    _initSocket();
    _initLocalStream();
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderers.values.forEach((renderer) => renderer.dispose());
    socket.dispose();
    super.dispose();
  }

  void _initSocket() {
    socket = IO.io('https://node-soket-video-eb793gy8z-ganeshs-projects-3b1b16ca.vercel.app', <String, dynamic>{
      'transports': ['websocket'],
    });
    socket.on('connect', (_) {
      print('Connected to the server');
      socket.emit('join', widget.roomId);
    });
    socket.on('user-joined', (userId) {
      print('User joined: $userId');
      if (userId != _id) {
        _createOffer(userId);
      }
    });
    socket.on('signal', (data) async {
      var signal = data['signal'];
      var from = data['from'];
      if (signal['type'] == 'offer') {
        await _peerConnection.setRemoteDescription(
            RTCSessionDescription(signal['sdp'], signal['type']));

        _createAnswer(from);
      } else if (signal['type'] == 'answer') {
        await _peerConnection.setRemoteDescription(
            RTCSessionDescription(signal['sdp'], signal['type']));
      } else if (signal['type'] == 'candidate') {
        await _peerConnection.addCandidate(RTCIceCandidate(
            signal['candidate'], signal['sdpMid'], signal['sdpMLineIndex']));
      }
    });
    socket.on('user-left', (userId) {
      print('User left: $userId');
      if (_remoteRenderers.containsKey(userId)) {
        setState(() {
          _remoteRenderers[userId]?.srcObject = null;
          _remoteRenderers[userId]?.dispose();
          _remoteRenderers.remove(userId);
        });
      }
    });
  }

  void _initLocalStream() async {
    _localStream = await navigator.mediaDevices.getUserMedia({
      'video': true,
      'audio': true,
    });
    setState(() {
      _localRenderer.srcObject = _localStream;
    });
    _createPeerConnection();
  }

  void _createPeerConnection() async {
    _peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    });
    _peerConnection.addStream(_localStream);
    _peerConnection.onIceCandidate = (candidate) {
      socket.emit('signal', {
        'to': _id,
        'signal': {
          'type': 'candidate',
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMlineIndex,
        },
      });
    };
    _peerConnection.onAddStream = (stream) {
      setState(() {
        var renderer = RTCVideoRenderer();
        renderer.initialize();
        renderer.srcObject = stream;
        _remoteRenderers[_id] = renderer;
      });
    };
  }

  void _createOffer(String userId) async {
    var offer = await _peerConnection.createOffer();
    await _peerConnection.setLocalDescription(offer);
    socket.emit('signal', {
      'to': userId,
      'from': _id,
      'signal': {
        'type': 'offer',
        'sdp': offer.sdp,
      },
    });
  }

  void _createAnswer(String userId) async {
    var answer = await _peerConnection.createAnswer();
    await _peerConnection.setLocalDescription(answer);
    socket.emit('signal', {
      'to': userId,
      'from': _id,
      'signal': {
        'type': 'answer',
        'sdp': answer.sdp,
      },
    });
  }

  void _toggleAudio() {
    bool enabled = _localStream.getAudioTracks()[0].enabled;
    _localStream.getAudioTracks()[0].enabled = !enabled;
    setState(() {
      _isAudioEnabled = !enabled;
    });
  }

  void _openInNewTab() {
    final url = 'http://localhost:3000/room/${widget.roomId}';
    _popupWindow = html.window.open(url, 'Video Conference');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Video Conference'),
      ),
      body: Column(
        children: [
          Expanded(
            child: RTCVideoView(_localRenderer),
          ),
          Expanded(
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
              ),
              itemCount: _remoteRenderers.length,
              itemBuilder: (context, index) {
                var userId = _remoteRenderers.keys.elementAt(index);
                var renderer = _remoteRenderers[userId];
                return RTCVideoView(renderer!);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _toggleAudio,
                  child:
                      Text(_isAudioEnabled ? 'Disable Audio' : 'Enable Audio'),
                ),
                SizedBox(width: 20),
                ElevatedButton(
                  onPressed: _openInNewTab,
                  child: Text('Open in New Tab'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}