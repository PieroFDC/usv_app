import 'package:location/location.dart';
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:lottie/lottie.dart' as lottie_package;
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:toggle_switch/toggle_switch.dart';
import 'package:audioplayers/audioplayers.dart';

class HomePage extends StatefulWidget {
  final List<List<double>> waypoints;
  final UsbPort? port;
  final List<BitmapDescriptor> icons;

  const HomePage({super.key, required this.waypoints, required this.port, required this.icons});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late List<List<double>> _waypoints;
  late List<LatLng> _latLngList = [];
  late UsbPort? _port;
  late List<BitmapDescriptor> _icons;
  
  String _data = "";
  final List<String> _messageBuffer = [];

  int lastNavMode = 1;

  // MAPS
  final Set<Polyline> _polylines = {};
  final Location _locationController = Location();
  LatLng? currentLocation;
  late BitmapDescriptor _workstationIcon;
  late BitmapDescriptor _usvIcon;

  double _headingPhone = 0;
  double _distanceValue = 0;

  // from USV
  // <latUSV,lonUSV,heading,_velocityValue,numWaypoints>
  double velocityValue = 0;
  double heading = 0;
  double latUSV = 0;
  double lonUSV = 0;
  int numWaypoints = 0; // Número de waypoints alcanzados

  // to USV
  // <_navigationMode,_start>
  int _navigationMode = 0;
  bool _start = false;

  @override
  void initState() {
    super.initState();
    _waypoints = widget.waypoints;
     _latLngList = _waypoints.map((coord) => LatLng(coord[0], coord[1])).toList();
    _port = widget.port;
    _icons = widget.icons;
    _initSerialCommunication();
    _getLocationUpdate();
    _drawInitialPolyline();
    _initCompass();

    getBytesFromAsset("assets/workstation.png", 128).then((onValue) {
      _workstationIcon =BitmapDescriptor.fromBytes(onValue!);});
    getBytesFromAsset("assets/USV.png", 128).then((onValue) {
      _usvIcon =BitmapDescriptor.fromBytes(onValue!);});
  }

  @override
  void dispose() {
    _port?.close();
    super.dispose();
  }

