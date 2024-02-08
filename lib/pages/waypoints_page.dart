import 'package:flutter/material.dart';
import 'serial_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lottie/lottie.dart';
import 'dart:io';
import 'package:xml/xml.dart';

class WaypointPage extends StatefulWidget {
  const WaypointPage({Key? key}) : super(key: key);

  @override
  // ignore: library_private_types_in_public_api
  _WaypointPageState createState() => _WaypointPageState();
}

class _WaypointPageState extends State<WaypointPage> {
  String buttonText = 'Carga los Waypoints';
  Color buttonColor = const Color(0xFF252525);

  List<List<double>> waypoints = [];

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      if (result.files.single.extension == 'gpx') {
        PlatformFile file = result.files.first;
        List<List<double>> coordinates = await _leerArchivoGPX(file.path!);
        setState(() {
          waypoints = coordinates;
        });

        // Navega a la página HomePage con una animación de transición
        _navigateToSerialPage();
      } else {
        // Archivo no es .txt, realizar animación
        _showErrorAnimation();
      }
    }
  }

  void _navigateToSerialPage() async {
    // Realiza la animación de cambio de página
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => SerialPage(waypoints: waypoints),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = 0.0;
          const end = 1.0;
          const curve = Curves.fastOutSlowIn;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var opacityAnimation = animation.drive(tween);

          return FadeTransition(
            opacity: opacityAnimation,
            child: child,
          );
        },
        transitionDuration: const Duration(seconds: 1),
      ),
    );
  }

  void _showErrorAnimation() async {
    setState(() {
      buttonText = 'Vuelve a intentar';
      buttonColor = Colors.red;
    });

    await Future.delayed(const Duration(seconds: 1));

    setState(() {
      buttonText = 'Carga los Waypoints';
      buttonColor = const Color(0xFF252525);
    });
  }

  Future<List<List<double>>> _leerArchivoGPX(String rutaArchivo) async {
    final archivo = File(rutaArchivo);
    final contenido = await archivo.readAsString();
    final document = XmlDocument.parse(contenido);

    List<List<double>> waypoints = [];

    final wpts = document.findAllElements('wpt');
    for (var wpt in wpts) {
      final latitud = double.parse(wpt.getAttribute('lat')!);
      final longitud = double.parse(wpt.getAttribute('lon')!);
      waypoints.add([latitud, longitud]);
    }

    return waypoints;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9E9E9),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Padding(
              padding: EdgeInsets.all(50),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'PASO 1',
                    style: TextStyle(
                      color: Color(0xFF252525),
                      fontSize: 20,
                      fontFamily: 'Roboto Condensed',
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(
                          color: Color.fromARGB(150, 0, 0, 0),
                          offset: Offset(10, 10),
                          blurRadius: 150,
                        ),
                      ]
                    ),
                  ),
                  Text(
                    'Selecciona los Waypoints',
                    style: TextStyle(
                      color: Color(0xFF252525),
                      fontSize: 20,
                      fontFamily: 'Roboto Condensed',
                      fontWeight: FontWeight.w300,
                      shadows: [
                        Shadow(
                          color: Color.fromARGB(150, 0, 0, 0),
                          offset: Offset(10, 10),
                          blurRadius: 150,
                        ),
                      ]
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 120),
              child: Lottie.asset(
                'assets/lottie_gps.json',
                height: 500,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickFile,
        label: Text(
          buttonText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontFamily: 'Roboto Condensed',
            fontWeight: FontWeight.w400,
          ),
        ),
        icon: const Icon(
          Icons.cloud_upload,
          color: Colors.white,
        ),
        elevation: 4.0,
        backgroundColor: buttonColor,
        tooltip: 'Cargar Waypoints',
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}