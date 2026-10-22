import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// ============================================================
// SIGNATURE PAD SCREEN
// The doctor draws a signature with a finger.
// When the doctor taps "Save", the screen closes and hands back
// the signature as a PNG picture (Uint8List).
// ============================================================

class SignaturePadScreen extends StatefulWidget {
  const SignaturePadScreen({super.key});

  @override
  State<SignaturePadScreen> createState() => _SignaturePadScreenState();
}

class _SignaturePadScreenState extends State<SignaturePadScreen> {
  // Every stroke is one line drawn without lifting the finger.
  // A stroke is a list of points.
  final List<List<Offset>> strokes = [];

  // The size of the drawing box (filled in when the screen is built)
  Size padSize = Size.zero;

  // Draws all the strokes on a canvas. It is used both to show the
  // signature on the screen and to create the final picture.
  static void paintStrokes(Canvas canvas, List<List<Offset>> strokes) {
    // The pen: black, round ends, medium thickness
    final pen = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // A filled dot, used when the doctor only taps once
    final dot = Paint()..color = Colors.black;

    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;

      if (stroke.length == 1) {
        // A single tap: draw a small dot
        canvas.drawCircle(stroke.first, 1.5, dot);
        continue;
      }

      // Connect all the points of the stroke with a line
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, pen);
    }
  }

  // Turns the drawing into a PNG picture (transparent background)
  Future<Uint8List?> exportPng() async {
    // Record the drawing instead of showing it
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    paintStrokes(canvas, strokes);

    // Convert the recording into an image of the same size as the box
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      padSize.width.toInt(),
      padSize.height.toInt(),
    );

    // Encode the image as PNG bytes
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  // Called when the doctor taps "Save"
  Future<void> save() async {
    // Nothing drawn yet
    if (strokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please draw your signature first.'),
        ),
      );
      return;
    }

    final bytes = await exportPng();

    // Something went wrong while creating the picture
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not create the signature. Please try again.'),
        ),
      );
      return;
    }

    if (!mounted) return;

    // Close this screen and give the picture back to the previous screen
    Navigator.pop(context, bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: const Text('Draw Your Signature'),
        backgroundColor: const Color(0xFF3F6FA8),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sign inside the box using your finger.',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF26384A),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Your signature is saved once and used on all your prescriptions.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // ----- The drawing box -----
            Container(
              height: 240,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFDCE5EE)),
              ),
              // ClipRRect keeps the drawing inside the rounded box
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                // LayoutBuilder tells us how big the box really is
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    padSize = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );

                    return GestureDetector(
                      // The finger touches the box: start a new stroke
                      onPanStart: (details) {
                        setState(() {
                          strokes.add([details.localPosition]);
                        });
                      },
                      // The finger moves: add the point to the stroke
                      onPanUpdate: (details) {
                        setState(() {
                          strokes.last.add(details.localPosition);
                        });
                      },
                      child: CustomPaint(
                        painter: _SignaturePainter(strokes),
                        size: Size.infinite,
                      ),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ----- Buttons -----
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    // Removes everything so the doctor can start again
                    onPressed: strokes.isEmpty
                        ? null
                        : () {
                            setState(() {
                              strokes.clear();
                            });
                          },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Clear'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: save,
                    icon: const Icon(Icons.check),
                    label: const Text('Save'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      backgroundColor: const Color(0xFF3F6FA8),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// The painter that shows the strokes on the screen
// ============================================================

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;

  _SignaturePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    _SignaturePadScreenState.paintStrokes(canvas, strokes);
  }

  // Redraw whenever the screen asks for it
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}