import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simple_permissions/simple_permissions.dart';

const directoryName = 'Signature';
List<Color> colorList = [
  Colors.indigo,
  Colors.blue,
  Colors.green,
  Colors.yellow,
  Colors.orange,
  Colors.red
];
GlobalKey<_ColorChoserState> colorChoserKey = GlobalKey();
Color backgroundColor = Colors.white;
Color penColor = Colors.blue;
bool showSendFAB = false;
bool showColorSelector = true;

void main() {
  runApp(MaterialApp(
    home: SignApp(),
    debugShowCheckedModeBanner: false,
  ));
}

class SignApp extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return SignAppState();
  }
}

class SignAppState extends State<SignApp> {
  GlobalKey<SignatureState> signatureKey = GlobalKey();
  var image;
  String _platformVersion = 'Unknown';
  Permission _permission = Permission.WriteExternalStorage;

  @override
  void initState() {
    super.initState();
    // SystemChrome.setEnabledSystemUIOverlays([]);  // hide status bar and bottom button bar
    initPlatformState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  initPlatformState() async {
    String platformVersion;
    // Platform messages may fail, so we use a try/catch PlatformException.
    try {
      platformVersion = await SimplePermissions.platformVersion;
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
    });
    print(_platformVersion);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: Visibility(
        visible: showSendFAB,
        child: FloatingActionButton(
          key: ValueKey(2),
          shape: CircleBorder(
            side: BorderSide(
                color: backgroundColor == Colors.white
                    ? Colors.grey
                    : Colors.white,
                width: 3.0),
          ),
          child: Icon(Icons.save),
          onPressed: () {
            print('Send');
            setRenderedImage(context);
          },
        ),
      ),
      body: Stack(
        children: <Widget>[
          Signature(key: signatureKey),
          ColorChoser(key: UniqueKey()),
          SafeArea(
            child: ButtonBar(children: <Widget>[
              IconButton(
                iconSize: 35,
                icon: CircleAvatar(
                    backgroundColor: Colors.grey[300],
                    child: Icon(Icons.undo)),
                onPressed: () => signatureKey.currentState.clearPoints(),
              ),
              IconButton(
                iconSize: 35,
                icon: CircleAvatar(
                    backgroundColor: Colors.grey[300],
                    child: Icon(Icons.done)),
                onPressed: () {
                  setState(() {
                    showSendFAB = true;
                    showColorSelector = false;
                  });
                },
              ),
            ]),
          )
        ],
      ),
    );
  }

  setRenderedImage(BuildContext context) async {
    ui.Image renderedImage = await signatureKey.currentState.rendered;

    setState(() {
      image = renderedImage;
    });

    showImage(context);
  }

  Future<Null> showImage(BuildContext context) async {
    var pngBytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (!(await checkPermission())) await requestPermission();
    // Use plugin [path_provider] to export image to storage
    Directory directory = await getExternalStorageDirectory();
    String path = directory.path;
    print(path);
    await Directory('$path/$directoryName').create(recursive: true);
    File('$path/$directoryName/${formattedDate()}.png')
        .writeAsBytesSync(pngBytes.buffer.asInt8List());
    return showDialog<Null>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(
              'Saved at $path/$directoryName/${formattedDate()}.png',
              style: TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w300,
                  color: Theme.of(context).primaryColor,
                  letterSpacing: 1.1),
            ),
            content: Image.memory(Uint8List.view(pngBytes.buffer)),
          );
        });
  }

  String formattedDate() {
    DateTime dateTime = DateTime.now();
    String dateTimeString = 'Signature_' + dateTime.toIso8601String();

    return dateTimeString;
  }

  requestPermission() async {
    PermissionStatus result =
        await SimplePermissions.requestPermission(_permission);
    return result;
  }

  checkPermission() async {
    bool result = await SimplePermissions.checkPermission(_permission);
    return result;
  }

  getPermissionStatus() async {
    final result = await SimplePermissions.getPermissionStatus(_permission);
    print("permission status is " + result.toString());
  }
}

class ColorChoser extends StatefulWidget {
  const ColorChoser({
    Key key,
  }) : super(key: key);

  @override
  _ColorChoserState createState() => _ColorChoserState();
}

class _ColorChoserState extends State<ColorChoser> {
  @override
  Widget build(BuildContext context) {
    return Align(
      key: ValueKey(1),
      alignment: Alignment.bottomCenter,
      child: Visibility(
        visible: showColorSelector,
        child: Container(
          height: 70,
          child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: colorList.length,
              itemBuilder: (context, index) {
                return InkWell(
                  onTap: () {
                    setState(() {
                      // backgroundColor = Colors.blue[index * 100];
                      penColor = colorList[index];
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: CircleAvatar(
                      backgroundColor: Colors.grey,
                      child: Padding(
                        padding: const EdgeInsets.all(3.0),
                        child: CircleAvatar(
                          backgroundColor: colorList[index],
                        ),
                      ),
                    ),
                  ),
                );
              }),
        ),
      ),
    );
  }
}

class Signature extends StatefulWidget {
  Signature({Key key}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return SignatureState();
  }
}

class SignatureState extends State<Signature> {
  // [SignatureState] responsible for receives drag/touch events by draw/user
  // @_points stores the path drawn which is passed to
  // [SignaturePainter]#contructor to draw canvas
  List<Offset> _points = <Offset>[];

  Future<ui.Image> get rendered {
    // [CustomPainter] has its own @canvas to pass our
    // [ui.PictureRecorder] object must be passed to [Canvas]#contructor
    // to capture the Image. This way we can pass @recorder to [Canvas]#contructor
    // using @painter[SignaturePainter] we can call [SignaturePainter]#paint
    // with the our newly created @canvas
    ui.PictureRecorder recorder = ui.PictureRecorder();
    Canvas canvas = Canvas(recorder);
    SignaturePainter painter = SignaturePainter(points: _points);
    var size = context.size;
    painter.paint(canvas, size);
    return recorder
        .endRecording()
        .toImage(size.width.floor(), size.height.floor());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        child: GestureDetector(
          onPanUpdate: (DragUpdateDetails details) {
            setState(() {
              RenderBox _object = context.findRenderObject();
              Offset _locationPoints =
                  _object.localToGlobal(details.globalPosition);
              _points = new List.from(_points)..add(_locationPoints);
            });
          },
          onPanStart: (details) {
            setState(() {
              showColorSelector = false;
              showSendFAB = false;
            });
          },
          onPanEnd: (DragEndDetails details) {
            setState(() {
              _points.add(null);
              // showColorSelector = true;
              // showSendFAB = true;
            });
          },
          child: CustomPaint(
            painter: SignaturePainter(points: _points),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }

  // clearPoints method used to reset the canvas
  // method can be called using
  //   key.currentState.clearPoints();
  void clearPoints() {
    setState(() {
      _points.clear();
    });
  }
}

class SignaturePainter extends CustomPainter {
  // [SignaturePainter] receives points through constructor
  // @points holds the drawn path in the form (x,y) offset;
  // This class responsible for drawing only
  // It won't receive any drag/touch events by draw/user.
  List<Offset> points = <Offset>[];

  SignaturePainter({this.points});
  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..color = penColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.0;

    var backgroundPaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = 100;
    canvas.drawPaint(backgroundPaint);

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i], points[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(SignaturePainter oldDelegate) {
    return oldDelegate.points != points;
  }
}
