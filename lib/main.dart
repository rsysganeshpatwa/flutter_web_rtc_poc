import 'package:flutter/material.dart';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:socket_io_client/socket_io_client.dart' as IO;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: VideoConference(),
    );
  }
}

class VideoConference extends StatefulWidget {
  @override
  _VideoConferenceState createState() => _VideoConferenceState();
}

class _VideoConferenceState extends State<VideoConference> {
  late IO.Socket socket;

  RTCVideoRenderer _localRenderer = RTCVideoRenderer();

  Map<String, RTCVideoRenderer> _remoteRenderers = {};

  Map<String, RTCPeerConnection> _peerConnections = {};

  late MediaStream _localStream;

  List<String> users = [];

  String roomId = 'test_room';

  @override
  void initState() {
    super.initState();

    _initializeRenderer();

    _initSocket();

    _initLocalStream();
  }

  void _initializeRenderer() async {
    await _localRenderer.initialize();
  }

  void _initSocket() {
    socket =
        IO.io('https://lace-transparent-dance.glitch.me', <String, dynamic>{
      'transports': ['websocket'],
    });

    socket.on('connect', (_) {
      print('connected');

      socket.emit('join', roomId);
    });

    socket.on('user-joined', (userId) {
      print('user-joined');
      setState(() {
        users.add(userId);
      });

      _createPeerConnection(userId, true);
    });

    socket.on('signal', (data) async {
      var pc = _peerConnections[data['from']];

      if (pc != null) {
        var description = RTCSessionDescription(
            data['signal']['sdp'], data['signal']['type']);

        await pc.setRemoteDescription(description);

        if (data['signal']['type'] == 'offer') {
          var answer = await pc.createAnswer();

          await pc.setLocalDescription(answer);

          socket.emit('signal', {
            'signal': answer.toMap(),
            'to': data['from'],
          });
        }
      }
    });

    socket.on('user-left', (userId) {
      var renderer = _remoteRenderers.remove(userId);

      renderer?.dispose();

      _peerConnections.remove(userId)?.close();

      setState(() {
        users.remove(userId);
      });
    });
  }

  void _initLocalStream() async {
    _localStream = await navigator.mediaDevices.getUserMedia({
      'video': true,
      'audio': true,
    });

    _localRenderer.srcObject = _localStream;
 // Initialize pc
  RTCPeerConnection pc = await createPeerConnection(configuration, constraints);

  pc.addStream(_localStream);

  // Create an offer or answer and start the connection process
  RTCSessionDescription description = await pc.createOffer();
  await pc.setLocalDescription(description);


  // Send the offer or answer to the remote peer...


    setState(() {});
  }

  Future<void> _createPeerConnection(String userId, bool isOffer) async {
    var pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}
      ],
    });

    pc.onIceCandidate = (candidate) {
      //print(candidate);
      if (candidate != null) {
        socket.emit('signal', {
          'signal': candidate.toMap(),
          'to': userId,
        });
      }
    };

  

    pc.onTrack = (RTCTrackEvent event) {
      print('onTrack: ${event.track.kind}');
      if (event.track.kind == 'video') {
        var renderer = RTCVideoRenderer();

        renderer.initialize().then((_) {
          print('renderer');
          renderer.srcObject = event.streams[0];
          print(event.streams[0]);
          print(_remoteRenderers.length);
           _remoteRenderers[userId] = renderer;

          setState(() {
           
          });
        });
      }
    };

    pc.addStream(_localStream);

    _peerConnections[userId] = pc;

    if (isOffer) {
      var offer = await pc.createOffer();

      await pc.setLocalDescription(offer);

      socket.emit('signal', {
        'signal': offer.toMap(),
        'to': userId,
      });
    }
  }

  @override
  void dispose() {
    _localRenderer.dispose();

    _peerConnections.forEach((_, pc) => pc.close());

    _remoteRenderers.forEach((_, renderer) => renderer.dispose());

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Video Conference')),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Expanded(
                  flex: 1,
                  child: RTCVideoView(_localRenderer),
                ),
                Expanded(
                  flex: 3,
                  child: GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 1.0,
                      mainAxisSpacing: 8.0,
                      crossAxisSpacing: 8.0,
                    ),
                    itemCount: _remoteRenderers.length,
                    itemBuilder: (context, index) {
                      var renderer = _remoteRenderers.values.elementAt(index);

                      return RTCVideoView(renderer);
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              color: Colors.grey[200],
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Users in Room',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        return ListTile(
                          title: Text(users[index]),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