  static Future<Uint8List?> getBytesFromAsset(String path, int width) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
    ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(format: ui.ImageByteFormat.png))?.buffer.asUint8List();
  }

  void _initCompass() {
    FlutterCompass.events!.listen((event) {
      setState(() {
        _headingPhone = event.heading!;
      });
    });
  }

  Future<void> _initSerialCommunication() async {
    await _port!.setDTR(true);
    await _port!.setRTS(true);
    await _port!.setPortParameters(115200, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

    // Escuchar el Stream de datos
    _port!.inputStream?.listen((Uint8List data) {
      // Hacer algo con los datos, por ejemplo mostrarlos en un Text
      setState(() {
        _processData(data);
      });
    }); 
  }

  Future<void> _sendSerialData(int navMode, bool start) async {
    String mode = navMode == 0 ? "M" : "A";
    String dataToSend = "<$mode,$start>\r\n";
    await _port!.write(Uint8List.fromList(dataToSend.codeUnits));
  }

  void _processData(Uint8List data) {
    String newData = String.fromCharCodes(data);

    // Agregar los nuevos datos al buffer
    _data += newData;

    // Verificar si el buffer contiene el símbolo "<" al principio
    if (_data.startsWith('<')) {
      // Verificar si el buffer contiene el símbolo ">" al final
      if (_data.contains('>')) {
        // Dividir los mensajes por el símbolo ">"
        List<String> messages = _data.split('>');

        // El último elemento en messages puede estar incompleto, ya que no tiene el ">"
        // Guardar este elemento en el buffer para procesarlo con los siguientes datos
        _messageBuffer.add(messages.removeLast());

        // Procesar y mostrar los mensajes completos
        for (String message in messages) {
          _processMessage(message);
        }

        // Limpiar el buffer
        _data = '';
      }
    } else {
      // Si el buffer no comienza con "<", limpiar los datos acumulados
      _data = '';
    }
  }

  void _processMessage(String message) {
    // Eliminar espacios y caracteres vacíos
    message = message.replaceAll(RegExp(r'\s+'), '');

    // Eliminar caracteres '<' y '>'
    message = message.replaceAll(RegExp(r'[<>]'), '');

    List<String> partes = message.split(',');

    // Asignar valores a las variables
    latUSV = double.parse(partes[0]);
    lonUSV = double.parse(partes[1]);
    heading = double.parse(partes[2]);
    velocityValue = double.parse(partes[3]);
    numWaypoints = int.parse(partes[4]);

    _distanceValue = _calculateDistance(currentLocation!.latitude, currentLocation!.longitude, latUSV, lonUSV);
  }

  void _drawInitialPolyline() async {
    const PolylineId polylineId = PolylineId('line');
    final List<LatLng> polylineCoordinates = [..._latLngList, _latLngList.first];
    final Polyline polyline = Polyline(
      polylineId: polylineId,
      color: const Color.fromARGB(50, 17, 17, 17),
      points: polylineCoordinates,
      width: 2,
      patterns: [PatternItem.dash(15), PatternItem.gap(15)],
    );

    setState(() {
      _polylines.add(polyline);
    });
  }

  Future<void> _playSound(file) async {
    final player = AudioPlayer();
    await player.play(AssetSource(file));
  }

  void _showConfirmationDialog(bool type, index) {

    if(type && (index != lastNavMode)) {
      return;
    }

    _playSound("alert.wav");

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Confirmación"),
          content: Row(
            children: [
              SizedBox(
                width: 200,
                child: Text(
                  type ?
                  _navigationMode == 1 ? "¿Estás seguro que quieres cambiar al modo manual?" : "¿Estás seguro que quieres cambiar al modo automático?" :
                  _start ? "¿Estás seguro que quieres detener el USV?" : "¿Estás seguro que quieres iniciar la navegación?"
                ),
              ),
              lottie_package.Lottie.asset(
                'assets/lottie_alert.json',
                height: 50,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  
                });
                Navigator.of(context).pop(); // Cerrar el diálogo
              },
              child: const Text("Cancelar"),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  if(!type) {
                    _start = !_start;
                  } else {
                    _navigationMode = index!;
                    lastNavMode = (_navigationMode != 1) ? 1 : 0;;
                  }
                  _sendSerialData(_navigationMode, _start);
                });
                Navigator.of(context).pop(); // Cerrar el diálogo
              },
              child: const Text("Aceptar"),
            ),
          ],
        );
      },
    );
  }

  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    int radiusEarth = 6371; // Radio de la Tierra en kilómetros
    double distanceMts;
    double dlat, dlng;
    double a, c;

    // Convertir de grados a radianes
    lat1 = lat1 * pi / 180;
    lat2 = lat2 * pi / 180;
    lng1 = lng1 * pi /180;
    lng2 = lng2 * pi / 180;

    // Fórmula del semiverseno
    dlat = lat2 - lat1;
    dlng = lng2 - lng1;
    a = sin(dlat / 2) * sin(dlat / 2) +
        cos(lat1) * cos(lat2) * sin(dlng / 2) * sin(dlng / 2);
    c = 2 * atan2(sqrt(a), sqrt(1 - a));

    // Calcular la distancia en kilómetros y convertirla a metros
    distanceMts = 1000 * radiusEarth * c;

    return distanceMts;
  }

  Future<void> _getLocationUpdate() async {
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    serviceEnabled = await _locationController.serviceEnabled();

    if(serviceEnabled) {
      serviceEnabled = await _locationController.requestService();
    } else {
      return;
    }

    permissionGranted = await _locationController.hasPermission();

    if(permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _locationController.requestPermission();
      if(permissionGranted != PermissionStatus.granted) {
        return;
      }
    }

    _locationController.onLocationChanged.listen((LocationData currentP) {
      if(currentP.latitude != null && currentP.longitude != null) {
        setState(() {
          currentLocation = LatLng(currentP.latitude!, currentP.longitude!);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    LatLng startLocation = LatLng(_waypoints[0][0], _waypoints[0][1]);

    final ButtonStyle elevatedButtonStyle = ElevatedButton.styleFrom(
      backgroundColor: _start ? Colors.red : Colors.green,
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0)
      )
    );

    // Crea la colección de marcadores
    Set<Marker> markers = Set.from(_latLngList.asMap().entries.map((entry) {
      int index = entry.key;
      LatLng latLng = entry.value;

      BitmapDescriptor icon = index == 0
          ? _icons[0]
          : index < numWaypoints + 1
              ? _icons[1]
              : _icons[2];

      return Marker(
        markerId: MarkerId(latLng.toString()),
        position: latLng,
        icon: icon,
      );
    }));

    return WillPopScope(
      onWillPop: () async {
        return false;
      },
      child: Scaffold(
        body: Stack(
          children: [
            currentLocation == null
            ? Center(
              child: lottie_package.Lottie.asset(
                    'assets/loading.json',
                    height: 120,
                  )
            ) :
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: startLocation,
                zoom: 15,
                ),
              markers: {
                ...markers,
                Marker(
                  markerId: const MarkerId("workstation"),
                  position: currentLocation!,
                  icon: _workstationIcon,
                  infoWindow: const InfoWindow(
                    title: "Estación",
                    snippet: "Aquí se encuentra la estación de control",
                  ),
                ),
                Marker(
                  markerId: const MarkerId("usv"),
                  position: LatLng(latUSV, lonUSV),
                  icon: _usvIcon,
                  visible: (latUSV == 0 && lonUSV == 0) ? false : true,
                  infoWindow: const InfoWindow(
                    title: "USV",
                    snippet: "Posición actual del vehículo",
                  ),
                ),
              },
              polylines: _polylines,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            ),
            Positioned(
              bottom: 5.0,
              left: 5.0,
              right: 5.0,
              child: Container(
                padding: const EdgeInsets.all(15.0),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9E9E9),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                    topLeft: Radius.circular(10),
                    topRight: Radius.circular(10),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.shade800.withOpacity(0.5),
                      spreadRadius: 6,
                      blurRadius: 50,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Modo De Navegación",
                              style: TextStyle(
                                      color: Color(0xFF252525),
                                      fontSize: 13,
                                      fontFamily: 'Roboto Condensed',
                                      fontWeight: FontWeight.w400,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: ToggleSwitch(
                                minWidth: 85,
                                minHeight: 80,
                                initialLabelIndex: _navigationMode,
                                cornerRadius: 10.0,
                                activeFgColor: Colors.white,
                                inactiveBgColor: const Color(0xFF252525),
                                inactiveFgColor: Colors.white,
                                totalSwitches: 2,
                                centerText: true,
                                isVertical: false,
                                labels: const ['M', 'A'],
                                icons: const [Icons.gamepad_rounded, Icons.navigation_rounded],
                                activeBgColors: [[Colors.blue.shade800],[Colors.blue.shade800]],
                                customTextStyles: const [
                                  TextStyle(
                                      color: Colors.white,
                                      fontSize: 15.0,
                                      fontFamily: 'Roboto Condensed',
                                      fontWeight: FontWeight.w500
                                      ),
                                ],
                                onToggle: (index) {
                                  // _playSound("alert.wav");
                                  _showConfirmationDialog(true, index);
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: ElevatedButton(
                                onPressed: () {
                                  // _playSound("alert.wav");
                                  _showConfirmationDialog(false, null);
                                  print("last: $lastNavMode");
                                  print("navMode: $_navigationMode");
                                },
                                style: elevatedButtonStyle,
                                child: SizedBox(
                                  width: 140,
                                  height: 80,
                                  child: Center(
                                    child: Text(
                                      _start ? "STOP" : "START",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 40,
                                        fontFamily: 'Roboto Condensed',
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 10),
                              child: Text(
                                "Ángulo De Rumbo: ${heading.ceil()}°",
                                style: const TextStyle(
                                        color: Color(0xFF252525),
                                        fontSize: 13,
                                        fontFamily: 'Roboto Condensed',
                                        fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 10, top: 5),
                              child: Container(
                                width: 170,
                                height: 170,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF252525),
                                  borderRadius: BorderRadius.circular(10.0),
                                ),
                                child: Transform.rotate(
                                  angle: - _headingPhone.ceil() * pi / 180,
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: Padding(
                                          padding: const EdgeInsets.all(3.0),
                                          child: Image.asset("assets/NSEW_compass.png"),
                                        ),
                                      ),
    
                                      Center(
                                        child: Transform.rotate(
                                          angle: - (heading - 90) * pi / 180,
                                          child: Container(
                                            width: 130,
                                            height: 130,
                                            decoration: const BoxDecoration(
                                              image: DecorationImage(
                                                image: AssetImage("assets/compass.png"), // Reemplaza con la ruta de tu imagen
                                              ),
                                            ),
                                          ),
                                        )
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.only(top: 15, bottom: 8),
                              width: 170,
                              child: SfLinearGauge(
                                interval: 0.5,
                                maximum: 3,
                                animateAxis: true,
                                animateRange: true,
                                labelPosition: LinearLabelPosition.outside,
                                tickPosition: LinearElementPosition.outside,
                                axisLabelStyle: const TextStyle(
                                  color: Color(0xFF252525),
                                  fontSize: 10,
                                  fontFamily: 'Roboto Condensed',
                                  fontWeight: FontWeight.w500,
                                ),
                                onGenerateLabels: () {
                                  return <LinearAxisLabel>[
                                    const LinearAxisLabel(text: '0', value: 0),
                                    const LinearAxisLabel(text: '1', value: 1),
                                    const LinearAxisLabel(text: '2', value: 2),
                                    const LinearAxisLabel(text: '3', value: 3),
                                  ];
                                },
                                axisTrackStyle: const LinearAxisTrackStyle(
                                    thickness: 5, color: Colors.transparent),
                                markerPointers: <LinearMarkerPointer>[
                                  LinearShapePointer(
                                      value: velocityValue,
                                      color: Colors.blue.shade800,
                                      width: 18,
                                      position: LinearElementPosition.cross,
                                      shapeType: LinearShapePointerType.triangle,
                                      height: 10),
                                ],
                                ranges: const <LinearGaugeRange>[
                                  LinearGaugeRange(
                                    midValue: 0,
                                    endValue: 1.5,
                                    startWidth: 10,
                                    midWidth: 10,
                                    endWidth: 10,
                                    position: LinearElementPosition.cross,
                                    color: Colors.green,
                                  ),
                                  LinearGaugeRange(
                                    startValue: 1.5,
                                    midValue: 0,
                                    startWidth: 10,
                                    midWidth: 10,
                                    endWidth: 10,
                                    position: LinearElementPosition.cross,
                                    color: Colors.red,
                                  )
                                ]
                              ),
                            ),
                            Text(
                              "Velocidad: $velocityValue m/s",
                              style: const TextStyle(
                                      color: Color(0xFF252525),
                                      fontSize: 13,
                                      fontFamily: 'Roboto Condensed',
                                      fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(
                          width: 10,
                        ),
                        Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.only(top: 15, bottom: 8),
                              width: 170,
                              child: SfLinearGauge(
                                interval: 0.5,
                                maximum: 1000,
                                animateAxis: true,
                                animateRange: true,
                                labelPosition: LinearLabelPosition.outside,
                                tickPosition: LinearElementPosition.outside,
                                axisLabelStyle: const TextStyle(
                                  color: Color(0xFF252525),
                                  fontSize: 10,
                                  fontFamily: 'Roboto Condensed',
                                  fontWeight: FontWeight.w500,
                                ),
                                onGenerateLabels: () {
                                  return <LinearAxisLabel>[
                                    const LinearAxisLabel(text: '0', value: 0),
                                    const LinearAxisLabel(text: '500', value: 500),
                                    const LinearAxisLabel(text: '750', value: 750),
                                    const LinearAxisLabel(text: '1k', value: 1000),
                                  ];
                                },
                                axisTrackStyle: const LinearAxisTrackStyle(
                                    thickness: 5, color: Colors.transparent),
                                markerPointers: <LinearMarkerPointer>[
                                  LinearShapePointer(
                                      value: _distanceValue,
                                      color: Colors.blue.shade800,
                                      width: 18,
                                      position: LinearElementPosition.cross,
                                      shapeType: LinearShapePointerType.triangle,
                                      height: 10),
                                ],
                                ranges: const <LinearGaugeRange>[
                                  LinearGaugeRange(
                                    midValue: 0,
                                    endValue: 500,
                                    startWidth: 10,
                                    midWidth: 10,
                                    endWidth: 10,
                                    position: LinearElementPosition.cross,
                                    color: Colors.green,
                                  ),
                                  LinearGaugeRange(
                                    startValue: 500,
                                    midValue: 0,
                                    endValue: 750,
                                    startWidth: 10,
                                    midWidth: 10,
                                    endWidth: 10,
                                    position: LinearElementPosition.cross,
                                    color: Colors.orange,
                                  ),
                                  LinearGaugeRange(
                                    startValue: 750,
                                    midValue: 0,
                                    endValue: 1000,
                                    startWidth: 10,
                                    midWidth: 10,
                                    endWidth: 10,
                                    position: LinearElementPosition.cross,
                                    color: Colors.red,
                                  )
                                ]
                              ),
                            ),
                            Text(
                              "Distancia: ${_distanceValue.toStringAsFixed(1)} m",
                              style: const TextStyle(
                                      color: Color(0xFF252525),
                                      fontSize: 13,
                                      fontFamily: 'Roboto Condensed',
                                      fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}