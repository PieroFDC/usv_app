import 'package:another_flushbar/flushbar.dart';
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
import 'package:audioplayers/audioplayers.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';

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
  
  String outputString = "";
  String tempString = "";
  bool waitingForSecondPart = false;

  // MAPS
  final Set<Polyline> _polylines = {};
  final Location _locationController = Location();
  LatLng? currentLocation;
  late BitmapDescriptor _workstationIcon;
  late BitmapDescriptor _usvIcon;

  double _headingPhone = 0;
  double _distanceValue = 0;

  bool sDialog = false;

  // from USV
  // <latUSV,lonUSV,heading,_velocityValue,numWaypoints, navMode, startNav, returnHome, battery, sonic, calibration>
  // <-12.862966,-72.693329,120,0.5,0,M,false,false,14.8,false,3>
  double velocityValue = 0;
  double heading = 0;
  double latUSV = 0;
  double lonUSV = 0;
  int numWaypoints = 0;
  String navMode = "M";
  bool startNav = false;
  bool returnHome = false;
  double battery = 0;
  bool sonic = false;
  int calibration = 0;

  String valNavMode = "M";
  bool valStartNav = false;

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
    await _port!.setPortParameters(2000000, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

    // Escuchar el Stream de datos
    _port!.inputStream?.listen((Uint8List data) {
      setState(() {
        outputString = _processData(data);
        if(outputString.isNotEmpty) {
          _processMessage(outputString);
        }
      });
    });

  }

  String _processData(Uint8List data) {
    String message = String.fromCharCodes(data);

    message = message.replaceAll(RegExp(r'\s+'), '');

    if (message.startsWith("<")) {
      if (message.endsWith(">")) {
        message = message.substring(1, message.length - 1);
        waitingForSecondPart = false;

        return message;

      } else if (!message.endsWith(">")) {
        message = message.substring(1);
        tempString = message;
        waitingForSecondPart = true;
      }

    } else if (!message.startsWith(">")) {
      if (!waitingForSecondPart) {
        return "";

      } else {
        // Si el mensaje termina con ">"
        if (message.endsWith(">")) {
          message = message.substring(0, message.length - 1);
          tempString += message;
          waitingForSecondPart = false;

          return tempString;

        } else {
          waitingForSecondPart = false;
        }
      }
    }

    return "";
  }

  void _processMessage(String message) {
    List<String> partes = message.split(',');

    if(partes.length == 11) {
      // Asignar valores a las variables
      latUSV = double.parse(partes[0]);
      lonUSV = double.parse(partes[1]);
      heading = double.parse(partes[2]);
      velocityValue = double.parse(partes[3]);
      numWaypoints = int.parse(partes[4]);
      navMode = partes[5];
      startNav = partes[6] == "1" ? true : false;
      returnHome = partes[7] == "1" ? true : false;
      battery = double.parse(partes[8]);
      sonic = partes[9] == "1" ? true : false;
      calibration = int.parse(partes[10]);

      if(latUSV == -999.0 || lonUSV == -999.0) {
        _distanceValue = 0.0;
      } else {
        _distanceValue = _calculateDistance(currentLocation!.latitude, currentLocation!.longitude, latUSV, lonUSV);
      }

      if(navMode != valNavMode) {
        flushMessage(navMode == "M" ? "¡Se cambió al modo manual!" : "¡Se cambió al modo automático!");
        valNavMode = navMode;
      }
      
      if(startNav != valStartNav) {
        flushMessage(startNav ? "¡Se inició la navegación!" : "¡Se detuvo la navegación!");
        valStartNav = startNav;
      }
    }
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

  void _showDialog() {

    _playSound("alert.wav");

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Perligro"),
          content: Row(
            children: [
              SizedBox(
                width: 200,
                child: Text(
                    "El vehículo está a ${_distanceValue.toStringAsFixed(0)} metros, ¡recuerde que la distancia máxima recomendada es de 1Km!"
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
                Navigator.of(context).pop(); // Cerrar el diálogo
              },
              child: const Text("Aceptar"),
            ),
          ],
        );
      },
    );
  }

  void flushMessage(String message) {
    Flushbar(
      title: 'Alerta',
      message: message,
      positionOffset: 60,
      icon: const Icon(
        Icons.crisis_alert_rounded,
        color: Colors.white,
        ),
      forwardAnimationCurve: Curves.easeInOutBack,
      reverseAnimationCurve: Curves.easeInOutBack,
      backgroundColor: const Color(0xFF252525),
      margin: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(10),
      duration: const Duration(seconds: 3),
      flushbarPosition: FlushbarPosition.TOP,
      flushbarStyle: FlushbarStyle.FLOATING,
      boxShadows: const [
        BoxShadow(
          offset: Offset(10, 10),
          blurRadius: 30.0,
          color: ui.Color.fromARGB(118, 49, 49, 49),
        )
      ],
    ).show(context);
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

    if(distanceMts >= 750 && distanceMts <= 2000  && !sDialog) {
      sDialog = true;
      _showDialog();

    } else if(distanceMts < 750 && sDialog) {
      sDialog = false;
    }

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
    double widgetsWidth = (MediaQuery.of(context).size.width / 2) * 0.78;

    LatLng startLocation = LatLng(_waypoints[0][0], _waypoints[0][1]);

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

    return PopScope(
      canPop: false,
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
            SlidingUpPanel(
              renderPanelSheet: true,
              color: Colors.transparent,
              minHeight: 70.0,
              maxHeight: MediaQuery.of(context).size.height / 2,
              slideDirection: SlideDirection.DOWN,
              boxShadow: const [
                BoxShadow(
                  offset: Offset(0, 10),
                  blurRadius: 20.0,
                  color: ui.Color.fromARGB(153, 49, 49, 49),
                )
              ],
              collapsed: const CollapsedSlidingWidget(),
              panel: PanelSlidingWidget(
                numWaypoints: numWaypoints,
                totalWaypoints: _waypoints.length,
                battery: battery,
                calibration: calibration,
                returnHome: returnHome,
                sonic: sonic
                ),
              body: GoogleMap(
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
            ),
            Positioned(
              bottom: 25.0,
              left: 25.0,
              right: 25.0,
              child: Card(
                elevation: 20.0,
                color: Colors.white,
                surfaceTintColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Column(
                        children: [
                          Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.only(bottom: 8),
                                width: widgetsWidth,
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
                                "Velocidad: ${velocityValue.toStringAsFixed(1)} m/s",
                                style: const TextStyle(
                                        color: Color(0xFF252525),
                                        fontSize: 13,
                                        fontFamily: 'Roboto Condensed',
                                        fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.only(top: 40, bottom: 8),
                                width: widgetsWidth,
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
                      Container(
                        width: widgetsWidth,
                        height: widgetsWidth,
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
                                  angle: - heading * pi / 180,
                                  child: Container(
                                    width: 100,
                                    height: 100,
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
                    ],
                  ),
                ),
              ),
            ),

            Positioned(
              bottom: 210.0,
              left: 25.0,
              child: Card(
                elevation: 10.0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                  height: 60,
                  width: 80,
                  decoration: BoxDecoration(
                    color: navMode == "M" ? Colors.white : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(15.0),
                  ),
                  child: Center(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          navMode == "M" ? Icons.gamepad_rounded : Icons.near_me_rounded,
                          color: const Color(0xFF252525),
                          size: 20,
                        ),

                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            navMode == "M" ? 'Manual' : 'Automático',
                            style: const TextStyle(
                              color: Color(0xFF252525),
                              fontSize: 13,
                              fontFamily: 'Roboto Condensed',
                              fontWeight: FontWeight.w400,
                              shadows: [
                                Shadow(
                                  color: ui.Color.fromARGB(169, 0, 0, 0),
                                  offset: Offset(2, 2),
                                  blurRadius: 30,
                                ),
                              ]
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            ),

            Positioned(
              bottom: 210.0,
              right: 25.0,
              child: Card(
                elevation: 10.0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                  height: 60,
                  width: 80,
                  decoration: BoxDecoration(
                    color: startNav ? const Color(0xFF64BE00) : const Color(0xFFDD3800),
                    borderRadius: BorderRadius.circular(15.0),
                  ),
                  child: Center(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          startNav ? Icons.play_arrow_rounded : Icons.pause_rounded,
                          color: Colors.white,
                          size: 25,
                        ),

                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            startNav ? 'Start' : 'Stop',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontFamily: 'Roboto Condensed',
                              fontWeight: FontWeight.w400,
                              shadows: [
                                Shadow(
                                  color: ui.Color.fromARGB(169, 0, 0, 0),
                                  offset: Offset(2, 2),
                                  blurRadius: 30,
                                ),
                              ]
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            ),
          ],
        ),
      ),
    );
  }
}

class CollapsedSlidingWidget extends StatelessWidget {
  const CollapsedSlidingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    // Aquí debes poner tu código para crear el widget que contiene el texto
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF252525),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(15.0),
          bottomRight: Radius.circular(15.0),
        ),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(
            Icons.expand_more,
            color: Colors.white,
            size: 30,
          ),
          SizedBox(
            height: 5,
          )
        ],
      ),
    );
  }
}

