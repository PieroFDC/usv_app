import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:usb_serial/transaction.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:lottie/lottie.dart';
import 'home_page.dart';

class SerialPage extends StatefulWidget {
  final List<List<double>> waypoints;
  const SerialPage({super.key, required this.waypoints});

  @override
  // ignore: library_private_types_in_public_api
  _SerialPageState createState() => _SerialPageState();
}

class _SerialPageState extends State<SerialPage> {

  late List<List<double>> _waypoints;
  UsbPort? _port;
  final List<BitmapDescriptor> _icons= [
    BitmapDescriptor.defaultMarker,
    BitmapDescriptor.defaultMarker,
    BitmapDescriptor.defaultMarker
  ];

  String _status = "Idle";
  List<Widget> _ports = [];
  final List<Widget> _serialData = [];

  StreamSubscription<String>? _subscription;
  Transaction<String>? _transaction;
  UsbDevice? _device;

  Future<bool> _connectTo(device) async {
    _serialData.clear();

    if (_subscription != null) {
      _subscription!.cancel();
      _subscription = null;
    }

    if (_transaction != null) {
      _transaction!.dispose();
      _transaction = null;
    }

    if (_port != null) {
      _port!.close();
      _port = null;
    }

    if (device == null) {
      _device = null;
      setState(() {
        _status = "Desconectado";
      });
      return true;
    }

    _port = await device.create();
    if (await (_port!.open()) != true) {
      setState(() {
        _status = "Failed to open port";
      });
      return false;
    }
    _device = device;

    await _port!.setDTR(true);
    await _port!.setRTS(true);
    await _port!.setPortParameters(9600, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

    _transaction = Transaction.stringTerminated(_port!.inputStream as Stream<Uint8List>, Uint8List.fromList([13, 10]));

    _subscription = _transaction!.stream.listen((String line) {
      setState(() {
        _serialData.add(Text(line));
        if (_serialData.length > 20) {
          _serialData.removeAt(0);
        }
      });
    });

    setState(() {
      _status = "Conectado";
    });
    return true;
  }

  void _getPorts() async {
    _ports = [];
    List<UsbDevice> devices = await UsbSerial.listDevices();
    if (!devices.contains(_device)) {
      _connectTo(null);
    }

    for (var device in devices) {
      _ports.add(ListTile(
          leading: const Icon(Icons.usb),
          title: Text(device.productName!),
          subtitle: Text(device.manufacturerName!),
          trailing: ElevatedButton(

            onPressed: () {
              _connectTo(_device == device ? null : device).then((res) {
                _getPorts();
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF252525),
            ),

            child: Text(
              _device == device ? "Desconectar" : "Conectar",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontFamily: 'Roboto Condensed',
                fontWeight: FontWeight.w400,
              ),
            ),
          )
        )
      );
    }
  }

  void _navigateToHomePage() async {
    // Realiza la animación de cambio de página
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => HomePage(waypoints: _waypoints, port: _port, icons: _icons),
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
      )
    );
  }

  void setCustomMarkerIcon() {
    getBytesFromAsset('assets/flag.png', 128).then((onValue) {
          _icons[0] =BitmapDescriptor.fromBytes(onValue!);});
    getBytesFromAsset('assets/green_pin.png', 64).then((onValue) {
          _icons[1] =BitmapDescriptor.fromBytes(onValue!);});
    getBytesFromAsset('assets/red_pin.png', 64).then((onValue) {
          _icons[2] =BitmapDescriptor.fromBytes(onValue!);});
  }

  static Future<Uint8List?> getBytesFromAsset(String path, int width) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
    ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(format: ui.ImageByteFormat.png))?.buffer.asUint8List();
  }

  @override
  void initState() {
    super.initState();
    setCustomMarkerIcon();
    _waypoints = widget.waypoints;

    UsbSerial.usbEventStream!.listen((UsbEvent event) {
      _getPorts();
    });

    _getPorts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9E9E9),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'PASO 2',
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
                    'Selecciona el Control',
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
              Lottie.asset(
                'assets/lottie_usb.json',
                height: 300,
              ),
            Center(
              child: Column(
                children: <Widget>[
                  Text(
                    _ports.isNotEmpty ? "Puertos serie disponibles" : "No hay dispositivos serie disponibles",
                    style: const TextStyle(
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
                  ..._ports,
                  Text('Status: $_status\n'),
                ]
              )
            )
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        // onPressed: _status == "Conectado" ? () => _navigateToHomePage() : null,
        onPressed: () => _navigateToHomePage(),
        icon: const Icon(
          Icons.queue_play_next,
          color: Colors.white,
        ),
        elevation: _status == "Conectado" ? 10.0 : 0.0,
        backgroundColor: _status == "Conectado" ? Colors.green.shade700 : Colors.grey,
        tooltip: 'Cargar Waypoints',
        label: const Text(
          "Siguiente",
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontFamily: 'Roboto Condensed',
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
