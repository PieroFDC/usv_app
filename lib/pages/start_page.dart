import 'package:flutter/material.dart';
import 'waypoints_page.dart';

class StartPage extends StatelessWidget {
  const StartPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const WaypointPage(),
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
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/background_usv.png'), // Reemplaza con la ruta de tu imagen
              fit: BoxFit.cover,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Padding(
                padding: EdgeInsets.all(50.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'USV',
                      style: TextStyle(
                        color: Color(0xFF252525),
                        fontSize: 60,
                        fontFamily: 'Roboto Condensed',
                        fontWeight: FontWeight.w700,
                        shadows: [
                          Shadow(
                            color: Color.fromARGB(120, 0, 0, 0),
                            offset: Offset(10, 10),
                            blurRadius: 100,
                          ),
                        ]
                      ),
                    ),
                    Text(
                      ' APP',
                      style: TextStyle(
                        color: Color(0xFF252525),
                        fontSize: 60,
                        fontFamily: 'Roboto Condensed',
                        fontWeight: FontWeight.w300,
                        shadows: [
                          Shadow(
                            color: Color.fromARGB(120, 0, 0, 0),
                            offset: Offset(10, 10),
                            blurRadius: 100,
                          ),
                        ]
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(50.0),
                child: Image.asset(
                  'assets/upc.png', // Reemplaza con la ruta de tu imagen PNG
                  height: 80, // Ajusta la altura según sea necesario
                  width: 80, // Ajusta el ancho según sea necesario
                  color: const Color(0xFF252525),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}