class PanelSlidingWidget extends StatefulWidget {

  final int numWaypoints;
  final int totalWaypoints;
  final bool returnHome;
  final double battery;
  final bool sonic;
  final int calibration;

  const PanelSlidingWidget({
    super.key,
    required this.numWaypoints,
    required this.totalWaypoints,
    required this.returnHome,
    required this.battery,
    required this.sonic,
    required this.calibration
    });

  @override
  State<PanelSlidingWidget> createState() => _PanelSlidingWidgetState();
}

class _PanelSlidingWidgetState extends State<PanelSlidingWidget> {

  @override
  Widget build(BuildContext context) {
    String calibrationStatus = "";

    double batPercent = (widget.battery - 12.8) / (16.8 - 12.8) * 100.0;

    switch (widget.calibration) {
      case 0:
        calibrationStatus = "No confiable";
        break;
      case 1:
        calibrationStatus = "Precisión Baja";
        break;
      case 2:
        calibrationStatus = "Precisión Media";
        break;
      case 3:
        calibrationStatus = "Precisión Alta";
        break;
    }

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF252525),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(15.0),
          bottomRight: Radius.circular(15.0),
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(0, 10, 0, 40),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        CustomContainer(
                          bottomPadding: 5.0,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              children: [
                                const Text(
                                  "ESTADO DE LA BATERÍA",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontFamily: 'Roboto Condensed',
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  "voltage: ${widget.battery.toStringAsFixed(2)} V",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontFamily: 'Roboto Condensed',
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                Text(
                                  "Porcentaje: ${batPercent.toStringAsFixed(0)} %",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontFamily: 'Roboto Condensed',
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Icon(
                                  Icons.battery_alert,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              ],
                            ),
                          ),
                        ),
                        CustomContainer(
                          bottomPadding: 5.0,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              children: [
                                const Text(
                                  "ESTADO DE LOS WAYPOINTS",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontFamily: 'Roboto Condensed',
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  "Cantidad de Waypoints: ${widget.totalWaypoints}", //
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontFamily: 'Roboto Condensed',
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                Text(
                                  "Estado: ${widget.numWaypoints}/${widget.totalWaypoints}", //
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontFamily: 'Roboto Condensed',
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Icon(
                                  Icons.my_location,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              ],
                            ),
                          )
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        CustomContainer(
                          bottomPadding: 5.0,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              children: [
                                const Text(
                                  "ESTADO RETORNO A CASA",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontFamily: 'Roboto Condensed',
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 500),
                                  curve: Curves.easeInOut,
                                  height: 60,
                                  width: 150,
                                  decoration: BoxDecoration(
                                    color: widget.returnHome ? const Color(0xFFE26E00) : const Color(0xFFFFBA00),
                                    borderRadius: BorderRadius.circular(15.0),
                                  ),
                                  child: Center(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          widget.returnHome ? Icons.u_turn_left : Icons.turn_sharp_right,
                                          color: Colors.white,
                                          size: 25,
                                        ),

                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(
                                            widget.returnHome ? 'Retornando' : 'Ruta Normal',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontFamily: 'Roboto Condensed',
                                              fontWeight: FontWeight.w400,
                                              shadows: [
                                                Shadow(
                                                  color: ui.Color.fromARGB(169, 0, 0, 0),
                                                  offset: Offset(2, 2),
                                                  blurRadius: 30,
                                                ),
                                              ]
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        CustomContainer(
                          bottomPadding: 5.0,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              children: [
                                const Text(
                                  "ESTADO DE RECOLECCIÓN",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontFamily: 'Roboto Condensed',
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 500),
                                  curve: Curves.easeInOut,
                                  height: 60,
                                  width: 150,
                                  decoration: BoxDecoration(
                                    color: widget.sonic ? const Color(0xFFDD3800) : const Color(0xFF64BE00),
                                    borderRadius: BorderRadius.circular(15.0),
                                  ),
                                  child: Center(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          widget.sonic ? Icons.delete_forever : Icons.recycling,
                                          color: Colors.white,
                                          size: 25,
                                        ),

                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(
                                            widget.sonic ? 'Contenedor Lleno' : 'Contenedor Normal',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontFamily: 'Roboto Condensed',
                                              fontWeight: FontWeight.w400,
                                              shadows: [
                                                Shadow(
                                                  color: ui.Color.fromARGB(169, 0, 0, 0),
                                                  offset: Offset(2, 2),
                                                  blurRadius: 30,
                                                ),
                                              ]
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  CustomContainer(
                    bottomPadding: 0.0,
                    child: Row(
                      children: [
                        SizedBox(
                          width: (MediaQuery.of(context).size.width / 2) - 20,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Text(
                                  "CALIBRACIÓN DE LA IMU",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontFamily: 'Roboto Condensed',
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  "Valor de calibración: ${widget.calibration}",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontFamily: 'Roboto Condensed',
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                Text(
                                  "Estado: $calibrationStatus",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontFamily: 'Roboto Condensed',
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Icon(
                                  Icons.assistant_direction_outlined,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(
                          width: MediaQuery.of(context).size.width / 2,
                          child: RadialTextPointer(calibration: widget.calibration)
                        ),
                      ],
                    )
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 5.0,
              left: (MediaQuery.of(context).size.width / 2) - 15,
              child: const Icon(
                Icons.expand_less,
                color: Colors.white,
                size: 30,
              ),
            )
          ],
        ),
      )
    );
  }
}

class CustomContainer extends StatefulWidget {
  final double bottomPadding;
  final Widget child;

  const CustomContainer({
    super.key,
    required this.child,
    required this.bottomPadding
  });

  @override
  State<CustomContainer> createState() => _CustomContainerState();
}

class _CustomContainerState extends State<CustomContainer> {
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          5.0,
          5.0,
          5.0,
          widget.bottomPadding
        ),
        child: Container(
          constraints: const BoxConstraints.expand(),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(5.0)),
            border: Border.all(
              width: 1,
              color: const ui.Color.fromARGB(75, 255, 255, 255)
            ),
          ),
          child: widget.child,
        ),
      )
    );
  }
}

class RadialTextPointer extends StatefulWidget {
  final int calibration;
  const RadialTextPointer({super.key, required this.calibration});

  @override
  State<RadialTextPointer> createState() => _RadialTextPointerState();
}

class _RadialTextPointerState extends State<RadialTextPointer> {
  @override
  Widget build(BuildContext context) {
    return _buildRadialTextPointer();
  }

  SfRadialGauge _buildRadialTextPointer() {
    double valuePointer = (30.0 * widget.calibration) + 15.0;
    return SfRadialGauge(
      axes: <RadialAxis>[
        RadialAxis(
            showAxisLine: false,
            showLabels: false,
            showTicks: false,
            startAngle: 180,
            endAngle: 360,
            maximum: 120,
            canScaleToFit: true,
            radiusFactor: 1,
            pointers: <GaugePointer>[
              NeedlePointer(
                needleEndWidth: 5,
                needleLength: 0.7,
                value: valuePointer,
                needleColor: Colors.white,
                knobStyle: const KnobStyle(
                  knobRadius: 0.1,
                  color: Colors.white                  
                )
              ),
            ],
            ranges: <GaugeRange>[
              GaugeRange(
                startValue: 0,
                endValue: 30,
                startWidth: 0.45,
                endWidth: 0.45,
                sizeUnit: GaugeSizeUnit.factor,
                color: const Color(0xFFDD3800)
              ),
              GaugeRange(
                startValue: 30,
                endValue: 60,
                startWidth: 0.45,
                endWidth: 0.45,
                sizeUnit: GaugeSizeUnit.factor,
                color: const Color(0xFFE26E00)
              ),
              GaugeRange(
                startValue: 60,
                endValue: 90,
                startWidth: 0.45,
                sizeUnit: GaugeSizeUnit.factor,
                endWidth: 0.45,
                color: const Color(0xFFFFBA00)
              ),
              GaugeRange(
                startValue: 90,
                endValue: 120,
                startWidth: 0.45,
                endWidth: 0.45,
                sizeUnit: GaugeSizeUnit.factor,
                color: const Color(0xFF64BE00)
              ),
            ]),
        RadialAxis(
          showAxisLine: false,
          showLabels: false,
          showTicks: false,
          startAngle: 180,
          endAngle: 360,
          maximum: 120,
          radiusFactor: 1,
          canScaleToFit: true,
          pointers: const <GaugePointer>[],
        ),
      ],
    );
  }
}